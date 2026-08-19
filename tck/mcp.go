package tck

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

// mcpExpectations is the `mcp:` block of <kit>/testdata/tck.yaml. It records
// the parts of a gateway registration that depend on the agent's own config
// format, which cannot be derived from the spec: the spec contains the shell
// script, so deriving expectations from it would assert the script against
// itself.
//
// Optional. Without it a kit still gets every format-independent assertion in
// RunMCPRegistrationTests.
type mcpExpectations struct {
	// ConfigPath is the file the script writes, exactly as it appears in the
	// script (env vars unexpanded, e.g. "$HOME/.kiro/settings/mcp.json").
	ConfigPath string `yaml:"configPath"`

	// TransportKey is the JSON key carrying the gateway URL, without quotes
	// (e.g. "url"). Asserted as a JSON key, so `url` matches `"url":`.
	TransportKey string `yaml:"transportKey"`

	// ForbiddenKeys are JSON keys this agent must NOT use — the
	// plausible-but-wrong spellings a neighbouring agent uses for the same
	// concept. Also unquoted.
	ForbiddenKeys []string `yaml:"forbiddenKeys"`
}

// mcpGuard is the no-op guard every registration script must open with. It is
// also the reason assertions about $MCP_GATEWAY_URL must exclude it: the guard
// mentions the variable, so a whole-script check for it is satisfied by the
// guard alone.
const mcpGuard = `[ -n "$MCP_GATEWAY_URL" ]`

// literalTokenPattern matches something shaped like a real bearer credential,
// as opposed to the $MCP_SENTINEL_TOKEN_NAME reference that belongs here.
var literalTokenPattern = regexp.MustCompile(`Bearer\s+[A-Za-z0-9_\-]{16,}`)

// RunMCPRegistrationTests verifies the kit's MCP-gateway registration, if it
// declares one.
//
// A kit wires the sandbox's MCP gateway into its agent with a setup.startup
// command that reads $MCP_GATEWAY_URL and writes the agent's own MCP config
// file. That script is shell embedded in YAML: nothing else validates it, and
// a mistake fails silently at runtime — the sandbox comes up healthy and the
// agent simply has no tools.
//
// Kits that declare no such command are skipped, so this is a no-op for the
// majority that do not register a gateway.
func (s *Suite) RunMCPRegistrationTests(t *testing.T) {
	script, user, ok := s.mcpStartupCommand()

	want := s.loadMCPExpectations(t)
	if !ok {
		// Expectations recorded for a kit that no longer registers anything
		// would otherwise sit unenforced forever.
		require.Nilf(t, want,
			"testdata/tck.yaml declares mcp expectations, but %s has no startup command reading $MCP_GATEWAY_URL",
			s.Artifact.Manifest.Name)
		return
	}

	t.Run("mcp_registration", func(t *testing.T) {
		// Without the guard, a sandbox with no gateway still gets a config
		// written — one pointing at an empty URL, which the agent reports as a
		// broken server rather than as no server at all.
		require.Contains(t, script, mcpGuard,
			"registration must no-op when MCP is not enabled")

		// Deliberately checked against the script with the guard removed. The
		// guard line contains $MCP_GATEWAY_URL itself, so asserting the env var
		// against the whole script is implied by the assertion above and can
		// never fail on its own — it would pass a script that guards on the
		// env var and then writes a hardcoded URL into the config.
		body := strings.Replace(script, mcpGuard, "", 1)
		require.Contains(t, body, "$MCP_GATEWAY_URL",
			"the gateway URL must be written into the config, not merely tested by the guard")

		// Both values are injected into the container environment per sandbox.
		// Baking either into the spec would pin one sandbox's value into an
		// artifact every sandbox shares.
		require.Contains(t, script, "$MCP_SENTINEL_TOKEN_NAME",
			"the auth header must reference the sentinel name")

		// The sentinel is a name; the proxy substitutes the real token per
		// request. Anything token-shaped here is a credential in a public repo.
		require.NotRegexp(t, literalTokenPattern, script,
			"auth header must carry the sentinel name, never a literal token")

		// The config lands under the agent user's $HOME. Writing it as root
		// leaves a file the agent cannot rewrite later.
		require.NotEmpty(t, user, "registration command must set an explicit user")
		require.NotContains(t, []string{"root", "0"}, user,
			"registration must run as the agent user, not root")

		if want == nil {
			t.Logf("%s registers an MCP gateway but declares no mcp: block in "+
				"testdata/tck.yaml, so its config format is unverified", s.Artifact.Manifest.Name)
			return
		}

		if want.ConfigPath != "" {
			require.Contains(t, script, want.ConfigPath,
				"registration must write %s", want.ConfigPath)
		}
		if want.TransportKey != "" {
			key := `"` + want.TransportKey + `"`
			require.Contains(t, script, key,
				"the gateway URL must be carried by %s", key)

			// Pair the key with the value. Asserting each separately passes a
			// config whose transport key holds a literal URL while the env var
			// appears only somewhere else in the script.
			pair := regexp.MustCompile(
				regexp.QuoteMeta(key) + `\s*:\s*"\$MCP_GATEWAY_URL"`)
			require.Regexp(t, pair, script,
				"%s must carry $MCP_GATEWAY_URL, not a literal address", key)
		}
		for _, forbidden := range want.ForbiddenKeys {
			key := `"` + forbidden + `"`
			require.NotContains(t, script, key,
				"%s must not use %s — see the mcp: block in testdata/tck.yaml",
				s.Artifact.Manifest.Name, key)
		}
	})
}

// mcpStartupCommand returns the script body and user of the kit's
// gateway-registration startup command, if it declares one.
func (s *Suite) mcpStartupCommand() (script, user string, ok bool) {
	if s.Artifact == nil || s.Artifact.Commands == nil {
		return "", "", false
	}
	for _, cmd := range s.Artifact.Commands.Startup {
		for _, arg := range cmd.Command {
			if strings.Contains(arg, "MCP_GATEWAY_URL") {
				return arg, cmd.User, true
			}
		}
	}
	return "", "", false
}

// loadMCPExpectations reads the optional `mcp:` block from
// <Dir>/testdata/tck.yaml. Returns nil when the file or the block is absent.
func (s *Suite) loadMCPExpectations(t *testing.T) *mcpExpectations {
	t.Helper()

	if s.Dir == "" {
		return nil
	}

	p := filepath.Join(s.Dir, "testdata", "tck.yaml")
	data, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return nil
	}
	require.NoErrorf(t, err, "read %s", p)

	// Only the mcp: block is decoded; every other key in the file belongs to
	// the e2e harness and is ignored here.
	var doc struct {
		MCP *mcpExpectations `yaml:"mcp"`
	}
	require.NoErrorf(t, yaml.Unmarshal(data, &doc), "parse %s", p)

	return doc.MCP
}
