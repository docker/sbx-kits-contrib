package tck

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

// Config formats an agent's MCP registration can be written in. The key
// assertions below are the only part of this file that cares: everything else
// about a registration (the guard, the env-var indirection, the absence of a
// literal token, the user it runs as) is the same shell in any format.
const (
	// mcpFormatJSON is the default, and what every kit registering a gateway
	// used before TOML turned up: a key is a quoted string followed by `:`.
	mcpFormatJSON = "json"

	// mcpFormatTOML: a key is a bare word followed by `=`, or the last
	// segment of a `[table.header]`. No quotes, no colon.
	mcpFormatTOML = "toml"
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

	// ConfigFormat is the syntax of that file: "json" (the default) or
	// "toml". It decides how TransportKey and ForbiddenKeys are matched.
	//
	// Explicit rather than inferred from ConfigPath's extension, for two
	// reasons. ConfigPath is optional, so inference would have nothing to go
	// on for a kit that omits it and would silently fall back to JSON — and
	// silently falling back to JSON is exactly the failure this field exists
	// to prevent, because JSON-shaped ForbiddenKeys assertions against a TOML
	// script cannot fail, and a check that cannot fail reads as coverage
	// while providing none. Stating the format also keeps the expectation
	// legible to a reviewer who does not know which agent uses which syntax.
	//
	// Defaulting to "json" is what keeps every kit written before this field
	// existed passing unchanged.
	//
	// The extension is still used, as a cross-check rather than as the
	// source of truth: a ".toml" path declared as "json" (or the reverse) is
	// rejected outright instead of quietly asserting the wrong syntax.
	ConfigFormat string `yaml:"configFormat"`

	// TransportKey is the key carrying the gateway URL, written bare (e.g.
	// "url"). How it is matched follows ConfigFormat: `"url":` in JSON,
	// `url =` in TOML.
	TransportKey string `yaml:"transportKey"`

	// ForbiddenKeys are keys this agent must NOT use — the
	// plausible-but-wrong spellings a neighbouring agent uses for the same
	// concept. Also written bare, and also matched per ConfigFormat.
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

// mcpT is the subset of *testing.T that assertMCPRegistration uses. Narrowing
// it is what lets this package's own tests drive the assertions with a
// recording T and prove that a wrong script really does fail them. An
// assertion nobody has watched fail is not evidence of anything.
type mcpT interface {
	require.TestingT
	Logf(format string, args ...any)
}

// format returns the declared config format, defaulted and normalised.
func (m *mcpExpectations) format() string {
	if m.ConfigFormat == "" {
		return mcpFormatJSON
	}
	return strings.ToLower(m.ConfigFormat)
}

// validate rejects an mcp: block the assertions cannot honour: an unknown
// format, or one that contradicts the extension of the file it describes.
//
// Both are silent-downgrade hazards rather than cosmetic complaints. An
// unrecognised value would otherwise fall through to the JSON default, and a
// ".toml" path left at the default would assert JSON syntax against a TOML
// script — which passes the forbidden-key checks trivially and reports
// coverage the kit does not have.
func (m *mcpExpectations) validate() error {
	format := m.format()
	if format != mcpFormatJSON && format != mcpFormatTOML {
		return fmt.Errorf("unknown configFormat %q: want %q or %q",
			m.ConfigFormat, mcpFormatJSON, mcpFormatTOML)
	}

	// Only extensions this package knows how to match are cross-checked;
	// anything else (no extension, ".jsonc", a bare "settings") is left to
	// the declared value.
	var implied string
	switch strings.ToLower(filepath.Ext(m.ConfigPath)) {
	case ".json":
		implied = mcpFormatJSON
	case ".toml":
		implied = mcpFormatTOML
	default:
		return nil
	}
	if implied != format {
		return fmt.Errorf("configPath %q is %s, but configFormat says %q",
			m.ConfigPath, implied, format)
	}
	return nil
}

// mcpKeyPatterns returns the two regexps that decide whether a registration
// script carries key as its transport key in the given format: present (used
// as a key at all) and assigned (bound to $MCP_GATEWAY_URL).
//
// A JSON key carries its own delimiters — the quotes and the colon — so it is
// unambiguous wherever it appears in the script. A TOML key is a bare word,
// indistinguishable from prose except by position: it must start a line and be
// followed by `=`. That is the one thing a TOML script needs that a JSON one
// does not, and it has a consequence for scripts embedded in a spec: the
// patterns are multi-line and tolerate leading whitespace, because a heredoc
// body inside a YAML block scalar keeps whatever indentation the author gave
// it relative to the scalar. Quoted TOML keys (`"url" = …`) are legal and
// matched too, though nothing in this repo writes them.
func mcpKeyPatterns(format, key string) (present, assigned *regexp.Regexp) {
	k := regexp.QuoteMeta(key)
	if format == mcpFormatTOML {
		return regexp.MustCompile(`(?m)^[ \t]*"?` + k + `"?[ \t]*=`),
			regexp.MustCompile(`(?m)^[ \t]*"?` + k + `"?[ \t]*=[ \t]*"\$MCP_GATEWAY_URL"`)
	}
	return regexp.MustCompile(`"` + k + `"\s*:`),
		regexp.MustCompile(`"` + k + `"\s*:\s*"\$MCP_GATEWAY_URL"`)
}

// mcpForbiddenPattern matches key used as a key anywhere in a script of the
// given format.
//
// Deliberately broader than mcpKeyPatterns' present: this is a negative
// assertion, so being generous about what counts as "the agent used this key"
// makes it stronger, not weaker. In JSON that means the quoted key with no
// colon required. In TOML it means both ways a key can be named: a bare
// assignment, and the final segment of a table header — the latter being the
// form that actually matters, since a nested table is how a wrong key reaches
// a TOML config in practice.
//
// The table form is segment-anchored so a longer key that merely ends in the
// forbidden one does not trip it: `headers` must not match
// `[mcp_servers.mcp-gateway.http_headers]`.
func mcpForbiddenPattern(format, key string) *regexp.Regexp {
	k := regexp.QuoteMeta(key)
	if format == mcpFormatTOML {
		return regexp.MustCompile(`(?m)^[ \t]*(?:` +
			`"?` + k + `"?[ \t]*=` +
			`|\[[ \t]*(?:[^]\n]*\.[ \t]*)?"?` + k + `"?[ \t]*\])`)
	}
	return regexp.MustCompile(`"` + k + `"`)
}

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
		assertMCPRegistration(t, s.Artifact.Manifest.Name, script, user, want)
	})
}

