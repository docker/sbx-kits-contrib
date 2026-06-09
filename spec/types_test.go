package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCredentialRoutingHosts(t *testing.T) {
	// apiKey-only
	apiKeyCred := Credential{Service: "anthropic", ApiKey: &ApiKey{
		Name:   "ANTHROPIC_API_KEY",
		Inject: []ApiKeyInject{{Domain: "api.anthropic.com"}, {Domain: "claude.ai"}},
	}}
	require.Equal(t, []string{"api.anthropic.com", "claude.ai"}, apiKeyCred.RoutingHosts())

	// oauth-only: token endpoint + resource hosts, deduped + sorted
	oauthCred := Credential{Service: "vertex", OAuth: &OAuth{
		TokenEndpoint: OAuthTokenEndpoint{Host: "oauth2.googleapis.com"},
		ResourceHosts: []string{"aiplatform.googleapis.com"},
	}}
	require.Equal(t, []string{"aiplatform.googleapis.com", "oauth2.googleapis.com"}, oauthCred.RoutingHosts())

	// both mechanisms, overlapping host deduped
	both := Credential{Service: "x",
		ApiKey: &ApiKey{Inject: []ApiKeyInject{{Domain: "api.x.com"}}},
		OAuth:  &OAuth{TokenEndpoint: OAuthTokenEndpoint{Host: "auth.x.com"}, ResourceHosts: []string{"api.x.com"}},
	}
	require.Equal(t, []string{"api.x.com", "auth.x.com"}, both.RoutingHosts())

	// empty
	require.Empty(t, Credential{Service: "none"}.RoutingHosts())
}
