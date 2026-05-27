//go:build e2e

// E2E test exercises a kit against a real, installed sbx CLI. The CI job is
// responsible for installing sbx and running `sbx login` before this test
// runs. Build-tagged `e2e` so it never runs in the default `go test ./...`
// flow that kit authors invoke locally — only the matrix job in tck.yml
// opts in via `-tags=e2e`.

package tck_test

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

// sandboxWorkDir is the workspace mount point inside every sbx template
// container. All templates inherit from the shared `base` stage which sets
// `WORKDIR /home/agent/workspace`, so `${WORKDIR}` placeholders in a kit's
// `commands.initFiles` resolve to this path at runtime. (The tck.TestWorkDir
// constant is `/workspace` because the in-suite testcontainers tests fabricate
// their own workdir; it does not match a real sbx sandbox.)
const sandboxWorkDir = "/home/agent/workspace"

// TestE2ECreateSandbox creates a sandbox with the kit under test against a
// real sbx daemon, asserts that `sbx create` succeeds, then verifies the kit
// content is present inside the running container: env vars, container files
// (from `files/home` and `commands.initFiles`), tmpfs mounts, and — when the
// kit declares an `agentContext:` block — the rendered file. The sandbox is
// removed in cleanup.
//
// The agent passed to `sbx create` depends on the kit's manifest:
//
//   - kind: sandbox → the kit's own name (sbx enforces this match).
//   - kind: mixin   → "claude" (the default agent kit-author exercised).
//
// KIT_UNDER_TEST is read from the environment; the CI matrix sets it per-kit.
func TestE2ECreateSandbox(t *testing.T) {
	kitPath := os.Getenv("KIT_UNDER_TEST")
	require.NotEmpty(t, kitPath, "KIT_UNDER_TEST must point at a kit directory")

	absKit, err := filepath.Abs(kitPath)
	require.NoError(t, err, "resolve KIT_UNDER_TEST=%q", kitPath)

	// Name the parent subtest after the kit directory so loops invoking this
	// test once per kit produce distinguishable test names in the output
	// (e.g. TestE2ECreateSandbox/crush, TestE2ECreateSandbox/code-server)
	// instead of repeated TestE2ECreateSandbox lines.
	t.Run(filepath.Base(absKit), func(t *testing.T) {
		info, err := os.Stat(absKit)
		require.NoErrorf(t, err, "stat KIT_UNDER_TEST=%q", absKit)
		require.Truef(t, info.IsDir(), "KIT_UNDER_TEST=%q must be a directory", absKit)

		suite, err := tck.NewSuiteFromDir(absKit)
		require.NoErrorf(t, err, "derive suite for %q", absKit)

		_, err = exec.LookPath("sbx")
		require.NoError(t, err, "sbx must be on PATH; CI installs it from docker/sbx-releases")

		workspace := t.TempDir()
		name := sandboxName(t, absKit)
		agent := agentForKit(suite.Artifact)

		t.Cleanup(func() {
			cleanCtx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			defer cancel()
			out, err := exec.CommandContext(cleanCtx, "sbx", "rm", "-f", name).CombinedOutput()
			if err != nil {
				t.Logf("cleanup `sbx rm -f %s` failed: %v\n%s", name, err, out)
			}
		})

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()

		createOut, err := runSbx(t, ctx, "create",
			"--kit", absKit,
			"--name", name,
			agent, workspace,
		)
		require.NoErrorf(t, err, "sbx create failed (agent=%s):\n%s", agent, createOut)
		t.Logf("sbx create succeeded for kit %s as sandbox %q (agent=%s)\n%s", absKit, name, agent, createOut)

		// Verify the kit content landed inside the running container. Files
		// are re-derived here so `${WORKDIR}` resolves to the real sandbox
		// workdir instead of the TCK in-suite constant.
		assertSbxEnv(t, ctx, name, suite.ExpectedEnvVars)
		assertSbxFiles(t, ctx, name, expectedSandboxFiles(suite.Artifact))
		assertSbxTmpfs(t, ctx, name, suite.ExpectedTmpfs)
		assertSbxAgentContext(t, ctx, name, suite.Artifact)
	})
}

