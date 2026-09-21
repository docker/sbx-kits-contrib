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
