package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNormalizeAgent(t *testing.T) {
	t.Run("populates_manifest_from_agent_block", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindAgent, SchemaVersion: SchemaVersion, Name: "a"},
			Agent: &agentBlock{
				Image:       "my-image",
				AIFilename:  "AI.md",
				Persistence: PersistencePersistent,
				Entrypoint: &entrypointBlock{
					Run:  []string{"bin", "--flag"},
					Args: []string{"--extra"},
				},
			},
		}
		require.NoError(t, s.normalize())
		require.Equal(t, "my-image", s.Template)
		require.Equal(t, "bin", s.Binary)
		require.Equal(t, []string{"--flag", "--extra"}, s.RunOptions)
		require.Equal(t, "AI.md", s.AIFilename)
		require.Equal(t, PersistencePersistent, s.Persistence)
	})

	t.Run("rejects_agent_block_on_mixin", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Agent:    &agentBlock{Image: "img"},
		}
		require.ErrorContains(t, s.normalize(), "only valid for kind")
	})

	t.Run("rejects_flat_template_field", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindAgent, SchemaVersion: SchemaVersion, Name: "a", Template: "img"},
		}
		require.ErrorContains(t, s.normalize(), "agent:")
	})

	t.Run("agent_requires_agent_block", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindAgent, SchemaVersion: SchemaVersion, Name: "a"},
		}
		require.ErrorContains(t, s.normalize(), "requires an 'agent:' block")
	})
}

func TestNormalizeSecrets(t *testing.T) {
	t.Run("converts_to_credential_sources", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Secrets:  []string{"ANTHROPIC_API_KEY", "GH_TOKEN"},
		}
		require.NoError(t, s.normalize())
		require.NotNil(t, s.Credentials)
		require.Contains(t, s.Credentials.Sources, "anthropic")
		require.Contains(t, s.Credentials.Sources, "github")
		require.True(t, s.Credentials.Sources["anthropic"].Required)
	})

	t.Run("conflict_with_existing_source", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Secrets:  []string{"ANTHROPIC_API_KEY"},
			Credentials: &CredentialPolicy{
				Sources: map[string]CredentialSource{
					"anthropic": {Env: []string{"EXISTING"}},
				},
			},
		}
		require.ErrorContains(t, s.normalize(), "conflicts")
	})
}

func TestNormalizeEgress(t *testing.T) {
	t.Run("converts_to_network_policy", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Egress:   map[string]string{"api.anthropic.com": "anthropic"},
		}
		require.NoError(t, s.normalize())
		require.NotNil(t, s.Network)
		require.Equal(t, "anthropic", s.Network.ServiceDomains["api.anthropic.com"])
		require.Equal(t, "x-api-key", s.Network.ServiceAuth["anthropic"].HeaderName)
	})

	t.Run("unknown_service_gets_no_default_auth", func(t *testing.T) {
		s := specFile{
			Manifest: Manifest{Kind: KindMixin, SchemaVersion: SchemaVersion, Name: "m"},
			Egress:   map[string]string{"custom.example.com": "custom"},
		}
		require.NoError(t, s.normalize())
		_, hasAuth := s.Network.ServiceAuth["custom"]
		require.False(t, hasAuth, "unknown services should not get default auth")
	})
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
