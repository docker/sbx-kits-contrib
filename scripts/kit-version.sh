#!/usr/bin/env bash
# Resolve the version a kit publishes under.
#
# Usage:
#   scripts/kit-version.sh <kit>     # print that kit's version
#   scripts/kit-version.sh --all     # print <kit> <TAB> <version> <TAB> <source>
#
#   scripts/kit-version.sh claude
#   scripts/kit-version.sh --all
#
# One resolver, two callers that must never disagree: publish-kit.sh tags the
# image with this, and check-release-tag.sh refuses a `<kit>/vX.Y.Z` tag that
# names something else. Those used to be two copies of one awk snippet reading
# a literal `version:`; in v3 the field is usually a reference, so the rule got
# too big to keep in two places.
#
# THE RULE, in order. The first source that answers wins:
#
#   1. literal    a top-level `version:` that is a plain string. The kit names
#                 its own release. Used by kits that ship no tool of their own
#                 (github-ssh, ecc) or whose tool cannot be pinned.
#
#   2. arg        a top-level `version:` of the form `${{ kit.args.<name> }}`,
#                 resolved to that build-phase arg's `default:`. This is the
#                 common case: the kit's version, the installer's pin and the
#                 `provides:` entry are all one number, so bumping the arg bumps
#                 the published tag with it. Any arg name is followed, not just
#                 `version` — the reference says which.
#
#   3. arg,       no top-level `version:` at all, but an arg literally named
#      implicit   `version` carrying a default. Same number as (2) would give;
#                 the kit just never wrote the field, because `provides:` is
#                 already expanded from that arg and the field would restate it.
#
#   4. provides   no `version:` and no `version` arg, but a single `provides:`
#                 entry pinned as `<name>@<version>`. Nine kits are shaped this
#                 way (lighthouse, mise, packages-through-sfw, playwright,
#                 smolagents, task, trivy, trivy-mixin, vale): they install one
#                 tool at one hard-coded version with no arg to vary it, so the
#                 provide IS the declaration of what the kit ships.
#
# On (4), which is the rule that needed arguing for. It reads as a stretch next
# to the first three, and the temptation is to refuse those nine and make them
# declare a `version:`. The reason not to: sources 2, 3 and 4 are all the same
# statement — "this kit's version is the version of the thing it provides" —
# written at three different levels of indirection, and (4) is simply the one
# with no indirection left to follow. Refusing it would mean nine kits cannot
# publish until someone adds a field restating a number already in the file, on
# pain of getting the restatement wrong. A single pinned provide is required,
# not just the first of several: a kit providing two tools has no one version,
# and guessing which one speaks for the kit is how a tag comes to name the
# wrong thing.
#
# A kit answering to NONE of the four cannot publish — there is no version to
# tag it with, and inventing one (0.0.0, the date, the sha) would put a number
# on the image that describes nothing. Fail, loudly, naming the four things
# that would have worked.
#
# Parsed with awk rather than a YAML library, for the same reason the rest of
# this directory is: it gates the build, so it runs before any toolchain is set
# up, and a resolver that needs installing is a resolver that can't fail the
# build early. The shapes it accepts are narrower than YAML — block mappings at
# fixed indents, a single-line flow sequence for `provides:` — which is every
# shape the 87 descriptors in this repo actually use, and a descriptor written
# some other legal way fails loudly here rather than resolving to something
# plausible and wrong.
#
# Exit codes: 0 resolved · 1 unresolvable · 2 usage error.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# resolve() answers through these rather than on stdout, so a caller can have
# both halves of the answer without running it twice. The source is only
# printed by --all, but it is what makes a surprising version diagnosable:
# "claude 2.1.267" is not obviously right or wrong until you know it came from
# an arg rather than a literal.
RESOLVED_VERSION=""
VERSION_SOURCE=""

