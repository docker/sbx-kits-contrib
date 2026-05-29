package tck

import (
	"fmt"
	"sort"
	"strings"

	"github.com/docker/sbx-kits-contrib/spec"
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
// For kind=agent artifacts, the container image is taken from the manifest's template.
// For kind=mixin artifacts, the image is resolved from the extends field using
// well-known agent templates, or defaults to the shell template.
// Use WithImage to override the image for any artifact.
func NewSuiteFromDir(dir string, opts ...Option) (*Suite, error) {
	artifact, err := spec.LoadFromDirectory(dir)
	if err != nil {
		return nil, fmt.Errorf("load artifact from %q: %w", dir, err)
	}

	image, err := containerImage(artifact)
	if err != nil {
		return nil, err
	}

	suite := &Suite{
		Artifact:               artifact,
		Image:                  image,
		ExpectedEnvVars:        deriveEnvVars(artifact.Environment),
		ExpectedContainerFiles: deriveContainerFiles(artifact.Files, artifact.Commands),
		ExpectedTmpfs:          deriveTmpfs(artifact.Manifest.TmpfsVolumes()),
	}

	// Derive network expectations
	if artifact.Network != nil {
		suite.ExpectedAllowedDomains = artifact.Network.AllowedDomains
		suite.ExpectedDeniedDomains = artifact.Network.DeniedDomains
		suite.ExpectedServiceDomains = artifact.Network.ServiceDomains
		suite.ExpectedServiceAuth = artifact.Network.ServiceAuth
	}

	// Apply functional options (e.g., WithImage)
	for _, opt := range opts {
		opt(suite)
	}

	return suite, nil
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
