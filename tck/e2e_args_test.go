package tck

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/stretchr/testify/require"
)

func TestBuildCreateArgsSandbox(t *testing.T) {
	got := buildCreateArgs(spec.KindSandbox, "/abs/kiro", "e2e-kiro-1234", "kiro", "/tmp/workspace", nil, "")

	require.Equal(t,
		[]string{"create", "/abs/kiro", "--name", "e2e-kiro-1234", "/tmp/workspace"},
		got,
		"kind:sandbox must pass the kit's own directory as the first positional, with no --kit and no agent argument")
}

func TestBuildCreateArgsSandboxWithKitArgFlags(t *testing.T) {
	got := buildCreateArgs(spec.KindSandbox, "/abs/kiro", "e2e-kiro-1234", "kiro", "/tmp/workspace",
		[]string{"--kit-arg", "kiro.model=fast"}, "")

	require.Equal(t,
		[]string{
			"create", "/abs/kiro", "--name", "e2e-kiro-1234",
			"--kit-arg", "kiro.model=fast",
			"/tmp/workspace",
		},
		got,
		"kit-arg flags must land between --name and the workspace, which stays last")
}

func TestBuildCreateArgsMixin(t *testing.T) {
	got := buildCreateArgs(spec.KindMixin, "/abs/aidlc-claude", "e2e-aidlc-1234", "claude", "/tmp/workspace", nil, "")

	require.Equal(t,
		[]string{"create", "--kit", "/abs/aidlc-claude", "--name", "e2e-aidlc-1234", "claude", "/tmp/workspace"},
		got,
		"kind:mixin must keep composing via --kit, with the base agent and workspace as trailing positionals")
}

func TestBuildCreateArgsMixinOnDefaultBase(t *testing.T) {
	got := buildCreateArgs(spec.KindMixin, "/abs/qemu", "e2e-qemu-1234", defaultMixinBase, "/tmp/workspace", nil, "")

	require.Equal(t,
		[]string{"create", "--kit", "/abs/qemu", "--name", "e2e-qemu-1234", defaultMixinBase, "/tmp/workspace"},
		got)
	require.Equal(t, defaultMixinBase, got[len(got)-2],
		"the OCI reference must land as the agent positional, right before the workspace")
}

func TestPublishedKitBase(t *testing.T) {
	repo := t.TempDir()
	copySpec := func(kit string) {
		t.Helper()
		data, err := os.ReadFile(filepath.Join("..", kit, "spec.yaml"))
		require.NoError(t, err)
		require.NoError(t, os.MkdirAll(filepath.Join(repo, kit), 0o755))
		require.NoError(t, os.WriteFile(filepath.Join(repo, kit, "spec.yaml"), data, 0o644))
	}
	copySpec("codex")
	copySpec("qemu")

	t.Run("sandbox_kit_is_published", func(t *testing.T) {
		base, ok := publishedKitBase(repo, "codex")
		require.True(t, ok)
		require.Equal(t, "docker.io/sbx/codex-kit:latest", base)
	})
	t.Run("mixin_is_not_a_base", func(t *testing.T) {
		_, ok := publishedKitBase(repo, "qemu")
		require.False(t, ok)
	})
	t.Run("missing_dir", func(t *testing.T) {
		_, ok := publishedKitBase(repo, "nosuchagent")
		require.False(t, ok)
	})
	t.Run("agent_with_a_path_separator", func(t *testing.T) {
		_, ok := publishedKitBase(repo, "../codex")
		require.False(t, ok)
		_, ok = publishedKitBase(repo, "codex/x")
		require.False(t, ok)
	})
	t.Run("empty_agent", func(t *testing.T) {
		_, ok := publishedKitBase(repo, "")
		require.False(t, ok)
	})
}

func TestAgentForKit(t *testing.T) {
	repoRoot := filepath.Join("..")
	mixin := func(requires string) *spec.Artifact {
		a := &spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "some-mixin"}}
		if requires != "" {
			a.Requires = &spec.Requires{Agent: requires}
		}
		return a
	}
	const pinned = "docker.io/sbx/x:latest"

	tests := []struct {
		name         string
		art          *spec.Artifact
		env          string
		wantPosition string
		wantFallback string
	}{
		{"sandbox returns manifest name",
			&spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindSandbox, Name: "kiro"}}, "", "kiro", ""},
		{"affinity to a published kit", mixin("codex"), "", "docker.io/sbx/codex-kit:latest", "codex"},
		{"affinity to an unpublished agent", mixin("nosuchagent"), "", "nosuchagent", ""},
		{"affinity to claude, no pin", mixin("claude"), "", defaultMixinBase, "claude"},
		{"affinity to claude, pinned", mixin("claude"), pinned, pinned, ""},
		{"no affinity, no pin", mixin(""), "", defaultMixinBase, "claude"},
		{"no affinity, pinned", mixin(""), pinned, pinned, ""},
		{"no affinity, blank pin", mixin(""), "  ", defaultMixinBase, "claude"},
		{"affinity to codex ignores the pin", mixin("codex"), pinned, "docker.io/sbx/codex-kit:latest", "codex"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv(mixinBaseEnv, tc.env)
			gotPos, gotFallback := agentForKit(tc.art, repoRoot)
			require.Equal(t, tc.wantPosition, gotPos)
			require.Equal(t, tc.wantFallback, gotFallback)
		})
	}
}

