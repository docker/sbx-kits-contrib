package bindings

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"go.yaml.in/yaml/v3"
)

func TestLoad_ParsesExampleFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte(`
bindings:
  anthropic:
    discovery:
      - env: [ANTHROPIC_API_KEY]
    allowedDomains: [api.anthropic.com]

  github:
    discovery:
      - env: [GH_TOKEN, GITHUB_TOKEN]
      - file:
          path: ~/.config/gh/token
    allowedDomains: [api.github.com, github.com]
`), 0o600))

	b, err := Load(path)
	require.NoError(t, err)
	require.NotNil(t, b)
	require.Contains(t, b.Bindings, "anthropic")
	require.Len(t, b.Bindings["anthropic"].Discovery, 1)
	require.Equal(t, []string{"ANTHROPIC_API_KEY"}, b.Bindings["anthropic"].Discovery[0].Env)
	require.Equal(t, []string{"api.anthropic.com"}, b.Bindings["anthropic"].AllowedDomains)

	require.Contains(t, b.Bindings, "github")
	require.Len(t, b.Bindings["github"].Discovery, 2)
	require.Equal(t, []string{"GH_TOKEN", "GITHUB_TOKEN"}, b.Bindings["github"].Discovery[0].Env)
	require.NotNil(t, b.Bindings["github"].Discovery[1].File)
	require.Equal(t, "~/.config/gh/token", b.Bindings["github"].Discovery[1].File.Path)
}

func TestLoad_MissingFileIsError(t *testing.T) {
	_, err := Load("/nonexistent/credentials.yaml")
	require.Error(t, err)
}

func TestLoad_EmptyPathIsError(t *testing.T) {
	_, err := Load("")
	require.Error(t, err)
}

func TestLoad_MalformedYAMLRejected(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte("bindings:\n  : oops\n  - unbalanced"), 0o600))
	_, err := Load(path)
	require.ErrorContains(t, err, "parse")
}

func TestLoad_DiscoveryWithBothEnvAndFileRejected(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte(`
bindings:
  bad:
    discovery:
      - env: [FOO]
        file:
          path: ~/foo
    allowedDomains: [foo.example.com]
`), 0o600))
	_, err := Load(path)
	require.ErrorContains(t, err, "exactly one of env or file")
}

func TestLoad_EmptyDiscoveryAccepted(t *testing.T) {
	// Discovery is optional — a binding with only allowedDomains is the
	// canonical way to express "the value lives in the secret store, I'm
	// just declaring the trust scope here." The resolver consults the
	// store before any user-declared discovery entries so an empty
	// discovery list is well-formed.
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte(`
bindings:
  store-only:
    discovery: []
    allowedDomains: [foo.example.com]
`), 0o600))
	b, err := Load(path)
	require.NoError(t, err)
	require.Equal(t, []string{"foo.example.com"}, b.Bindings["store-only"].AllowedDomains)
	require.Empty(t, b.Bindings["store-only"].Discovery)
}

func TestLoad_FilePathRequired(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte(`
bindings:
  bad:
    discovery:
      - file: {}
    allowedDomains: [foo.example.com]
`), 0o600))
	_, err := Load(path)
	require.ErrorContains(t, err, "file.path is required")
}

func TestDefaultPath_ResolvesXDGConfigHome(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("XDG_CONFIG_HOME is a non-Windows convention")
	}
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)

	path := DefaultPath()
	require.True(t, strings.HasPrefix(path, dir),
		"DefaultPath should resolve under XDG_CONFIG_HOME (%q), got %q", dir, path)
	require.True(t, strings.HasSuffix(path, "sbx/credentials.yaml"),
		"DefaultPath should end with sbx/credentials.yaml, got %q", path)
}

func TestDefaultPath_FallsBackToHomeDir(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("home-dir convention is non-Windows")
	}
	t.Setenv("XDG_CONFIG_HOME", "")

	path := DefaultPath()
	home, err := os.UserHomeDir()
	require.NoError(t, err)
	require.True(t, strings.HasPrefix(path, home),
		"DefaultPath should fall back under $HOME (%q), got %q", home, path)
	require.True(t, strings.HasSuffix(path, ".config/sbx/credentials.yaml"),
		"DefaultPath should end with .config/sbx/credentials.yaml on non-Windows, got %q", path)
}

// TestUserBindings_RoundTripPreservesRememberedAndVariants guards D11: the
// sandboxes-side consent flow rewrites credentials.yaml via yaml.Marshal of
// this struct, so any section the struct does not model is silently dropped
// on save. Named-variant keys (service@variant) and the remembered section
// are RFC P2 features we do not implement yet but MUST not destroy when a
// user has hand-written them. This test loads a file containing both, marshals
// it back out, reloads, and asserts nothing was lost.
func TestUserBindings_RoundTripPreservesRememberedAndVariants(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "credentials.yaml")
	require.NoError(t, os.WriteFile(path, []byte(`
bindings:
  github:
    discovery:
      - env: [GITHUB_TOKEN]
    allowedDomains: [api.github.com, github.com]
  github@work-org-a:
    discovery:
      - env: [ORG_A_GITHUB_TOKEN]
    allowedDomains: [api.github.com]
remembered:
  /Users/me/work/org-a:
    github: github@work-org-a
  /Users/me/personal/oss:
    github: github
`), 0o600))

	first, err := Load(path)
	require.NoError(t, err)
	require.Contains(t, first.Bindings, "github@work-org-a")
	require.Equal(t, "github@work-org-a", first.Remembered["/Users/me/work/org-a"]["github"])
	require.Equal(t, "github", first.Remembered["/Users/me/personal/oss"]["github"])

	// Re-marshal (what the CLI saveBindings does) and reload.
	out, err := yaml.Marshal(first)
	require.NoError(t, err)
	rewritten := filepath.Join(dir, "rewritten.yaml")
	require.NoError(t, os.WriteFile(rewritten, out, 0o600))

	second, err := Load(rewritten)
	require.NoError(t, err)
	require.Equal(t, first.Remembered, second.Remembered, "remembered section lost on round-trip")
	require.Contains(t, second.Bindings, "github@work-org-a", "named-variant binding lost on round-trip")
	require.Equal(t, first.Bindings, second.Bindings)
}

// TestValidate_ToleratesVariantKeysAndDomainsOnlyBindings locks the contract
// the sandboxes side depends on (D11): a service@variant binding name and a
// binding that declares only allowedDomains (value lives in the secret store,
// discovery empty) must both validate. If a future validation rule wants to
// constrain these, it must do so deliberately and update this test.
func TestValidate_ToleratesVariantKeysAndDomainsOnlyBindings(t *testing.T) {
	b := &UserBindings{
		Bindings: map[string]Binding{
			"anthropic@personal": {
				AllowedDomains: []string{"api.anthropic.com"},
				// Discovery intentionally empty: the value is expected in
				// the secret store under the binding name.
			},
		},
		Remembered: map[string]map[string]string{
			"/work": {"anthropic": "anthropic@personal"},
		},
	}
	require.NoError(t, Validate(b))
}
