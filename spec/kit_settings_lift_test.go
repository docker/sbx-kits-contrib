package spec

import (
	"os"
	"os/exec"
	"path/filepath"
	"slices"
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
  "permissions": { "defaultMode": "bypassPermissions" },
  "bypassPermissionsModeAccepted": true,
  "skipDangerousModePermissionPrompt": true
}
`
	claudeSettingsAPIKey = `{
  "themeId": 1,
  "alwaysThinkingEnabled": true,
  "apiKeyHelper": "echo proxy-managed",
  "permissions": { "defaultMode": "bypassPermissions" },
  "bypassPermissionsModeAccepted": true,
  "skipDangerousModePermissionPrompt": true
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

// runSettingsInstallScript runs the kit's settings-seeding install script in a
// fresh temp home and returns the content of the produced settings.json.
func runSettingsInstallScript(t *testing.T, script, modeEnv string) string {
	t.Helper()
	tmp := t.TempDir()
	runSettingsScriptIn(t, tmp, script, modeEnv)

	data, err := os.ReadFile(filepath.Join(tmp, ".claude", "settings.json"))
	require.NoError(t, err)
	return string(data)
}

// runSettingsScriptIn executes a settings script with the absolute /home/agent
// paths rewritten to home. Several runs can share one home, the way a recreate
// or restart reuses the same settings.json.
func runSettingsScriptIn(t *testing.T, home, script, modeEnv string) {
	t.Helper()

	// /home/agent -> home so the script writes inside the sandbox of the test.
	script = strings.ReplaceAll(script, "/home/agent", home)

	// The test process is not root, so a no-op chown on PATH stands in for
	// every chown form the kits use, inside traps included.
	bin := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(bin, "chown"), []byte("#!/bin/sh\nexit 0\n"), 0o755))

	cmd := exec.Command("sh", "-c", script)
	// Drop an inherited mode so an empty modeEnv means the variable is unset.
	cmd.Env = slices.DeleteFunc(os.Environ(), func(kv string) bool {
		return strings.HasPrefix(kv, "SBX_CRED_ANTHROPIC_MODE=") || strings.HasPrefix(kv, "PATH=")
	})
	cmd.Env = append(cmd.Env, "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	if modeEnv != "" {
		cmd.Env = append(cmd.Env, modeEnv)
	}
	out, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "settings script failed: %s", out)
}