// assertMCPRegistration holds the whole body of the mcp_registration subtest.
// Split out from RunMCPRegistrationTests so it can be driven with a script and
// an expectation directly, without a kit directory on disk behind it.
func assertMCPRegistration(t mcpT, kit, script, user string, want *mcpExpectations) {
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
			"testdata/tck.yaml, so its config format is unverified", kit)
		return
	}

	require.NoErrorf(t, want.validate(), "invalid mcp: block in %s/testdata/tck.yaml", kit)
	format := want.format()

	if want.ConfigPath != "" {
		require.Contains(t, script, want.ConfigPath,
			"registration must write %s", want.ConfigPath)
	}
	if want.TransportKey != "" {
		present, assigned := mcpKeyPatterns(format, want.TransportKey)
		require.Regexp(t, present, script,
			"the gateway URL must be carried by a %s key %q", format, want.TransportKey)

		// Pair the key with the value. Asserting each separately passes a
		// config whose transport key holds a literal URL while the env var
		// appears only somewhere else in the script.
		require.Regexp(t, assigned, script,
			"%q must carry $MCP_GATEWAY_URL, not a literal address", want.TransportKey)
	}
	for _, forbidden := range want.ForbiddenKeys {
		require.NotRegexp(t, mcpForbiddenPattern(format, forbidden), script,
			"%s must not use a %s key %q — see the mcp: block in testdata/tck.yaml",
			kit, format, forbidden)
	}
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
