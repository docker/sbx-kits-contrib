#!/usr/bin/env bash
# Run one kit end-to-end against a real installed `sbx` CLI: compose it into a
# sandbox, prove the sandbox is usable, and prove the kit's DECLARED egress was
# all it needed.
#
# Usage:
#   scripts/test-kit-e2e.sh <kit-dir>         # from repo root
#   ../scripts/test-kit-e2e.sh                # from inside the kit's directory
#   ../scripts/test-kit-e2e.sh my-other-kit   # also works
#
# Extra arguments are forwarded to `sbx run`.
#
# WHAT E2E STILL ADDS OVER CONFORMANCE
#
# scripts/test-kit.sh judges the built artifact against the specification. It
# cannot tell you whether the thing RUNS: whether a lifecycle hook's command
# actually works on the base it composes onto, whether the hosts the kit declares
# are the hosts it really reaches, or whether a mixin's requirements resolve
# against a real workload. That is this script, and it is the reason it is worth
# the minutes it costs.
#
# v3 made it much simpler than the v2 version of this script. `sbx run ./<kit>`
# takes a kit in SOURCE form and builds it on demand, so the working tree is what
# runs — by construction. The v2 script had to build the kit's image with docker,
# `docker save` it to a tar, `sbx template load` it into the scoped daemon's own
# image store and then create with `--pull=never`, all to defeat two failure modes
# that no longer exist: pulling a stale published image and so silently ignoring a
# Dockerfile change in the branch, or 403ing because a first-of-its-kind kit had no
# published image at all. None of that machinery survives; nothing replaced it.
#
# What the script does for you (so the author doesn't have to):
#   - Scopes every sbx call to APP_NAME=sbx-kits-contrib-tck so the test daemon,
#     sandboxes, policy and cache are isolated from your main sbx state. Nothing
#     the script does touches your day-to-day daemon.
#   - Sets the scoped daemon's default network policy to `deny-all` so the run is
#     a real contract test of the kit's network-policy@1 declaration — each kit
#     gets EXACTLY the outbound reachability it declares and nothing more.
#   - Picks the base a mixin composes onto, from the mixin's own `requires:`.
#   - Fails the run when the policy log recorded a blocked request, even if
#     nothing else complained. See the policy-log check below for why that is not
#     redundant with the run succeeding. Hosts a kit leaves unreachable on
#     purpose (telemetry, update checks) are listed one per line in the kit's
#     testdata/e2e-expected-blocked; blocks on those hosts pass.
#   - On failure, prints the policy log itself rather than telling you to go read
#     it — in CI the runner and its daemon are destroyed the moment the job ends.
#
# The script is idempotent (every step is a write that yields the same outcome on
# repeat runs) and non-interactive (no prompts; relies on `-f`/`--force` and
# `</dev/null` for the few sbx commands that would otherwise prompt).
#
# Prerequisites (one-time per machine):
#   - `sbx` on PATH, from a build that understands kit v3 — the stable line does
#     not. Use scripts/install-sbx.sh, which defaults to the right channel.
#   - The scoped daemon must be logged in to Docker Hub:
#         sbx --app-name sbx-kits-contrib-tck login
#     Each --app-name has its own credential store; this is separate from any
#     login on your main daemon. On Linux, sbx uses a Secret Service provider for
#     libsecret when one is available (gnome-keyring, kwallet, etc.), and
#     otherwise falls back to an encrypted on-disk store — no Secret Service
#     setup is required.
#
# Overrides (env vars):
#   APP_NAME  change the app-name (default: sbx-kits-contrib-tck).
#   POLICY    default network policy applied to the scoped daemon (default:
#             deny-all). Set POLICY= (empty) to skip the policy step entirely —
#             which also disables the blocked-request check, since without a
#             default deny there is nothing to block.
#   E2E_HOST  the base a MIXIN composes onto: a built-in agent name (`shell`,
#             `claude`, …) or an explicit `./path` to a workload kit in this
#             repo. Default: resolved from the mixin's `requires:` (see below).
#   KIT_ARGS  space-separated name=value pairs for arguments the kit declares,
#             e.g. KIT_ARGS="repo=docker/sbx-kits-contrib". Passed scoped to this
#             kit (`--kit-arg <kit>.<name>=<value>`), so composing a base kit that
#             declares the same argument name is unaffected.
#   KEEP_SANDBOX  set to 1 to keep the sandbox after a PASSING run too (a failing
#             run always leaves it behind).
#
# Mirrors scripts/test-kit.sh — keep the kit-resolution logic in sync.

set -euo pipefail

APP_NAME=${APP_NAME:-sbx-kits-contrib-tck}
POLICY=${POLICY-deny-all}

# Locate the repo root from the script's own location so the command works
# regardless of where it's invoked from.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Resolve the kit directory. The first positional arg is the kit (relative to
# $PWD, relative to the repo root, or absolute). If the first arg is a flag
# (starts with `-`) or absent, default to $PWD so authors can just run
# `../scripts/test-kit-e2e.sh` from inside their kit directory.
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  kit_arg=$1
  shift
else
  kit_arg=$PWD
fi

# Allow either an absolute path or a path relative to repo root or CWD.
if [ -d "$kit_arg" ]; then
  kit_abs=$(cd "$kit_arg" && pwd)
elif [ -d "$REPO_ROOT/$kit_arg" ]; then
  kit_abs=$(cd "$REPO_ROOT/$kit_arg" && pwd)
