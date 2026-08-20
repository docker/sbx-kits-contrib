// Validates a migrated kit spec, and optionally confirms it's semantically
// identical to another directory's spec — the check a v1→v2 migration runs
// after hand-restoring comments the mechanical rewrite dropped, to prove the
// restoration didn't change what the spec actually means.
//
// Usage:
//
//	go run ./scripts/verify-kit-spec <kit-dir>
//	go run ./scripts/verify-kit-spec <kit-dir> <compare-dir>
//
// With one argument: loads <kit-dir> through the same path `sbx kit
// validate`/`sbx kit inspect` use (spec.OpenFromDirectory already validates
// internally), and additionally fails if Artifact.Warnings is non-empty —
// this environment has no `sbx` binary to run those commands directly, so
// this is the equivalent check.
//
// With two arguments: additionally loads <compare-dir> and fails unless both
// parse to the same spec, ignoring Artifact.Files — migrate-v1-to-v2.go only
// ever reads and writes spec.yaml, so <compare-dir> only needs a spec.yaml
// (e.g. a scratch copy regenerated fresh from the original v1 backup, with
// no comments restored); it has no files/, Dockerfile, or icons/ tree to
// compare, and forcing that tree to match would compare something this tool
// was never meant to check. Typical use: prove a hand-edited
// comment-restoration pass didn't alter any field.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"

	"github.com/docker/sbx-kits-contrib/spec"
)

func main() {
	if len(os.Args) != 2 && len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: verify-kit-spec <kit-dir> [<compare-dir>]")
		os.Exit(2)
	}

	a := loadOrExit(os.Args[1])

	if len(os.Args) != 3 {
		return
	}

	b := loadOrExit(os.Args[2])

	// Files reflects the whole kit directory's tree, which this tool's
	// two-directory comparison was never meant to check (see the doc
	// comment above) — cleared here rather than compared. a and b are not
	// used after this, so mutated in place rather than copied first.
	a.Files, b.Files = nil, nil

	if !reflect.DeepEqual(a, b) {
		fmt.Fprintln(os.Stderr, "MISMATCH: the two directories' specs differ (Files excluded from this comparison)")
		fmt.Fprintln(os.Stderr, os.Args[1]+":", marshalOrExit(a))
		fmt.Fprintln(os.Stderr, os.Args[2]+":", marshalOrExit(b))
		os.Exit(1)
	}
	fmt.Println("MATCH: both directories' specs are identical (Files excluded)")
}

// loadOrExit loads and validates dir, additionally rejecting any warning
// (spec.OpenFromDirectory validates but does not treat a warning as fatal —
// a migrated kit should have none). Uses the streaming path: validation and
// the two-directory comparison only ever need Target/RelativePath, never
// file content, so there's nothing to gain from reading files/ eagerly.
// Exits the process on any failure.
func loadOrExit(dir string) *spec.Artifact {
	a, err := spec.OpenFromDirectory(dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: load %s: %v\n", dir, err)
		os.Exit(1)
	}
	if len(a.Warnings) > 0 {
		fmt.Fprintf(os.Stderr, "error: %s has %d warning(s): %v\n", dir, len(a.Warnings), a.Warnings)
		os.Exit(1)
	}
	fmt.Printf("%s: valid, no warnings\n", dir)
	return a
}

func marshalOrExit(a *spec.Artifact) string {
	b, err := json.Marshal(a)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error: marshal:", err)
		os.Exit(1)
	}
	return string(b)
}
