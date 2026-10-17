package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

// TestNewV2View_RendersV2Grammar checks the internal → v2 block renames that
// are the whole point of the projection: the canonical field names are the
// engine's internal vocabulary and several are not valid v2 YAML keys.
func TestNewV2View_RendersV2Grammar(t *testing.T) {
	a := &Artifact{
		Manifest: Manifest{
			SchemaVersion: "1",
			Kind:          KindSandbox,
			Name:          "kit",
			Template:      "img:latest",
			AIFilename:    "AGENT.md",
			Binary:        "agentbin",
			RunOptions:    []string{"-l"},
			Resources:     &Resources{CPU: 2, MemoryMB: 4096, GPU: "1"},
		},
		AgentContext: "ctx",
		Caps:         &Caps{Network: &CapsNetwork{Allow: []string{"a.example.com"}}},
		Environment:  &EnvironmentPolicy{Variables: map[string]string{"K": "v"}},
		Commands:     &CommandsPolicy{InitFiles: []InitFile{{Path: "/p", Content: "c"}}},
	}

	v := NewV2View(a)

	// template -> sandbox.image, memoryMB -> byte-size memory.
	require.NotNil(t, v.Sandbox)
	require.Equal(t, "img:latest", v.Sandbox.Image)
	require.Equal(t, "4096m", v.Sandbox.Resources.Memory)
	// aiFilename + agentContext -> agentInstructions.
	require.Equal(t, "AGENT.md", v.AgentInstructions.Filename)
	require.Equal(t, "ctx", v.AgentInstructions.Content)
	// caps -> permissions.
	require.Equal(t, []string{"a.example.com"}, v.Permissions.Network.Allow)
	// commands.initFiles -> setup.files.
	require.Len(t, v.Setup.Files, 1)
	require.Equal(t, map[string]string{"K": "v"}, v.Environment.Variables)

	// SchemaVersion is carried through, not silently promoted: only a caller
	// rewriting the kit (the migrator) may claim "2".
	require.Equal(t, "1", v.SchemaVersion)
}

// Empty blocks must be omitted so the output reads like an authored
// spec.yaml rather than a struct dump.
func TestNewV2View_OmitsEmptyBlocks(t *testing.T) {
	v := NewV2View(&Artifact{
		Manifest: Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "m"},
	})
	require.Nil(t, v.Sandbox)
	require.Nil(t, v.AgentInstructions)
	require.Nil(t, v.Permissions)
	require.Nil(t, v.Environment)
	require.Nil(t, v.Setup)

	out, err := yaml.Marshal(v)
	require.NoError(t, err)
	require.Equal(t, "schemaVersion: \"2\"\nkind: mixin\nname: m\n", string(out))
}

// A mixin must never gain a sandbox: block (SPEC-v2 §4.1 makes it a hard
// error), so an artifact carrying nothing sandbox-shaped must not produce one.
func TestNewV2View_NoSandboxBlockWithoutSandboxFields(t *testing.T) {
	v := NewV2View(&Artifact{
		Manifest:    Manifest{SchemaVersion: "2", Kind: KindMixin, Name: "m"},
		Credentials: []Credential{{Service: "svc"}},
	})
	require.Nil(t, v.Sandbox)
}

