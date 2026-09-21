//go:build unix

package tck

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// argsKitSpec is a minimal kit that substitutes one defaulted argument, so a
// load either reaches the staging copy or fails visibly.
const argsKitSpec = "schemaVersion: \"2\"\nkind: mixin\nname: staging-kit\n" +
	"args:\n  v:\n    default: \"substituted\"\n" +
	"environment:\n  variables:\n    V: \"${{ kit.args.v }}\"\n"

func TestNewSuiteFromDirSkipsNonRegularFiles(t *testing.T) {
	dir := writeKit(t, map[string]string{
		"spec.yaml":                        argsKitSpec,
		"files/home/.staging-kit/keep.txt": "kept\n",
	})
	require.NoError(t, syscall.Mkfifo(filepath.Join(dir, "pipe"), 0o600))

	type result struct {
		suite *Suite
		err   error
	}
	done := make(chan result, 1)
	go func() {
		suite, err := NewSuiteFromDir(dir)
		done <- result{suite, err}
	}()

	select {
	case got := <-done:
		require.NoError(t, got.err)
		require.Equal(t, "substituted", got.suite.Artifact.Environment.Variables["V"])
	case <-time.After(20 * time.Second):
		t.Fatal("loading a kit that contains a fifo blocked; a non-regular file must never be opened")
	}
}

func TestNewSuiteFromDirThroughASymlinkedRoot(t *testing.T) {
	dir := writeKit(t, map[string]string{
		"spec.yaml":                        argsKitSpec,
		"files/home/.staging-kit/keep.txt": "kept\n",
	})
	link := filepath.Join(t.TempDir(), "kit-link")
	require.NoError(t, os.Symlink(dir, link))

	suite, err := NewSuiteFromDir(link)
	require.NoError(t, err)
	require.Equal(t, "substituted", suite.Artifact.Environment.Variables["V"])
	require.Len(t, suite.Artifact.Files, 1, "the kit's files/ tree must survive the copy")
}

func TestNewSuiteFromDirWithASymlinkedSpecFile(t *testing.T) {
	dir := writeKit(t, map[string]string{
		"real/kit.yaml":                    argsKitSpec,
		"files/home/.staging-kit/keep.txt": "kept\n",
	})
	require.NoError(t, os.Symlink(filepath.Join(dir, "real", "kit.yaml"), filepath.Join(dir, "spec.yaml")))

	suite, err := NewSuiteFromDir(dir)
	require.NoError(t, err)
	require.Equal(t, "substituted", suite.Artifact.Environment.Variables["V"],
		"the staged spec must carry the substituted bytes, not a link to unsubstituted ones")
}

func TestStagedDirectoryKeepsItsMode(t *testing.T) {
	dir := writeKit(t, map[string]string{
		"spec.yaml":                        argsKitSpec,
		"files/home/.staging-kit/config":   "x\n",
		"files/home/.staging-kit/sub/deep": "y\n",
	})
	guarded := filepath.Join(dir, "files", "home", ".staging-kit")
	require.NoError(t, os.Chmod(filepath.Join(guarded, "sub"), 0o555))
	require.NoError(t, os.Chmod(guarded, 0o555))
	// t.TempDir's own cleanup cannot unlink out of a read-only directory.
	t.Cleanup(func() {
		_ = os.Chmod(guarded, 0o755)
		_ = os.Chmod(filepath.Join(guarded, "sub"), 0o755)
	})

	staged, err := stageExpandedKit(dir, "spec.yaml", []byte("spec: replaced\n"), map[string]string{"v": "1"})
	require.NoError(t, err)
	require.NotEmpty(t, staged)
	t.Cleanup(func() { removeStaging(staged) })

	for _, rel := range []string{
		filepath.Join("files", "home", ".staging-kit"),
		filepath.Join("files", "home", ".staging-kit", "sub"),
	} {
		info, err := os.Stat(filepath.Join(staged, rel))
		require.NoError(t, err)
		require.Equalf(t, os.FileMode(0o555), info.Mode().Perm(), "staged mode of %s", rel)
	}
	deep, err := os.ReadFile(filepath.Join(staged, "files", "home", ".staging-kit", "sub", "deep"))
	require.NoError(t, err, "a read-only directory must still have been populated")
	require.Equal(t, "y\n", string(deep))
}