func TestBuildCreateArgsMixinWithKitArgFlags(t *testing.T) {
	got := buildCreateArgs(spec.KindMixin, "/abs/aidlc-claude", "e2e-aidlc-1234", "claude", "/tmp/workspace",
		[]string{"--kit-arg", "aidlc-claude.affinity=bedrock"}, "")

	require.Equal(t,
		[]string{
			"create", "--kit", "/abs/aidlc-claude", "--name", "e2e-aidlc-1234",
			"--kit-arg", "aidlc-claude.affinity=bedrock",
			"claude", "/tmp/workspace",
		},
		got,
		"kit-arg flags must land between --name and the agent/workspace positionals")
}

func TestBuildCreateArgsTreatsOnlyKindSandboxAsBase(t *testing.T) {
	args := buildCreateArgs(spec.KindAgent, "/abs/k", "n", "claude", "/ws", nil, "")
	require.Contains(t, args, "--kit", "an unnormalized v1 kind is not recognized as a base here")
}

func TestBuildCreateArgsSandboxWithPullPolicy(t *testing.T) {
	got := buildCreateArgs(spec.KindSandbox, "/abs/kiro", "e2e-kiro-1234", "kiro", "/tmp/workspace", nil, "never")

	require.Equal(t,
		[]string{"create", "/abs/kiro", "--name", "e2e-kiro-1234", "--pull=never", "/tmp/workspace"},
		got,
		"--pull must follow --name, before the workspace positional")
}

func TestBuildCreateArgsMixinWithPullPolicy(t *testing.T) {
	got := buildCreateArgs(spec.KindMixin, "/abs/aidlc-claude", "e2e-aidlc-1234", "claude", "/tmp/workspace", nil, "missing")

	require.Equal(t,
		[]string{
			"create", "--kit", "/abs/aidlc-claude", "--name", "e2e-aidlc-1234",
			"--pull=missing", "claude", "/tmp/workspace",
		},
		got,
		"--pull must follow --name, before the agent/workspace positionals")
}

func TestShouldFallBackToBuiltin(t *testing.T) {
	collisionOut := `ERROR: agent "claude" is already registered (` + builtinCollisionMarker + ")"
	codexOut := `ERROR: agent "codex" is already registered (` + builtinCollisionMarker + ")"
	const codexKit = "docker.io/sbx/codex-kit:latest"
	fail := errors.New("exit status 1")

	tests := []struct {
		name     string
		kind     string
		agent    string
		fallback string
		err      error
		out      string
		want     bool
	}{
		{"mixin on default, collision", spec.KindMixin, defaultMixinBase, "claude", fail, collisionOut, true},
		{"mixin on default, other failure", spec.KindMixin, defaultMixinBase, "claude", fail, "ERROR: image pull failed", false},
		{"mixin on default, no error", spec.KindMixin, defaultMixinBase, "claude", nil, collisionOut, false},
		{"mixin on default, collision names another agent", spec.KindMixin, defaultMixinBase, "claude", fail,
			`ERROR: agent "qemu" is already registered (` + builtinCollisionMarker + ")", false},
		{"sandbox on default, collision", spec.KindSandbox, defaultMixinBase, "claude", fail, collisionOut, false},
		{"mixin on pinned base, no fallback", spec.KindMixin, "docker.io/sbx/shell-docker-kit:latest", "", fail, collisionOut, false},
		{"mixin already on the built-in", spec.KindMixin, "claude", "claude", fail, collisionOut, false},
		{"mixin on codex kit, collision names codex", spec.KindMixin, codexKit, "codex", fail, codexOut, true},
		{"mixin on codex kit, collision names claude", spec.KindMixin, codexKit, "codex", fail, collisionOut, false},
		{"mixin on codex kit, no fallback", spec.KindMixin, codexKit, "", fail, codexOut, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, shouldFallBackToBuiltin(tc.kind, tc.agent, tc.fallback, tc.err, tc.out))
		})
	}
}

func TestIsBuiltinCollision(t *testing.T) {
	collisionOut := `ERROR: agent "kiro" is already registered (` + builtinCollisionMarker + ")"

	tests := []struct {
		name string
		err  error
		out  string
		want bool
	}{
		{"collision", errors.New("exit status 1"), collisionOut, true},
		{"other failure", errors.New("exit status 1"), "ERROR: image pull failed", false},
		{"collision text without a failure", nil, collisionOut, false},
		{"success", nil, "created", false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, isBuiltinCollision(tc.err, tc.out))
		})
	}
}

func TestIsHubThrottled(t *testing.T) {
	const throttled = "error: resolve kits: load kit policy: read kit.allowedSources: administrator settings are unavailable"
	tests := []struct {
		name string
		err  error
		out  string
		want bool
	}{
		{"failure with the marker", errors.New("exit status 1"), throttled, true},
		{"failure with other text", errors.New("exit status 1"), "error: kit not found", false},
		{"success mentioning the marker", nil, throttled, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.want, isHubThrottled(tt.err, tt.out))
		})
	}
}