else
  echo "kit directory not found: $kit_arg" >&2
  exit 1
fi

# A v3 kit is a directory whose descriptor is named after it — the same contract
# scripts/discover-kits.sh uses to decide what a kit is.
kit_name=$(basename "$kit_abs")
descriptor="$kit_abs/$kit_name.yaml"
if [ ! -f "$descriptor" ]; then
  echo "no $kit_name.yaml in $kit_abs — is this a v3 kit directory?" >&2
  exit 1
fi

if ! command -v sbx >/dev/null 2>&1; then
  echo "sbx not on PATH — install with scripts/install-sbx.sh" >&2
  exit 1
fi

# Read a scalar top-level field out of a descriptor with awk rather than a YAML
# parser, to keep this script dependency-free (see scripts/README.md). Anchoring
# to column zero is what makes it correct rather than accidentally right: `kind:`
# and `description:` also appear indented under capabilities and lifecycle
# entries, and a nested one must not win.
descriptor_field() {
  awk -v key="$2" '
    $0 ~ "^" key ":" {
      sub("^" key ":[[:space:]]*", "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$1"
}

kind=$(descriptor_field "$descriptor" kind)
case "$kind" in
  workload|mixin) ;;
  "") echo "ERROR: $kit_name.yaml declares no top-level kind:" >&2; exit 1 ;;
  *)  echo "ERROR: $kit_name.yaml declares an unknown kind: $kind" >&2; exit 1 ;;
esac

# A kit may declare arguments, and an argument may be `required: true` with no
# default — github-clone's `repo` is interpolated into a real `git clone`, so
# there is no value this script could invent that would mean anything. v2 kept
# such values in each kit's testdata/tck.yaml; v3 source kits have no equivalent
# file, so the only honest options are "caller supplies it" or "skip loudly".
# Skipping keeps the CI matrix green-or-meaningful instead of permanently red on
# a kit that is not actually broken.
# Scoped by the same column-zero rule as requirement_names: any unindented line
# ends the block, comments included. Erring that way makes the detector miss a
# required argument below a column-zero comment INSIDE args: — which fails later
# at create, with sbx naming the missing argument — rather than skip a kit that was
# fine, which would silently lose coverage.
if [ -z "${KIT_ARGS:-}" ] && awk '
    /^args:/         { in_args = 1; next }
    /^[^[:space:]]/  { in_args = 0 }
    in_args && /required:[[:space:]]*true/ { found = 1 }
    END { exit !found }
  ' "$descriptor"; then
  cat >&2 <<EOF
SKIP: $kit_name declares a required argument with no default, so a sandbox cannot
be created without a caller-supplied value. Re-run with one, e.g.

  KIT_ARGS="name=value" $0 $kit_name

EOF
  exit 0
fi

# Turn KIT_ARGS into `--kit-arg` flags, scoped to this kit by name. The
# `kit.name=value` form exists precisely so composing a base that declares the
# same argument name does not pick up this kit's value.
kit_arg_flags=""
if [ -n "${KIT_ARGS:-}" ]; then
  for pair in $KIT_ARGS; do
    kit_arg_flags="$kit_arg_flags --kit-arg ${kit_name}.${pair}"
  done
fi

# Prints the names a mixin requires, one per line, with version constraints and
# package-ecosystem forms already stripped — i.e. only the names that could
# plausibly BE a base.
#
# Both spellings have to work, because kits in this repo use both:
#
#     requires: ["claude"]          flow, value on the `requires:` line itself
#     requires:                     block sequence, value on the lines after
#       - claude
#
# Two traps, both hit while writing this:
#   * The flow form must be captured from the `requires:` line before anything
#     else looks at it. Mutating $0 in that rule and falling through means the
#     next rule sees `["claude"]`, decides a new top-level key has started, and
#     the value is dropped — silently, leaving every flow-form mixin composing
#     onto the fallback base.
#   * Any line at column zero ends the block, INCLUDING a comment. These
#     descriptors carry long column-zero MIGRATION NOTE comment blocks right
#     after `requires:`, and treating `#` as "still inside" would scan English
#     prose for requirement names — which silently picks a base out of a comment
#     that happens to mention an agent.
# $2 is the field: `requires` or `provides`. Same grammar, same traps.
declared_names() {
  awk -v field="$2" '
    $0 ~ "^" field ":" {
      rest = $0
      sub("^" field ":[[:space:]]*", "", rest)
      in_req = 1
      if (rest != "") print rest
      next
    }
    /^[^[:space:]]/ { in_req = 0 }
    in_req {
      line = $0
      sub(/#.*/, "", line)
      if (line ~ /[^[:space:]]/) print line
    }
  ' "$1" | sed 's/\${{[^}]*}}//g; s/\${{.*//' | tr -d '[]",' | tr ' ' '\n' | while IFS= read -r token; do
    # Cut a version constraint in either spelling: `claude@2.1` or `claude>=2.1`.
    token=${token%%@*}
    token=${token%%[<>=]*}
    case "$token" in
      # A block-sequence dash, or an empty field from the split.
      -|"") continue ;;
      # `deb/jq` and friends name a distribution package, satisfied by whatever
      # base is used rather than by a kit in this repo.
      */*) continue ;;
      # Debris from an unexpanded `${{ kit.args.x }}`, which `provides:` entries
      # carry and the sed above does not catch when it spans lines. Left in, two
      # kits "overlap" on `}}` and every composition looks incoherent.
      *'{'*|*'}'*|*'$'*|kit.args.*) continue ;;
    esac
    printf '%s\n' "$token"
  done
}

requirement_names() { declared_names "$1" requires; }

# The credential services a descriptor declares. `service:` appears only under
# credential@1 in this repo (checked), so the indent-anchored match is enough
# without tracking which capability block we are inside.
credential_services() {
  awk '{ line = $0; sub(/#.*/, "", line)
         if (line ~ /^[[:space:]]+service:[[:space:]]*[^[:space:]]/) {
           sub(/^[[:space:]]+service:[[:space:]]*/, "", line)
           sub(/[[:space:]]+$/, "", line)
           gsub(/^["'"'"']|["'"'"']$/, "", line)
           print line } }' "$1" | sort -u
}

