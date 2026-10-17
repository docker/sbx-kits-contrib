package spec

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// hasWarningContaining reports whether any warning message contains sub.
func hasWarningContaining(warnings []string, sub string) bool {
	for _, w := range warnings {
		if strings.Contains(w, sub) {
			return true
		}
	}
	return false
}

// P1 forward-compat fields (mixins, sandbox.build) are accepted at decode
// time so kits and the published v2 docs can declare them, but neither is
// wired to runtime behavior yet. These tests pin that contract: the fields
// decode and round-trip, a load-time warning fires on use, and a build-only
// kit is rejected with an actionable error.

func TestMixins_DecodeAndWarn(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
mixins:
  - dhi.io/python:3-debian13
  - pandas
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Equal(t, []string{"dhi.io/python:3-debian13", "pandas"}, art.Mixins,
		"mixins must round-trip onto Artifact.Mixins unchanged")
	require.True(t, hasWarningContaining(art.Warnings, "mixins"),
		"using mixins must emit a not-yet-implemented warning, got: %v", art.Warnings)
}

func TestMixins_Absent_NoWarning(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
sandbox:
  image: my-image
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Empty(t, art.Mixins)
	require.False(t, hasWarningContaining(art.Warnings, "mixins"),
		"no mixins declared must not warn, got: %v", art.Warnings)
}

func TestBuild_WithImage_DecodesWarnsAndUsesImage(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
sandbox:
  image: my-image
  build:
    context: .
    dockerfile: Dockerfile
    args:
      AGENT_VERSION: "1.4.2"
    target: runtime
    platforms:
      - linux/amd64
      - linux/arm64
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)

	// Image remains the source of truth this release.
	require.Equal(t, "my-image", art.Manifest.Template)

	// build: decodes and round-trips onto the Manifest.
	require.NotNil(t, art.Manifest.Build)
	require.Equal(t, ".", art.Manifest.Build.Context)
	require.Equal(t, "Dockerfile", art.Manifest.Build.Dockerfile)
	require.Equal(t, map[string]string{"AGENT_VERSION": "1.4.2"}, art.Manifest.Build.Args)
	require.Equal(t, "runtime", art.Manifest.Build.Target)
	require.Equal(t, []string{"linux/amd64", "linux/arm64"}, art.Manifest.Build.Platforms)

	require.True(t, hasWarningContaining(art.Warnings, "sandbox.build"),
		"using build must emit a not-yet-implemented warning, got: %v", art.Warnings)
}

func TestRequires_DecodeAndValidate(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: mixin
name: claude-model-runner
requires:
  agent: claude
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.NotNil(t, art.Requires, "requires must decode onto Artifact.Requires")
	require.Equal(t, "claude", art.Requires.Agent,
		"requires.agent must round-trip onto Artifact.Requires.Agent unchanged")
	// Affinity is enforced by the composing consumer, not the spec library,
	// so declaring it must not emit a not-implemented warning.
	require.False(t, hasWarningContaining(art.Warnings, "requires"),
		"declaring requires must not warn, got: %v", art.Warnings)
}

func TestRequires_Absent(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: mixin
name: plain-mixin
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.Nil(t, art.Requires, "absent requires must leave Artifact.Requires nil")
}

func TestRequires_InvalidAgentName_Rejected(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: mixin
name: bad-affinity
requires:
  agent: "Not A Name"
`)
	// LoadArtifactFromBytes decodes but does not validate (per its contract);
	// well-formedness is enforced by ValidateArtifact on the load-from-disk
	// paths, so validate the decoded artifact explicitly here.
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	require.ErrorContains(t, ValidateArtifact(art), "requires.agent")
}

func TestExtends_SandboxWithoutImage_Loads(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: claude-model-runner
extends: claude
environment:
  variables:
    ANTHROPIC_BASE_URL: "http://host.docker.internal:12434"
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err, "a sandbox kit that extends a parent may omit sandbox.image")
	require.Equal(t, "claude", art.Extends)
	require.Empty(t, art.Manifest.Template,
		"leaf carries no image; it is inherited from the extends parent at resolve time")
}

func TestBuild_Only_Rejected(t *testing.T) {
	yaml := []byte(`
schemaVersion: "2"
kind: sandbox
name: test-kit
sandbox:
  build:
    context: .
    dockerfile: Dockerfile
`)
	_, err := LoadArtifactFromBytes(yaml)
	require.Error(t, err)
	require.ErrorContains(t, err, "sandbox.build is accepted in the schema but not yet implemented")
	require.ErrorContains(t, err, "specify sandbox.image")
}
