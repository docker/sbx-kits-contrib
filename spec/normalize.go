package spec

import (
	"fmt"
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
	s.normalizeAgentContext(w)
	return nil
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

// normalizeSecrets converts the flat secrets: [NAME] list into credential sources.
func (s *specFile) normalizeSecrets() error {
	if len(s.Secrets) == 0 {
		return nil
	}

	if s.Credentials == nil {
		s.Credentials = &CredentialPolicy{Sources: make(map[string]CredentialSource)}
	}
	if s.Credentials.Sources == nil {
		s.Credentials.Sources = make(map[string]CredentialSource)
	}

	for _, name := range s.Secrets {
		svc := deriveServiceKey(name)
		if _, exists := s.Credentials.Sources[svc]; exists {
			return fmt.Errorf("secret %q conflicts with existing credential source %q", name, svc)
		}
		s.Credentials.Sources[svc] = CredentialSource{
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

// normalizeEgress converts the egress: {domain: hook} map into network policy.
func (s *specFile) normalizeEgress() error {
	if len(s.Egress) == 0 {
		return nil
	}

	if s.Network == nil {
		s.Network = &NetworkPolicy{
			ServiceDomains: make(map[string]string),
			ServiceAuth:    make(map[string]ServiceAuth),
		}
	}
	if s.Network.ServiceDomains == nil {
		s.Network.ServiceDomains = make(map[string]string)
	}
	if s.Network.ServiceAuth == nil {
		s.Network.ServiceAuth = make(map[string]ServiceAuth)
	}

	for domain, hookName := range s.Egress {
		if existing, ok := s.Network.ServiceDomains[domain]; ok {
			return fmt.Errorf("egress domain %q conflicts with existing serviceDomain (mapped to %q)", domain, existing)
		}
		s.Network.ServiceDomains[domain] = hookName

		if _, exists := s.Network.ServiceAuth[hookName]; !exists {
			if auth, ok := wellKnownAuth[hookName]; ok {
				s.Network.ServiceAuth[hookName] = auth
			}
		}
	}

	return nil
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