# True when composing the mixin at $1 onto the kit directory $2 is refused
# outright. Two ways, both fatal at create and neither visible until then:
#
#   provides   "capability X is provided by more than one kit"
#   credential "credential (X, runtime) is declared by more than one kit"
#
# The second is why `claude` cannot be every mixin's base: 16 agent mixins
# declare the `anthropic` credential it also declares.
base_conflicts() {
  _desc="$2/$(basename "$2").yaml"
  [ -f "$_desc" ] || _desc="$2/$(basename "$2").yml"
  [ -f "$_desc" ] || return 0
  for _field in provides credential; do
    if [ "$_field" = provides ]; then
      _mix=$(declared_names "$1" provides); _base=$(declared_names "$_desc" provides)
    else
      _mix=$(credential_services "$1"); _base=$(credential_services "$_desc")
    fi
    for _a in $_mix; do
      for _b in $_base; do
        [ "$_a" = "$_b" ] && return 0
      done
    done
  done
  return 1
}

# WHAT A MIXIN COMPOSES ONTO
#
# A mixin is not runnable by itself, so e2e has to choose a base — and the choice
# is not cosmetic: v3 resolves the mixin's `requires:` against what the composed
# set provides, so the wrong base fails the run before the kit is exercised at all.
#
# The mixin usually states the answer itself, so the chain is, in order:
#
#   1. E2E_HOST, when the caller knows better than any of this.
#   2. A requirement naming a WORKLOAD kit in this repo → that kit's directory.
#      Best case: the composition CI exercises is one this repo actually ships.
#      The kind check matters — `task` is a requirement that names a repo kit,
#      but it is a mixin, and a mixin cannot be another mixin's base.
#   3. A requirement naming nothing in this repo → pass it through as a built-in
#      agent name (`claude-bedrock` is one such). Deliberately not filtered
#      against a hardcoded list of built-ins: such a list goes stale silently,
#      whereas sbx rejects an unknown agent by name, which is a better error than
#      composing onto the wrong base and failing somewhere inside the build.
#   4. (removed) The `<base>-mixin` naming convention sent `foo-mixin` to `foo`.
#      That is refused by construction: the two are the same agent in two
#      shapes and both declare `provides: [foo]`, so the set is incoherent --
#      "capability is provided by more than one kit". True of all 30 pairs here.
#   5. The `claude` WORKLOAD KIT in this repo.
#
# Step 5 was the built-in `shell` agent, on the reasoning that it is the cheapest
# and most neutral base with no agent credentials in play. That does not work in
# v3: a built-in agent name contributes no WORKLOAD KIT to the composed set, and
# v3 requires exactly one, so every mixin falling through to it failed create with
#
#   resolve: the kit set is not coherent:
#     - no workload kit in the set; every composition needs exactly one
#
# before the mixin was exercised at all. The base has to be a kit, and `claude` is
# the one workload here that every mixin can sit on. It is heavier than `shell`
# was, which is the price of the base being a real kit; a mixin that wants
# something cheaper should say so in `requires:` (step 2) or pass E2E_HOST.
#
# A repo with a `shell` WORKLOAD kit should make that the default instead. There
# is none today.
host=""
host_source=""
host_is_kit=yes
host_conflict=""
if [ "$kind" = "mixin" ]; then
  if [ -n "${E2E_HOST:-}" ]; then
    host=$E2E_HOST
    host_source="E2E_HOST"
  else
    for dep in $(requirement_names "$descriptor"); do
      dep_descriptor="$REPO_ROOT/$dep/$dep.yaml"
      if [ -f "$dep_descriptor" ]; then
        if [ "$(descriptor_field "$dep_descriptor" kind)" = "workload" ]; then
          # Even a base the kit asked for is unusable if the two contend for
          # the same capability or credential. gstack-mixin is the case: it
          # requires `claude` and declares `anthropic`, which claude owns.
          if base_conflicts "$descriptor" "$REPO_ROOT/$dep"; then
            host_conflict=$dep
            continue
          fi
          host="./$dep"
          host_source="the kit's requires:, which names a workload kit in this repo"
          break
        fi
        continue
      fi
      # Step 3, and in v3 it can no longer produce a RUNNABLE base. A built-in
      # agent name contributes no workload kit, and v3 needs exactly one, so
      # composing onto it fails create with "no workload kit in the set". The
      # name is recorded so the skip below can say which requirement is
      # unsatisfiable here rather than failing with a resolution error that
      # looks like a kit bug.
      host=$dep
      host_source="the kit's requires:, which names no kit in this repo"
      host_is_kit=no
      break
    done
    # Only when the kit asked for nothing. A kit that DID ask, and whose answer
    # conflicts, must not be quietly rehomed onto a base that cannot satisfy the
    # requirement anyway — it skips below instead.
    if [ -z "$host" ] && [ -z "$host_conflict" ]; then
      host="./claude"
      host_source="the default workload kit (the kit requires no particular base)"
      # A base providing what the mixin provides is refused as incoherent, so
      # fall to the first workload that does not. This is what `claude-mixin`
      # needs: it provides `claude`, same as the default base.
      if base_conflicts "$descriptor" "$REPO_ROOT/claude"; then
        host=""
        for cand in $("$SCRIPT_DIR/discover-kits.sh"); do
          [ "$(descriptor_field "$REPO_ROOT/$cand/$cand.yaml" kind)" = "workload" ] || continue
          base_conflicts "$descriptor" "$REPO_ROOT/$cand" && continue
          host="./$cand"
          host_source="the first workload kit that does not contend with this mixin"
          break
        done
      fi
    fi
  fi
  if [ -z "$host" ] && [ -n "$host_conflict" ]; then
    cat >&2 <<EOF