func TestSetSandboxEntrypoint(t *testing.T) {
	t.Run("restores_the_authors_split", func(t *testing.T) {
		// The loader folds an entrypoint tail into RunOptions, so the
		// projection alone cannot tell "entrypoint: [bin, --always]" from
		// "entrypoint: [bin]" + "command.default: [--always]".
		a := &Artifact{Manifest: Manifest{
			SchemaVersion: "2", Kind: KindSandbox, Name: "k", Template: "img",
			Binary: "bin", RunOptions: []string{"--always", "-l"},
		}}
		v := NewV2View(a)
		require.Equal(t, []string{"bin"}, v.Sandbox.Entrypoint)
		require.Equal(t, []string{"--always", "-l"}, v.Sandbox.Command.Default)

		v.SetSandboxEntrypoint([]string{"bin", "--always"}, []string{"-l"}, nil)
		require.Equal(t, []string{"bin", "--always"}, v.Sandbox.Entrypoint)
		require.Equal(t, []string{"-l"}, v.Sandbox.Command.Default)
	})

	t.Run("no_command_block_when_no_tail", func(t *testing.T) {
		v := NewV2View(&Artifact{Manifest: Manifest{
			SchemaVersion: "2", Kind: KindSandbox, Name: "k", Template: "img",
			Binary: "bin", RunOptions: []string{"-l"},
		}})
		v.SetSandboxEntrypoint([]string{"bin", "-l"}, nil, nil)
		require.Nil(t, v.Sandbox.Command, "an empty command: block must not be emitted")
	})

	t.Run("creates_sandbox_block_if_absent", func(t *testing.T) {
		v := NewV2View(&Artifact{Manifest: Manifest{SchemaVersion: "2", Kind: KindSandbox, Name: "k"}})
		require.Nil(t, v.Sandbox)
		v.SetSandboxEntrypoint([]string{"bin"}, nil, nil)
		require.NotNil(t, v.Sandbox)
		require.Equal(t, []string{"bin"}, v.Sandbox.Entrypoint)
	})
}

// The emitted YAML must load back through the v2 grammar. This is what makes
// the view safe to write to disk: a projection that emitted an internal name
// would fail the v2 decoder's strict field check.
func TestNewV2View_RoundTripsThroughV2Loader(t *testing.T) {
	a := &Artifact{
		Manifest: Manifest{
			SchemaVersion: "2", Kind: KindSandbox, Name: "round", Template: "img:1",
			Binary: "bin", RunOptions: []string{"-l"}, AIFilename: "A.md",
			Resources: &Resources{MemoryMB: 2048},
		},
		AgentContext:   "ctx",
		Licenses:       []string{"MIT"},
		Args:           map[string]KitArg{"version": {Default: strPtr("latest"), Description: "which version"}},
		Caps:           &Caps{Network: &CapsNetwork{Allow: []string{"h.example.com"}, Deny: []string{"bad.example.com"}}},
		PublishedPorts: []PublishedPort{{Container: 8080, Name: "web"}},
		Environment:    &EnvironmentPolicy{Variables: map[string]string{"A": "b"}},
		Commands:       &CommandsPolicy{Install: []InstallCommand{{Command: "echo hi"}}},
	}

	out, err := yaml.Marshal(NewV2View(a))
	require.NoError(t, err)

	got, err := LoadArtifactFromBytes(out)
	require.NoError(t, err, "emitted v2 spec must load through the v2 grammar:\n%s", out)
	require.Empty(t, got.Warnings, "a canonical v2 emit must not trigger deprecation warnings")

	require.Equal(t, "img:1", got.Manifest.Template)
	require.Equal(t, "A.md", got.Manifest.AIFilename)
	require.Equal(t, "ctx", got.AgentContext)
	require.Equal(t, []string{"MIT"}, got.Licenses)
	require.Equal(t, map[string]KitArg{"version": {Default: strPtr("latest"), Description: "which version"}}, got.Args)
	require.Equal(t, []string{"h.example.com"}, got.Caps.Network.Allow)
	require.Equal(t, []string{"bad.example.com"}, got.Caps.Network.Deny)
	require.Len(t, got.PublishedPorts, 1)
	require.Equal(t, int64(2048), got.Manifest.Resources.MemoryMB)
	require.Len(t, got.Commands.Install, 1)
}

// Regression: licenses and mixins have no home in a hand-maintained emit
// struct unless someone remembers to add them. They were both silently
// dropped before this projection became the single implementation.
func TestNewV2View_PreservesLicensesAndMixins(t *testing.T) {
	v := NewV2View(&Artifact{
		Manifest: Manifest{SchemaVersion: "2", Kind: KindSandbox, Name: "k", Template: "img"},
		Licenses: []string{"MIT", "Apache-2.0"},
		Mixins:   []string{"some-mixin"},
	})
	require.Equal(t, []string{"MIT", "Apache-2.0"}, v.Licenses)
	require.Equal(t, []string{"some-mixin"}, v.Mixins)

	out, err := yaml.Marshal(v)
	require.NoError(t, err)
	require.Contains(t, string(out), "licenses:")
	require.Contains(t, string(out), "mixins:")
}