usage() {
  echo "usage: $0 <kit>        # print the version that kit publishes under" >&2
  echo "       $0 --all        # print <kit> <version> <source> for every kit" >&2
  exit 2
}

descriptor() {
  local kit=$1
  if [ -f "$REPO_ROOT/$kit/$kit.yaml" ]; then
    printf '%s\n' "$REPO_ROOT/$kit/$kit.yaml"
  elif [ -f "$REPO_ROOT/$kit/$kit.yml" ]; then
    printf '%s\n' "$REPO_ROOT/$kit/$kit.yml"
  fi
}

# A TOP-LEVEL scalar, column zero only. Anything indented belongs to a
# capability, an arg or a hook, and is not the kit's own.
top_scalar() {
  awk -v key="$2" '
    /^[[:space:]]*#/ { next }
    index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      # Comment first, THEN quotes: stripping quotes first leaves the closing
      # one stranded on `version: "1.0.0"  # note`, and the kit publishes a
      # tag with a quote in it.
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$1"
}

# The `default:` of one named arg under the top-level `args:` block.
#
# Indents are matched EXACTLY — arg names at two spaces, their properties at
# four — rather than as "deeper than the block". Some args carry nested blocks
# of their own (an enum, a per-platform table), and a "deeper than" rule would
# happily return a `default:` from inside one of those as though it were the
# arg's. Every `default:` in this repo's 87 descriptors sits at exactly four
# spaces, so the exact rule costs nothing and cannot be fooled.
arg_default() {
  awk -v want="$2" '
    # A column-zero key ends the args block — and starts it, if it IS args:.
    /^[^[:space:]#]/ { in_args = ($0 ~ /^args:[[:space:]]*$/); in_want = 0; next }
    !in_args { next }
    /^[[:space:]]*#/ { next }
    # An arg name. Each one closes the previous arg, so in_want is reassigned
    # on every name rather than only on a match — otherwise the first matching
    # arg would stay "open" and swallow later args default:.
    /^  [^[:space:]#]/ {
      name = $0
      sub(/^  /, "", name)
      sub(/:.*$/, "", name)
      in_want = (name == want)
      next
    }
    in_want && /^    default:/ {
      sub(/^    default:[[:space:]]*/, "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
  ' "$1"
}

# The version off a `provides:` list holding exactly one pinned entry.
#
# Prints nothing — which the caller reads as "this source has no answer" — for
# an empty list, more than one entry, an unpinned entry (`provides: ["kiro"]`),
# or one whose pin is still an unexpanded `${{ … }}` reference. Each of those
# is a real shape in this repo, and none of them names a version.
sole_provide_version() {
  local raw entry
  raw=$(awk '
    /^[[:space:]]*#/ { next }
    index($0, "provides:") == 1 {
      sub(/^provides:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1")

  # Only the single-line flow form is understood, which is the only form used
  # here. A block sequence would arrive as an empty value and resolve to "no
  # answer" rather than to a wrong one.
  case "$raw" in
    \[*\]) entry=${raw#\[}; entry=${entry%\]} ;;
    *) return 0 ;;
  esac

  # Exactly one entry. A comma means two or more, and two tools have no one
  # version between them.
  case "$entry" in
    *,*) return 0 ;;
  esac

  # Strip surrounding whitespace and quotes.
  entry=$(printf '%s' "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')

  case "$entry" in
    *'${{'*) return 0 ;;   # still a reference; sources 2 and 3 own that case
    *@*) printf '%s\n' "${entry##*@}" ;;
  esac
}

# Sets RESOLVED_VERSION and VERSION_SOURCE, or explains what is missing on
# stderr and returns 1.
resolve() {
  local kit=$1 file declared argname value
  RESOLVED_VERSION=""
  VERSION_SOURCE=""

  file=$(descriptor "$kit")
  if [ -z "$file" ]; then
    echo "error: no kit '${kit}' at the repo root (expected ${kit}/${kit}.yaml)" >&2
    return 1
  fi

  declared=$(top_scalar "$file" version)

  # 1. A literal. Anything that is not a `${{ … }}` reference is the kit's own
  #    version, taken verbatim.
  case "$declared" in
    "") ;;
    *'${{'*) ;;
    *)
      RESOLVED_VERSION=$declared
      VERSION_SOURCE=literal
      return 0
      ;;
  esac

  # 2. A reference. `${{ kit.args.<name> }}`, optionally spaced — resolved to
  #    that arg's default. The arg name is read out of the reference rather
  #    than assumed to be `version`, because the descriptor says which.
  if [ -n "$declared" ]; then
    argname=$(printf '%s' "$declared" |
      sed -n 's/^[[:space:]]*\${{[[:space:]]*kit\.args\.\([A-Za-z0-9_-]*\)[[:space:]]*}}[[:space:]]*$/\1/p')
    if [ -z "$argname" ]; then
      cat >&2 <<EOF

error: ${kit} declares a 'version:' this publisher cannot resolve

  version: ${declared}

Only a plain string or a build-phase arg reference of the form
\${{ kit.args.<name> }} can be turned into a publish tag. An expression over
anything else has no value until the build runs, which is after the tag has to
be chosen.
EOF
      return 1
    fi
    value=$(arg_default "$file" "$argname")
    if [ -z "$value" ]; then
      cat >&2 <<EOF

error: ${kit}'s version references an arg with no default

  version: ${declared}
  arg     : ${argname}

The publisher resolves the tag before the build, so it can only read the
arg's 'default:'. Give args.${argname} a default, or write the version as a
literal.
EOF
      return 1
    fi
    RESOLVED_VERSION=$value
    VERSION_SOURCE="arg:${argname}"
    return 0
  fi

  # 3. No `version:` field, but an arg named `version` — the same number (2)
  #    would have produced, with the restating field left out.
  value=$(arg_default "$file" version)
  if [ -n "$value" ]; then
    RESOLVED_VERSION=$value
    VERSION_SOURCE="arg:version"
    return 0
  fi

  # 4. A single pinned provide. See the header for why this counts.
  value=$(sole_provide_version "$file")
  if [ -n "$value" ]; then
    RESOLVED_VERSION=$value
    VERSION_SOURCE=provides
    return 0
  fi

  cat >&2 <<EOF

error: ${kit} declares no version, so it cannot be published

  descriptor: ${file#"$REPO_ROOT"/}

A kit is published as an image tagged with its own version. Give ${kit} one of:

  * a literal   version: "1.0.0"
  * a reference version: "\${{ kit.args.version }}", with args.version.default set
  * an arg      args.version.default, with no 'version:' field at all
  * a provide   provides: ["<tool>@<version>"] — one entry, pinned
EOF
  return 1
}

[ $# -eq 1 ] || usage

if [ "$1" = "--all" ]; then
  # Every discovered kit, and a non-zero exit if ANY of them is unresolvable —
  # so this doubles as the gate CI runs over the whole repo before building
  # anything. Failures are reported for all kits rather than aborting on the
  # first, because "these four kits need a version" is one fix and four
  # sequential red builds is the same fix found four times.
  failed=0
  while IFS= read -r kit; do
    # Called directly, not through $(…): resolve answers in globals, and a
    # command substitution would run it in a subshell whose assignments die
    # with it.
    if resolve "$kit"; then
      printf '%s\t%s\t%s\n' "$kit" "$RESOLVED_VERSION" "$VERSION_SOURCE"
    else
      failed=$((failed + 1))
    fi
  done < <("$SCRIPT_DIR/discover-kits.sh")

  if [ "$failed" -gt 0 ]; then
    echo >&2 "${failed} kit(s) have no resolvable version."
    exit 1
  fi
  exit 0
fi

case "$1" in
  -*) usage ;;
esac

resolve "$1"
printf '%s\n' "$RESOLVED_VERSION"