SKIP: $kit_name requires "$host_conflict", and composing with it is refused.

Both declare the same capability or credential, and v3 gives each one owner, so
the kit this mixin asks for is the one kit it cannot sit on. No other workload
here satisfies the requirement. It needs a base that carries the requirement
without owning the credential — a shell workload — which this repo does not have.

EOF
    exit 0
  fi
  if [ "$host_is_kit" = "no" ]; then
    cat >&2 <<EOF
SKIP: $kit_name requires "$host", which is not a workload kit in this repo.

A v3 composition needs exactly one workload KIT, and a built-in agent name does
not supply one, so there is nothing here to compose this mixin onto. Substituting
the default base would exercise a composition the kit says is wrong.

Re-run against a real base when one exists:

  E2E_HOST=./<workload-kit> $0 $kit_name

EOF
    exit 0
  fi
  echo "==> $kit_name is a mixin; composing onto ${host} (${host_source})"
fi

# RUNNING A KIT WHOSE NAME A BUILT-IN AGENT ALREADY HOLDS
#
# sbx refuses to register a kit under a name a built-in agent owns:
#
#   error: agent "claude" is already registered
#          (built-in agents cannot be overridden by a kit)
#
# Eleven workloads here are in that position (claude, codex, cursor, devin,
# docker-agent, nanobot, openclaw, opencode, opencode-model-runner, picoclaw,
# zeroclaw), and so is the `claude` base every mixin now composes onto, so
# without this the collision would take out both halves of the matrix.
#
# A v3 kit's NAME IS ITS DIRECTORY STEM — the descriptor carries no `name:`
# field, and the frontend pairs `<stem>.yaml` with `<stem>.dockerfile` by stem.
# So renaming a kit is renaming a directory and the two files named after it,
# with no document to rewrite. (The v2 harness needed copyKitRenamed in
# tck/e2e_rename.go to re-encode spec.yaml's `name:`; that function is v2-only
# and is not what runs here.)
#
# Everything else the kit depends on travels: `contentFile:` and the recipe's
# COPY paths are relative to the kit directory, which is copied whole.
# `provides:` is declared, not derived from the stem, so the mixin requirements
# that resolve against a renamed base resolve identically.
#
# NOT gated on a hardcoded list of built-in names — the existing rule in this
# script is that such a list goes stale silently. It is also not gated on
# testdata the way v2's was (`ExtractedFromBuiltin`); v3 deleted those files.
# It fires only when sbx itself has refused, which keeps it self-limiting: a
# kit whose name is fine never takes this path.
e2e_rename_suffix=-e2e
builtin_collision_marker="built-in agents cannot be overridden by a kit"

# Copies $1 (a kit directory) into a temp parent as "<stem>${e2e_rename_suffix}",
# renaming the descriptor and recipe to match, and prints the new directory.
copy_kit_renamed() {
  src=$1
  stem=$(basename "$src")
  new_stem="${stem}${e2e_rename_suffix}"

  parent=$(mktemp -d "${TMPDIR:-/tmp}/sbx-e2e-rename-XXXXXX") || return 1
  rename_dirs="${rename_dirs}${rename_dirs:+ }${parent}"
  dst="$parent/$new_stem"

  cp -a "$src" "$dst" || return 1
  for ext in yaml yml dockerfile; do
    if [ -f "$dst/$stem.$ext" ]; then
      mv "$dst/$stem.$ext" "$dst/$new_stem.$ext" || return 1
    fi
  done
  # The descriptor is the one file that must exist under the new stem; a kit
  # that somehow has neither would otherwise fail later as "not a kit".
  if [ ! -f "$dst/$new_stem.yaml" ] && [ ! -f "$dst/$new_stem.yml" ]; then
    echo "ERROR: $src has no $stem.yaml to rename" >&2
    return 1
  fi
  printf '%s\n' "$dst"
}

# Sandbox name prefix and name. sbx accepts letters, numbers, hyphens, periods
# and plus signs — no underscores, so a kit directory carrying one is folded to
# hyphens. The prefix is what the stale-sandbox sweep below matches on, so only
# this kit's own leftovers are ever removed, never someone else's under the same
# --app-name.
kit_sandbox_prefix="e2e-$(printf '%s' "$kit_name" | tr '[:upper:]_' '[:lower:]-')-"
sandbox_name="${kit_sandbox_prefix}$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"

