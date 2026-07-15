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
	"go.yaml.in/yaml/v3"
)

// sandboxWorkDir is the workspace mount point inside every sbx template
// container. All templates inherit from the shared `base` stage which sets
// `WORKDIR /home/agent/workspace`, so `${WORKDIR}` placeholders in a kit's
// `commands.initFiles` resolve to this path at runtime. (The tck.TestWorkDir
// constant is `/workspace` because the in-suite testcontainers tests fabricate
// their own workdir; it does not match a real sbx sandbox.)
const sandboxWorkDir = "/home/agent/workspace"

// TestE2EKit is the single e2e entry point for all kit types. It creates one
// sandbox, verifies kit content (env vars, files, tmpfs, agentContext) for
// every kit, and — for kind:sandbox kits that declare promptArgs in their
// testdata/tck.yaml — also sends a non-interactive prompt to the agent.
//
// Subtest layout:
//
//	TestE2EKit/<kit>
//	  env          — all kits
//	  files        — all kits
//	  tmpfs        — all kits
//	  agentContext — all kits (skipped when agentContext is absent)
//	  prompt       — kind:sandbox only, skipped when tck.yaml/promptArgs absent
//
// The agent passed to `sbx create` depends on the kit's manifest:
//
//	kind: sandbox → the kit's own name (sbx enforces this match).
//	kind: mixin   → "claude" (the default agent the kit is exercised against).
//
// KIT_UNDER_TEST is read from the environment; the CI matrix sets it per-kit.
func TestE2EKit(t *testing.T) {
	kitPath := os.Getenv("KIT_UNDER_TEST")
	require.NotEmpty(t, kitPath, "KIT_UNDER_TEST must point at a kit directory")

	absKit, err := filepath.Abs(kitPath)
	require.NoError(t, err, "resolve KIT_UNDER_TEST=%q", kitPath)

	t.Run(filepath.Base(absKit), func(t *testing.T) {
		info, err := os.Stat(absKit)
		require.NoErrorf(t, err, "stat KIT_UNDER_TEST=%q", absKit)
		require.Truef(t, info.IsDir(), "KIT_UNDER_TEST=%q must be a directory", absKit)

		suite, err := tck.NewSuiteFromDir(absKit)
		require.NoErrorf(t, err, "derive suite for %q", absKit)

		_, err = exec.LookPath("sbx")
		require.NoError(t, err, "sbx must be on PATH; CI installs it from docker/sbx-releases")

		agent := agentForKit(suite.Artifact)

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
		defer cancel()

		name := createSbx(t, ctx, absKit, agent)

		// Verify kit content landed inside the running container. Files are
		// re-derived here so `${WORKDIR}` resolves to the real sandbox workdir
		// instead of the TCK in-suite constant. These run for all kit kinds.
		assertSbxEnv(t, ctx, name, suite.ExpectedEnvVars)
		assertSbxFiles(t, ctx, name, expectedSandboxFiles(suite.Artifact))
		assertSbxTmpfs(t, ctx, name, suite.ExpectedTmpfs)
		assertSbxAgentContext(t, ctx, name, suite.Artifact)

		// Prompt subtest: kind:sandbox only, opt-in via testdata/tck.yaml.
		if suite.Artifact.Manifest.Kind != spec.KindSandbox {
			return
		}
		td := loadKitTCKData(t, absKit)
		if td == nil || len(td.PromptArgs) == 0 {
			return
		}

		// Wait for any background installation before sending the prompt.
		waitForAgentReady(t, ctx, name, td.ReadyFile)

		binary := td.Binary
		if binary == "" {
			binary = filepath.Base(suite.Artifact.Manifest.Binary)
		}
		require.NotEmptyf(t, binary,
			"kit %s: binary not derivable from spec.yaml entrypoint or tck.yaml", suite.Artifact.Manifest.Name)

		t.Run("prompt", func(t *testing.T) {
			execArgs := []string{"exec", name, "--", binary}
			execArgs = append(execArgs, td.PromptArgs...)
			execArgs = append(execArgs, promptMessage)

			// Ignore exit error: auth failures (401/403) are expected without
			// credentials. The assertion is that the agent ran and responded.
			out, _ := runSbx(t, ctx, execArgs...)
			require.NotEmptyf(t, out,
				"sbx exec produced no output for kit %s (binary=%s, promptArgs=%v)",
				absKit, binary, td.PromptArgs)
			t.Logf("sbx exec output for kit %s (binary=%s, promptArgs=%v):\n%s",
				absKit, binary, td.PromptArgs, out)
		})
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

// kitTCKData holds kit-specific configuration for TCK e2e tests, loaded from
// <kit-dir>/testdata/tck.yaml.
type kitTCKData struct {
	// ReadyFile is the absolute path of a sentinel file written inside the
	// sandbox when a background installation completes. When set,
	// TestE2ERunAgent polls `sbx exec -- test -f <readyFile>` before running
	// the prompt subtest. Leave empty for kits whose install commands are synchronous.
	ReadyFile string `yaml:"readyFile"`

	// PromptArgs are the arguments prepended before the prompt message when
	// invoking the binary non-interactively via `sbx exec`, e.g. ["-p"] for
	// claude, ["-m"] for nanobot, ["chat", "-q"] for hermes. An empty slice
	// skips the prompt subtest (for agents with no non-interactive mode).
	PromptArgs []string `yaml:"promptArgs"`

	// Binary overrides the agent binary name used in `sbx exec`. When absent,
	// filepath.Base(suite.Artifact.Manifest.Binary) is used — the normalizer
	// derives that from sandbox.entrypoint.run[0]. Set this only when the
	// entrypoint is a wrapper script whose real binary has a different name
	// (e.g. nanoclaw's nanoclaw-start wraps claude).
	Binary string `yaml:"binary"`
}

// loadKitTCKData reads <kitDir>/testdata/tck.yaml. Returns nil, nil when the
// file does not exist — callers should skip rather than fail in that case.
func loadKitTCKData(t *testing.T, kitDir string) *kitTCKData {
	t.Helper()

	p := filepath.Join(kitDir, "testdata", "tck.yaml")
	data, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return nil
	}
	require.NoErrorf(t, err, "read %s", p)

	var td kitTCKData
	if err := yaml.Unmarshal(data, &td); err != nil {
		require.NoErrorf(t, err, "parse %s", p)
	}
	return &td
}

// promptMessage is the fixed text sent to every agent in TestE2EKit's prompt subtest.
// It is short, benign, and produces a non-empty response even when the
// agent rejects the call with an authentication error.
const promptMessage = "what version are you running"

// createSbx creates a sandbox for the kit using `sbx create`, registers a
// t.Cleanup that force-removes it, and returns the sandbox name. A fresh temp
// dir is used as the workspace.
func createSbx(t *testing.T, ctx context.Context, absKit, agent string) string {
	t.Helper()
	workspace := t.TempDir()
	name := sandboxName(t, absKit)
	t.Cleanup(func() {
		cleanCtx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		out, err := exec.CommandContext(cleanCtx, "sbx", "--app-name", "sbx-kits-contrib-tck", "rm", "-f", name).CombinedOutput()
		if err != nil {
			t.Logf("cleanup `sbx rm -f %s` failed: %v\n%s", name, err, out)
		}
	})
	createOut, err := runSbx(t, ctx, "create", "--kit", absKit, "--name", name, agent, workspace)
	require.NoErrorf(t, err, "sbx create failed (agent=%s):\n%s", agent, createOut)
	t.Logf("sbx create succeeded for kit %s as sandbox %q (agent=%s)\n%s", absKit, name, agent, createOut)
	return name
}

// waitForAgentReady polls until readyFile exists inside the sandbox, indicating
// that a background installation completed. No-op when readyFile is empty
// (synchronous-install kits are ready as soon as sbx create returns).
func waitForAgentReady(t *testing.T, ctx context.Context, name, readyFile string) {
	t.Helper()
	if readyFile == "" {
		return
	}
	t.Logf("polling for %s in sandbox %s...", readyFile, name)
	for {
		_, err := runSbx(t, ctx, "exec", name, "--", "test", "-f", readyFile)
		if err == nil {
			t.Logf("%s present — agent installation complete", readyFile)
			return
		}
		select {
		case <-ctx.Done():
			t.Fatalf("timed out waiting for %s in sandbox %s — installation did not complete", readyFile, name)
			return
		case <-time.After(10 * time.Second):
		}
	}
}

// agentForKit picks the positional agent argument for `sbx create`. Sandbox
// kits must be invoked with their own name as the agent. A mixin that declares
// base-agent affinity (requires.agent) must be exercised on that agent —
// composing it onto any other base is a hard error, since affinity is enforced
// at compose time. Mixins without affinity default to claude.
func agentForKit(a *spec.Artifact) string {
	if a.Manifest.Kind == spec.KindSandbox {
		return a.Manifest.Name
	}
	if a.Requires != nil && a.Requires.Agent != "" {
		return a.Requires.Agent
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
// `sbx login` step flow through. --app-name is prepended to every call for
// telemetry attribution. Marked as a test helper so require/Fatal failures
// inside callers point at the call site, not this wrapper.
func runSbx(t *testing.T, ctx context.Context, args ...string) (string, error) {
	t.Helper()
	all := make([]string, 0, len(args)+2)
	all = append(all, "--app-name", "sbx-kits-contrib-tck")
	all = append(all, args...)
	cmd := exec.CommandContext(ctx, "sbx", all...)
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// shellQuote single-quotes a string for safe inclusion in an `sh -c` command.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
