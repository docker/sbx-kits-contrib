package spec

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestV2LaunchKeepsStructure(t *testing.T) {
	tests := []struct {
		name    string
		sandbox string
		want    *Launch
		run     []string
		inter   []string
	}{
		{
			name:    "list command",
			sandbox: "  entrypoint: [agent, --fixed]\n  command: [--model, sonnet]\n",
			want:    &Launch{Entrypoint: []string{"agent", "--fixed"}, Default: []string{"--model", "sonnet"}},
			run:     []string{"--fixed", "--model", "sonnet"},
			inter:   []string{"--fixed", "--model", "sonnet"},
		},
		{
			name:    "map with interactive",
			sandbox: "  entrypoint: [agent, serve]\n  command:\n    default: [--headless]\n    interactive: [--tui]\n",
			want:    &Launch{Entrypoint: []string{"agent", "serve"}, Default: []string{"--headless"}, Interactive: []string{"--tui"}},
			run:     []string{"serve", "--headless"},
			inter:   []string{"serve", "--tui"},
		},
		{
			name:    "map without interactive",
			sandbox: "  entrypoint: [agent]\n  command:\n    default: [--headless]\n",
			want:    &Launch{Entrypoint: []string{"agent"}, Default: []string{"--headless"}},
			run:     []string{"--headless"},
			inter:   []string{"--headless"},
		},
		{
			name:    "empty interactive",
			sandbox: "  entrypoint: [agent]\n  command:\n    default: [--headless]\n    interactive: []\n",
			want:    &Launch{Entrypoint: []string{"agent"}, Default: []string{"--headless"}, Interactive: []string{}},
			run:     []string{"--headless"},
		},
		{
			name:    "empty list command",
			sandbox: "  entrypoint: [agent, sub]\n  command: []\n",
			want:    &Launch{Entrypoint: []string{"agent", "sub"}, Default: []string{}},
			run:     []string{"sub"},
			inter:   []string{"sub"},
		},
		{
			name:    "entrypoint only",
			sandbox: "  entrypoint: [agent, sub]\n",
			want:    &Launch{Entrypoint: []string{"agent", "sub"}},
			run:     []string{"sub"},
			inter:   []string{"sub"},
		},
		{
			name:    "command only",
			sandbox: "  command: [-l]\n",
			want:    &Launch{Default: []string{"-l"}},
			run:     []string{"-l"},
			inter:   []string{"-l"},
		},
		{
			name: "neither",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a, err := LoadArtifactFromBytes([]byte("schemaVersion: \"2\"\nkind: sandbox\nname: k\nsandbox:\n  image: img\n" + tt.sandbox))
			require.NoError(t, err)
			m := a.Manifest
			require.Equal(t, tt.want, m.Launch)
			if tt.want != nil {
				// nil and empty differ in Launch; require.Equal checks that.
				require.Equal(t, tt.want.Interactive == nil, m.Launch.Interactive == nil)
				require.Equal(t, tt.want.Default == nil, m.Launch.Default == nil)
			}
			// The flat fields keep their existing values.
			require.Equal(t, tt.run, m.RunOptions)
			require.Equal(t, tt.inter, m.InteractiveOptions)
		})
	}
}

func TestLaunchNotSerialized(t *testing.T) {
	a, err := LoadArtifactFromBytes([]byte("schemaVersion: \"2\"\nkind: sandbox\nname: k\nsandbox:\n  image: img\n  entrypoint: [agent, --fixed]\n  command: [--x]\n"))
	require.NoError(t, err)
	require.NotNil(t, a.Manifest.Launch)
	with, err := json.Marshal(a)
	require.NoError(t, err)
	a.Manifest.Launch = nil
	without, err := json.Marshal(a)
	require.NoError(t, err)
	require.Equal(t, string(without), string(with), "Launch must not change content identity")
}

func TestV1HasNoLaunch(t *testing.T) {
	a, err := LoadArtifactFromBytes([]byte("schemaVersion: \"1\"\nkind: sandbox\nname: k\nsandbox:\n  image: img\n  entrypoint:\n    run: [agent, --fixed]\n    args: [--x]\n"))
	require.NoError(t, err)
	require.Nil(t, a.Manifest.Launch)
	require.Nil(t, a.Manifest.StructuredLaunch())
}

func TestStructuredLaunch(t *testing.T) {
	parent := Manifest{
		Binary:             "claude",
		RunOptions:         []string{"--dangerously-skip-permissions"},
		InteractiveOptions: []string{"--dangerously-skip-permissions"},
		Launch:             &Launch{Entrypoint: []string{"claude", "--dangerously-skip-permissions"}},
	}
	require.Same(t, parent.Launch, parent.StructuredLaunch())

	// A merge that copies the parent and replaces only the flat options
	// (as a field-by-field extends merge does) leaves a stale Launch.
	merged := parent
	merged.RunOptions = []string{"--model", "sonnet"}
	merged.InteractiveOptions = []string{"--model", "sonnet"}
	require.Nil(t, merged.StructuredLaunch())

	// A child Launch without an entrypoint cannot describe the binary.
	merged.Launch = &Launch{Default: []string{"--model", "sonnet"}}
	require.Nil(t, merged.StructuredLaunch())

	// Different binary.
	other := parent
	other.Binary = "codex"
	require.Nil(t, other.StructuredLaunch())

	// Empty interactive tail matches flat options that fell back to nothing.
	empty := Manifest{
		Binary:     "agent",
		RunOptions: []string{"--headless"},
		Launch:     &Launch{Entrypoint: []string{"agent"}, Default: []string{"--headless"}, Interactive: []string{}},
	}
	require.NotNil(t, empty.StructuredLaunch())
	require.Empty(t, empty.StructuredLaunch().InteractiveTail())
}
