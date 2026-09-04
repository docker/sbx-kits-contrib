package tck

import (
	"fmt"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// recordingT is an mcpT that records failures instead of failing the
// enclosing test. It is what lets the negative cases below assert that a
// wrong script *does* trip an assertion — the point of the exercise, since a
// check that cannot fail is worse than no check.
type recordingT struct {
	failed bool
	msgs   []string
}

func (r *recordingT) Errorf(format string, args ...any) {
	r.failed = true
	r.msgs = append(r.msgs, fmt.Sprintf(format, args...))
}

// FailNow must not return: require.* relies on it to stop the assertion chain
// after the first failure. runtime.Goexit unwinds the goroutine that
// captureFailure runs the assertions on, which is the only way to honour that
// contract outside a real *testing.T.
func (r *recordingT) FailNow() { runtime.Goexit() }

func (r *recordingT) Logf(string, ...any) {}

// captureFailure runs fn against a recordingT and reports whether it failed,
// along with everything it complained about.
func captureFailure(fn func(t mcpT)) (failed bool, msg string) {
	rec := &recordingT{}
	done := make(chan struct{})
	go func() {
		defer close(done)
		fn(rec)
	}()
	<-done
	return rec.failed, strings.Join(rec.msgs, "\n")
}

// The two scripts below are the shapes this repo actually ships, trimmed to
// what the assertions look at: a JSON registration in the style of copilot and
// kiro, and a TOML one in the style of codex. Both keep their heredoc bodies
// indented, because that is how they read inside a YAML block scalar and it is
// the case a line-anchored TOML pattern has to tolerate.
const jsonScript = `set -e
[ -n "$MCP_GATEWAY_URL" ] || exit 0
mkdir -p "$HOME/.copilot"
cat > "$HOME/.copilot/mcp-config.json" <<EOF
{
  "mcpServers": {
    "mcp-gateway": {
      "type": "http",
      "url": "$MCP_GATEWAY_URL",
      "headers": {
        "Authorization": "Bearer $MCP_SENTINEL_TOKEN_NAME"
      }
    }
  }
}
EOF
`

const tomlScript = `set -e
[ -n "$MCP_GATEWAY_URL" ] || exit 0
cfg="$HOME/.codex/config.toml"
grep -q "^\[mcp_servers.mcp-gateway\]" "$cfg" && exit 0
cat >> "$cfg" <<EOF

  [mcp_servers.mcp-gateway]
  type = "http"
  url = "$MCP_GATEWAY_URL"
  [mcp_servers.mcp-gateway.http_headers]
  Authorization = "Bearer $MCP_SENTINEL_TOKEN_NAME"
EOF
`

func TestMCPExpectationsValidate(t *testing.T) {
	tests := []struct {
		name    string
		want    mcpExpectations
		format  string
		errText string
	}{
		{
			name:   "empty_format_defaults_to_json",
			want:   mcpExpectations{ConfigPath: "$HOME/.copilot/mcp-config.json"},
			format: mcpFormatJSON,
		},
		{
			name:   "explicit_toml",
			want:   mcpExpectations{ConfigPath: "$HOME/.codex/config.toml", ConfigFormat: "toml"},
			format: mcpFormatTOML,
		},
		{
			name:   "format_is_case_insensitive",
			want:   mcpExpectations{ConfigPath: "$HOME/.codex/config.toml", ConfigFormat: "TOML"},
			format: mcpFormatTOML,
		},
		{
			name:   "unknown_extension_trusts_declared_format",
			want:   mcpExpectations{ConfigPath: "$HOME/.agent/settings", ConfigFormat: "toml"},
			format: mcpFormatTOML,
		},
		{
			name:   "no_config_path",
			want:   mcpExpectations{ConfigFormat: "toml"},
			format: mcpFormatTOML,
		},
		{
			name:    "unknown_format_rejected",
			want:    mcpExpectations{ConfigFormat: "yaml"},
			format:  "yaml",
			errText: `unknown configFormat "yaml"`,
		},
		{
			// The silent-downgrade case the cross-check exists for: a TOML
			// path left at the JSON default would assert JSON syntax against
			// a TOML script, where the forbidden-key checks cannot fail.
			name:    "toml_path_declared_json",
			want:    mcpExpectations{ConfigPath: "$HOME/.codex/config.toml"},
			format:  mcpFormatJSON,
			errText: `is toml, but configFormat says "json"`,
		},
		{
			name:    "json_path_declared_toml",
			want:    mcpExpectations{ConfigPath: "$HOME/.kiro/settings/mcp.json", ConfigFormat: "toml"},
			format:  mcpFormatTOML,
			errText: `is json, but configFormat says "toml"`,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.format, tc.want.format())
			err := tc.want.validate()
			if tc.errText == "" {
				require.NoError(t, err)
				return
			}
			require.ErrorContains(t, err, tc.errText)
		})
	}
}

