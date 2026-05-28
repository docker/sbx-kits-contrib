package spec

import (
	"os"
	"path/filepath"
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
		require.NotNil(t, a.Network)
		require.NotNil(t, a.Credentials)
		require.NotNil(t, a.Environment)
		require.NotNil(t, a.Settings)
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

func TestLoadFromFS_NetworkPublishedPorts(t *testing.T) {
	// YAML round-trip for the new network.publishedPorts field: the
	// minimal form (just container) and the full form (container +
	// protocol + name) must both parse, defaulting protocol at use-site
	// rather than at decode-time (the spec keeps zero values).
	fsys := fstest.MapFS{
		"port-kit/spec.yaml": &fstest.MapFile{
			Data: []byte(`schemaVersion: "1"
kind: mixin
name: port-kit
displayName: Port Kit
description: "exercises network.publishedPorts"
network:
  publishedPorts:
    - container: 9418
    - container: 8080
      protocol: tcp
      name: web
    - container: 53
      protocol: udp
      name: dns
`),
		},
	}

	a, err := LoadFromFS(fsys, "port-kit")
	require.NoError(t, err)
	require.NotNil(t, a.Network)
	require.Len(t, a.Network.PublishedPorts, 3)

	require.Equal(t, 9418, a.Network.PublishedPorts[0].Container)
	require.Empty(t, a.Network.PublishedPorts[0].Protocol, "minimal form leaves protocol empty; consumers default it")
	require.Empty(t, a.Network.PublishedPorts[0].Name)

	require.Equal(t, 8080, a.Network.PublishedPorts[1].Container)
	require.Equal(t, "tcp", a.Network.PublishedPorts[1].Protocol)
	require.Equal(t, "web", a.Network.PublishedPorts[1].Name)

	require.Equal(t, 53, a.Network.PublishedPorts[2].Container)
	require.Equal(t, "udp", a.Network.PublishedPorts[2].Protocol)
	require.Equal(t, "dns", a.Network.PublishedPorts[2].Name)
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
// unknown top-level keys (and unknown nested keys under known blocks) hard-
// fail rather than getting silently dropped. This is the contract the
// engine relies on so that removed fields like `persistence:` and
// `kitDir:` produce a clear diagnostic for kit authors, not a silent no-op.
func TestParseArtifact_StrictUnknownField(t *testing.T) {
	t.Run("unknown_top_level_key_rejected", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`schemaVersion: "1"
kind: mixin
name: bogus-toplevel
persistence: persistent
`), 0o644))
		_, err := LoadFromDirectory(dir)
		require.ErrorContains(t, err, "persistence")
	})

	t.Run("unknown_nested_key_rejected", func(t *testing.T) {
		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "spec.yaml"), []byte(`schemaVersion: "1"
kind: agent
name: bogus-nested
agent:
  image: docker/sandbox-templates:shell-docker
  persistence: persistent
`), 0o644))
		_, err := LoadFromDirectory(dir)
		require.ErrorContains(t, err, "persistence")
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

	_, err := collectFilesFromDir(dir)
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
