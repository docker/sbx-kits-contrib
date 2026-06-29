// Package bindings defines the user-side credential bindings file format
// (`~/.config/sbx/credentials.yaml` on Linux/macOS, `%APPDATA%\sbx\
// credentials.yaml` on Windows). The file declares, per service, which
// credential mechanisms the user has approved and which domains the engine
// may use them with.
//
// Why this exists: pre-Phase-3 kits declared credential discovery in
// their own spec.yaml (`credentials.sources[svc].env`,
// `network.allowedDomains`). Phase 3 moved the kit-side declaration to
// "what the kit needs" (service identity, inject domains/headers); the
// per-mechanism approval half of the contract moves out of the kit and
// into this user-controlled file. The split lets a kit ship a minimal
// description and lets the user explicitly approve which mechanisms sbx
// may use for each service.
//
// Commit 10 ships the file format, the loader, and basic validation.
// The resolver runtime integration (commit 11) walks these bindings as
// one of several candidate buckets and enforces inject-domain ∈ approved
// domains intersection at injection time.
package bindings

// UserBindings is the on-disk credentials.yaml shape. Decoded directly
// from YAML by Load.
type UserBindings struct {
	// Bindings maps a binding name to its per-mechanism approval
	// declaration. The binding name is the kit's credentials[].service
	// from the v2 spec, optionally suffixed with "@<variant>" for named
	// variants (RFC P2). Variant selection is not implemented yet; the
	// map preserves any @variant keys verbatim for forward-compat.
	Bindings map[string]Binding `yaml:"bindings"`

	// Remembered maps an absolute workspace path to a per-service binding
	// selection (service -> binding name, e.g. "github" -> "github@work").
	// RFC P2 "workspace associations." Not consulted by resolution yet;
	// modeled here so the consent flow's save (yaml.Marshal of this struct)
	// round-trips a user's hand-written section instead of discarding it.
	Remembered map[string]map[string]string `yaml:"remembered,omitempty"`
}

// Binding is the per-service declaration of which credential mechanisms the
// user has approved and the domains the engine may use them with. A block's
// presence is the approval: ApiKey present ⟺ inject the stored secret (resolved
// from the secret store by service name) to ApiKey.Domains; OAuth present ⟺ the
// user approved OAuth for this service (login is manual; the proxy is trusted to
// refresh/route at OAuth.Domains). A binding with neither block is meaningless;
// declining a credential writes no binding entry at all.
type Binding struct {
	ApiKey *ApiKeyBinding `yaml:"apiKey,omitempty"`
	OAuth  *OAuthBinding  `yaml:"oauth,omitempty"`
}

// ApiKeyBinding records that the api-key mechanism is approved for a service and
// the domains the stored secret may be injected into (the kit spec's
// credentials[].apiKey.inject[].domain, intersected with the user's approval).
type ApiKeyBinding struct {
	Domains []string `yaml:"domains"`
}

// OAuthBinding records that OAuth is approved for a service and the domains the
// grant covers: the token-refresh host plus any resource hosts.
type OAuthBinding struct {
	Domains []string `yaml:"domains"`
}

// ApiKeyDomains returns the approved api-key domains, or nil if the api-key
// mechanism is not approved. Nil-safe so callers can skip a presence check.
func (b Binding) ApiKeyDomains() []string {
	if b.ApiKey == nil {
		return nil
	}
	return b.ApiKey.Domains
}

// OAuthDomains returns the approved OAuth domains, or nil if OAuth is not
// approved. Nil-safe.
func (b Binding) OAuthDomains() []string {
	if b.OAuth == nil {
		return nil
	}
	return b.OAuth.Domains
}

// AllDomains returns the deduplicated union of the api-key and OAuth domains
// approved for this service — the full set the engine may inject this
// credential into across both mechanisms. Api-key domains come first, then any
// OAuth-only domains, preserving first appearance. This is the per-mechanism
// replacement for the old flat AllowedDomains (which was itself the union), so
// daemon-side injection authorization keeps the same effective domain set.
func (b Binding) AllDomains() []string {
	seen := map[string]bool{}
	var out []string
	for _, d := range b.ApiKeyDomains() {
		if !seen[d] {
			seen[d] = true
			out = append(out, d)
		}
	}
	for _, d := range b.OAuthDomains() {
		if !seen[d] {
			seen[d] = true
			out = append(out, d)
		}
	}
	return out
}
