package tck

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/docker/sbx-kits-contrib/spec"
	"go.yaml.in/yaml/v3"
)

// Option is a functional option for customizing a Suite.
type Option func(*Suite)

// WithImage overrides the container image used for integration tests.
func WithImage(image string) Option {
	return func(s *Suite) {
		s.Image = image
	}
}

// NewSuiteFromDir loads a kit artifact from the given directory and derives
// all test expectations from the spec.yaml and files/ directory.
//
// The artifact is loaded via spec.OpenFromDirectory (streaming path) so the
// TCK exercises on-demand file reading via ArtifactFile.Open. File content is
// still read into memory at the copy boundary inside RunContainerTests, but
// only one file at a time.
//
// For kind=agent artifacts, the container image is taken from the manifest's template.
// For kind=mixin artifacts, the image is resolved from extends or the declared
// base-agent affinity (requires.agent) using well-known agent templates, or
// defaults to the shell template.
// Use WithImage to override the image for any artifact.
func NewSuiteFromDir(dir string, opts ...Option) (*Suite, error) {
	artifact, err := spec.OpenFromDirectory(dir)
	if err != nil {
		return nil, fmt.Errorf("load artifact from %q: %w", dir, err)
	}

	suite := &Suite{
		Artifact:               artifact,
		Dir:                    dir,
		ExpectedEnvVars:        deriveEnvVars(artifact.Environment),
		ExpectedContainerFiles: deriveContainerFiles(artifact.Files, artifact.Commands),
		ExpectedTmpfs:          deriveTmpfs(artifact.Manifest.TmpfsVolumes()),
	}

	// Derive network expectations. Post-Phase-3 commit 7: allow/deny
	// derive from Caps.Network; serviceDomains/serviceAuth derive from
	// Credentials[].ApiKey.Inject. The Suite's expected-field names are
	// preserved for backward compatibility with existing TCK tests.
	if artifact.Caps != nil && artifact.Caps.Network != nil {
		suite.ExpectedAllowedDomains = artifact.Caps.Network.Allow
		suite.ExpectedDeniedDomains = artifact.Caps.Network.Deny
	}
	if len(artifact.Credentials) > 0 {
		domains := map[string]string{}
		auth := map[string]spec.ServiceAuth{}
		for _, c := range artifact.Credentials {
			if c.ApiKey == nil {
				continue
			}
			for _, inj := range c.ApiKey.Inject {
				if inj.Domain != "" {
					domains[inj.Domain] = c.Service
				}
			}
			if len(c.ApiKey.Inject) > 0 {
				if _, exists := auth[c.Service]; !exists {
					inj := c.ApiKey.Inject[0]
					auth[c.Service] = spec.ServiceAuth{HeaderName: inj.Header, ValueFormat: inj.Format}
				}
			}
		}
		if len(domains) > 0 {
			suite.ExpectedServiceDomains = domains
		}
		if len(auth) > 0 {
			suite.ExpectedServiceAuth = auth
		}
	}

	// Apply functional options first, so WithImage can override image
	// resolution — including rescuing an artifact whose image cannot be
	// derived from the spec (unknown extends, or a sandbox with no template).
	for _, opt := range opts {
		opt(suite)
	}

	// Resolve the container image from the spec only when WithImage has not
	// already supplied one. This keeps the "use WithImage" guidance in
	// containerImage's error messages truthful: a caller can always override.
	if suite.Image == "" {
		image, err := containerImage(artifact)
		if err != nil {
			return nil, err
		}
		suite.Image = image
	}

	cfg, err := loadKitTestConfig(dir)
	if err != nil {
		return nil, err
	}
	if cfg != nil {
		suite.PostInstallChecks = cfg.PostInstallChecks
	}

	return suite, nil
}

// kitTestConfig holds kit-specific TCK container-test configuration, loaded
// from <kit-dir>/testdata/tck.yaml. The same file also carries e2e-only
// fields (promptArgs, readyFile, binary — see e2e_test.go's kitTCKData);
// unmarshaling here into a struct that only knows about PostInstallChecks
// silently ignores those, so one file serves both test surfaces.
type kitTestConfig struct {
	// PostInstallChecks are extra commands run in the same TCK container
	// right after the kit's own install commands succeed — for
	// self-contained checks (imports, offline signing self-tests, version
	// assertions) that need the installed toolchain but not a live sandbox.
	// Anything requiring real credentials or live network access belongs in
	// the kit's README as a manual/e2e step instead.
	PostInstallChecks []spec.InstallCommand `yaml:"postInstallChecks"`
}

// loadKitTestConfig reads <dir>/testdata/tck.yaml. Returns nil, nil when the
// file does not exist — most kits have none.
func loadKitTestConfig(dir string) (*kitTestConfig, error) {
	p := filepath.Join(dir, "testdata", "tck.yaml")
	data, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", p, err)
	}

	var cfg kitTestConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", p, err)
	}
	return &cfg, nil
}

// deriveEnvVars builds expected "KEY=VALUE" strings from Environment.Variables.
// Results are sorted for deterministic output.
func deriveEnvVars(env *spec.EnvironmentPolicy) []string {
	if env == nil || len(env.Variables) == 0 {
		return nil
	}

	vars := make([]string, 0, len(env.Variables))
	for k, v := range env.Variables {
		vars = append(vars, fmt.Sprintf("%s=%s", k, v))
	}
	sort.Strings(vars)
	return vars
}

// TestWorkDir is the workspace path used when substituting ${WORKDIR} in
// initFiles during TCK container tests.
const TestWorkDir = "/workspace"

// deriveContainerFiles builds expected absolute container paths from both the
// artifact's files/ directory and commands.initFiles (with ${WORKDIR} resolved
// to TestWorkDir). Only "home" target static files are included since workspace
// paths depend on the workdir.
func deriveContainerFiles(files []spec.ArtifactFile, commands *spec.CommandsPolicy) []string {
	var paths []string

	for _, f := range files {
		if f.Target == spec.TargetHome {
			paths = append(paths, HomeDir+"/"+f.RelativePath)
		}
	}

	if commands != nil {
		for _, f := range commands.InitFiles {
			paths = append(paths, resolveWorkdir(f.Path))
		}
	}

	return paths
}

// resolveWorkdir replaces ${WORKDIR} with TestWorkDir.
func resolveWorkdir(s string) string {
	return strings.ReplaceAll(s, "${WORKDIR}", TestWorkDir)
}

// deriveTmpfs builds the expected tmpfs mounts from the manifest's tmpfs
// volumes (those entries on Manifest.Volumes with Type == "tmpfs"), always
// including /run/secrets for the secrets tmpfs. The result is a path→
// option-string map suitable for testcontainers-go's WithTmpfs (Size and
// Mode compose into the comma-separated value Docker expects).
func deriveTmpfs(manifestTmpfs []spec.MountSpec) map[string]string {
	tmpfs := map[string]string{
		"/run/secrets": "rw,noexec,nosuid",
	}
	for _, t := range manifestTmpfs {
		var opts []string
		if t.Size != "" {
			opts = append(opts, "size="+t.Size)
		}
		if t.Mode != "" {
			opts = append(opts, "mode="+t.Mode)
		}
		tmpfs[t.Path] = strings.Join(opts, ",")
	}
	return tmpfs
}
