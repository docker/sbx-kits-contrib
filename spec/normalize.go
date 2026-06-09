package spec

import (
	"fmt"
	"sort"
	"strings"
)

// normalize converts sugar fields in specFile into canonical Artifact fields.
// Non-fatal validation issues (typically v1 → v2 deprecation warnings) are
// collected on w; callers surface them via Artifact.Warnings.
func (s *specFile) normalize(w *warnings) error {
	s.normalizeKind(w)
	if err := s.normalizeSandbox(w); err != nil {
		return err
	}
	if err := s.normalizeSecrets(); err != nil {
		return err
	}
	if err := s.normalizeEgress(); err != nil {
		return err
	}
	if err := s.normalizeLegacyCredentials(w); err != nil {
		return err
	}
	if err := s.normalizeLegacyOAuthBlock(w); err != nil {
		return err
	}
	if err := s.normalizeCapsNetwork(w); err != nil {
		return err
	}
	s.normalizePublishedPorts(w)
	s.normalizeAgentContext(w)
	s.normalizeLegacyPersistence(w)
	s.normalizeLegacyKitDir(w)
	s.normalizeLegacyTmpfs(w)
	s.normalizeVolumes(w)
	return nil
}

// normalizeVolumes folds the specFile-level volumes wrapper into the
// canonical Manifest.Volumes slice. The wrapper accepts both the v2
// sequence shape (List) and the v1 mapping shape (LegacyMap); the latter
// is converted to MountSpec entries (Path from key, Size from value) and
// emits a deprecation warning. Iteration over LegacyMap is sorted by path
// so the resulting Volumes order is stable across runs.
func (s *specFile) normalizeVolumes(w *warnings) {
	if len(s.Volumes.List) > 0 {
		s.Manifest.Volumes = append(s.Manifest.Volumes, s.Volumes.List...)
		s.Volumes.List = nil
	}
	if len(s.Volumes.LegacyMap) > 0 {
		paths := make([]string, 0, len(s.Volumes.LegacyMap))
		for p := range s.Volumes.LegacyMap {
			paths = append(paths, p)
		}
		sort.Strings(paths)
		for _, p := range paths {
			spec := MountSpec{Path: p}
			if size := s.Volumes.LegacyMap[p]; size != "" {
				spec.Size = size
			}
			s.Manifest.Volumes = append(s.Manifest.Volumes, spec)
		}
		w.deprecate("volumes (mapping form)", "use the v2 sequence form: '- path: <path>' entries instead (kit-spec v2)")
		s.Volumes.LegacyMap = nil
	}
}

// normalizeLegacyTmpfs folds the v1 `tmpfs: { /path: size }` mapping into
// the canonical v2 Volumes list, each entry tagged with Type=Tmpfs. PR #37
// replaced the v1 map shape with a `Tmpfs []MountSpec` list, then PR #59
// dropped the standalone block entirely in favor of `volumes:` entries
// with `type: tmpfs`. The strict-decode flip turned legacy specs into hard
// rejections; this shim re-admits them with a deprecation warning.
// Iteration order is sorted by path so the emitted Volumes order is stable.
func (s *specFile) normalizeLegacyTmpfs(w *warnings) {
	if len(s.LegacyTmpfs) == 0 {
		return
	}
	paths := make([]string, 0, len(s.LegacyTmpfs))
	for p := range s.LegacyTmpfs {
		paths = append(paths, p)
	}
	sort.Strings(paths)
	for _, p := range paths {
		s.Manifest.Volumes = append(s.Manifest.Volumes, MountSpec{
			Path: p,
			Type: MountTypeTmpfs,
			Size: s.LegacyTmpfs[p],
		})
	}
	w.deprecate("tmpfs", "use 'volumes:' entries with 'type: tmpfs' instead (kit-spec v2)")
	s.LegacyTmpfs = nil
}

// normalizeLegacyPersistence drops the v1 `persistence:` field with a
// deprecation warning. The field was always a no-op (never consumed by
// any runtime decision); pre-v0.31 specs that still set it are accepted
// here so the strict-decode flip introduced in PR #37 doesn't break them
// outright. Authors should remove the line; the field is gone in Phase 6.
func (s *specFile) normalizeLegacyPersistence(w *warnings) {
	if s.LegacyPersistence == "" {
		return
	}
	w.deprecate("persistence", "field has no effect and is removed in kit-spec v2; safe to delete")
	s.LegacyPersistence = ""
}

