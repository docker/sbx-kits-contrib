//go:build unix

package tck

import (
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestCopyKitRenamedSkipsNonRegularFiles(t *testing.T) {
	src := writeKit(t, fixtureKitFiles)
	require.NoError(t, syscall.Mkfifo(filepath.Join(src, "pipe"), 0o600))

	_, entries, err := planKitTree(src, "spec.yaml", []byte(fixtureSpecYAML), nil)
	require.NoError(t, err)
	for _, e := range entries {
		require.NotEqual(t, "pipe", e.rel, "a non-regular entry must never be planned")
	}

	dst := filepath.Join(t.TempDir(), "dst")
	done := make(chan error, 1)
	go func() {
		done <- copyKitRenamed(src, dst, "fixture-kit-e2e")
	}()

	select {
	case err := <-done:
		require.NoError(t, err)
	case <-time.After(10 * time.Second):
		t.Fatal("copyKitRenamed blocked, likely opening the fifo at pipe")
	}
}
