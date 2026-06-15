// Package bindings defines the user-side credential bindings file format
// (`~/.config/sbx/credentials.yaml` on Linux/macOS, `%APPDATA%\sbx\
// credentials.yaml` on Windows). The file declares, per service, where
// the user wants their credentials to come from and which domains the
// engine may inject the resolved value into.
//
// Why this exists: pre-Phase-3 kits declared credential discovery in
// their own spec.yaml (`credentials.sources[svc].env`,
// `network.allowedDomains`). Phase 3 moved the kit-side declaration to
// "what the kit needs" (service identity, inject domains/headers); the
// "where the credential lives" half of the contract moves out of the
// kit and into this user-controlled file. The split lets a kit ship a
// minimal description and lets the user point sbx at whatever
// credential storage they actually use.
//
// Commit 10 ships the file format, the loader, and basic validation.
// The resolver runtime integration (commit 11) walks these bindings as
// one of several candidate buckets and enforces inject-domain ∈
// allowedDomains intersection at injection time.
package bindings

// UserBindings is the on-disk credentials.yaml shape. Decoded directly
// from YAML by Load.
type UserBindings struct {
	// Bindings maps a binding name to its discovery + allow-list
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

// Binding is the per-service declaration: how to find the credential
// on the host (Discovery) and which domains the engine may inject the
// resolved value into (AllowedDomains).
type Binding struct {
	// Discovery is a non-empty list of places to look for this
	// credential on the host. Entries are tried in order; the first
	// entry that yields a value wins.
	Discovery []DiscoverySpec `yaml:"discovery"`

	// AllowedDomains is the explicit list of domains the engine may
	// inject this credential into. Cross-checked against the kit's
	// credentials[].apiKey.inject[].domain at sandbox-create time;
	// inject domains not in AllowedDomains are silently dropped from
	// the injection set with a one-line warning in interactive
	// contexts.
	AllowedDomains []string `yaml:"allowedDomains"`
}

// DiscoverySpec is one place to look for a credential. Exactly one of
// Env or File should be non-nil per entry; an entry with both is
// rejected at validate time.
type DiscoverySpec struct {
	// Env lists environment variable names to check on the host, in
	// priority order (first set wins within an Env entry).
	Env []string `yaml:"env,omitempty"`

	// File describes a file-backed credential location.
	File *DiscoveryFile `yaml:"file,omitempty"`
}

// DiscoveryFile is the file-backed variant of a discovery entry.
type DiscoveryFile struct {
	// Path is the file path on the host (~ is expanded to the user's
	// home directory before reading).
	Path string `yaml:"path"`

	// Parser describes how to extract the credential value from the
	// file. Empty means "the entire file content trimmed of trailing
	// whitespace." Supported parsers ship in commit 11; for the
	// file-format commit the field is just decoded.
	Parser string `yaml:"parser,omitempty"`
}
