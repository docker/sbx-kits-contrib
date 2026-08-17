// TestKitTCK exercises the full TCK suite against the kit identified by the
// KIT environment variable. Replaces the per-kit `<kit>_tck_test.go` files
// that each contained the same boilerplate. CI sets KIT once per matrix entry;
// local users invoke as e.g. `KIT="$PWD/code-server" go test -v ./tck/...`.
//
// Mirrors the shape of TestE2ECreateSandbox in this same package so the two
// surfaces stay symmetrical: same env-var convention, same path resolution,
// same kit-name subtest wrapper.

package tck_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

// TestKitTCK loads the kit at $KIT and runs the full TCK suite against it
// (validation, network/credential/environment policies, commands, container
// assertions via testcontainers, etc. — everything Suite.RunAll exposes).
//
// KIT must be an absolute path. `go test ./tck/...` runs the binary with
// cwd set to ./tck/, so a relative KIT resolves against ./tck/ — anchor
// against $PWD or $GITHUB_WORKSPACE when calling from the repo root.
func TestKitTCK(t *testing.T) {
	kitPath := os.Getenv("KIT")
	if kitPath == "" {
		// The self-test job in tck.yml runs `go test ./spec/... ./tck/...`
		// with no KIT — it's exercising the TCK package's own tests, not
		// any kit. Skip cleanly there. The wrapper scripts and per-kit CI
		// matrix always set KIT, so this only fires in the self-test path.
		t.Skip("KIT not set — set via scripts/test-kit.sh or the per-kit CI matrix")
	}

	absKit, err := filepath.Abs(kitPath)
	require.NoError(t, err, "resolve KIT=%q", kitPath)

	info, err := os.Stat(absKit)
	require.NoErrorf(t, err, "stat KIT=%q", absKit)
	require.Truef(t, info.IsDir(), "KIT=%q must be a directory", absKit)

	// Name the parent subtest after the kit directory so loops over many
	// kits produce distinguishable subtest names (TestKitTCK/crush, …)
	// instead of repeated TestKitTCK lines.
	t.Run(filepath.Base(absKit), func(t *testing.T) {
		suite, err := tck.NewSuiteFromDir(absKit)
		require.NoErrorf(t, err, "derive suite for %q", absKit)
		suite.RunAll(t)
	})
}