func TestMCPKeyPatterns(t *testing.T) {
	t.Run("json", func(t *testing.T) {
		present, assigned := mcpKeyPatterns(mcpFormatJSON, "url")

		require.Regexp(t, present, `"url": "$MCP_GATEWAY_URL"`)
		require.Regexp(t, assigned, `"url": "$MCP_GATEWAY_URL"`)

		// A TOML assignment is not a JSON key, and vice versa. This is the
		// gap the format discriminator closes.
		require.NotRegexp(t, present, `url = "$MCP_GATEWAY_URL"`)
		require.NotRegexp(t, assigned, `"url": "https://gateway.example"`)

		// The key must be a key, not a substring of a value.
		require.NotRegexp(t, present, `"httpUrl": "$MCP_GATEWAY_URL"`)
	})

	t.Run("toml", func(t *testing.T) {
		present, assigned := mcpKeyPatterns(mcpFormatTOML, "url")

		require.Regexp(t, present, "url = \"$MCP_GATEWAY_URL\"")
		require.Regexp(t, assigned, "url = \"$MCP_GATEWAY_URL\"")

		// Indented, as a heredoc body inside a YAML block scalar can be.
		require.Regexp(t, assigned, "  url   =  \"$MCP_GATEWAY_URL\"")
		// Quoted keys are legal TOML.
		require.Regexp(t, assigned, "\"url\" = \"$MCP_GATEWAY_URL\"")

		// A literal address is not the env var.
		require.NotRegexp(t, assigned, "url = \"https://gateway.example\"")
		// A longer key that merely ends in the same word is a different key.
		require.NotRegexp(t, present, "base_url = \"$MCP_GATEWAY_URL\"")
		// Not anchored to a line start, so not a key.
		require.NotRegexp(t, present, "echo url = nope")
	})
}

func TestMCPForbiddenPattern(t *testing.T) {
	t.Run("json", func(t *testing.T) {
		re := mcpForbiddenPattern(mcpFormatJSON, "headers")
		require.Regexp(t, re, `"headers": {}`)
		require.NotRegexp(t, re, `"http_headers": {}`)
		// A TOML table is invisible to a JSON pattern — the whole reason
		// codex could not express these assertions before.
		require.NotRegexp(t, re, "[mcp_servers.mcp-gateway.headers]")
	})

	t.Run("toml", func(t *testing.T) {
		re := mcpForbiddenPattern(mcpFormatTOML, "headers")

		// Both ways TOML can name a key.
		require.Regexp(t, re, "headers = { Authorization = \"x\" }")
		require.Regexp(t, re, "[mcp_servers.mcp-gateway.headers]")
		require.Regexp(t, re, "  [headers]")
		require.Regexp(t, re, `  "headers" = {}`)

		// Segment-anchored: the correct key must not read as the wrong one.
		require.NotRegexp(t, re, "[mcp_servers.mcp-gateway.http_headers]")
		require.NotRegexp(t, re, "http_headers = {}")
		// A value, not a key.
		require.NotRegexp(t, re, `type = "headers"`)
	})
}

