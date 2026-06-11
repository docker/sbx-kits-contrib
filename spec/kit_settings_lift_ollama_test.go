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
	a, err := LoadFromDirectory("../claude-ollama")
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
}
