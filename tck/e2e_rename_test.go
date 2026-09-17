package tck

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/stretchr/testify/require"
)

// fixtureSpecYAML is a minimal v2 kind:sandbox spec.LoadFromDirectory accepts.
const fixtureSpecYAML = `schemaVersion: "2"
kind: sandbox
name: fixture-kit
version: "1.0.0"
displayName: Fixture Kit
sandbox:
  image: "docker.io/sbx/fixture-image:latest"
  entrypoint: [fixture]
`

// fixtureKitFiles is a minimal kit: a spec file plus a nested files/ tree.
var fixtureKitFiles = map[string]string{
	"spec.yaml":                 fixtureSpecYAML,
	"files/home/.cfg":           "k=v\n",
	"files/home/nested/note.md": "nested\n",
}

// parameterizedSpecYAML parameterizes the AI profile filename, a field the
// spec pattern-checks, so only the arg-substituting loader accepts the copy.
const parameterizedSpecYAML = `schemaVersion: "2"
kind: sandbox
name: fixture-kit
version: "1.0.0"
displayName: Fixture Kit
args:
  profile:
    default: "DEFAULT.md"
sandbox:
  image: "docker.io/sbx/fixture-image:latest"
  entrypoint: [fixture]
agentInstructions:
  filename: "${{ kit.args.profile }}"
  content: "fixture instructions"
`

func TestE2ERenamedKitName(t *testing.T) {
	require.Equal(t, "kiro-e2e", e2eRenamedKitName("kiro"))
}

func TestCopyKitRenamed(t *testing.T) {
	src := writeKit(t, fixtureKitFiles)
	cfgPath := filepath.Join(src, "files", "home", ".cfg")
	require.NoError(t, os.Chmod(cfgPath, 0o600))
	if runtime.GOOS != "windows" {
		require.NoError(t, os.Symlink(".cfg", filepath.Join(src, "files", "home", "cfg-link")))
	}

	dst := filepath.Join(t.TempDir(), "dst")
	require.NoError(t, copyKitRenamed(src, dst, "fixture-kit-e2e"))

	t.Run("loads under the new name", func(t *testing.T) {
		srcArtifact, err := spec.LoadFromDirectory(src)
		require.NoError(t, err)
		require.Equal(t, "fixture-kit", srcArtifact.Manifest.Name, "copying must not mutate src")

		dstArtifact, err := spec.LoadFromDirectory(dst)
		require.NoError(t, err)
		require.Equal(t, "fixture-kit-e2e", dstArtifact.Manifest.Name)

		// Manifest carries no directory-derived fields, so zeroing Name is the
		// only adjustment needed before comparing the rest.
		srcManifest, dstManifest := srcArtifact.Manifest, dstArtifact.Manifest
		srcManifest.Name = ""
		dstManifest.Name = ""
		require.Equal(t, srcManifest, dstManifest)

		require.Equal(t, "1.0.0", dstArtifact.Manifest.Version, "quoted scalar must still decode as a string")

		rewritten, err := os.ReadFile(filepath.Join(dst, "spec.yaml"))
		require.NoError(t, err)
		require.Contains(t, string(rewritten), `version: "1.0.0"`, "unrelated scalar style must survive the rewrite")
	})

	t.Run("preserves file modes", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("mode bits differ on Windows")
		}
		info, err := os.Stat(filepath.Join(dst, "files", "home", ".cfg"))
		require.NoError(t, err)
		require.Equal(t, os.FileMode(0o600), info.Mode().Perm())
	})

	t.Run("preserves symlinks", func(t *testing.T) {
		if runtime.GOOS == "windows" {
			t.Skip("symlink semantics differ on Windows")
		}
		linkPath := filepath.Join(dst, "files", "home", "cfg-link")
		linkInfo, err := os.Lstat(linkPath)
		require.NoError(t, err)
		require.True(t, linkInfo.Mode()&os.ModeSymlink != 0, "cfg-link must still be a symlink")

		target, err := os.Readlink(linkPath)
		require.NoError(t, err)
		require.Equal(t, ".cfg", target)
	})
}

