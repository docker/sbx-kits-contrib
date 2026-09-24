#!/bin/sh
# Parses SNYK_COMPONENTS (comma-separated: scan, guard, studio; default "scan")
# and prints `scan=0|1 guard=0|1 studio=0|1 auth_mode=enterprise|standalone|none`
# for callers to `eval`. Only validates the shape of SNYK_COMPONENTS itself
# (unknown/empty selection); it does not require credentials for a selected
# component. Install steps run unconditionally regardless of auth_mode -
# callers that need a credential to actually do something (guard install,
# scan) check auth_mode themselves and skip with a clear message if it's
# insufficient, rather than failing sandbox creation.
set -eu

auth_mode="$(sh "$(dirname "$0")/auth.sh")"

raw="${SNYK_COMPONENTS:-scan}"
normalized="$(printf '%s' "$raw" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"

scan=0
guard=0
studio=0
for component in $normalized; do
  case "$component" in
    scan) scan=1 ;;
    guard) guard=1 ;;
    studio) studio=1 ;;
    *)
      echo "snyk-ads: ERROR unknown component '$component' in SNYK_COMPONENTS (expected: scan, guard, studio)." >&2
      exit 1
      ;;
  esac
done

if [ "$scan" = 0 ] && [ "$guard" = 0 ] && [ "$studio" = 0 ]; then
  echo "snyk-ads: ERROR SNYK_COMPONENTS ('$raw') resolved to no components; expected a comma-separated list of scan, guard, studio." >&2
  exit 1
fi

echo "scan=$scan guard=$guard studio=$studio auth_mode=$auth_mode"
