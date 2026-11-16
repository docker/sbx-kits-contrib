package spec

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestApiKeyProxyManagedRoundTrips(t *testing.T) {
	t.Run("proxyManaged true", func(t *testing.T) {
		in := []byte("schemaVersion: \"2\"\nkind: sandbox\nname: t\nsandbox:\n  image: x\ncredentials:\n  - service: openai\n    apiKey:\n      name: OPENAI_API_KEY\n      proxyManaged: true\n      inject:\n        - {domain: api.openai.com, header: Authorization, format: \"Bearer %s\"}\n")
		a, err := LoadArtifactFromBytes(in)
		require.NoError(t, err)
		require.Len(t, a.Credentials, 1)
		require.NotNil(t, a.Credentials[0].ApiKey)
		require.True(t, a.Credentials[0].ApiKey.ProxyManaged)
	})

	t.Run("proxyManaged absent defaults to false", func(t *testing.T) {
		in := []byte("schemaVersion: \"2\"\nkind: sandbox\nname: t\nsandbox:\n  image: x\ncredentials:\n  - service: openai\n    apiKey:\n      name: OPENAI_API_KEY\n      inject:\n        - {domain: api.openai.com, header: Authorization, format: \"Bearer %s\"}\n")
		a, err := LoadArtifactFromBytes(in)
		require.NoError(t, err)
		require.Len(t, a.Credentials, 1)
		require.NotNil(t, a.Credentials[0].ApiKey)
		require.False(t, a.Credentials[0].ApiKey.ProxyManaged)
	})
}

// Only an explicit empty interactiveOptions changes the bytes. Unset and nonempty lists encode
// exactly as before, in place, ahead of the fields that follow them.
func TestManifestInteractiveOptionsJSON(t *testing.T) {
	const head = `{"schemaVersion":"2","kind":"sandbox","name":"k","binary":"bin","template":"img","runOptions":["-x"],`
	const tail = `"resources":{"cpu":2},"security":{"privileged":true},"volumes":[{"path":"/data"}]}`
	for _, tt := range []struct {
		name        string
		interactive []string
		want        string
	}{
		{name: "unset is omitted", interactive: nil, want: head + tail},
		{name: "nonempty is unchanged", interactive: []string{"-i"}, want: head + `"interactiveOptions":["-i"],` + tail},
		{name: "explicit empty is kept", interactive: []string{}, want: head + `"interactiveOptions":[],` + tail},
	} {
		t.Run(tt.name, func(t *testing.T) {
			m := Manifest{
				SchemaVersion: "2", Kind: KindSandbox, Name: "k", Binary: "bin", Template: "img",
				RunOptions: []string{"-x"}, InteractiveOptions: tt.interactive,
				Resources: &Resources{CPU: 2}, Security: &Security{Privileged: true}, Volumes: []MountSpec{{Path: "/data"}},
			}
			got, err := json.Marshal(m)
			require.NoError(t, err)
			require.Equal(t, tt.want, string(got))

			var back Manifest
			require.NoError(t, json.Unmarshal(got, &back))
			require.Equal(t, tt.interactive, back.InteractiveOptions)
		})
	}
}

// A v2 command.interactive that is present, even empty, replaces the default tail for
// interactive launches; an absent or null one falls back to the default tail.
func TestV2InteractiveCommandPresence(t *testing.T) {
	for _, tt := range []struct {
		name            string
		sandbox         string
		wantRun         []string
		wantInteractive []string
	}{
		{name: "absent falls back to default", sandbox: "entrypoint: [bin]\n  command: {default: [-x]}",
			wantRun: []string{"-x"}, wantInteractive: []string{"-x"}},
		{name: "null falls back to default", sandbox: "entrypoint: [bin]\n  command: {default: [-x], interactive: null}",
			wantRun: []string{"-x"}, wantInteractive: []string{"-x"}},
		{name: "empty without fixed arguments", sandbox: "entrypoint: [bin]\n  command: {default: [-x], interactive: []}",
			wantRun: []string{"-x"}, wantInteractive: []string{}},
		{name: "empty after fixed arguments", sandbox: "entrypoint: [bin, --always]\n  command: {default: [-x], interactive: []}",
			wantRun: []string{"--always", "-x"}, wantInteractive: []string{"--always"}},
		{name: "empty with no default", sandbox: "entrypoint: [bin]\n  command: {interactive: []}",
			wantRun: nil, wantInteractive: []string{}},
		{name: "no command", sandbox: "entrypoint: [bin]",
			wantRun: nil, wantInteractive: nil},
	} {
		t.Run(tt.name, func(t *testing.T) {
			in := "schemaVersion: \"2\"\nkind: sandbox\nname: k\nsandbox:\n  image: img\n  " + tt.sandbox + "\n"
			a, err := LoadArtifactFromBytes([]byte(in))
			require.NoError(t, err)
			require.Equal(t, tt.wantRun, a.Manifest.RunOptions)
			require.Equal(t, tt.wantInteractive, a.Manifest.InteractiveOptions)
		})
	}
}

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