# Smoke test — fail fast if the scoped daemon can't talk to the runtime. The most
# common cause is "not logged in to Docker Hub" (`sbx run` would otherwise fail
# minutes into the build), but the same probe also catches a dead daemon, KVM
# access issues, etc. `sbx ls` exercises the runtime and is a no-op when
# everything is fine, making it safe to run unconditionally.
#
# stdin comes from /dev/null so an interactive sbx prompt (e.g. "Docker Sandboxes
# has been updated and needs to restart. Restart now? (y/N)" after a CLI upgrade)
# fails the probe with its message instead of waiting on a terminal behind the
# suppressed output, which looks like a silent hang.
probe_err=$(sbx --app-name "$APP_NAME" ls 2>&1 >/dev/null </dev/null) || {
  cat >&2 <<EOF
ERROR: smoke test failed — sbx --app-name $APP_NAME is not usable.

$probe_err

Most common fix: the scoped daemon has its own credential store, separate from
any login on your main sbx daemon. Run this one-time setup, then re-run this
script:

  sbx --app-name $APP_NAME login

EOF
  exit 1
}
unset probe_err

# Lists sandbox names under $APP_NAME starting with $1, via `ls --json` rather
# than the human table so this survives table-formatting changes. `ls --json`
# pretty-prints (a space after the ':'), so match that loosely rather than
# assuming compact JSON. The prefix match uses a bash `case` glob, not
# `grep "^$1"`: sbx names allow periods and plus signs, both regex
# metacharacters that a grep anchor would misinterpret and could match sandboxes
# outside this kit's own prefix. `*`/`?` are the only glob metacharacters and sbx
# names can't contain them, so this is safe for every name sbx will accept.
list_sandboxes_matching() {
  sbx --app-name "$APP_NAME" ls --json 2>/dev/null \
    | grep -o '"name":[[:space:]]*"[^"]*"' \
    | cut -d'"' -f4 \
    | while IFS= read -r name; do
        case "$name" in
          "$1"*) printf '%s\n' "$name" ;;
        esac
      done
}

# A sandbox from a previous FAILED run of this same kit is deliberately left
# behind (see the on_exit trap) so its policy log survives for post-mortem
# inspection. That means a stale one can exist when this script starts; remove it
# now so it doesn't pile up indefinitely across repeated local debugging
# iterations. Best-effort: nothing to clean up is the common case, not an error.
for stale in $(list_sandboxes_matching "$kit_sandbox_prefix"); do
  echo "Removing stale sandbox from a previous failed run: $stale"
  sbx --app-name "$APP_NAME" rm -f "$stale" >/dev/null 2>&1 || true
done

# Configure the scoped daemon's global network policy. `policy init` is one-time
# per daemon (sbx errors with "already initialized" on the second call), so to
# stay idempotent we try `init` first and fall back to a reset when a policy is
# already set — that lands the scoped daemon on the desired baseline regardless of
# prior state (a reused local daemon is the normal case; CI runners are always
# fresh, so the first `init` succeeds there). The `--force` skips the confirmation
# prompt about stopping running sandboxes (a stale one from a previous failed run
# was just removed above; a currently-running sandbox here would mean a concurrent
# invocation, which isn't a supported use of this script). Skipped when POLICY is
# explicitly set to the empty string.
if [ -n "$POLICY" ]; then
  echo "Initializing --app-name=$APP_NAME global policy to $POLICY"
  if ! sbx --app-name "$APP_NAME" policy init "$POLICY" >/dev/null 2>&1; then
    # `policy reset` wipes the store, restarts the daemon, and then — when its
    # stdin is a terminal — opens the interactive policy chooser ITSELF, which is
    # how a reused daemon ended up on allow-all/balanced behind this script's
    # back. With stdin from /dev/null it skips the chooser and may exit non-zero
    # complaining the policy is not initialized: that is exactly the state we
    # want, so its exit code is ignored and the `init` below is the real check.
    reset_out=$(sbx --app-name "$APP_NAME" policy reset --force </dev/null 2>&1) || true
    printf '%s\n' "$reset_out"
    # `init` sets the preset and prints 'Global network policy initialized to
    # "<preset>"'. If anything else initialized the policy first, `init` fails as
    # already initialized, which aborts the run instead of testing under a
    # baseline we did not ask for.
    init_out=$(sbx --app-name "$APP_NAME" policy init "$POLICY" </dev/null 2>&1) || {
      printf '%s\n' "$init_out" >&2
      echo "ERROR: could not re-initialize the --app-name=$APP_NAME global policy to $POLICY after reset" >&2
      exit 1
    }
    printf '%s\n' "$init_out"
  fi
fi

# A fresh temp directory as the sandbox's workspace, never the repo: a workspace
# is mounted read-write at /home/agent/workspace inside the sandbox, and handing
# a kit under test the checkout it was built from is a needless blast radius.
workspace=$(mktemp -d "${TMPDIR:-/tmp}/sbx-e2e-workspace-XXXXXX") || {
  echo "ERROR: could not create a temp workspace directory" >&2
  exit 1
}

