// Reconcile the project's .claude/settings.json with the AI-DLC harness one.
//
//   usage: bun aidlc-merge-settings.ts <shipped-settings.json> <project-settings.json>
//
// Why this exists: the harness install is `cp -R --update=none`, which silently
// skips any file the project already owns. For every other file that is the
// right call — but settings.json is what *wires* the harness. Its `hooks` block
// wires the aidlc-*.ts hooks that enforce the stage protocol — state-transition
// guard, plan-approval guard, review freeze, reviewer scope, human-turn
// recording, and the session lifecycle; its `env` block selects Bedrock and pins
// the model tiers; `statusLine` points at aidlc-statusline.ts. Skipping it leaves
// every hook script on disk with nothing invoking them — `/aidlc` still starts,
// the guards never fire, and upstream's own doctor fails loudly with "Hook
// contract: settings.json wires no aidlc-*.ts hooks"
// (core/tools/aidlc-utility.ts). So merge instead of skipping.
//
// Merge direction is always project-wins: a value the project already set is
// never overwritten, only missing keys are filled and arrays unioned. That makes
// the pass idempotent across the container restarts that re-run setup.startup,
// and keeps a project that deliberately chose its own model, region, or status
// line in charge of those.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

type Json = Record<string, any>;

const SELF = "aidlc-merge-settings";
// Matches the hook-command shape the upstream doctor looks for, so the
// post-merge self-check below fails on exactly what the doctor would fail on.
const AIDLC_HOOK = /aidlc-[\w.-]+\.ts/;

function die(msg: string): never {
  console.error(`${SELF}: ${msg}`);
  process.exit(1);
}

function readText(path: string, label: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch (e: any) {
    die(`cannot read ${label} (${path}): ${e.message}`);
  }
}

function parseObject(raw: string, path: string, label: string): Json {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch (e: any) {
    // Deliberately fatal, and deliberately before this script changes settings
    // or the later harness copy runs. The fresh-project version lock may already
    // exist; it records selection, not installation success.
    die(
      `${label} (${path}) is not valid JSON: ${e.message}\n` +
        `  Claude Code settings must be strict JSON — no comments, no trailing commas.\n` +
        `  Fix or move that file and restart the sandbox; settings.json has not ` +
        `been changed and the harness copy has not started.`,
    );
  }
  if (!isPlainObject(value)) die(`${label} (${path}) is not a JSON object`);
  return value;
}