// expectedSandboxFiles derives the absolute paths a kit must materialize
// inside a real sbx sandbox: every file under `files/home` lands at
// /home/agent/<relpath>, every `commands.initFiles` entry lands at its
// declared path with `${WORKDIR}` replaced by the actual sandbox workdir.
func expectedSandboxFiles(a *spec.Artifact) []string {
	var paths []string
	for _, f := range a.Files {
		if f.Target == spec.TargetHome {
			paths = append(paths, tck.HomeDir+"/"+f.RelativePath)
		}
	}
	if a.Commands != nil {
		for _, f := range a.Commands.InitFiles {
			paths = append(paths, strings.ReplaceAll(f.Path, "${WORKDIR}", sandboxWorkDir))
		}
	}
	return paths
}

// assertSbxEnv runs `printenv` in the sandbox and checks each declared
// environment variable from `environment.variables` is set to the expected
// value.
func assertSbxEnv(t *testing.T, ctx context.Context, name string, expected []string) {
	if len(expected) == 0 {
		return
	}
	t.Run("env", func(t *testing.T) {
		out, err := runSbx(t, ctx, "exec", name, "--", "env")
		require.NoErrorf(t, err, "sbx exec env failed:\n%s", out)
		for _, kv := range expected {
			require.Containsf(t, out, kv,
				"sandbox env should contain %q\nfull env output:\n%s", kv, out)
		}
	})
}

// assertSbxFiles checks that each expected file exists and is non-empty inside
// the sandbox.
func assertSbxFiles(t *testing.T, ctx context.Context, name string, expected []string) {
	if len(expected) == 0 {
		return
	}
	t.Run("files", func(t *testing.T) {
		for _, path := range expected {
			path := path
			t.Run(path, func(t *testing.T) {
				out, err := runSbx(t, ctx, "exec", name, "--", "test", "-s", path)
				require.NoErrorf(t, err,
					"file %q should exist and be non-empty in sandbox:\n%s", path, out)
			})
		}
	})
}

// assertSbxTmpfs verifies each expected tmpfs path is mounted as tmpfs inside
// the sandbox. The /run/secrets entry is always present and is checked along
// with any manifest-declared tmpfs paths.
func assertSbxTmpfs(t *testing.T, ctx context.Context, name string, expected map[string]string) {
	if len(expected) == 0 {
		return
	}
	t.Run("tmpfs", func(t *testing.T) {
		out, err := runSbx(t, ctx, "exec", name, "--", "mount")
		require.NoErrorf(t, err, "sbx exec mount failed:\n%s", out)
		for path := range expected {
			path := path
			t.Run(path, func(t *testing.T) {
				marker := fmt.Sprintf("tmpfs on %s ", path)
				require.Containsf(t, out, marker,
					"%s should be mounted as tmpfs; mount output:\n%s", path, out)
			})
		}
	})
}