# Auto-diagnose on failure. The most common e2e failure is a host the kit reaches
# for but does not declare, which `sbx policy log` surfaces precisely. In CI the
# runner and its scoped daemon are destroyed the moment the job ends, so printing
# instructions for a human to run afterward is useless there — by the time anyone
# reads the log there is nothing left to inspect. So run the diagnostics here and
# print the real output, making a CI failure debuggable from the job log alone.
#
# Wired as an EXIT trap (not ERR) so it also fires when `set -e` aborts mid-run.
# Every diagnostic call is best-effort (`|| true`): if the scoped daemon is itself
# wedged or already gone, that failure must not mask the original exit code.
#
# Unlike the v2 version of this script, the sandbox name does not have to be
# recovered from a file the Go harness wrote: this script chose the name itself
# and passed it to `--name`, so the name is known even when `sbx run` rolled the
# sandbox back on a failed build or kit-apply and `sbx ls` shows nothing at all.
# The daemon's policy log is independent of the sandbox object's lifetime (a
# daemon-level log filtered by VM name), so `policy log <name>` still works after
# such a rollback.
#
# `stage` names what the script was doing, and the trap uses it to print only the
# diagnostics that can still be relevant. It is set here so the trap can never
# read it unset, and updated in step with the run below.
stage=startup
rename_dirs=""
on_exit() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "" >&2
    echo "e2e test failed (exit $rc) during: ${stage}." >&2

    # The blocked-request check below prints the log and explains it itself, so
    # re-printing here would just bury its message under a copy of itself.
    if [ "$stage" != "egress check" ]; then
      echo "" >&2
      echo "Policy log for sandbox $sandbox_name (policy: ${POLICY:-current default}):" >&2
      if policy_log_out=$(sbx --app-name "$APP_NAME" policy log "$sandbox_name" 2>&1); then
        echo "$policy_log_out" >&2
        case "$policy_log_out" in
          *"Blocked requests"*)
            cat >&2 <<EOF

