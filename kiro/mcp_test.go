package kiro

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/docker/sbx-kits-contrib/spec"
)

// TestKiroMCPStartupCommand verifies that the kiro kit registers the
// sandbox's MCP gateway via a commands.startup entry that writes
// ~/.kiro/settings/mcp.json. Under the gateway-first lifecycle,
// sandboxd injects MCP_GATEWAY_URL + MCP_SENTINEL_TOKEN_NAME into the
// container env by the time startup commands run, so the script reads
// them with shell substitution rather than via Go-template rendering.
//
// Shape note: kiro-cli (cli.kiro.dev) reads MCP servers from
// ~/.kiro/settings/mcp.json. A remote/HTTP server is keyed by the
// `url` field plus a `headers` object — no `type` field, no separate
// `httpUrl` key. Per upstream docs:
//
//	https://kiro.dev/docs/cli/mcp/configuration/
//
// (specifically the "Authorization Example" using `Authorization: Bearer …`
// inside `headers`).
func TestKiroMCPStartupCommand(t *testing.T) {
	artifact, err := spec.LoadFromDirectory(".")
	require.NoError(t, err)

	require.NotNil(t, artifact.Commands, "kiro kit must declare commands")
	require.NotEmpty(t, artifact.Commands.Startup, "kiro needs at least one startup command")

	var mcpScript string
	var mcpUser string
	for _, cmd := range artifact.Commands.Startup {
		if len(cmd.Command) < 3 {
			continue
		}
		if strings.Contains(cmd.Command[2], "MCP_GATEWAY_URL") {
			mcpScript = cmd.Command[2]
			mcpUser = cmd.User
			break
		}
	}
	require.NotEmpty(t, mcpScript, "kiro must declare a startup command that registers via $MCP_GATEWAY_URL")
	require.Equal(t, "agent", mcpUser, "write runs as the agent user so the file ownership stays correct")

	// --- Skip-when-not-enabled guard ---
	require.Contains(t, mcpScript, `[ -n "$MCP_GATEWAY_URL" ]`,
		"script must no-op when MCP isn't enabled ($MCP_GATEWAY_URL empty)")

	// --- JSON shape (kiro-cli uses `url`, not `httpUrl`) ---
	require.Contains(t, mcpScript, `"mcp-gateway"`)
	require.Contains(t, mcpScript, `"url": "$MCP_GATEWAY_URL"`,
		"url must reference the gateway via env var")
	require.Contains(t, mcpScript, `"Authorization": "Bearer $MCP_SENTINEL_TOKEN_NAME"`,
		"auth header must reference the sentinel name env var")
	require.NotContains(t, mcpScript, `"httpUrl"`,
		`kiro-cli uses "url" for HTTP MCP servers, not "httpUrl"`)

	// --- Destination ---
	require.Contains(t, mcpScript, "$HOME/.kiro/settings/mcp.json",
		"destination must be the user-level kiro MCP config path")
	require.Contains(t, mcpScript, `mkdir -p "$HOME/.kiro/settings"`,
		"settings/ subdir may not exist on first boot — mkdir -p before writing")
}
