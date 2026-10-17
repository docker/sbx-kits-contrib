package spec

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// v2SchemeSpec builds a minimal v2 mixin whose single apiKey inject entry is
// the block passed in, so each case below is just the inject fields.
func v2SchemeSpec(inject string) []byte {
	return []byte(`schemaVersion: "2"
kind: mixin
name: scheme-kit
permissions:
  network:
    allow:
      - api.cloudflare.com
credentials:
  - service: cloudflare-api
    apiKey:
      name: CLOUDFLARE_API_TOKEN
      inject:
        - domain: api.cloudflare.com
` + inject)
}

// scheme: bearer is sugar for the complete Authorization header. Header is the
// only carrier of the header name on the normalized artifact, so the sugar must
// fill it in; a kit that writes `scheme: bearer` with no `header:` used to load
// and validate clean while injecting into no header at all.
func TestSchemeBearer_SetsAuthorizationHeader(t *testing.T) {
	a, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: bearer\n"))
	require.NoError(t, err)

	inj := a.Credentials[0].ApiKey.Inject[0]
	require.Equal(t, "Authorization", inj.Header)
	require.Equal(t, "Bearer %s", inj.Format)
	require.Empty(t, inj.Scheme, "scheme is expanded away on the normalized artifact")
	require.NoError(t, ValidateArtifact(a))
}

// An explicit header: wins — Bearer-formatted values can target a
// non-standard header.
func TestSchemeBearer_ExplicitHeaderPreserved(t *testing.T) {
	a, err := LoadArtifactFromBytes(v2SchemeSpec("          header: X-Auth\n          scheme: bearer\n"))
	require.NoError(t, err)

	inj := a.Credentials[0].ApiKey.Inject[0]
	require.Equal(t, "X-Auth", inj.Header)
	require.Equal(t, "Bearer %s", inj.Format)
}

// scheme: basic is username-driven at the proxy rather than a header
// encoding, so it sets only the Format placeholder and leaves the header
// exactly as the author wrote it (including empty).
func TestSchemeBasic_LeavesHeaderAsWritten(t *testing.T) {
	a, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: basic\n          username: x-access-token\n"))
	require.NoError(t, err)

	inj := a.Credentials[0].ApiKey.Inject[0]
	require.Empty(t, inj.Header)
	require.Equal(t, "%s", inj.Format)
	require.Equal(t, "x-access-token", inj.Username)

	withHeader, err := LoadArtifactFromBytes(v2SchemeSpec("          header: Authorization\n          scheme: basic\n          username: x-access-token\n"))
	require.NoError(t, err)
	require.Equal(t, "Authorization", withHeader.Credentials[0].ApiKey.Inject[0].Header)
}

func TestSchemeErrors(t *testing.T) {
	t.Run("bearer_rejects_username", func(t *testing.T) {
		_, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: bearer\n          username: nope\n"))
		require.ErrorContains(t, err, "'username' is not valid with scheme: bearer")
	})

	t.Run("basic_requires_username", func(t *testing.T) {
		_, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: basic\n"))
		require.ErrorContains(t, err, "scheme: basic requires 'username'")
	})

	t.Run("scheme_and_format_exclusive", func(t *testing.T) {
		_, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: bearer\n          format: \"Bearer %s\"\n"))
		require.ErrorContains(t, err, "mutually exclusive")
	})

	t.Run("unknown_scheme", func(t *testing.T) {
		_, err := LoadArtifactFromBytes(v2SchemeSpec("          scheme: digest\n"))
		require.ErrorContains(t, err, `unknown scheme "digest"`)
	})
}
