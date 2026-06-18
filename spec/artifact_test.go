package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/stretchr/testify/require"
)

func TestLoadFromDirectory(t *testing.T) {
	t.Run("sample-mixin", func(t *testing.T) {
		a, err := LoadFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)

		require.Equal(t, "sample-mixin", a.Manifest.Name)
		require.Equal(t, KindMixin, a.Manifest.Kind)
		require.Equal(t, "1.0.0", a.Manifest.Version)
		require.Equal(t, "https://example.com/sample-mixin", a.Manifest.SourceURL)
		require.Empty(t, a.Manifest.Template, "mixins have no template")
		require.NotEmpty(t, a.PublishedPorts)
		require.NotNil(t, a.Credentials)
		require.NotNil(t, a.Environment)
		require.NotNil(t, a.Commands)
		require.NotEmpty(t, a.Files, "should have static files")
	})

	t.Run("sample-agent", func(t *testing.T) {
		a, err := LoadFromDirectory("testdata/sample-agent")
		require.NoError(t, err)

		require.Equal(t, "sample-agent", a.Manifest.Name)
		require.Equal(t, KindSandbox, a.Manifest.Kind)
		require.Equal(t, "1.0.0", a.Manifest.Version)
		require.Equal(t, "https://example.com/sample-agent", a.Manifest.SourceURL)
		require.NotEmpty(t, a.Manifest.Template, "agents must have a template")
		require.Equal(t, "sample-bin", a.Manifest.Binary)
		require.Equal(t, []string{"--verbose", "--task-mode"}, a.Manifest.RunOptions)
		require.Equal(t, "SAMPLE.md", a.Manifest.AIFilename)
		require.NotEmpty(t, a.AgentContext)

		// v1 network.publishedPorts is promoted to the canonical top-level
		// PublishedPorts with a deprecation warning steering authors to the
		// v2 spelling (sample-agent-v2 shows the canonical form).
		require.Equal(t, []PublishedPort{{Container: 8080, Protocol: "tcp", Name: "web"}}, a.PublishedPorts)
		var sawPortWarning bool
		for _, w := range a.Warnings {
			if strings.Contains(w, "network.publishedPorts") {
				sawPortWarning = true
			}
		}
		require.True(t, sawPortWarning, "v1 network.publishedPorts must warn; got %v", a.Warnings)
	})

	t.Run("sample-agent-v2", func(t *testing.T) {
		// Canonical schemaVersion 2 reference kit: exercises the full v2
		// surface and must load with ZERO deprecation warnings.
		a, err := LoadFromDirectory("testdata/sample-agent-v2")
		require.NoError(t, err)
		require.Empty(t, a.Warnings, "canonical v2 kit must not emit deprecation warnings")

		require.Equal(t, "sample-agent-v2", a.Manifest.Name)
		require.Equal(t, KindSandbox, a.Manifest.Kind)
		require.Equal(t, "2.0.0", a.Manifest.Version)
		require.Equal(t, "https://example.com/sample-agent-v2", a.Manifest.SourceURL)
		require.Equal(t, "docker/sandbox-templates:shell-docker", a.Manifest.Template)
		require.Equal(t, []string{"sandbox.image"}, a.Locked)

		// Top-level publishedPorts (the v2 home): minimal, full-tcp, and udp forms.
		require.Equal(t, []PublishedPort{
			{Container: 9418},
			{Container: 8080, Protocol: "tcp", Name: "web"},
			{Container: 53, Protocol: "udp", Name: "dns"},
		}, a.PublishedPorts)

		// Egress under caps.network (not the removed network block).
		require.NotNil(t, a.Caps)
		require.NotNil(t, a.Caps.Network)
		require.ElementsMatch(t, []string{"api.anthropic.com", "api.openai.com:443", "*.example.com"}, a.Caps.Network.Allow)
		require.ElementsMatch(t, []string{"telemetry.example.com"}, a.Caps.Network.Deny)

		// Unified credentials[].
		require.Len(t, a.Credentials, 3)
		var services []string
		for _, c := range a.Credentials {
			services = append(services, c.Service)
		}
		require.ElementsMatch(t, []string{"anthropic", "github", "workos"}, services)

		require.Len(t, a.Manifest.Volumes, 2)
		require.NotNil(t, a.Commands)
		require.NotEmpty(t, a.Commands.Startup)
		require.NotEmpty(t, a.Commands.InitFiles)
		require.NotEmpty(t, a.AgentContext)
		require.NotEmpty(t, a.Files, "v2 reference kit ships static files")
	})

	t.Run("missing_directory", func(t *testing.T) {
		_, err := LoadFromDirectory("testdata/does-not-exist")
		require.Error(t, err)
	})

	t.Run("files_collected", func(t *testing.T) {
		a, err := LoadFromDirectory("testdata/sample-mixin")
		require.NoError(t, err)

		var paths []string
		for _, f := range a.Files {
			paths = append(paths, f.Target+"/"+f.RelativePath)
		}
		require.Contains(t, paths, "home/.sample/config.json")
	})

	t.Run("not_a_directory", func(t *testing.T) {
		_, err := LoadFromDirectory("testdata/sample-mixin/spec.yaml")
		require.ErrorContains(t, err, "not a directory")
	})
}