// normalizeLegacyKitDir drops the v1 `kitDir:` field with a deprecation
// warning. Same story as normalizeLegacyPersistence — never consumed,
// removed alongside Persistence in PR #37, re-admitted as a deprecation
// shim so legacy specs survive the strict-decode flip.
func (s *specFile) normalizeLegacyKitDir(w *warnings) {
	if s.LegacyKitDir == "" {
		return
	}
	w.deprecate("kitDir", "field has no effect and is removed in kit-spec v2; safe to delete")
	s.LegacyKitDir = ""
}

// normalizePublishedPorts promotes the v1 `network.publishedPorts`
// (LegacyNetwork) into the canonical top-level PublishedPorts list, emitting
// a deprecation warning. v2 entries already decoded into PublishedPorts are
// kept; the legacy entries are appended after them.
func (s *specFile) normalizePublishedPorts(w *warnings) {
	if s.LegacyNetwork == nil || len(s.LegacyNetwork.PublishedPorts) == 0 {
		return
	}
	s.PublishedPorts = append(s.PublishedPorts, s.LegacyNetwork.PublishedPorts...)
	s.LegacyNetwork.PublishedPorts = nil
	w.deprecate("network.publishedPorts", "use the top-level 'publishedPorts' field instead (kit-spec v2)")
}

// normalizeKind maps the v1 `kind: agent` value to `sandbox`. The v2 value
// is the canonical form; the v1 value triggers a deprecation warning.
func (s *specFile) normalizeKind(w *warnings) {
	if s.Manifest.Kind == KindAgent {
		s.Manifest.Kind = KindSandbox
		w.deprecate("kind: agent", "use 'kind: sandbox' instead (kit-spec v2)")
	}
}

// normalizeAgentContext maps the v1 `memory:` field onto AgentContext.
// The v2 field wins if both are set.
func (s *specFile) normalizeAgentContext(w *warnings) {
	if s.LegacyMemory == "" {
		return
	}
	if s.AgentContext == "" {
		s.AgentContext = s.LegacyMemory
	}
	w.deprecate("memory", "use 'agentContext' instead (kit-spec v2)")
	s.LegacyMemory = ""
}

// normalizeSandbox populates Manifest fields from the sandbox: block.
// Renamed from normalizeAgent in v2 alongside the YAML rename. v1
// `agent:` is migrated onto Sandbox at load time with a deprecation
// warning.
func (s *specFile) normalizeSandbox(w *warnings) error {
	if s.LegacyAgent != nil {
		if s.Sandbox == nil {
			s.Sandbox = s.LegacyAgent
		}
		w.deprecate("agent:", "use 'sandbox:' block instead (kit-spec v2)")
		s.LegacyAgent = nil
	}
	// `persistence:` lived both at the spec root (handled by
	// normalizeLegacyPersistence) AND inside the (then-)agent block.
	// PR #37 dropped the nested form too. Surface it as a deprecation
	// warning here rather than letting strict decode reject Andre's
	// kit shape.
	if s.Sandbox != nil && s.Sandbox.LegacyPersistence != "" {
		w.deprecate("sandbox.persistence", "field has no effect and is removed in kit-spec v2; safe to delete")
		s.Sandbox.LegacyPersistence = ""
	}

	isSandbox := s.Kind == KindSandbox

	if s.Template != "" || s.Binary != "" || len(s.RunOptions) > 0 {
		return fmt.Errorf("use the 'sandbox:' block instead of flat 'template'/'binary'/'runOptions' fields")
	}
	if s.AIFilename != "" {
		return fmt.Errorf("use 'sandbox.aiFilename' instead of flat 'aiFilename' field")
	}

	if s.Sandbox != nil && !isSandbox {
		return fmt.Errorf("'sandbox:' block is only valid for kind %q, not %q", KindSandbox, s.Kind)
	}

	if s.Sandbox == nil {
		if isSandbox {
			return fmt.Errorf("kind %q requires a 'sandbox:' block with at least 'sandbox.image'", KindSandbox)
		}
		return nil
	}

	s.Template = s.Sandbox.Image
	s.AIFilename = s.Sandbox.AIFilename
	s.Resources = s.Sandbox.Resources

	if s.Sandbox.Entrypoint != nil {
		if len(s.Sandbox.Entrypoint.Run) > 0 {
			s.Binary = s.Sandbox.Entrypoint.Run[0]
			if len(s.Sandbox.Entrypoint.Run) > 1 {
				s.RunOptions = s.Sandbox.Entrypoint.Run[1:]
			}
		}
		if len(s.Sandbox.Entrypoint.Args) > 0 {
			s.RunOptions = append(s.RunOptions, s.Sandbox.Entrypoint.Args...)
		}
	}

	return nil
}