Every row under 'Blocked requests' above is a host this kit reached for. Add it
to the right phase of the kit's com.docker.sandbox/network-policy@1 config and
re-run. Phase matters: a host a lifecycle install hook reaches belongs under
\`install\`, a host the agent reaches at steady state belongs under \`runtime\`,
and an absent phase grants nothing.
EOF
            ;;
          *)
            cat >&2 <<EOF

The policy log above reported no blocked requests, so this failure is probably
not egress-related.
EOF
            ;;
        esac
      else
        echo "$policy_log_out" >&2
        cat >&2 <<EOF

The policy log could not be read, so this failure could not be ruled
egress-related or not.
EOF
      fi
    fi

    # The daemon's own log. The daemon does not log the cause behind its
    # `failed to run sandbox container` catch-all, so this rarely names the
    # fault, but it does show what the daemon was doing. The scoped daemon
    # publishes a short alias to its state dir; resolve that rather than guess
    # the nested storage layout.
    daemon_log=""
    for alias in "/tmp/sboxd-$(id -u)-${APP_NAME}" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/*/"${APP_NAME}"/d; do
      [ -e "$alias" ] || continue
      state_dir=$(readlink -f "$alias" 2>/dev/null) || continue
      [ -f "$state_dir/daemon.log" ] && { daemon_log="$state_dir/daemon.log"; break; }
    done
    [ -n "$daemon_log" ] || daemon_log=$(find "${XDG_STATE_HOME:-$HOME/.local/state}" -path "*/${APP_NAME}/*" -name daemon.log 2>/dev/null | head -1)
    if [ -n "$daemon_log" ]; then
      echo "" >&2
      echo "Daemon log ($daemon_log), lines mentioning $sandbox_name or the last 60:" >&2
      if grep -F -- "$sandbox_name" "$daemon_log" 2>/dev/null | tail -60 | grep -q .; then
        grep -F -- "$sandbox_name" "$daemon_log" 2>/dev/null | tail -60 >&2
      else
        tail -60 "$daemon_log" >&2 || true
      fi
    else
      echo "" >&2
      echo "(no daemon.log found for app-name $APP_NAME)" >&2
    fi

    # Only worth raising while the kit was still being resolved or composed: past
    # that point the base demonstrably worked.
    if [ "$kind" = "mixin" ] && { [ "$stage" = "inspect" ] || [ "$stage" = "run" ]; }; then
      cat >&2 <<EOF

This is a mixin, composed onto '${host}', chosen from ${host_source}. If the
failure was a requirement that would not resolve, the base is the first thing to
question — override it with E2E_HOST=<built-in agent>|./<workload-kit>.
EOF
    fi

    cat >&2 <<EOF

The sandbox was left in place for inspection:
'sbx --app-name $APP_NAME exec $sandbox_name -- ...'. The next run of this script
removes any such leftover automatically before starting.

If the scoped daemon is wedged, wipe it (your main sbx is unaffected):

  sbx --app-name $APP_NAME reset --force

If you haven't logged in to the scoped daemon yet:

  sbx --app-name $APP_NAME login

EOF
  fi
  rm -rf "$workspace"
  # Each rename retry makes its own temp parent; there is at most one of the
  # kit and one of the base, but the loop costs nothing and does not assume.
  for d in ${rename_dirs:-}; do rm -rf "$d"; done
  exit "$rc"
}
trap on_exit EXIT

# Pre-flight: can sbx load and resolve this kit at all? `sbx kit inspect` takes a
# v3 kit in source form, builds it and prints the resolved declarations, so a
# descriptor sbx cannot resolve fails here — in seconds, with the resolution error
# — instead of minutes later inside a sandbox create.
#
# `sbx kit validate` is NOT the command for this: its load path has no kit builder
# configured, so it rejects a v3 source kit outright. Do not "fix" the line below
# by switching to validate.
stage=inspect
echo "==> sbx kit inspect ${kit_abs}"
# Inspect builds the kit, so a kit with a required argument needs KIT_ARGS here too.
sbx --app-name "$APP_NAME" kit inspect "$kit_abs" $kit_arg_flags </dev/null

# The run itself. `-d` starts the sandbox and prints its ID without opening an
# agent session, which is the supported non-interactive path — a plain `sbx run`
# wants a terminal. For a workload the kit IS the agent, so it is the positional;
# for a mixin the base is the positional and the kit rides in on `--kit`.
#
# $kit_arg_flags and the forwarded "$@" are deliberately unquoted/word-split: they
# are flag lists assembled above, not single values.
stage=run
echo "==> sbx run -d --name ${sandbox_name} (workspace ${workspace})"

# staged_name is the stem the composed sandbox stages this kit's sources under.
# It follows a rename, which is why the agent-context check below reads it
# rather than $kit_name.
staged_name=$kit_name

# Output is captured, not streamed, because the retry decision is made on it.
# It is echoed either way, so a passing run reads as it did before and a failing
# one still shows sbx's own message before this script's diagnosis.
# run_kit <kit-path> <base|""> [forwarded args...]
# The first two are positional because they are what a retry swaps; everything
# after them is the caller's forwarded "$@" and is passed through untouched.
run_kit() {
  rk_kit=$1
  rk_host=$2
  shift 2
  if [ "$kind" = "workload" ]; then
    sbx --app-name "$APP_NAME" run -d --name "$sandbox_name" \
      $kit_arg_flags "$@" "$rk_kit" "$workspace" </dev/null 2>&1
  else
    sbx --app-name "$APP_NAME" run -d --name "$sandbox_name" \
      --kit "$rk_kit" $kit_arg_flags "$@" "$rk_host" "$workspace" </dev/null 2>&1
  fi
}

if [ "$kind" = "workload" ]; then
  if run_out=$(run_kit "$kit_abs" "" "$@"); then
    printf '%s\n' "$run_out"
  else
    printf '%s\n' "$run_out"
    case "$run_out" in
      *"$builtin_collision_marker"*)
        renamed=$(copy_kit_renamed "$kit_abs") || exit 1
        staged_name=$(basename "$renamed")
        # --kit-arg is scoped `<kit>.<arg>=<value>`, so the scope has to follow
        # the rename or this kit's own arguments stop reaching it.
        if [ -n "${KIT_ARGS:-}" ]; then
          kit_arg_flags=""
          for pair in $KIT_ARGS; do
            kit_arg_flags="$kit_arg_flags --kit-arg ${staged_name}.${pair}"
          done
        fi
        echo "==> NOTICE: a built-in agent already holds the name '${kit_name}';" \
             "retrying from a copy renamed '${staged_name}'"
        run_out=$(run_kit "$renamed" "" "$@") || { printf '%s\n' "$run_out"; exit 1; }
        printf '%s\n' "$run_out"
        ;;
      *) exit 1 ;;
    esac
  fi
else
  # The BASE can collide too: every mixin without its own affinity now composes
  # onto ./claude, and `claude` is one of the names a built-in holds. Only a
  # local-path base can be renamed — a built-in agent name or a registry
  # reference is not this repo's directory to copy.
  if run_out=$(run_kit "$kit_abs" "$host" "$@"); then
    printf '%s\n' "$run_out"
  else
    printf '%s\n' "$run_out"
    case "$run_out" in
      *"$builtin_collision_marker"*)
        case "$host" in
          ./*)
            renamed_host=$(copy_kit_renamed "$REPO_ROOT/${host#./}") || exit 1
            echo "==> NOTICE: a built-in agent already holds the base's name" \
                 "('${host}'); retrying with a copy renamed '$(basename "$renamed_host")'"
            run_out=$(run_kit "$kit_abs" "$renamed_host" "$@") || { printf '%s\n' "$run_out"; exit 1; }
            printf '%s\n' "$run_out"
            ;;
          *)
            echo "ERROR: the base '${host}' collides with a built-in agent name and is" >&2
            echo "       not a local path, so it cannot be renamed. Set E2E_HOST to a" >&2
            echo "       ./<workload-kit> in this repo." >&2
            exit 1
            ;;
        esac
        ;;
      *) exit 1 ;;
    esac
  fi
fi

# The sandbox exists; prove it is usable. `sbx run` returning is not quite the
# same claim — it reports that create and kit-apply succeeded, while this
# round-trips a command through the running VM.
stage="sandbox check"
echo "==> sbx exec ${sandbox_name} -- true"
sbx --app-name "$APP_NAME" exec "$sandbox_name" -- true </dev/null

# A kit declaring agent-context@1 with a contentFile promises the runtime a file
# it can read from inside the sandbox. The frontend rewrites the descriptor's
# relative path to the staged absolute one at build time, so the composed sandbox
# must carry it at /usr/share/sandbox/kit/<kit>/<file>. kit-tck checks that the
# ARTIFACT stages it; this checks that composing the kit actually landed it, which
# is the half a conformance run cannot see. `test -s` and not `test -f`: an empty
# context file is a kit whose guidance silently says nothing.
# Comments are stripped BEFORE matching: eight descriptors here carry a prose
# comment mentioning `contentFile:`, and matching one yields a staged path made
# of English, which the check below then fails on.
context_file=$(awk '
  {
    line = $0
    sub(/#.*/, "", line)
    if (line ~ /^[[:space:]]*contentFile:[[:space:]]*[^[:space:]]/) {
      sub(/^[[:space:]]*contentFile:[[:space:]]*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      gsub(/^["'"'"']|["'"'"']$/, "", line)
      print line
      exit
    }
  }
' "$descriptor")
if [ -n "$context_file" ]; then
  stage="agent-context check"
  staged="/usr/share/sandbox/kit/${staged_name}/$(basename "$context_file")"
  echo "==> checking agent context landed at ${staged}"
  sbx --app-name "$APP_NAME" exec "$sandbox_name" -- test -s "$staged" </dev/null
fi

# THE CONTRACT TEST, AND WHY IT RUNS ON SUCCESS
#
# Under a deny-all default, a blocked request does not reliably fail anything. A
# lifecycle hook that pipes an unchecked `curl -s` into a parser succeeds with
# empty input — github-ssh's install hook is exactly that shape: blocking
# api.github.com leaves `jq` reading nothing, writing an empty known_hosts, and
# exiting 0. The kit is then silently inert: the host keys it exists to pin were
# never fetched, and every other check here still passes.
#
# So the policy log is read on the SUCCESS path too, and a blocked request fails
# the run. This is what makes the e2e a test of the kit's declared egress rather
# than an assumption about it. v2 only consulted the log when something else had
# already failed, which missed this entire class.
#
# Skipped when POLICY was cleared, because without a default deny there is nothing
# to block. ALLOW_BLOCKED=1 downgrades it to a warning while iterating on a kit.
#
# Hosts a kit leaves unreachable on purpose (telemetry, update checks) are the
# user's call to open, so the kit lists them in testdata/e2e-expected-blocked
# and only a block outside that list fails. Ports and the resolver's search
# suffix (`<host>.<sandbox>.docker.internal` on DNS blocks) are stripped first.
expected_blocked_file="$kit_abs/testdata/e2e-expected-blocked"
if [ -n "$POLICY" ]; then
  stage="egress check"
  echo "==> checking the policy log for blocked requests"
  policy_log=$(sbx --app-name "$APP_NAME" policy log "$sandbox_name" 2>&1) || {
    echo "WARNING: could not read the policy log, so declared egress could not be verified:" >&2
    printf '%s\n' "$policy_log" >&2
    policy_log=""
  }
  case "$policy_log" in
    *"Blocked requests"*)
      printf '%s\n' "$policy_log"
      blocked_hosts=$(printf '%s\n' "$policy_log" | awk -v sb="$sandbox_name" '
          /^Blocked requests:/ { in_blocked = 1; next }
          /^Allowed requests:/ { in_blocked = 0 }
          in_blocked && $1 == sb {
            host = $3
            sub(/:[0-9]+$/, "", host)
            sub("\\." sb "\\.docker\\.internal$", "", host)
            print host
          }' | sort -u)
      expected_blocked=""
      if [ -f "$expected_blocked_file" ]; then
        expected_blocked=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$expected_blocked_file" | grep -v '^$' | sort -u)
      fi
      # An empty pattern file would make grep -F match every line, so an empty
      # expected list is handled without grep.
      if [ -n "$expected_blocked" ]; then
        unexpected_blocked=$(printf '%s\n' "$blocked_hosts" | grep -vxF -f <(printf '%s\n' "$expected_blocked") || true)
      else
        unexpected_blocked=$blocked_hosts
      fi
      if [ -z "$unexpected_blocked" ]; then
        echo "Every blocked host is listed in ${expected_blocked_file#"$kit_abs/"}; the kit leaves them unreachable on purpose."
      elif [ -n "${ALLOW_BLOCKED:-}" ]; then
        echo "WARNING: blocked requests above; ALLOW_BLOCKED is set, so continuing." >&2
      else
        cat >&2 <<EOF

ERROR: $kit_name reached hosts it does not declare:
$unexpected_blocked

The run otherwise succeeded, which is exactly the trap: a blocked request often
leaves a hook quietly doing nothing instead of failing.

Add each host to the right phase of the kit's com.docker.sandbox/network-policy@1
config (\`install\` for a lifecycle install hook, \`runtime\` for the agent's
steady state; an absent phase grants nothing). If the kit leaves the host
unreachable on purpose, list it in testdata/e2e-expected-blocked instead. Or set
ALLOW_BLOCKED=1 to proceed anyway while iterating.
EOF
        exit 1
      fi
      ;;
  esac
fi

echo ""
echo "PASS: ${kit_name} (${kind}) composed, booted and stayed inside its declared egress."

# Remove the sandbox on the way out. Only on success: a failing run leaves it for
# post-mortem (the on_exit trap says so), and the next run of this script sweeps
# it up.
if [ -z "${KEEP_SANDBOX:-}" ]; then
  echo "==> removing sandbox ${sandbox_name}"
  sbx --app-name "$APP_NAME" rm -f "$sandbox_name" >/dev/null 2>&1 || true
else
  echo "==> KEEP_SANDBOX set; sandbox ${sandbox_name} left in place"
fi
