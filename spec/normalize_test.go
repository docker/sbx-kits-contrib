package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNormalizeSandbox(t *testing.T) {
	t.Run("populates_manifest_from_sandbox_block", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindSandbox, SchemaVersion: SchemaVersion, Name: "a"},
			Sandbox: &sandboxBlock{
				Image:      "my-image",
				AIFilename: "AI.md",
				Resources:  &Resources{CPU: 4, MemoryMB: 8192, GPU: "1"},
				Entrypoint: &entrypointBlock{
					Run:  []string{"bin", "--flag"},
					Args: []string{"--extra"},
				},
			},
		}
		require.NoError(t, s.normalize(&warnings{}))
		require.Equal(t, "my-image", s.Template)
		require.Equal(t, "bin", s.Binary)
		require.Equal(t, []string{"--flag", "--extra"}, s.RunOptions)
		require.Equal(t, "AI.md", s.AIFilename)
		require.NotNil(t, s.Resources)
		require.InDelta(t, 4.0, s.Resources.CPU, 0.0001)
		require.Equal(t, int64(8192), s.Resources.MemoryMB)
		require.Equal(t, "1", s.Resources.GPU)
	})

	t.Run("rejects_sandbox_block_on_mixin", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Sandbox:  &sandboxBlock{Image: "img"},
		}
		require.ErrorContains(t, s.normalize(&warnings{}), "only valid for kind")
	})

	t.Run("rejects_flat_template_field", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindSandbox, SchemaVersion: SchemaVersion, Name: "a", Template: "img"},
		}
		require.ErrorContains(t, s.normalize(&warnings{}), "sandbox:")
	})

	t.Run("sandbox_requires_sandbox_block", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindSandbox, SchemaVersion: SchemaVersion, Name: "a"},
		}
		require.ErrorContains(t, s.normalize(&warnings{}), "requires a 'sandbox:' block")
	})
}

func TestNormalizeSecrets(t *testing.T) {
	t.Run("converts_to_credential_sources", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Secrets:  []string{"ANTHROPIC_API_KEY", "GH_TOKEN"},
		}
		require.NoError(t, s.normalize(&warnings{}))
		// After normalize, the v1 LegacySources have been folded into
		// Credentials.List as v2 Credential entries.
		services := map[string]Credential{}
		for _, c := range s.Credentials.List {
			services[c.Service] = c
		}
		require.Contains(t, services, "anthropic")
		require.Contains(t, services, "github")
		require.True(t, services["anthropic"].Required)
		require.NotNil(t, services["anthropic"].ApiKey)
		require.Equal(t, "ANTHROPIC_API_KEY", services["anthropic"].ApiKey.Name)
	})

	t.Run("conflict_with_existing_source", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Secrets:  []string{"ANTHROPIC_API_KEY"},
			Credentials: credentialsField{
				LegacySources: map[string]CredentialSource{
					"anthropic": {Env: []string{"EXISTING"}},
				},
			},
		}
		require.ErrorContains(t, s.normalize(&warnings{}), "conflicts")
	})
}

func TestNormalizeEgress(t *testing.T) {
	t.Run("converts_to_network_policy", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Egress:   map[string]string{"api.anthropic.com": "anthropic"},
		}
		require.NoError(t, s.normalize(&warnings{}))
		// Egress folds into LegacyNetwork.ServiceDomains+ServiceAuth (v1
		// intermediate); normalizeLegacyCredentials then folds that into
		// Credentials.List. Assert against the final canonical shape.
		require.Len(t, s.Credentials.List, 1)
		c := s.Credentials.List[0]
		require.Equal(t, "anthropic", c.Service)
		require.NotNil(t, c.ApiKey)
		require.Len(t, c.ApiKey.Inject, 1)
		require.Equal(t, "api.anthropic.com", c.ApiKey.Inject[0].Domain)
		require.Equal(t, "x-api-key", c.ApiKey.Inject[0].Header)
	})

	t.Run("unknown_service_gets_no_default_auth", func(t *testing.T) {
		s := SpecFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Egress:   map[string]string{"custom.example.com": "custom"},
		}
		require.NoError(t, s.normalize(&warnings{}))
		// Service "custom" has no wellKnownAuth entry, so its inject
		// entry has no header. The Credential exists with apiKey.Inject
		// but no Header value.
		require.Len(t, s.Credentials.List, 1)
		c := s.Credentials.List[0]
		require.Equal(t, "custom", c.Service)
		require.NotNil(t, c.ApiKey)
		require.Len(t, c.ApiKey.Inject, 1)
		require.Empty(t, c.ApiKey.Inject[0].Header)
	})
}

