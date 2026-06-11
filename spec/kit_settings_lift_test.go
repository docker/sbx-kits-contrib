package spec

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// Phase 4 Stage C lifted the former `settings: { containerSettings: { claude:
// true } }` block out of the contrib claude-family kits and into a
// commands.install script that seeds ~/.claude/settings.json, branching on the
// SBX_CRED_<SERVICE>_MODE container env var. These oracle strings are the exact
// settings.json the verified claude kit produces for each auth mode; the
// lifted scripts must reproduce them byte-for-byte.
const (
	claudeSettingsNone = `{
  "themeId": 1,
  "alwaysThinkingEnabled": true,
  "defaultMode": "bypassPermissions",
  "bypassPermissionsModeAccepted": true
}
`
	claudeSettingsAPIKey = `{
  "themeId": 1,
  "alwaysThinkingEnabled": true,
  "apiKeyHelper": "echo proxy-managed",
  "defaultMode": "bypassPermissions",
  "bypassPermissionsModeAccepted": true
}
`
)

// findSettingsInstall returns the install command that seeds settings.json
// (the one whose script references SBX_CRED_..._MODE).
func findSettingsInstall(t *testing.T, c *CommandsPolicy) InstallCommand {
	t.Helper()
	require.NotNil(t, c, "kit must have commands")
	for _, ic := range c.Install {
		if strings.Contains(ic.Command, "settings.json") &&
			strings.Contains(ic.Command, "_MODE") {
			return ic
		}
	}
	t.Fatalf("no settings.json-seeding install command found")
	return InstallCommand{}
}

// runSettingsInstallScript executes the kit's settings-seeding install script
// in a temp dir, rewriting the absolute /home/agent paths to the temp dir and
// making chown non-fatal (the test process is not root), then returns the
// content of the produced settings.json.
func runSettingsInstallScript(t *testing.T, script, modeEnv string) string {
	t.Helper()
	tmp := t.TempDir()

	// /home/agent -> tmp so the script writes inside the sandbox of the test.
	script = strings.ReplaceAll(script, "/home/agent", tmp)
	// chown will fail for a non-root test process; keep it non-fatal so the
	// `set -e` script does not abort before/after writing the file.
	script = strings.ReplaceAll(script, "chown -R agent:agent", "chown -R agent:agent 2>/dev/null || true #")

	cmd := exec.Command("sh", "-c", script)
	cmd.Env = append(os.Environ(), modeEnv)
	out, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "install script failed: %s", out)

	data, err := os.ReadFile(filepath.Join(tmp, ".claude", "settings.json"))
	require.NoError(t, err)
	return string(data)
}

func TestNanoclawSettingsLift(t *testing.T) {
	a, err := LoadFromDirectory("../nanoclaw")
	require.NoError(t, err)

	// (a) settings: block removed (no settings deprecation warning means the
	// kit no longer carries a v1 settings: block for the shim to absorb).
	require.NotContains(t, strings.Join(a.Warnings, "\n"), "settings",
		"nanoclaw settings block must be removed; got warnings %v", a.Warnings)

	// (b) a commands.install entry exists.
	require.NotNil(t, a.Commands)
	require.NotEmpty(t, a.Commands.Install, "nanoclaw must have commands.install")

	ic := findSettingsInstall(t, a.Commands)
	require.Contains(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE",
		"nanoclaw declares the anthropic credential service")

	// (c) parity: apikey -> apiKeyHelper present; none -> absent.
	require.Equal(t, claudeSettingsAPIKey,
		runSettingsInstallScript(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE=apikey"))
	require.Equal(t, claudeSettingsNone,
		runSettingsInstallScript(t, ic.Command, "SBX_CRED_ANTHROPIC_MODE=none"))
}