// normalizeSecrets converts the flat secrets: [NAME] list into v1-shape
// credential sources stashed on Credentials.LegacySources. The later
// normalizeLegacyCredentials pass folds them into Credentials.List.
func (s *specFile) normalizeSecrets() error {
	if len(s.Secrets) == 0 {
		return nil
	}

	if s.Credentials.LegacySources == nil {
		s.Credentials.LegacySources = make(map[string]CredentialSource)
	}

	for _, name := range s.Secrets {
		svc := deriveServiceKey(name)
		if _, exists := s.Credentials.LegacySources[svc]; exists {
			return fmt.Errorf("secret %q conflicts with existing credential source %q", name, svc)
		}
		s.Credentials.LegacySources[svc] = CredentialSource{
			Env:      []string{name},
			Required: true,
		}
	}

	return nil
}

// serviceKeyAliases maps common env var names to their canonical service keys.
var serviceKeyAliases = map[string]string{
	"GH_TOKEN":     "github",
	"GITHUB_TOKEN": "github",
}

// deriveServiceKey extracts a service key from an environment variable name.
func deriveServiceKey(envVar string) string {
	if canonical, ok := serviceKeyAliases[envVar]; ok {
		return canonical
	}
	name := strings.ToLower(envVar)
	for _, suffix := range []string{"_api_key", "_token", "_key", "_secret"} {
		if strings.HasSuffix(name, suffix) {
			return strings.TrimSuffix(name, suffix)
		}
	}
	return name
}

// normalizeEgress converts the egress: {domain: hook} map into v1-shape
// network policy entries stashed on LegacyNetwork. The later
// normalizeLegacyCredentials pass folds them into Credentials.List.
func (s *specFile) normalizeEgress() error {
	if len(s.Egress) == 0 {
		return nil
	}

	if s.LegacyNetwork == nil {
		s.LegacyNetwork = &NetworkPolicy{
			ServiceDomains: make(map[string]string),
			ServiceAuth:    make(map[string]ServiceAuth),
		}
	}
	if s.LegacyNetwork.ServiceDomains == nil {
		s.LegacyNetwork.ServiceDomains = make(map[string]string)
	}
	if s.LegacyNetwork.ServiceAuth == nil {
		s.LegacyNetwork.ServiceAuth = make(map[string]ServiceAuth)
	}

	for domain, hookName := range s.Egress {
		if existing, ok := s.LegacyNetwork.ServiceDomains[domain]; ok {
			return fmt.Errorf("egress domain %q conflicts with existing serviceDomain (mapped to %q)", domain, existing)
		}
		s.LegacyNetwork.ServiceDomains[domain] = hookName

		if _, exists := s.LegacyNetwork.ServiceAuth[hookName]; !exists {
			if auth, ok := wellKnownAuth[hookName]; ok {
				s.LegacyNetwork.ServiceAuth[hookName] = auth
			}
		}
	}

	return nil
}