func TestNormalize_OAuthOnlyService_DomainsMoveToResourceHosts(t *testing.T) {
	yaml := []byte(`
schemaVersion: "1"
kind: agent
name: vertex-test
agent:
  image: x
network:
  serviceDomains:
    aiplatform.googleapis.com: vertex
    europe-west4-aiplatform.googleapis.com: vertex
    oauth2.googleapis.com: vertex
oauth:
  service: vertex
  tokenEndpoint:
    host: oauth2.googleapis.com
    path: /token
  sentinels:
    accessToken: a-sentinel
    refreshToken: r-sentinel
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)

	var vertex *Credential
	for i := range art.Credentials {
		if art.Credentials[i].Service == "vertex" {
			vertex = &art.Credentials[i]
		}
	}
	require.NotNil(t, vertex, "vertex credential should exist")
	require.Nil(t, vertex.ApiKey, "degenerate apiKey must be dropped for an oauth-only service")
	require.NotNil(t, vertex.OAuth)
	require.Equal(t, []string{"aiplatform.googleapis.com", "europe-west4-aiplatform.googleapis.com"}, vertex.OAuth.ResourceHosts,
		"resource hosts moved + sorted; token endpoint NOT included")
	require.Equal(t, "oauth2.googleapis.com", vertex.OAuth.TokenEndpoint.Host)
}

func TestNormalize_BothMechanisms_KeepsApiKey(t *testing.T) {
	yaml := []byte(`
schemaVersion: "1"
kind: agent
name: anthropic-test
agent:
  image: x
credentials:
  sources:
    anthropic: {env: [ANTHROPIC_API_KEY]}
network:
  serviceDomains:
    api.anthropic.com: anthropic
  serviceAuth:
    anthropic: {headerName: x-api-key, valueFormat: "%s"}
oauth:
  service: anthropic
  tokenEndpoint: {host: platform.claude.com, path: /v1/oauth/token}
  sentinels: {accessToken: a, refreshToken: r}
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)
	var c *Credential
	for i := range art.Credentials {
		if art.Credentials[i].Service == "anthropic" {
			c = &art.Credentials[i]
		}
	}
	require.NotNil(t, c)
	require.NotNil(t, c.ApiKey, "real apiKey (has env name + header) must be kept")
	require.Equal(t, "ANTHROPIC_API_KEY", c.ApiKey.Name)
	require.NotNil(t, c.OAuth)
	require.Empty(t, c.OAuth.ResourceHosts, "shared hosts stay in apiKey.inject; not duplicated")
}

// TestNormalize_OAuthMerge_SortsAndDedupes exercises the else-branch in
// normalizeLegacyOAuthBlock where c.OAuth != nil. It verifies that when a
// Credential already has an OAuth block with resourceHosts PLUS a routing-only
// apiKey, and a v1 standalone oauth: block is folded in, the domains from the
// apiKey are moved to resourceHosts and the final list is sorted and deduped.
func TestNormalize_OAuthMerge_SortsAndDedupes(t *testing.T) {
	yaml := []byte(`
schemaVersion: "1"
kind: agent
name: merge-test
agent:
  image: x
# v2 credential with existing OAuth resourceHosts AND a routing-only apiKey
# (no name, no header on inject entries = routing only).
credentials:
  - service: vertex
    apiKey:
      inject:
        - domain: new.googleapis.com
        - domain: aaa-first.googleapis.com
        - domain: existing.googleapis.com
    oauth:
      resourceHosts:
        - existing.googleapis.com
        - zzz-last.googleapis.com
      tokenEndpoint:
        host: oauth2.googleapis.com
        path: /token
      sentinels:
        accessToken: a
        refreshToken: r
# v1 standalone oauth block for same service triggers the merge branch
oauth:
  service: vertex
  tokenEndpoint:
    host: oauth2.googleapis.com
    path: /token
  sentinels:
    accessToken: a-sentinel
    refreshToken: r-sentinel
`)
	art, err := LoadArtifactFromBytes(yaml)
	require.NoError(t, err)

	var vertex *Credential
	for i := range art.Credentials {
		if art.Credentials[i].Service == "vertex" {
			vertex = &art.Credentials[i]
		}
	}
	require.NotNil(t, vertex, "vertex credential should exist")
	require.Nil(t, vertex.ApiKey, "routing-only apiKey must be dropped after merge")
	require.NotNil(t, vertex.OAuth)
	// Expect sorted + deduped: aaa-first, existing (deduped), new, zzz-last
	// The token endpoint (oauth2.googleapis.com) is excluded from the move.
	require.Equal(t,
		[]string{"aaa-first.googleapis.com", "existing.googleapis.com", "new.googleapis.com", "zzz-last.googleapis.com"},
		vertex.OAuth.ResourceHosts,
		"merged resourceHosts should be sorted and deduped")
}