// TestV1Settings_AbsorbedWithDeprecationWarning asserts the Phase 4 behavior:
// a v1 `settings:` block must still PARSE under strict decoding (the
// LegacySettings shim absorbs it) and normalize must emit a deprecation
// warning naming `settings` — not strict-reject. The canonical
// Artifact.Settings surface is gone (removed in Phase 4); strict-reject is the
// Phase 6 cutover's job. The sample-mixin fixture still carries a settings:
// block, so it exercises the shim directly.
func TestV1Settings_AbsorbedWithDeprecationWarning(t *testing.T) {
	a, err := LoadFromDirectory("testdata/sample-mixin")
	require.NoError(t, err, "v1 settings: must load (absorb-and-warn), not strict-reject in Phase 4")
	require.Contains(t, strings.Join(a.Warnings, "\n"), "settings",
		"v1 settings: must emit a deprecation warning; got %v", a.Warnings)
}

func TestLoadFromFS(t *testing.T) {
	fsys := fstest.MapFS{
		"mykit/spec.yaml": &fstest.MapFile{
			Data: []byte(`schemaVersion: "1"
kind: mixin
name: fs-kit
displayName: FS Kit
description: "loaded from fs.FS"
`),
		},
		"mykit/files/home/hello.txt": &fstest.MapFile{
			Data: []byte("hello"),
			Mode: 0o644,
		},
	}

	a, err := LoadFromFS(fsys, "mykit")
	require.NoError(t, err)
	require.Equal(t, "fs-kit", a.Manifest.Name)
	require.Len(t, a.Files, 1)
	require.Equal(t, "hello.txt", a.Files[0].RelativePath)
	require.Equal(t, TargetHome, a.Files[0].Target)
}