func TestAssertMCPRegistration(t *testing.T) {
	t.Run("json_kit_passes", func(t *testing.T) {
		assertMCPRegistration(t, "copilot", jsonScript, "agent", &mcpExpectations{
			ConfigPath:    "$HOME/.copilot/mcp-config.json",
			TransportKey:  "url",
			ForbiddenKeys: []string{"httpUrl", "transport"},
		})
	})

	t.Run("toml_kit_passes", func(t *testing.T) {
		assertMCPRegistration(t, "codex", tomlScript, "agent", &mcpExpectations{
			ConfigPath:    "$HOME/.codex/config.toml",
			ConfigFormat:  "toml",
			TransportKey:  "url",
			ForbiddenKeys: []string{"headers", "httpUrl"},
		})
	})

	// Everything below asserts that a wrong script fails. Without these the
	// TOML path would be indistinguishable from no path at all.
	negatives := []struct {
		name    string
		kit     string
		script  string
		user    string
		want    *mcpExpectations
		errText string
	}{
		{
			name:   "toml_wrong_transport_key",
			kit:    "codex",
			script: strings.ReplaceAll(tomlScript, "url = ", "endpoint = "),
			user:   "agent",
			want: &mcpExpectations{
				ConfigPath:   "$HOME/.codex/config.toml",
				ConfigFormat: "toml",
				TransportKey: "url",
			},
			errText: "the gateway URL must be carried by a toml key",
		},
		{
			// The env var is still in the script — just not in the key that
			// matters. This is the case the paired assertion exists for: the
			// format-independent "$MCP_GATEWAY_URL appears in the body" check
			// is satisfied and the config still points somewhere fixed.
			name: "toml_transport_key_holds_literal_address",
			kit:  "codex",
			script: strings.Replace(tomlScript,
				`url = "$MCP_GATEWAY_URL"`,
				"url = \"https://gateway.example\"\necho \"registering $MCP_GATEWAY_URL\"", 1),
			user: "agent",
			want: &mcpExpectations{
				ConfigPath:   "$HOME/.codex/config.toml",
				ConfigFormat: "toml",
				TransportKey: "url",
			},
			errText: "must carry $MCP_GATEWAY_URL, not a literal address",
		},
		{
			// The bug this kit's TCK entry exists to catch: Codex spells the
			// header table `http_headers` and ignores unknown keys, so a
			// `headers` table registers a gateway that sends no
			// Authorization at all and still looks healthy.
			name:   "toml_forbidden_key_as_table_header",
			kit:    "codex",
			script: strings.Replace(tomlScript, "http_headers]", "headers]", 1),
			user:   "agent",
			want: &mcpExpectations{
				ConfigPath:    "$HOME/.codex/config.toml",
				ConfigFormat:  "toml",
				TransportKey:  "url",
				ForbiddenKeys: []string{"headers"},
			},
			errText: `must not use a toml key "headers"`,
		},
		{
			name:   "toml_forbidden_key_as_assignment",
			kit:    "codex",
			script: strings.Replace(tomlScript, "type = \"http\"", "httpUrl = \"x\"", 1),
			user:   "agent",
			want: &mcpExpectations{
				ConfigPath:    "$HOME/.codex/config.toml",
				ConfigFormat:  "toml",
				TransportKey:  "url",
				ForbiddenKeys: []string{"httpUrl"},
			},
			errText: `must not use a toml key "httpUrl"`,
		},
		{
			name:   "json_wrong_transport_key",
			kit:    "copilot",
			script: strings.Replace(jsonScript, `"url":`, `"httpUrl":`, 1),
			user:   "agent",
			want: &mcpExpectations{
				ConfigPath:   "$HOME/.copilot/mcp-config.json",
				TransportKey: "url",
			},
			errText: "the gateway URL must be carried by a json key",
		},
		{
			// A TOML kit that forgets configFormat gets caught rather than
			// silently asserting JSON syntax it can never satisfy.
			name:   "toml_path_left_at_json_default",
			kit:    "codex",
			script: tomlScript,
			user:   "agent",
			want: &mcpExpectations{
				ConfigPath:   "$HOME/.codex/config.toml",
				TransportKey: "url",
			},
			errText: `is toml, but configFormat says "json"`,
		},
		{
			name:   "unknown_format",
			kit:    "codex",
			script: tomlScript,
			user:   "agent",
			want: &mcpExpectations{
				ConfigFormat: "ini",
				TransportKey: "url",
			},
			errText: `unknown configFormat "ini"`,
		},
		{
			name:    "root_user_rejected",
			kit:     "codex",
			script:  tomlScript,
			user:    "root",
			want:    nil,
			errText: "must run as the agent user",
		},
	}

	for _, tc := range negatives {
		t.Run(tc.name, func(t *testing.T) {
			failed, msg := captureFailure(func(rt mcpT) {
				assertMCPRegistration(rt, tc.kit, tc.script, tc.user, tc.want)
			})
			require.True(t, failed, "expected an assertion failure, got none")
			require.Contains(t, msg, tc.errText)
		})
	}
}

// TestAssertMCPRegistrationNoExpectations covers the kit that registers a
// gateway but declares no mcp: block — the format-independent assertions still
// run and the format-dependent ones are skipped with a notice.
func TestAssertMCPRegistrationNoExpectations(t *testing.T) {
	assertMCPRegistration(t, "someagent", tomlScript, "agent", nil)

	failed, msg := captureFailure(func(rt mcpT) {
		assertMCPRegistration(rt, "someagent", "echo no guard here", "agent", nil)
	})
	require.True(t, failed)
	require.Contains(t, msg, "registration must no-op when MCP is not enabled")
}
