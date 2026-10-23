package spec

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

const claudeAPIKeyHelper = "echo proxy-managed"

// TestClaudeSettingsAPIKeyHelper pins which credential modes get Claude Code's
// apiKeyHelper. A subscription must not, or Claude Code disables its claude.ai connectors.
func TestClaudeSettingsAPIKeyHelper(t *testing.T) {
	for _, kit := range []string{"claude", "claude-mixin"} {
		seed := findSettingsInstall(t, loadV3Commands(t, kit)).Command

		for _, tc := range []struct {
			name       string
			modes      []string
			wantHelper string
		}{
			{name: "unset", modes: []string{""}},
			{name: "none", modes: []string{"none"}},
			{name: "api key", modes: []string{"apikey"}, wantHelper: claudeAPIKeyHelper},
			{name: "subscription OAuth", modes: []string{"oauth"}},
			{name: "unknown mode", modes: []string{"unknown"}},
			{name: "recreate from api key to OAuth", modes: []string{"apikey", "oauth"}},
			{name: "recreate from OAuth to api key", modes: []string{"oauth", "apikey"}, wantHelper: claudeAPIKeyHelper},
		} {
			t.Run(kit+"/"+tc.name, func(t *testing.T) {
				home := t.TempDir()
				for _, mode := range tc.modes {
					runSettingsScriptIn(t, home, seed, credModeEnv(mode))
				}
				requireAPIKeyHelper(t, home, tc.wantHelper)
			})
		}
	}
}

// TestClaudeOllamaSettingsAPIKeyHelper keeps the ollama kits' copy of the rule
// in step. They declare no credential, so only a composed base could set a mode.
func TestClaudeOllamaSettingsAPIKeyHelper(t *testing.T) {
	for _, kit := range []string{"claude-ollama", "claude-ollama-mixin"} {
		seed := findSettingsInstall(t, loadV3Commands(t, kit)).Command

		for _, tc := range []struct {
			name       string
			mode       string
			wantHelper string
		}{
			{name: "unset"},
			{name: "none", mode: "none"},
			{name: "api key", mode: "apikey", wantHelper: claudeAPIKeyHelper},
			{name: "subscription OAuth", mode: "oauth"},
		} {
			t.Run(kit+"/"+tc.name, func(t *testing.T) {
				home := t.TempDir()
				runSettingsScriptIn(t, home, seed, credModeEnv(tc.mode))
				requireAPIKeyHelper(t, home, tc.wantHelper)
			})
		}
	}
}

// TestClaudeMemReconcilerAPIKeyHelper runs the claude-mem startup reconciler
// over the settings.json the claude kit seeded, as the composed sandbox does.
func TestClaudeMemReconcilerAPIKeyHelper(t *testing.T) {
	if _, err := exec.LookPath("node"); err != nil {
		if os.Getenv("CI") != "" {
			t.Fatal("the claude-mem reconciler needs node on PATH")
		}
		t.Skip("the claude-mem reconciler needs node on PATH")
	}
	seed := findSettingsInstall(t, loadV3Commands(t, "claude")).Command
	reconciler := findSettingsReconciler(t, loadV3Commands(t, "claude-mem"))
	require.Contains(t, reconciler, "/tmp/claude-mem-reconcile.log")

	for _, tc := range []struct {
		name          string
		seedMode      string
		existing      string
		reconcileMode string
		wantHelper    string
	}{
		{name: "unset"},
		{name: "none", seedMode: "none", reconcileMode: "none"},
		{name: "api key", seedMode: "apikey", reconcileMode: "apikey", wantHelper: claudeAPIKeyHelper},
		{name: "restart after adding an api key", seedMode: "none", reconcileMode: "apikey", wantHelper: claudeAPIKeyHelper},
		{name: "subscription OAuth", seedMode: "oauth", reconcileMode: "oauth"},
		{name: "unknown mode", seedMode: "unknown", reconcileMode: "unknown"},
		{name: "restart after switching to OAuth", seedMode: "apikey", reconcileMode: "oauth"},
		{name: "restart after removing the credential", seedMode: "apikey", reconcileMode: "none"},
		{
			name:          "OAuth keeps a custom helper",
			existing:      `{"themeId": 1, "apiKeyHelper": "my-helper"}`,
			reconcileMode: "oauth",
			wantHelper:    "my-helper",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			if tc.existing != "" {
				require.NoError(t, os.MkdirAll(filepath.Join(home, ".claude"), 0o755))
				require.NoError(t, os.WriteFile(filepath.Join(home, ".claude", "settings.json"), []byte(tc.existing), 0o644))
			} else {
				runSettingsScriptIn(t, home, seed, credModeEnv(tc.seedMode))
			}

			logPath := filepath.Join(home, "reconcile.log")
			t.Cleanup(func() {
				if t.Failed() {
					log, _ := os.ReadFile(logPath)
					t.Logf("reconcile log:\n%s", log)
				}
			})
			script := strings.ReplaceAll(reconciler, "/tmp/claude-mem-reconcile.log", logPath)
			runSettingsScriptIn(t, home, script, credModeEnv(tc.reconcileMode))
			requireAPIKeyHelper(t, home, tc.wantHelper)
		})
	}
}

// loadV3Commands decodes the lifecycle@1 capability of ../<kit>/<kit>.yaml.
// Its install and startup entries share CommandsPolicy's field names.
func loadV3Commands(t *testing.T, kit string) *CommandsPolicy {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", kit, kit+".yaml"))
	require.NoError(t, err)
	var descriptor struct {
		Capabilities []struct {
			Type   string    `yaml:"type"`
			Config yaml.Node `yaml:"config"`
		} `yaml:"capabilities"`
	}
	require.NoError(t, yaml.Unmarshal(data, &descriptor))
	for _, c := range descriptor.Capabilities {
		if c.Type == "com.docker.sandbox/lifecycle@1" {
			var commands CommandsPolicy
			require.NoError(t, c.Config.Decode(&commands))
			return &commands
		}
	}
	t.Fatalf("%s declares no lifecycle@1 capability", kit)
	return nil
}

// credModeEnv returns the SBX_CRED_ANTHROPIC_MODE assignment for mode, or ""
// for an empty mode so the variable stays unset.
func credModeEnv(mode string) string {
	if mode == "" {
		return ""
	}
	return "SBX_CRED_ANTHROPIC_MODE=" + mode
}

// findSettingsReconciler returns the startup script that merges into
// settings.json (the one whose script references SBX_CRED_..._MODE).
func findSettingsReconciler(t *testing.T, c *CommandsPolicy) string {
	t.Helper()
	require.NotNil(t, c, "kit must have commands")
	for _, sc := range c.Startup {
		if len(sc.Command) == 0 {
			continue
		}
		script := sc.Command[len(sc.Command)-1]
		if strings.Contains(script, "settings.json") && strings.Contains(script, "_MODE") {
			return script
		}
	}
	t.Fatalf("no settings.json-reconciling startup command found")
	return ""
}

// requireAPIKeyHelper asserts settings.json carries want as its apiKeyHelper,
// or no apiKeyHelper at all when want is empty.
func requireAPIKeyHelper(t *testing.T, home, want string) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(home, ".claude", "settings.json"))
	require.NoError(t, err)
	var settings map[string]any
	require.NoError(t, json.Unmarshal(data, &settings))
	if want == "" {
		require.NotContains(t, settings, "apiKeyHelper")
		return
	}
	require.Equal(t, want, settings["apiKeyHelper"])
}