func TestNormalizeFoldsProxyManagedToMarker(t *testing.T) {
	in := []byte(`schemaVersion: "1"
kind: agent
name: t
agent: {image: x}
network:
  serviceDomains: {generativelanguage.googleapis.com: google, api.github.com: github}
  serviceAuth:
    google: {headerName: x-goog-api-key, valueFormat: "%s"}
    github: {headerName: Authorization, valueFormat: "Bearer %s"}
credentials:
  sources:
    google: {env: [GOOGLE_API_KEY, GEMINI_API_KEY]}
    github: {env: [GH_TOKEN]}
environment:
  proxyManaged: [GOOGLE_API_KEY, GEMINI_API_KEY]
`)
	a, err := LoadArtifactFromBytes(in)
	require.NoError(t, err)
	bySvc := map[string]*ApiKey{}
	for i := range a.Credentials {
		bySvc[a.Credentials[i].Service] = a.Credentials[i].ApiKey
	}
	require.NotNil(t, bySvc["google"])
	require.Equal(t, "GOOGLE_API_KEY", bySvc["google"].Name) // primary; GEMINI not preserved
	require.True(t, bySvc["google"].ProxyManaged)            // marked
	require.NotNil(t, bySvc["github"])
	require.False(t, bySvc["github"].ProxyManaged) // not in proxyManaged → unmarked

	// Environment.ProxyManaged is DERIVED from the marked credentials: only
	// google's canonical GOOGLE_API_KEY (GEMINI secondary dropped, github
	// unmarked). This is the in-container sentinel set the engine reads.
	require.NotNil(t, a.Environment)
	require.Equal(t, []string{"GOOGLE_API_KEY"}, a.Environment.ProxyManaged)
}

// A v2 spec that declares apiKey.proxyManaged directly (no environment block)
// gets Environment.ProxyManaged derived from the markers, so the engine sees
// the in-container sentinel set without a v1 environment.proxyManaged list.
func TestNormalizeDerivesProxyManagedFromV2Markers(t *testing.T) {
	in := []byte(`schemaVersion: "2"
kind: sandbox
name: t
sandbox: {image: x}
credentials:
  - service: openai
    apiKey: {name: OPENAI_API_KEY, proxyManaged: true, inject: [{domain: api.openai.com, header: Authorization, format: "Bearer %s"}]}
  - service: github
    apiKey: {name: GH_TOKEN, inject: [{domain: api.github.com, header: Authorization, format: "Bearer %s"}]}
`)
	a, err := LoadArtifactFromBytes(in)
	require.NoError(t, err)
	require.NotNil(t, a.Environment)
	require.Equal(t, []string{"OPENAI_API_KEY"}, a.Environment.ProxyManaged) // github unmarked → excluded
}

func TestDeriveServiceKey(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"ANTHROPIC_API_KEY", "anthropic"},
		{"OPENAI_API_KEY", "openai"},
		{"GH_TOKEN", "github"},
		{"GITHUB_TOKEN", "github"},
		{"SOME_SECRET", "some"},
		{"PLAIN_NAME", "plain_name"},
	}
	for _, tc := range tests {
		t.Run(tc.input, func(t *testing.T) {
			require.Equal(t, tc.expected, deriveServiceKey(tc.input))
		})
	}
}

func TestLoadFromBytes(t *testing.T) {
	t.Run("mixin_round_trip", func(t *testing.T) {
		in := []byte(`schemaVersion: "1"
kind: mixin
name: normalize-kit
displayName: Normalize Kit
`)
		sf, err := LoadFromBytes(in)
		require.NoError(t, err)

		out, err := Marshal(sf)
		require.NoError(t, err)

		again, err := LoadFromBytes(out)
		require.NoError(t, err)
		require.Equal(t, sf, again)
	})

	t.Run("matches_artifact_loader", func(t *testing.T) {
		in := []byte(`schemaVersion: "1"
kind: mixin
name: normalize-kit
displayName: Normalize Kit
`)
		fromBytes, err := LoadArtifactFromBytes(in)
		require.NoError(t, err)

		sf, err := LoadFromBytes(in)
		require.NoError(t, err)
		require.Equal(t, fromBytes.Manifest.Name, sf.Name)
		require.Equal(t, fromBytes.Manifest.Kind, sf.Kind)
	})
}