// normalizeLegacyCredentials folds the four v1 credential surfaces
// (Credentials.LegacySources, LegacyNetwork.ServiceAuth,
// LegacyNetwork.ServiceDomains, Environment.LegacyProxyManaged) into a
// single canonical Credentials.List per service. Emits one deprecation
// warning per legacy surface touched. v2 entries already present in
// Credentials.List take precedence — a v2 entry for a given service
// suppresses the v1 fold for that service entirely.
//
// After this pass, Credentials.List is the source of truth and the
// Legacy* fields are left intact only so artifact.go can still see
// they were present (for any diagnostic surface that wants to report
// "kit used v1 spelling X").
func (s *specFile) normalizeLegacyCredentials(w *warnings) error {
	// Track which services already have v2 entries.
	v2Services := make(map[string]bool, len(s.Credentials.List))
	for _, c := range s.Credentials.List {
		v2Services[c.Service] = true
	}

	// Track which legacy surfaces we actually consume, so we emit one
	// warning per kind rather than per service.
	var sawSources, sawServiceAuth, sawServiceDomains, sawProxyManaged bool

	// Build "service -> partial Credential" from the legacy surfaces.
	// We accumulate inject entries first (from serviceDomains+serviceAuth),
	// then attach apiKey.Name from LegacySources, then attach Required from
	// LegacySources.required, then fold proxyManaged as the apiKey.Name
	// fallback if LegacySources didn't supply one.
	type pending struct {
		required bool
		envName  string // becomes ApiKey.Name
		inject   []ApiKeyInject
	}
	byService := make(map[string]*pending)

	get := func(svc string) *pending {
		p, ok := byService[svc]
		if !ok {
			p = &pending{}
			byService[svc] = p
		}
		return p
	}

	// Fold v1 credentials.sources entries.
	for svc, src := range s.Credentials.LegacySources {
		if v2Services[svc] {
			continue
		}
		sawSources = true
		p := get(svc)
		if src.Required {
			p.required = true
		}
		if len(src.Env) > 0 {
			p.envName = src.Env[0]
		}
	}

	// Fold v1 network.serviceDomains + network.serviceAuth into inject entries.
	if s.LegacyNetwork != nil {
		// Domain -> service map; for each, emit one inject entry with header
		// from serviceAuth if present. Iterate in sorted domain order so the
		// resulting Credentials[].ApiKey.Inject list is deterministic — Go map
		// iteration order is randomised, so otherwise byte-identical specs
		// would produce different normalized artifacts across loads.
		domains := make([]string, 0, len(s.LegacyNetwork.ServiceDomains))
		for d := range s.LegacyNetwork.ServiceDomains {
			domains = append(domains, d)
		}
		sort.Strings(domains)
		for _, domain := range domains {
			svc := s.LegacyNetwork.ServiceDomains[domain]
			if v2Services[svc] {
				continue
			}
			sawServiceDomains = true
			p := get(svc)
			inj := ApiKeyInject{Domain: domain, Format: "%s"}
			if auth, ok := s.LegacyNetwork.ServiceAuth[svc]; ok {
				sawServiceAuth = true
				inj.Header = auth.HeaderName
				if auth.ValueFormat != "" {
					inj.Format = auth.ValueFormat
				}
			}
			p.inject = append(p.inject, inj)
		}
		// serviceAuth entries that have no serviceDomain partner still
		// count as touched (and surface the warning) but contribute no
		// inject rows by themselves.
		if !sawServiceAuth && len(s.LegacyNetwork.ServiceAuth) > 0 {
			sawServiceAuth = true
		}
	}

	// Fold v1 environment.proxyManaged: each entry is an env-var name the
	// proxy populates inside the container. Map it onto the matching
	// pending.envName by lookup against LegacySources (if a kit lists
	// proxyManaged: [ANTHROPIC_API_KEY], the matching service is whatever
	// LegacySources or serviceAuth maps that env-var to). If we can't
	// derive the service from existing data, fall back to deriveServiceKey.
	if s.Environment != nil && len(s.Environment.LegacyProxyManaged) > 0 {
		sawProxyManaged = true
		// Build env-var -> service lookup from LegacySources first.
		envToService := make(map[string]string)
		for svc, src := range s.Credentials.LegacySources {
			for _, e := range src.Env {
				envToService[e] = svc
			}
		}
		for _, envName := range s.Environment.LegacyProxyManaged {
			svc, ok := envToService[envName]
			if !ok {
				svc = deriveServiceKey(envName)
			}
			if v2Services[svc] {
				continue
			}
			p := get(svc)
			if p.envName == "" {
				p.envName = envName
			}
		}
	}

	// Materialize Credential entries in a stable order (sorted by service
	// name) so the resulting Credentials.List is deterministic.
	services := make([]string, 0, len(byService))
	for svc := range byService {
		services = append(services, svc)
	}
	sortStrings(services)

	for _, svc := range services {
		p := byService[svc]
		c := Credential{Service: svc, Required: p.required}
		if p.envName != "" || len(p.inject) > 0 {
			c.ApiKey = &ApiKey{Name: p.envName, Inject: p.inject}
		}
		s.Credentials.List = append(s.Credentials.List, c)
	}

	if sawSources {
		w.deprecate("credentials.sources", "use the top-level credentials: list with apiKey: sub-blocks (kit-spec v2)")
	}
	if sawServiceAuth {
		w.deprecate("network.serviceAuth", "use credentials[].apiKey.inject[].header/format (kit-spec v2)")
	}
	if sawServiceDomains {
		w.deprecate("network.serviceDomains", "use credentials[].apiKey.inject[].domain (kit-spec v2)")
	}
	if sawProxyManaged {
		w.deprecate("environment.proxyManaged", "use credentials[].apiKey.name (kit-spec v2)")
	}

	return nil
}