func TestCopyKitRenamedNeverWritesThroughToSource(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("symlink and mode semantics differ on Windows")
	}

	t.Run("symlinked kit root", func(t *testing.T) {
		src := writeKit(t, fixtureKitFiles)
		link := filepath.Join(t.TempDir(), "link")
		require.NoError(t, os.Symlink(src, link))

		dst := filepath.Join(t.TempDir(), "dst")
		require.NoError(t, copyKitRenamed(link, dst, "fixture-kit-e2e"))

		assertRenamedCopy(t, src, dst)
	})

	t.Run("read-only spec file", func(t *testing.T) {
		src := writeKit(t, fixtureKitFiles)
		require.NoError(t, os.Chmod(filepath.Join(src, "spec.yaml"), 0o444))

		dst := filepath.Join(t.TempDir(), "dst")
		require.NoError(t, copyKitRenamed(src, dst, "fixture-kit-e2e"))

		dstArtifact, err := spec.LoadFromDirectory(dst)
		require.NoError(t, err)
		require.Equal(t, "fixture-kit-e2e", dstArtifact.Manifest.Name)

		info, err := os.Stat(filepath.Join(dst, "spec.yaml"))
		require.NoError(t, err)
		require.Equal(t, os.FileMode(0o444), info.Mode().Perm(),
			"the source's read-only mode must round-trip through the write path")
	})
}

// assertRenamedCopy checks src still declares the fixture's own name and dst
// declares the renamed one.
func assertRenamedCopy(t *testing.T, src, dst string) {
	t.Helper()

	srcArtifact, err := spec.LoadFromDirectory(src)
	require.NoError(t, err)
	require.Equal(t, "fixture-kit", srcArtifact.Manifest.Name)

	dstArtifact, err := spec.LoadFromDirectory(dst)
	require.NoError(t, err)
	require.Equal(t, "fixture-kit-e2e", dstArtifact.Manifest.Name)
}

func TestCopyKitRenamedMissingSpecFileErrors(t *testing.T) {
	src := writeKit(t, map[string]string{"README.md": "no spec here"})

	dst := filepath.Join(t.TempDir(), "dst")
	err := copyKitRenamed(src, dst, "whatever-e2e")
	require.Error(t, err)
	require.Contains(t, err.Error(), "no parseable spec.yaml or spec.yml")
}

func TestCopyKitRenamedSpecWithoutNameErrors(t *testing.T) {
	src := writeKit(t, map[string]string{"spec.yaml": "schemaVersion: \"2\"\nkind: sandbox\n"})

	dst := filepath.Join(t.TempDir(), "dst")
	err := copyKitRenamed(src, dst, "whatever-e2e")
	require.Error(t, err)
	require.Contains(t, err.Error(), "no top-level name key")
}

func TestCopyKitRenamedAliasedNameErrors(t *testing.T) {
	src := writeKit(t, map[string]string{"spec.yaml": "schemaVersion: \"2\"\nkind: sandbox\nx-anchor: &n fixture-kit\nname: *n\n"})

	dst := filepath.Join(t.TempDir(), "dst")
	err := copyKitRenamed(src, dst, "fixture-kit-e2e")
	require.Error(t, err)
	require.Contains(t, err.Error(), "name is not a scalar")
}

func TestCopyKitRenamedValidatesWithArgumentsSubstituted(t *testing.T) {
	src := writeKit(t, map[string]string{
		"spec.yaml":         parameterizedSpecYAML,
		"testdata/tck.yaml": "args:\n  profile: \"FIXTURE.md\"\n",
	})

	dst := filepath.Join(t.TempDir(), "dst")
	require.NoError(t, copyKitRenamed(src, dst, "fixture-kit-e2e"))

	artifact, err := openKitArtifact(dst)
	require.NoError(t, err)
	require.Equal(t, "fixture-kit-e2e", artifact.Manifest.Name)
	require.Equal(t, "FIXTURE.md", artifact.Manifest.AIFilename,
		"the copied testdata/tck.yaml must resolve the argument the same way")

	_, err = spec.LoadFromDirectory(dst)
	require.Error(t, err, "the copy keeps the placeholder the substitution resolves")
}
