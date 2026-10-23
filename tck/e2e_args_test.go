package tck

import (
	"errors"
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

func TestAgentForKit(t *testing.T) {
	t.Run("sandbox_returns_manifest_name", func(t *testing.T) {
		a := &spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindSandbox, Name: "kiro"}}
		require.Equal(t, "kiro", agentForKit(a))
	})

	t.Run("mixin_with_affinity_returns_required_agent", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "aidlc-codex"},
			Requires: &spec.Requires{Agent: "codex"},
		}
		require.Equal(t, "codex", agentForKit(a))
	})

	t.Run("mixin_without_requires_returns_default_base", func(t *testing.T) {
		t.Setenv(mixinBaseEnv, "")
		a := &spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "qemu"}}
		require.Equal(t, defaultMixinBase, agentForKit(a))
	})

	t.Run("mixin_without_requires_honours_env_override", func(t *testing.T) {
		t.Setenv(mixinBaseEnv, "docker.io/sbx/shell-docker-kit:latest")
		a := &spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "qemu"}}
		require.Equal(t, "docker.io/sbx/shell-docker-kit:latest", agentForKit(a))
	})

	t.Run("mixin_requiring_claude_composes_onto_the_base", func(t *testing.T) {
		t.Setenv(mixinBaseEnv, "")
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "aidlc-claude"},
			Requires: &spec.Requires{Agent: "claude"},
		}
		require.Equal(t, defaultMixinBase, agentForKit(a))
	})

	t.Run("mixin_requiring_claude_honours_env_override", func(t *testing.T) {
		t.Setenv(mixinBaseEnv, "docker.io/sbx/shell-docker-kit:latest")
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "aidlc-claude"},
			Requires: &spec.Requires{Agent: "claude"},
		}
		require.Equal(t, "docker.io/sbx/shell-docker-kit:latest", agentForKit(a))
	})

	t.Run("mixin_without_requires_ignores_blank_env_override", func(t *testing.T) {
		t.Setenv(mixinBaseEnv, "  ")
		a := &spec.Artifact{Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "qemu"}}
		require.Equal(t, defaultMixinBase, agentForKit(a))
	})
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
	fail := errors.New("exit status 1")

	tests := []struct {
		name  string
		kind  string
		agent string
		err   error
		out   string
		want  bool
	}{
		{"mixin on default, collision", spec.KindMixin, defaultMixinBase, fail, collisionOut, true},
		{"mixin on default, other failure", spec.KindMixin, defaultMixinBase, fail, "ERROR: image pull failed", false},
		{"mixin on default, no error", spec.KindMixin, defaultMixinBase, nil, collisionOut, false},
		{"mixin on default, collision names another agent", spec.KindMixin, defaultMixinBase, fail,
			`ERROR: agent "qemu" is already registered (` + builtinCollisionMarker + ")", false},
		{"sandbox on default, collision", spec.KindSandbox, defaultMixinBase, fail, collisionOut, false},
		{"mixin on pinned base, collision", spec.KindMixin, "docker.io/sbx/shell-docker-kit:latest", fail, collisionOut, false},
		{"mixin on built-in, collision", spec.KindMixin, "claude", fail, collisionOut, false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, shouldFallBackToBuiltin(tc.kind, tc.agent, tc.err, tc.out))
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