// normalizeLegacyOAuthBlock folds the v1 standalone top-level `oauth:`
// block (specFile.LegacyOAuth) into Credentials.List. If a Credential
// entry for LegacyOAuth.Service already exists, the OAuth shape is
// attached to it; otherwise a fresh Credential entry is synthesized.
// Emits a deprecation warning.
func (s *specFile) normalizeLegacyOAuthBlock(w *warnings) error {
	if s.LegacyOAuth == nil {
		return nil
	}
	o := s.LegacyOAuth
	if o.Service == "" {
		return fmt.Errorf("oauth: standalone block requires a service field")
	}

	v2 := &OAuth{
		TokenEndpoint:  o.TokenEndpoint,
		Sentinels:      o.Sentinels,
		CredentialFile: o.CredentialFile,
		SkipIfEnv:      o.SkipIfEnv,
		ResponseFields: o.ResponseFields,
		// v1 PassthroughResponse maps directly to v2 Passthrough (renamed;
		// same semantics).
		Passthrough: o.PassthroughResponse,
	}

	// Attach to existing Credential if present.
	for i, c := range s.Credentials.List {
		if c.Service == o.Service {
			if c.OAuth == nil {
				s.Credentials.List[i].OAuth = v2
			}
			w.deprecate("oauth: (standalone block)", "use credentials[].oauth (kit-spec v2)")
			return nil
		}
	}

	// Otherwise synthesize a new entry.
	s.Credentials.List = append(s.Credentials.List, Credential{
		Service: o.Service,
		OAuth:   v2,
	})
	w.deprecate("oauth: (standalone block)", "use credentials[].oauth (kit-spec v2)")
	return nil
}

// normalizeCapsNetwork promotes v1 network.allowedDomains/deniedDomains
// (LegacyNetwork) into the canonical Caps.Network.Allow/Deny lists.
// Emits one deprecation warning per legacy field touched.
func (s *specFile) normalizeCapsNetwork(w *warnings) error {
	hasV1Allow := s.LegacyNetwork != nil && len(s.LegacyNetwork.AllowedDomains) > 0
	hasV1Deny := s.LegacyNetwork != nil && len(s.LegacyNetwork.DeniedDomains) > 0
	if !hasV1Allow && !hasV1Deny {
		return nil
	}

	if s.Caps == nil {
		s.Caps = &Caps{}
	}
	if s.Caps.Network == nil {
		s.Caps.Network = &CapsNetwork{}
	}

	if hasV1Allow {
		s.Caps.Network.Allow = append(s.Caps.Network.Allow, s.LegacyNetwork.AllowedDomains...)
		w.deprecate("network.allowedDomains", "use 'caps.network.allow' instead (kit-spec v2)")
	}
	if hasV1Deny {
		s.Caps.Network.Deny = append(s.Caps.Network.Deny, s.LegacyNetwork.DeniedDomains...)
		w.deprecate("network.deniedDomains", "use 'caps.network.deny' instead (kit-spec v2)")
	}

	return nil
}

// sortStrings is a small helper to keep the slice sort import local.
func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j-1] > s[j]; j-- {
			s[j-1], s[j] = s[j], s[j-1]
		}
	}
}

// wellKnownAuth maps well-known service hook names to their default auth configuration.
var wellKnownAuth = map[string]ServiceAuth{
	"anthropic": {HeaderName: "x-api-key", ValueFormat: "%s"},
	"openai":    {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"google":    {HeaderName: "x-goog-api-key", ValueFormat: "%s"},
	"github":    {HeaderName: "Authorization", ValueFormat: "token %s"},
	"xai":       {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"nebius":    {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"mistral":   {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"groq":      {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"cursor":    {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
	"factory":   {HeaderName: "Authorization", ValueFormat: "Bearer %s"},
}
