package spec

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

// licenses is a real declarative metadata field (SPDX identifiers governing
// the kit), not a forward-compat stub. Unlike mixins/sandbox.build it decodes,
// validates, and carries onto the Artifact with no "not yet implemented"
// warning. These tests pin that contract.

func TestLicenses_DecodeAndCarry(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
licenses:
  - MIT
  - Apache-2.0
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Equal(t, []string{"MIT", "Apache-2.0"}, art.Licenses,
		"licenses must round-trip onto Artifact.Licenses unchanged")
	require.False(t, hasWarningContaining(art.Warnings, "licenses"),
		"licenses is a real field and must not emit a not-yet-implemented warning, got: %v", art.Warnings)
}

func TestLicenses_Absent_NoError(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Empty(t, art.Licenses)
}

// LoadFromDirectory runs ValidateArtifact (unlike LoadArtifactFromBytes, which only
// decodes/normalizes), so a malformed licenses list is rejected on a real
// disk load — the path the engine and migration script use.
func TestLicenses_InvalidRejectedAtLoad(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`schemaVersion: "2"
kind: sandbox
name: test-kit
licenses:
  - MIT
  - ""
sandbox:
  image: my-image
`), 0o644))

	_, err := LoadFromDirectory(dir)
	require.ErrorContains(t, err, "must not be empty")
}
