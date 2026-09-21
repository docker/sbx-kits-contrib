package spec

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestClaudeOllamaSettingsLift verifies the Phase 4 Stage C lift of the
// claude-ollama kit. Shared helpers (findSettingsInstall, runSettingsInstallScript)
// and the oracle constants live in kit_settings_lift_test.go.
//
// claude-ollama declares no credential service (Ollama is a local model; the
// wrapper unsets ANTHROPIC_API_KEY and routes Claude Code at
// host.docker.internal:11434), so SBX_CRED_ANTHROPIC_MODE is never set in the
// real container. The lifted install command therefore always takes the unset
// -> none path: settings.json without apiKeyHelper.
func TestClaudeOllamaSettingsLift(t *testing.T) {
	// Reads a frozen copy of the kit's v2 spec.yaml rather than the live
	// directory: the kit itself has since migrated to the v3 descriptor, so
	// there is no v2 spec.yaml in the tree for this to load. The fixture is
	// the v2 artifact this lift was written against, which is what keeps the
	// assertion meaningful now that the v2 grammar is history the package
	// documents rather than a format the repository's kits are authored in.
	a, err := LoadFromDirectory("testdata/claude-ollama-v2")
	require.NoError(t, err)

	// (a) settings: block removed (no settings deprecation warning means the
	// kit no longer carries a v1 settings: block for the shim to absorb).
	require.NotContains(t, strings.Join(a.Warnings, "\n"), "settings",
		"claude-ollama settings block must be removed; got warnings %v", a.Warnings)

	// (b) a commands.install entry exists.
	require.NotNil(t, a.Commands)
	require.NotEmpty(t, a.Commands.Install, "claude-ollama must have commands.install")

	ic := findSettingsInstall(t, a.Commands)
	require.Contains(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE")

	// No credential service: both unset and explicit =none yield the none
	// oracle (no apiKeyHelper).
	require.Equal(t, claudeSettingsNone,
		runSettingsInstallScript(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE=none"))
	require.Equal(t, claudeSettingsNone,
		runSettingsInstallScript(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE="))

	// (c) apikey branch parity: the lifted script is copy-shared across the
	// claude-family kits, so its apikey path must still produce the
	// apiKeyHelper oracle even though this kit never sets the mode in a real
	// container. This guards the shared script contract against drift.
	require.Equal(t, claudeSettingsAPIKey,
		runSettingsInstallScript(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE=apikey"))
}
