//go:build e2e

// E2E test exercises a kit against a real, installed sbx CLI. The CI job is
// responsible for installing sbx and running `sbx login` before this test
// runs. Build-tagged `e2e` so it never runs in the default `go test ./...`
// flow that kit authors invoke locally — only the matrix job in tck.yml
// opts in via `-tags=e2e`.
//
// This is a thin wrapper around the exported tck.RunE2EKit — see tck/e2e.go
// for the actual e2e logic, which any module importing this package (e.g.
// sbx-kits-internal) can drive against its own app-name.

package tck_test

import (
	"os"
	"testing"

	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

// appName scopes every `sbx` call this repo's own e2e run makes, keeping it
// isolated from a developer's or another module's main sbx state. Must stay
// in sync with scripts/test-kit-e2e.sh's default APP_NAME.
const appName = "sbx-kits-contrib-tck"

// TestE2EKit is the single e2e entry point for all kit types in this repo.
// KIT_UNDER_TEST is read from the environment; the CI matrix and
// scripts/test-kit-e2e.sh set it per-kit. See tck.RunE2EKit for what it
// actually does (subtests: env, files, tmpfs, agentContext, prompt).
func TestE2EKit(t *testing.T) {
	kitPath := os.Getenv("KIT_UNDER_TEST")
	require.NotEmpty(t, kitPath, "KIT_UNDER_TEST must point at a kit directory")

	tck.RunE2EKit(t, kitPath, tck.E2EOptions{AppName: appName})
}
