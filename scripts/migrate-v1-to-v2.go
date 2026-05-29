// Command migrate-v1-to-v2 walks a kit artifact directory, rewrites its
// spec.yaml from schemaVersion 1 to schemaVersion 2, and writes a `.bak`
// of the original. It is the mechanical companion to the v2 spec-package
// breaking changes — kit authors run it once to convert their kit
// without hand-editing every renamed field.
//
// Usage:
//
//	go run scripts/migrate-v1-to-v2.go <path-to-kit-directory>
//
// The script is INCREMENTAL: it ships with the v2 migration in stages,
// each phase adding the transforms for that phase. Today's scope is the
// Phase 1 cosmetic renames:
//
//	memory:    → agentContext:
//	kind: agent → kind: sandbox
//	agent:     → sandbox:
//
// Later phases will extend the transforms as their PRs land. See
// sandboxes/docs/specs/2026-05-27-unified-kit-spec-v2.md for the
// migration roadmap.
//
// The script is intentionally STANDALONE: it has no module dependencies
// outside the Go standard library, so kit authors can run it via
// `go run` against any checkout without needing to pull the rest of
// sbx-kits-contrib.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: migrate-v1-to-v2 <kit-directory>")
		os.Exit(2)
	}
	if err := migrate(os.Args[1], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

// migrate runs the in-place migration on the spec.yaml under kitDir.
// All progress messages are written to w; the only error condition is
// a real I/O or contract failure (missing spec.yaml, refuse to clobber
// an existing .bak, etc.). A migrated spec with no transforms required
// is a successful no-op.
func migrate(kitDir string, w io.Writer) error {
	specPath, err := findSpec(kitDir)
	if err != nil {
		return err
	}

	original, err := os.ReadFile(specPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", specPath, err)
	}

	migrated, changes := applyPhase1Transforms(string(original))

	if len(changes) == 0 {
		fmt.Fprintf(w, "no changes needed in %s\n", specPath)
		return nil
	}

	bakPath := specPath + ".bak"
	if _, err := os.Stat(bakPath); err == nil {
		return fmt.Errorf("%s already exists; refusing to clobber an existing backup", bakPath)
	}
	if err := os.WriteFile(bakPath, original, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", bakPath, err)
	}
	if err := os.WriteFile(specPath, []byte(migrated), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", specPath, err)
	}

	fmt.Fprintf(w, "migrated %s (backup at %s)\n", specPath, bakPath)
	for _, c := range changes {
		fmt.Fprintf(w, "  - %s\n", c)
	}
	return nil
}

// findSpec returns the path to spec.yaml (or spec.yml) under kitDir,
// or an error if neither exists.
func findSpec(kitDir string) (string, error) {
	for _, name := range []string{"spec.yaml", "spec.yml"} {
		path := filepath.Join(kitDir, name)
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("no spec.yaml or spec.yml found in %s", kitDir)
}

// Phase 1 transforms: rename three top-level YAML keys/values. Anchored
// to the start of a line so nested keys with the same name (unlikely but
// possible) are left alone. Each transform reports the change in
// human-readable form for the migration summary.

var (
	kindAgentRE  = regexp.MustCompile(`(?m)^kind:\s*agent\s*$`)
	agentBlockRE = regexp.MustCompile(`(?m)^agent:`)
	memoryFieldRE = regexp.MustCompile(`(?m)^memory:`)
)

// applyPhase1Transforms runs the Phase 1 v1 → v2 renames on src. Returns
// the rewritten YAML and a list of human-readable change descriptions
// (empty when no transforms applied).
func applyPhase1Transforms(src string) (string, []string) {
	var changes []string

	if kindAgentRE.MatchString(src) {
		src = kindAgentRE.ReplaceAllString(src, "kind: sandbox")
		changes = append(changes, "kind: agent → kind: sandbox")
	}
	if agentBlockRE.MatchString(src) {
		src = agentBlockRE.ReplaceAllString(src, "sandbox:")
		changes = append(changes, "agent: block → sandbox: block")
	}
	if memoryFieldRE.MatchString(src) {
		src = memoryFieldRE.ReplaceAllString(src, "agentContext:")
		changes = append(changes, "memory: → agentContext:")
	}

	return src, changes
}
