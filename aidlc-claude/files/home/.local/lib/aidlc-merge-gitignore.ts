// Reconcile the project's .gitignore with the AI-DLC section of the harness one.
//
//   usage: bun aidlc-merge-gitignore.ts <shipped-.gitignore> <project-.gitignore>
//
// Why this exists: `dist/claude/` ships three things, not two — `.claude/`,
// `aidlc/`, and a `.gitignore` that carries the workspace's commit/ignore split.
// `aidlc/` is *meant* to be committed (that is how a team shares method memory,
// state, audit shards, and artifacts), but the same tree also accumulates
// per-user and per-machine files at runtime. The .gitignore is what draws the
// line. Without it every one of these becomes a Git change in the project:
//
//   aidlc/active-space, .../intents/active-intent  per-user cursors; committing
//       them turns navigation into shared state and conflicts on every intent
//       create and cursor switch
//   aidlc/.aidlc-clone-id                          names *this clone's* audit
//       shard — shared, every clone appends to one shard and git-conflicts,
//       which is the exact failure per-clone sharding exists to prevent
//   .../intents/*/runtime-graph.json               regenerated telemetry
//   .../intents/**/.aidlc-sensors/                 derived per-machine caches
//   .../knowledge/.sources.local.json              alias -> ABSOLUTE root; would
//       hand every clone one developer's directory layout
//
// This matters more here than for a hand install: `$WORKSPACE_DIR` for a
// bind-mounted workspace is the user's real project directory on the host, and
// what the kit writes there outlives `sbx rm`.
//
// The copy is `cp -R --update=none`, which would silently skip a .gitignore the
// project already owns — i.e. skip in exactly the case that matters. So, as with
// settings.json, reconcile instead of skipping, following upstream's documented
// procedure (README.md "Set up your project"): copy the complete starter file
// only when the project has none; when one exists, preserve every project-owned
// rule and merge only the section from `# AI-DLC` through the end of the shipped
// file — never its generic node_modules/editor starter rules.
//
// Ours goes in a marked block so a re-run replaces it instead of appending a
// second copy, and so an upstream rule change lands on the next sandbox. Text
// inside the markers is kit-managed and overwritten; project rules belong
// outside it. A file that already carries a hand-merged `# AI-DLC` section is
// left completely alone — that is the same project-wins rule the settings merge
// follows.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";

const SELF = "aidlc-merge-gitignore";
const BEGIN = "# >>> AI-DLC (managed by the aidlc-claude sbx kit) >>>";
const END = "# <<< AI-DLC (managed by the aidlc-claude sbx kit) <<<";
// Upstream's own section header, and the boundary its install instructions name.
const SECTION_HEADER = /^#\s*AI-DLC\b/;

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

function ruleLines(section: string): string[] {
  return section
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "" && !l.startsWith("#"));
}

// Everything from upstream's `# AI-DLC` header to EOF, which is exactly the span
// its install instructions say to merge.
function extractSection(raw: string, path: string): string {
  const lines = raw.split("\n");
  const start = lines.findIndex((l) => SECTION_HEADER.test(l));
  if (start === -1) {
    die(
      `${path} carries no "# AI-DLC" section — refusing to guess which of its ` +
        `rules are the AI-DLC ones. Check that the shipped .gitignore still has it.`,
    );
  }
  const section = lines.slice(start).join("\n").trimEnd();
  // Contract check in the spirit of the settings merge's hook check: a block
  // with no aidlc rules in it is not worth writing, and means upstream moved
  // the section boundary out from under us.
  if (!ruleLines(section).some((l) => l.includes("aidlc"))) {
    die(`the "# AI-DLC" section of ${path} carries no aidlc rules — refusing to write it`);
  }
  return section;
}

function write(destPath: string, next: string): void {
  mkdirSync(dirname(destPath), { recursive: true });
  // Temp file in the destination directory so the rename is an atomic same-fs
  // swap: a concurrent `git status` sees the old or the new file, never a partial.
  const tmp = join(dirname(destPath), `.${SELF}.${process.pid}.tmp`);
  writeFileSync(tmp, next, { mode: 0o644 });
  renameSync(tmp, destPath);
}

const [srcPath, destPath] = process.argv.slice(2);
if (!srcPath || !destPath) {
  console.error(`${SELF}: usage: <shipped-.gitignore> <project-.gitignore>`);
  process.exit(2);
}

const shippedRaw = readText(srcPath, "shipped AI-DLC .gitignore");
const section = extractSection(shippedRaw, srcPath);
const block = `${BEGIN}\n${section}\n${END}\n`;
const ruleCount = ruleLines(section).length;

// No project file: install upstream's complete starter byte-for-byte, exactly as
// its guarded `cp` does. Unmarked, because the whole file is ours — there is no
// project content to keep separable, and marking it would only invite a later
// run to rewrite a file the project has since taken ownership of.
if (!existsSync(destPath)) {
  write(destPath, shippedRaw);
  console.log(`${SELF}: installed ${destPath} from ${srcPath} (${ruleCount} AI-DLC rules)`);
  process.exit(0);
}

const before = readText(destPath, "project .gitignore");
const begin = before.indexOf(BEGIN);
const end = before.indexOf(END);

// Hand-merged already (upstream's header present, but not under our markers):
// the rules are in place, so there is nothing to fix and no reason to touch a
// file whose owner clearly managed it themselves.
if (begin === -1 && before.split("\n").some((l) => SECTION_HEADER.test(l))) {
  console.log(
    `${SELF}: ${destPath} already carries an "# AI-DLC" section (not kit-managed), left as is`,
  );
  process.exit(0);
}

let next: string;
if (begin !== -1 && end !== -1 && end > begin) {
  // Replace in place, so the block stays where the project put it and an
  // upstream rule change lands without the file growing on every restart.
  const head = before.slice(0, begin);
  const tail = before.slice(end + END.length).replace(/^\n/, "");
  next = `${head}${block}${tail}`;
} else if (begin !== -1 || end !== -1) {
  die(
    `${destPath} has a half-written AI-DLC block (one marker without its pair). ` +
      `Remove the stray marker line and restart the sandbox; nothing has been written.`,
  );
} else {
  // Append. Last matching pattern wins in .gitignore, so appending is also what
  // makes these rules effective over a broader project pattern above them — at
  // the cost that a project `!negation` for one of these paths would be
  // overridden. That is upstream's documented placement ("merge the section",
  // at the end of the file), and re-negating below the block still works.
  const head = before.endsWith("\n") || before === "" ? before : `${before}\n`;
  next = `${head}${head.endsWith("\n\n") || head === "" ? "" : "\n"}${block}`;
}

if (next === before) {
  console.log(`${SELF}: ${destPath} already reconciled, no change`);
  process.exit(0);
}

write(destPath, next);
console.log(
  begin === -1
    ? `${SELF}: appended the AI-DLC section (${ruleCount} rules) to the project's existing ${destPath}`
    : `${SELF}: refreshed the managed AI-DLC block (${ruleCount} rules) in ${destPath}`,
);