func TestParseArtifact_SpecYmlFallback(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yml"), []byte(`schemaVersion: "1"
kind: mixin
name: yml-kit
displayName: YML Kit
description: "loaded from spec.yml"
`), 0o644))

	a, err := LoadFromDirectory(dir)
	require.NoError(t, err)
	require.Equal(t, "yml-kit", a.Manifest.Name)
}

func TestParseArtifact_NoSpecFile(t *testing.T) {
	dir := t.TempDir()
	_, err := LoadFromDirectory(dir)
	require.ErrorContains(t, err, "spec.yaml")
}

func TestParseArtifact_InvalidYAML(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`{{{invalid`), 0o644))
	_, err := LoadFromDirectory(dir)
	require.ErrorContains(t, err, "invalid")
}

// TestParseArtifact_StrictUnknownField guards the strict-decode behaviour:
// truly unknown top-level keys (and unknown nested keys under known blocks)
// hard-fail rather than getting silently dropped. Fields that USED to be
// valid pre-v2 but were retired — `persistence:`, `kitDir:` — are routed
// through the LegacyXxx + normalize.go deprecation-warning path instead;
// their behaviour is pinned by the tests in v1_compat_test.go.
func TestParseArtifact_StrictUnknownField(t *testing.T) {
	t.Run("unknown_top_level_key_rejected", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`schemaVersion: "1"
kind: mixin
name: bogus-toplevel
totallyBogus: yes
`), 0o644))
		_, err := LoadFromDirectory(dir)
		require.ErrorContains(t, err, "totallyBogus")
	})

	t.Run("unknown_nested_key_rejected", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`schemaVersion: "1"
kind: agent
name: bogus-nested
agent:
  image: docker/sandbox-templates:shell-docker
  totallyBogus: yes
`), 0o644))
		_, err := LoadFromDirectory(dir)
		require.ErrorContains(t, err, "totallyBogus")
	})
}

func TestCollectFilesFromDir_SymlinkEscape(t *testing.T) {
	dir := t.TempDir()
	homeDir := filepath.Join(dir, "files", "home")
	require.NoError(t, os.MkdirAll(homeDir, 0o755))

	// Create a real file outside the artifact directory to symlink to
	outsideFile := filepath.Join(t.TempDir(), "outside.txt")
	require.NoError(t, os.WriteFile(outsideFile, []byte("secret"), 0o644))

	require.NoError(t, os.Symlink(outsideFile, filepath.Join(homeDir, "escaped")))

	_, err := enumerateDirFiles(dir)
	require.ErrorContains(t, err, "escapes the artifact directory")
}

func TestLoadFromBytes(t *testing.T) {
	t.Run("happy_path", func(t *testing.T) {
		a, err := LoadFromBytes([]byte(`schemaVersion: "1"
kind: mixin
name: bytes-kit
displayName: Bytes Kit
description: loaded directly from bytes
`))
		require.NoError(t, err)
		require.Equal(t, "bytes-kit", a.Manifest.Name)
		require.Equal(t, KindMixin, a.Manifest.Kind)
		require.Empty(t, a.Files, "LoadFromBytes never populates Files")
	})

	t.Run("does_not_validate_files", func(t *testing.T) {
		// LoadFromBytes is deliberately validation-free for Files — the
		// caller is expected to populate Artifact.Files from a separate
		// source (e.g. an OCI tar layer) and then call ValidateArtifact.
		// Here we synthesize an Artifact that parses cleanly, then attach
		// a malformed Files entry that only ValidateArtifact catches.
		a, err := LoadFromBytes([]byte(`schemaVersion: "1"
kind: mixin
name: deferred-validate
`))
		require.NoError(t, err)

		a.Files = []ArtifactFile{
			{Target: "bogus-target", RelativePath: "x"},
		}
		require.ErrorContains(t, ValidateArtifact(a), "invalid target")
	})

	t.Run("invalid_yaml", func(t *testing.T) {
		_, err := LoadFromBytes([]byte(`{{{ broken`))
		require.ErrorContains(t, err, "invalid")
	})

	t.Run("unknown_field_rejected", func(t *testing.T) {
		// Strict-decode behaviour applies to LoadFromBytes the same way it
		// does to LoadFromDirectory.
		_, err := LoadFromBytes([]byte(`schemaVersion: "1"
kind: mixin
name: typo-kit
mystery: 42
`))
		require.Error(t, err)
	})
}

func TestManifest_VersionAndSourceURL(t *testing.T) {
	a, err := LoadFromBytes([]byte(`schemaVersion: "1"
kind: mixin
name: versioned-kit
version: "2.3.1"
sourceURL: https://example.com/versioned-kit
`))
	require.NoError(t, err)
	require.Equal(t, "2.3.1", a.Manifest.Version)
	require.Equal(t, "https://example.com/versioned-kit", a.Manifest.SourceURL)
}
