package spec

import (
	"fmt"
	"path"
	"regexp"
	"strings"
)

// namePattern matches valid kit names: lowercase alphanumeric with hyphens,
// must start and end with alphanumeric, 1-64 characters.
var namePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$`)

// shellIdentifierPattern matches valid shell variable names.
var shellIdentifierPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// placeholderPattern matches ${...} placeholders in init file content.
var placeholderPattern = regexp.MustCompile(`\$\{[^}]+\}`)

// supportedPlaceholders lists the placeholders allowed in initFiles content.
var supportedPlaceholders = map[string]bool{
	"${WORKDIR}": true,
}

// ValidateManifest validates a Manifest for correctness.
func ValidateManifest(m *Manifest) error {
	if m.SchemaVersion == "" {
		return fmt.Errorf("manifest: schemaVersion is required")
	}
	if m.SchemaVersion != SchemaVersion {
		return fmt.Errorf("manifest: unsupported schemaVersion %q (supported: %q)", m.SchemaVersion, SchemaVersion)
	}

	if m.Kind == "" {
		return fmt.Errorf("manifest: kind is required")
	}
	if m.Kind != KindAgent && m.Kind != KindMixin {
		return fmt.Errorf("manifest: invalid kind %q (must be %q or %q)", m.Kind, KindAgent, KindMixin)
	}

	if m.Name == "" {
		return fmt.Errorf("manifest: name is required")
	}
	if !namePattern.MatchString(m.Name) {
		return fmt.Errorf("manifest: invalid name %q (must be lowercase alphanumeric with hyphens, 1-64 chars)", m.Name)
	}

	if m.Kind == KindAgent {
		if m.Template == "" {
			return fmt.Errorf("manifest: template is required for kind %q", KindAgent)
		}
	}

	if m.Persistence != "" && m.Persistence != PersistenceEphemeral && m.Persistence != PersistencePersistent {
		return fmt.Errorf("manifest: invalid persistence %q (must be %q or %q)", m.Persistence, PersistenceEphemeral, PersistencePersistent)
	}

	return nil
}

// ValidateNetworkPolicy validates a NetworkPolicy for correctness.
func ValidateNetworkPolicy(n *NetworkPolicy) error {
	if n == nil {
		return nil
	}

	for service := range n.ServiceAuth {
		auth := n.ServiceAuth[service]
		if auth.HeaderName == "" {
			return fmt.Errorf("network: serviceAuth[%q].headerName is required", service)
		}
		if auth.ValueFormat == "" {
			return fmt.Errorf("network: serviceAuth[%q].valueFormat is required", service)
		}
		if !strings.Contains(auth.ValueFormat, "%s") {
			return fmt.Errorf("network: serviceAuth[%q].valueFormat must contain %%s placeholder", service)
		}
	}

	if len(n.AllowedDomains) > 0 && len(n.DeniedDomains) > 0 {
		allowed := make(map[string]bool, len(n.AllowedDomains))
		for _, d := range n.AllowedDomains {
			allowed[d] = true
		}
		for _, d := range n.DeniedDomains {
			if allowed[d] {
				return fmt.Errorf("network: domain %q is in both allowedDomains and deniedDomains", d)
			}
		}
	}

	return nil
}

// ValidateCredentialPolicy validates a CredentialPolicy for correctness.
func ValidateCredentialPolicy(c *CredentialPolicy) error {
	if c == nil {
		return nil
	}

	for service, source := range c.Sources {
		if len(source.Env) == 0 && source.File == nil {
			return fmt.Errorf("credentials: sources[%q] must have at least one of env or file", service)
		}

		if source.File != nil {
			if source.File.Path == "" {
				return fmt.Errorf("credentials: sources[%q].file.path is required", service)
			}
		}

		if source.Priority != "" && source.Priority != "env-first" && source.Priority != "file-first" {
			return fmt.Errorf("credentials: sources[%q].priority must be \"env-first\" or \"file-first\"", service)
		}
	}

	return nil
}

// ValidateEnvironmentPolicy validates an EnvironmentPolicy for correctness.
func ValidateEnvironmentPolicy(e *EnvironmentPolicy) error {
	if e == nil {
		return nil
	}

	for key := range e.Variables {
		if key == "" {
			return fmt.Errorf("environment: variable key cannot be empty")
		}
		if !shellIdentifierPattern.MatchString(key) {
			return fmt.Errorf("environment: variable key %q is not a valid shell identifier", key)
		}
	}

	for _, key := range e.ProxyManaged {
		if key == "" {
			return fmt.Errorf("environment: proxyManaged entry cannot be empty")
		}
		if !shellIdentifierPattern.MatchString(key) {
			return fmt.Errorf("environment: proxyManaged entry %q is not a valid shell identifier", key)
		}
	}

	return nil
}

// ValidateCommandsPolicy validates a CommandsPolicy for correctness.
func ValidateCommandsPolicy(c *CommandsPolicy) error {
	if c == nil {
		return nil
	}

	for i, cmd := range c.Install {
		if cmd.Command == "" {
			return fmt.Errorf("commands: install[%d].command is required", i)
		}
	}

	for i, cmd := range c.Startup {
		if len(cmd.Command) == 0 {
			return fmt.Errorf("commands: startup[%d].command is required", i)
		}
	}

	for i, f := range c.InitFiles {
		if f.Path == "" {
			return fmt.Errorf("commands: initFiles[%d].path is required", i)
		}
		if !strings.HasPrefix(f.Path, "/") {
			return fmt.Errorf("commands: initFiles[%d].path must be absolute (got %q)", i, f.Path)
		}
		if err := validateInitFileContent(i, f.Content); err != nil {
			return err
		}
	}

	return nil
}

func validateInitFileContent(index int, content string) error {
	for _, match := range placeholderPattern.FindAllString(content, -1) {
		if !supportedPlaceholders[match] {
			return fmt.Errorf("commands: initFiles[%d].content contains unsupported placeholder %q (supported: ${WORKDIR})", index, match)
		}
	}
	return nil
}

// ValidateSecurity validates a Security configuration for correctness.
func ValidateSecurity(_ *Security) error {
	return nil
}

// ValidateVolumes validates volume mount paths.
func ValidateVolumes(volumes map[string]string) error {
	for p := range volumes {
		if p == "" {
			return fmt.Errorf("manifest: volume path must not be empty")
		}
		if !strings.HasPrefix(p, "/") {
			return fmt.Errorf("manifest: volume path %q must be an absolute path", p)
		}
	}
	return nil
}

// ValidateTmpfs validates tmpfs mount paths.
func ValidateTmpfs(tmpfs map[string]string) error {
	for p := range tmpfs {
		if p == "" {
			return fmt.Errorf("manifest: tmpfs path must not be empty")
		}
		if !strings.HasPrefix(p, "/") {
			return fmt.Errorf("manifest: tmpfs path %q must be an absolute path", p)
		}
	}
	return nil
}

// ValidateArtifact validates a complete Artifact for internal consistency.
func ValidateArtifact(a *Artifact) error {
	if err := ValidateManifest(&a.Manifest); err != nil {
		return err
	}
	if err := ValidateSecurity(a.Manifest.Security); err != nil {
		return err
	}
	if err := ValidateVolumes(a.Manifest.Volumes); err != nil {
		return err
	}
	if err := ValidateTmpfs(a.Manifest.Tmpfs); err != nil {
		return err
	}
	if err := ValidateNetworkPolicy(a.Network); err != nil {
		return err
	}
	if err := ValidateCredentialPolicy(a.Credentials); err != nil {
		return err
	}
	if err := ValidateEnvironmentPolicy(a.Environment); err != nil {
		return err
	}
	if err := ValidateCommandsPolicy(a.Commands); err != nil {
		return err
	}
	if err := ValidateOAuthPolicy(a.OAuth); err != nil {
		return err
	}

	for i, f := range a.Files {
		if f.Target != TargetHome && f.Target != TargetWorkspace {
			return fmt.Errorf("artifact: files[%d] has invalid target %q (must be %q or %q)", i, f.Target, TargetHome, TargetWorkspace)
		}
		if f.RelativePath == "" {
			return fmt.Errorf("artifact: files[%d] has empty relativePath", i)
		}
		if strings.HasPrefix(f.RelativePath, "/") || strings.HasPrefix(f.RelativePath, "\\") {
			return fmt.Errorf("artifact: files[%d] relativePath %q must not be absolute", i, f.RelativePath)
		}
		cleaned := path.Clean(f.RelativePath)
		if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
			return fmt.Errorf("artifact: files[%d] relativePath %q escapes the target directory", i, f.RelativePath)
		}
	}

	return nil
}

// ValidateOAuthPolicy validates the oauth policy if present.
func ValidateOAuthPolicy(p *OAuthPolicy) error {
	if p == nil {
		return nil
	}
	if p.Service == "" {
		return fmt.Errorf("artifact: oauth: service is required")
	}
	if p.TokenEndpoint.Host == "" {
		return fmt.Errorf("artifact: oauth: tokenEndpoint.host is required")
	}
	if p.TokenEndpoint.Path == "" {
		return fmt.Errorf("artifact: oauth: tokenEndpoint.path is required")
	}
	if p.Sentinels.AccessToken == "" {
		return fmt.Errorf("artifact: oauth: sentinels.accessToken is required")
	}
	if p.Sentinels.RefreshToken == "" {
		return fmt.Errorf("artifact: oauth: sentinels.refreshToken is required")
	}
	if p.CredentialFile != nil {
		if p.CredentialFile.Path == "" {
			return fmt.Errorf("artifact: oauth: credentialFile.path is required")
		}
		if p.CredentialFile.Template == "" {
			return fmt.Errorf("artifact: oauth: credentialFile.template is required")
		}
	}
	return nil
}
