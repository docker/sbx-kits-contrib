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
    apiKey:
      domains: [api.anthropic.com]

  github:
    apiKey:
      domains: [api.github.com, github.com]
`), 0o600))

	b, err := Load(path)
	require.NoError(t, err)
	require.NotNil(t, b)
	require.Contains(t, b.Bindings, "anthropic")
	require.NotNil(t, b.Bindings["anthropic"].ApiKey)
	require.Equal(t, []string{"api.anthropic.com"}, b.Bindings["anthropic"].ApiKey.Domains)

	require.Contains(t, b.Bindings, "github")
	require.NotNil(t, b.Bindings["github"].ApiKey)
	require.Equal(t, []string{"api.github.com", "github.com"}, b.Bindings["github"].ApiKey.Domains)
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

// TestUserBindings_RoundTripPreservesRememberedAndVariants guards the contract
// that the sandboxes-side consent flow rewrites credentials.yaml via yaml.Marshal
// of this struct, so any section the struct does not model is silently dropped
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
    apiKey:
      domains: [api.github.com, github.com]
  github@work-org-a:
    apiKey:
      domains: [api.github.com]
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

// TestValidate_ToleratesVariantKeysAndOAuthOnlyBindings locks the contract
// the sandboxes side depends on: a service@variant binding name and a
// binding that declares only OAuth (value is user-granted, no secret store)
// must both validate. If a future validation rule wants to constrain these,
// it must do so deliberately and update this test.
func TestValidate_ToleratesVariantKeysAndOAuthOnlyBindings(t *testing.T) {
	b := &UserBindings{
		Bindings: map[string]Binding{
			"anthropic@personal": {
				OAuth: &OAuthBinding{Domains: []string{"platform.claude.com"}},
			},
		},
		Remembered: map[string]map[string]string{
			"/work": {"anthropic": "anthropic@personal"},
		},
	}
	require.NoError(t, Validate(b))
}

func TestBinding_RoundTrip_PerMechanism(t *testing.T) {
	in := &UserBindings{Bindings: map[string]Binding{
		"anthropic": {
			ApiKey: &ApiKeyBinding{Domains: []string{"api.anthropic.com", "claude.ai"}},
			OAuth:  &OAuthBinding{Domains: []string{"platform.claude.com"}},
		},
		"github": {ApiKey: &ApiKeyBinding{Domains: []string{"api.github.com"}}},
	}}
	data, err := yaml.Marshal(in)
	require.NoError(t, err)
	require.Contains(t, string(data), "apiKey:")
	require.Contains(t, string(data), "oauth:")
	require.NotContains(t, string(data), "discovery")
	require.NotContains(t, string(data), "allowedDomains")

	var out UserBindings
	require.NoError(t, yaml.Unmarshal(data, &out))
	require.Equal(t, in.Bindings, out.Bindings)
}

func TestBinding_NilSafeAccessors(t *testing.T) {
	require.Nil(t, Binding{}.ApiKeyDomains())
	require.Nil(t, Binding{}.OAuthDomains())
	require.Equal(t, []string{"x"}, Binding{ApiKey: &ApiKeyBinding{Domains: []string{"x"}}}.ApiKeyDomains())
	require.Equal(t, []string{"y"}, Binding{OAuth: &OAuthBinding{Domains: []string{"y"}}}.OAuthDomains())
}

func TestBinding_AllDomains(t *testing.T) {
	require.Nil(t, Binding{}.AllDomains())
	// Union, deduped, apiKey-first: api.anthropic.com is shared between both
	// mechanisms and must appear once; platform.claude.com is OAuth-only.
	got := Binding{
		ApiKey: &ApiKeyBinding{Domains: []string{"api.anthropic.com", "console.anthropic.com"}},
		OAuth:  &OAuthBinding{Domains: []string{"api.anthropic.com", "platform.claude.com"}},
	}.AllDomains()
	require.Equal(t, []string{"api.anthropic.com", "console.anthropic.com", "platform.claude.com"}, got)
}

func TestValidate_OK_PerMechanism(t *testing.T) {
	require.NoError(t, Validate(&UserBindings{Bindings: map[string]Binding{
		"anthropic": {OAuth: &OAuthBinding{Domains: []string{"platform.claude.com"}}},
	}}))
}

func TestValidate_EmptyServiceName(t *testing.T) {
	require.Error(t, Validate(&UserBindings{Bindings: map[string]Binding{
		"": {ApiKey: &ApiKeyBinding{Domains: []string{"x"}}},
	}}))
}