// assertSbxAgentContext verifies that a kit's `agentContext:` content was
// rendered into a file inside the sandbox. For `kind: sandbox` kits the
// agentContext is inlined in the AI profile file (Manifest.AIFilename); for
// `kind: mixin` kits the engine writes a per-kit file as
// `kits-agent-context/<kit-name>.md` next to the parent agent's AI file. The
// exact directory varies per template, so we locate candidate files by name
// first, then grep each one for a stable substring of the declared content.
func assertSbxAgentContext(t *testing.T, ctx context.Context, name string, a *spec.Artifact) {
	if a.AgentContext == "" {
		return
	}
	target := agentContextFilename(a)
	if target == "" {
		t.Logf("agentContext check skipped: kit %s declares agentContext but has no aiFilename (kind=%s)",
			a.Manifest.Name, a.Manifest.Kind)
		return
	}
	needle := agentContextNeedle(a.AgentContext)
	if needle == "" {
		t.Logf("agentContext check skipped: no usable line in declared agentContext")
		return
	}
	t.Run("agentContext", func(t *testing.T) {
		// Find candidates by filename in writable trees. Prune pseudo-fs to
		// keep the traversal fast and avoid permission noise. `|| true`
		// hides find's non-zero exit when it bumps into unreadable
		// subdirectories — we judge by the printed paths, not the status.
		findCmd := fmt.Sprintf(
			"find / -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o "+
				"-type f -name %s -print 2>/dev/null || true",
			shellQuote(target),
		)
		findOut, err := runSbx(t, ctx, "exec", name, "--", "sh", "-c", findCmd)
		require.NoErrorf(t, err, "sbx exec find failed:\n%s", findOut)

		paths := strings.Fields(findOut)
		require.NotEmptyf(t, paths,
			"no agentContext file %q found anywhere in sandbox (kind=%s, name=%s)",
			target, a.Manifest.Kind, a.Manifest.Name)

		for _, p := range paths {
			grepCmd := fmt.Sprintf("grep -qF -- %s %s", shellQuote(needle), shellQuote(p))
			if _, err := runSbx(t, ctx, "exec", name, "--", "sh", "-c", grepCmd); err == nil {
				t.Logf("agentContext matched in %s", p)
				return
			}
		}
		t.Fatalf("agentContext needle %q not found in any candidate %v (kind=%s, name=%s)",
			needle, paths, a.Manifest.Kind, a.Manifest.Name)
	})
}

// agentContextFilename returns the filename the engine writes a kit's
// agentContext into.
//   kind: sandbox → Manifest.AIFilename (inlined agentContext)
//   kind: mixin   → "<kit-name>.md" under .../kits-agent-context/
func agentContextFilename(a *spec.Artifact) string {
	if a.Manifest.Kind == spec.KindSandbox {
		return a.Manifest.AIFilename
	}
	if a.Manifest.Kind == spec.KindMixin {
		return a.Manifest.Name + ".md"
	}
	return ""
}

// agentContextNeedle picks the longest non-empty, non-fenced, no-backtick
// line from the declared agentContext to use as a grep target. Avoiding
// backticks keeps the quoting story simple; picking the longest line
// minimizes the chance the substring collides with boilerplate.
func agentContextNeedle(agentContext string) string {
	var best string
	for _, raw := range strings.Split(agentContext, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "```") || strings.ContainsAny(line, "`'") {
			continue
		}
		if len(line) > len(best) {
			best = line
		}
	}
	if len(best) > 80 {
		best = best[:80]
	}
	return best
}

// agentForKit picks the positional agent argument for `sbx create`. Sandbox
// kits must be invoked with their own name as the agent; mixin kits
// piggy-back on whichever agent kit-author wants to exercise — claude is
// the default.
func agentForKit(a *spec.Artifact) string {
	if a.Manifest.Kind == spec.KindSandbox {
		return a.Manifest.Name
	}
	return "claude"
}

// sandboxName builds a unique, sbx-name-safe identifier from the kit
// directory and a random suffix. sbx accepts letters, numbers, hyphens,
// periods, plus and minus signs — no underscores.
func sandboxName(t *testing.T, kitDir string) string {
	t.Helper()

	base := strings.ToLower(filepath.Base(kitDir))
	base = strings.ReplaceAll(base, "_", "-")

	var raw [4]byte
	_, err := rand.Read(raw[:])
	require.NoError(t, err)

	return "e2e-" + base + "-" + hex.EncodeToString(raw[:])
}

// runSbx invokes the sbx CLI and returns combined stdout+stderr. Inherits the
// current environment so secrets and credential stores set up by the CI
// `sbx login` step flow through. Marked as a test helper so require/Fatal
// failures inside callers point at the call site, not this wrapper.
func runSbx(t *testing.T, ctx context.Context, args ...string) (string, error) {
	t.Helper()
	cmd := exec.CommandContext(ctx, "sbx", args...)
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// shellQuote single-quotes a string for safe inclusion in an `sh -c` command.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