function isPlainObject(v: unknown): v is Json {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

// Union preserving the project's order, appending only shipped entries that are
// not already there. Identity is structural, which is what makes a re-run a
// no-op for object entries like permission strings or announcement blocks.
function unionArray(mine: any[], theirs: any[]): any[] {
  const seen = new Set(mine.map((x) => JSON.stringify(x)));
  const out = [...mine];
  for (const x of theirs) {
    const k = JSON.stringify(x);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(structuredClone(x));
  }
  return out;
}

// Fill-missing / union-arrays / recurse-objects. A scalar the project already
// set is left exactly as it is — that is the project-wins rule.
function fillMissing(dest: Json, src: Json): string[] {
  const notes: string[] = [];
  for (const [k, v] of Object.entries(src)) {
    if (!(k in dest)) {
      dest[k] = structuredClone(v);
      notes.push(k);
    } else if (Array.isArray(dest[k]) && Array.isArray(v)) {
      const before = dest[k].length;
      dest[k] = unionArray(dest[k], v);
      const added = dest[k].length - before;
      if (added > 0) notes.push(`${k}[+${added}]`);
    } else if (isPlainObject(dest[k]) && isPlainObject(v)) {
      notes.push(...fillMissing(dest[k], v).map((n) => `${k}.${n}`));
    }
  }
  return notes;
}

// `hooks` gets its own pass rather than going through fillMissing's array union.
// A structural union would append a shipped matcher group verbatim even when the
// project had already wired one of the commands inside it, double-running that
// hook. Dedupe at the command level instead, per event.
function mergeHooks(dest: Json, src: Json): string[] {
  const notes: string[] = [];
  for (const [event, srcGroups] of Object.entries(src)) {
    if (!Array.isArray(srcGroups)) continue;
    if (!Array.isArray(dest[event])) dest[event] = [];
    const destGroups: Json[] = dest[event];
    const wired = new Set<string>(
      destGroups
        .flatMap((g) => (Array.isArray(g?.hooks) ? g.hooks : []))
        .map((h) => h?.command)
        .filter((c): c is string => typeof c === "string"),
    );
    for (const group of srcGroups) {
      const fresh = (Array.isArray(group?.hooks) ? group.hooks : []).filter(
        (h: Json) => !wired.has(h?.command),
      );
      if (fresh.length === 0) continue;
      for (const h of fresh) wired.add(h?.command);
      // Same matcher already present (the project wired something else under it):
      // extend that group rather than adding a second one with the same matcher.
      const sameMatcher = destGroups.find(
        (g) => (g?.matcher ?? "") === (group?.matcher ?? ""),
      );
      if (sameMatcher && Array.isArray(sameMatcher.hooks)) {
        sameMatcher.hooks.push(...structuredClone(fresh));
      } else {
        destGroups.push({ ...structuredClone(group), hooks: structuredClone(fresh) });
      }
      notes.push(`${event}(${group?.matcher || "*"})+${fresh.length}`);
    }
  }
  return notes;
}

function countAidlcHooks(hooks: unknown): number {
  if (!isPlainObject(hooks)) return 0;
  return Object.values(hooks)
    .flatMap((gs) => (Array.isArray(gs) ? gs : []))
    .flatMap((g: Json) => (Array.isArray(g?.hooks) ? g.hooks : []))
    .filter((h: Json) => typeof h?.command === "string" && AIDLC_HOOK.test(h.command))
    .length;
}

const [srcPath, destPath] = process.argv.slice(2);
if (!srcPath || !destPath) {
  console.error(`${SELF}: usage: <shipped-settings.json> <project-settings.json>`);
  process.exit(2);
}

const shippedRaw = readText(srcPath, "shipped AI-DLC settings");
const shipped = parseObject(shippedRaw, srcPath, "shipped AI-DLC settings");

// Read and validate the project's file before this script changes settings or
// the later harness copy begins. A fresh-project version lock may already exist.
const before = existsSync(destPath) ? readText(destPath, "project settings") : null;

// Nothing to merge into: install upstream's file byte-for-byte rather than
// round-tripping it through JSON.stringify, so the installed settings.json stays
// diffable against dist/claude/.claude/settings.json.
const project: Json = before === null ? shipped : parseObject(before, destPath, "project settings");
const notes: string[] = [];

if (before !== null) {
  const { hooks: shippedHooks, ...shippedRest } = shipped;
  if (!isPlainObject(project.hooks)) project.hooks = {};
  if (isPlainObject(shippedHooks)) notes.push(...mergeHooks(project.hooks, shippedHooks));
  notes.push(...fillMissing(project, shippedRest));
}

// Mirror of the doctor's own contract check: if we would produce a file that
// wires no aidlc hooks, that is the broken install this script exists to
// prevent — refuse rather than write it.
if (countAidlcHooks(project.hooks) === 0) {
  die(
    "settings.json wires no aidlc-*.ts hooks — refusing to write a harness " +
      "`/aidlc --doctor` would reject. Check that " +
      `${srcPath} still carries its hooks block.`,
  );
}

// Not fatal — it is a legitimate (if workflow-breaking) policy choice, and a
// higher-precedence settings layer can still override it — but it is the exact
// silent failure upstream's t324 regression test was written for, so say it.
if (project.disableAllHooks === true) {
  console.warn(
    `${SELF}: WARNING: ${destPath} sets "disableAllHooks": true. Claude Code will ` +
      "run none of the AI-DLC hooks and `/aidlc --doctor` will fail its \"Hooks " +
      "enabled\" row. Remove it, or override it in a higher-precedence settings layer.",
  );
}

const next = before === null ? shippedRaw : `${JSON.stringify(project, null, 2)}\n`;
if (next === before) {
  console.log(`${SELF}: ${destPath} already reconciled, no change`);
  process.exit(0);
}

mkdirSync(dirname(destPath), { recursive: true });
// Temp file in the destination directory so the rename is an atomic same-fs
// swap: a concurrent Claude Code read sees the old or new file, never a partial.
const tmp = join(dirname(destPath), `.${SELF}.${process.pid}.tmp`);
writeFileSync(tmp, next, { mode: 0o644 });
renameSync(tmp, destPath);

console.log(
  before === null
    ? `${SELF}: installed ${destPath} from ${srcPath}`
    : `${SELF}: merged AI-DLC keys into the project's existing ${destPath} ` +
      `(project values kept): ${notes.join(", ") || "none"}`,
);
