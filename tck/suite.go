// Package tck provides a Technology Compatibility Kit for validating sandbox kit artifacts.
// It loads an artifact from a directory, derives test expectations from its spec.yaml,
// and verifies them against a real container using testcontainers-go.
package tck

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
)

const (
	// DefaultShellImage is the Docker image used for kind=mixin container tests.
	DefaultShellImage = "docker/sandbox-templates:shell-docker"

	// HomeDir is the agent's home directory inside sandbox containers.
	HomeDir = "/home/agent"
)

var shellIdentifierPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// Suite holds test expectations derived from a kit artifact.
type Suite struct {
	// Artifact is the loaded and validated kit artifact.
	Artifact *spec.Artifact

	// Image is the container image used for integration tests.
	Image string

	// Derived expectations
	ExpectedEnvVars        []string
	ExpectedContainerFiles []string
	ExpectedAllowedDomains []string
	ExpectedDeniedDomains  []string
	ExpectedServiceDomains map[string]string
	ExpectedServiceAuth    map[string]spec.ServiceAuth
	ExpectedTmpfs          map[string]string // path -> options (manifest tmpfs + /run/secrets)
}

// RunAll runs all TCK tests for the kit artifact.
// A single container is started and reused for all container-based assertions.
func (s *Suite) RunAll(t *testing.T) {
	t.Run(s.Artifact.Manifest.Name+"_TCK", func(t *testing.T) {
		// Pure logic tests — no container needed
		s.RunValidationTests(t)
		s.RunNetworkPolicyTests(t)
		s.RunCredentialPolicyTests(t)
		s.RunEnvironmentPolicyTests(t)
		s.RunCommandsValidationTests(t)
		s.RunOAuthPolicyTests(t)

		// Container tests — single container for all assertions
		s.RunContainerTests(t)
	})
}

// RunContainerTests starts a single container, injects files, and runs all
// container-based assertions against it.
func (s *Suite) RunContainerTests(t *testing.T) {
	t.Run("container", func(t *testing.T) {
		ctx := context.Background()
		container := s.startContainer(t, ctx)

		// Inject static files from files/ directory
		for _, f := range s.Artifact.Files {
			var targetDir string
			if f.Target == spec.TargetHome {
				targetDir = HomeDir
			} else {
				targetDir = TestWorkDir
			}
			containerPath := targetDir + "/" + f.RelativePath

			parentDir := filepath.Dir(containerPath)
			code, _, err := container.Exec(ctx, []string{"mkdir", "-p", parentDir})
			require.NoError(t, err)
			require.Equal(t, 0, code, "mkdir -p %s failed", parentDir)

			rc, err := f.Open()
			require.NoError(t, err, "failed to open %s for container copy", containerPath)
			fileBytes, readErr := io.ReadAll(rc)
			closeErr := rc.Close()
			require.NoError(t, readErr, "failed to read %s for container copy", containerPath)
			require.NoError(t, closeErr, "failed to close %s after read", containerPath)
			err = container.CopyToContainer(ctx, fileBytes, containerPath, f.Mode)
			require.NoError(t, err, "failed to copy %s to container", containerPath)
		}

		// Simulate initFiles — Docker Sandboxes write these at startup with ${WORKDIR} resolved
		if s.Artifact.Commands != nil {
			for _, f := range s.Artifact.Commands.InitFiles {
				containerPath := strings.ReplaceAll(f.Path, "${WORKDIR}", TestWorkDir)
				content := strings.ReplaceAll(f.Content, "${WORKDIR}", TestWorkDir)

				parentDir := filepath.Dir(containerPath)
				code, _, err := container.Exec(ctx, []string{"mkdir", "-p", parentDir})
				require.NoError(t, err)
				require.Equal(t, 0, code, "mkdir -p %s failed", parentDir)

				mode := int64(0o644)
				if f.Mode != "" {
					fmt.Sscanf(f.Mode, "%o", &mode)
				}

				err = container.CopyToContainer(ctx, []byte(content), containerPath, mode)
				require.NoError(t, err, "failed to write initFile %s to container", containerPath)
			}
		}

		// Execute install commands as a real sandbox would. This catches
		// failures that pure spec validation cannot — wrong user (writes
		// to root-owned paths as user 1000), missing tools, syntax
		// errors, conflicting flags. Skipped under -short.
		s.assertInstallExecution(t, ctx, container)

		// All container assertions against the same container
		s.assertEnvVars(t, ctx, container)
		s.assertFiles(t, ctx, container)
		s.assertTmpfs(t, ctx, container)
	})
}

// assertInstallExecution runs each install command from the artifact in the
// test container with the user it declares, and asserts a clean exit. The
// TCK container has no proxy or network policy enforcement, so this catches
// permission, syntax, and missing-tool bugs but not allowedDomains gaps.
//
// Skipped when testing.Short() is set so contributors can iterate quickly
// (some install commands run multi-minute network-bound tasks like
// "npm install --maxsockets=1").
func (s *Suite) assertInstallExecution(t *testing.T, ctx context.Context, container testcontainers.Container) {
	if s.Artifact.Commands == nil || len(s.Artifact.Commands.Install) == 0 {
		return
	}
	if testing.Short() {
		t.Log("install_execution: skipped under -short")
		return
	}

	t.Run("install_execution", func(t *testing.T) {
		for i, cmd := range s.Artifact.Commands.Install {
			user := cmd.User
			if user == "" {
				// Mirrors sandboxlib/kit/agent.go buildInstallCustomizers:
				// install commands default to root since they typically
				// install system packages.
				user = "0"
			}

			label := cmd.Description
			if label == "" {
				label = fmt.Sprintf("install[%d]", i)
			}

			t.Run(label, func(t *testing.T) {
				// Wrap with "sh -c" to match the real install runner —
				// kit authors write natural shell strings (pipes,
				// expansions) without explicit shell wrapping.
				code, reader, err := container.Exec(ctx,
					[]string{"sh", "-c", cmd.Command},
					tcexec.WithUser(user),
					tcexec.Multiplexed(),
				)
				require.NoError(t, err, "exec install command (user=%s): %s", user, cmd.Command)

				output := readOutput(t, reader)
				require.Equalf(t, 0, code,
					"install command exited %d (user=%s)\n  command: %s\n  output:\n%s",
					code, user, cmd.Command, output,
				)
			})
		}
	})
}

func (s *Suite) assertEnvVars(t *testing.T, ctx context.Context, container testcontainers.Container) {
	if len(s.ExpectedEnvVars) == 0 {
		return
	}

	t.Run("environment_variables", func(t *testing.T) {
		code, reader, err := container.Exec(ctx, []string{"env"})
		require.NoError(t, err)
		require.Equal(t, 0, code, "env command failed")

		envOutput := readOutput(t, reader)

		for _, expected := range s.ExpectedEnvVars {
			require.Contains(t, envOutput, expected,
				"container should have env var %s", expected)
		}
	})
}

func (s *Suite) assertFiles(t *testing.T, ctx context.Context, container testcontainers.Container) {
	if len(s.ExpectedContainerFiles) == 0 {
		return
	}

	t.Run("files", func(t *testing.T) {
		for _, containerPath := range s.ExpectedContainerFiles {
			t.Run(containerPath, func(t *testing.T) {
				code, _, err := container.Exec(ctx, []string{"test", "-f", containerPath})
				require.NoError(t, err)
				require.Equal(t, 0, code, "file %s should exist in the container", containerPath)

				code, r, err := container.Exec(ctx, []string{"cat", containerPath})
				require.NoError(t, err)
				require.Equal(t, 0, code, "should be able to read %s", containerPath)
				require.NotEmpty(t, readOutput(t, r), "file %s should not be empty", containerPath)
			})
		}
	})
}

func (s *Suite) assertTmpfs(t *testing.T, ctx context.Context, container testcontainers.Container) {
	if len(s.ExpectedTmpfs) == 0 {
		return
	}

	t.Run("tmpfs_mounts", func(t *testing.T) {
		code, reader, err := container.Exec(ctx, []string{"mount"})
		require.NoError(t, err)
		require.Equal(t, 0, code, "mount command failed")

		mountOutput := readOutput(t, reader)

		for mountPath := range s.ExpectedTmpfs {
			t.Run(mountPath, func(t *testing.T) {
				expected := fmt.Sprintf("tmpfs on %s", mountPath)
				require.Contains(t, mountOutput, expected,
					"%s should be mounted as tmpfs; mount output: %s", mountPath, mountOutput)
			})
		}
	})
}

// RunValidationTests verifies all manifest fields are well-formed.
func (s *Suite) RunValidationTests(t *testing.T) {
	t.Run("validation", func(t *testing.T) {
		m := s.Artifact.Manifest

		t.Run("required_fields", func(t *testing.T) {
			require.NotEmpty(t, m.SchemaVersion, "schemaVersion is required")
			require.Contains(t, spec.SupportedSchemaVersions, m.SchemaVersion, "schemaVersion must be one of %v", spec.SupportedSchemaVersions)
			require.NotEmpty(t, m.Kind, "kind is required")
			require.NotEmpty(t, m.Name, "name is required")
			require.NotEmpty(t, m.DisplayName, "displayName is required")
			require.NotEmpty(t, m.Description, "description is required")
		})

		t.Run("kind_rules", func(t *testing.T) {
			if m.Kind == spec.KindMixin {
				require.Empty(t, m.Template, "mixins should not define their own template")
				require.Empty(t, m.Binary, "mixins should not define a binary")
			}
			if m.Kind == spec.KindAgent {
				require.NotEmpty(t, m.Template, "agents must define a template")
			}
		})

		if m.Security != nil {
			t.Run("security", func(t *testing.T) {
				// privileged is a bool — just verify the field is reachable
				t.Logf("security.privileged=%v", m.Security.Privileged)
			})
		}

		if len(m.Volumes) > 0 {
			t.Run("volumes", func(t *testing.T) {
				for i, v := range m.Volumes {
					require.True(t, strings.HasPrefix(v.Path, "/"),
						"volumes[%d].path %q must be absolute", i, v.Path)
				}
			})
		}

		if tmpfsVolumes := m.TmpfsVolumes(); len(tmpfsVolumes) > 0 {
			t.Run("tmpfs", func(t *testing.T) {
				for i, mnt := range tmpfsVolumes {
					require.True(t, strings.HasPrefix(mnt.Path, "/"),
						"tmpfs[%d].path %q must be absolute", i, mnt.Path)
				}
			})
		}

		if s.Artifact.Extends != "" {
			t.Run("extends", func(t *testing.T) {
				require.Equal(t, spec.KindMixin, m.Kind,
					"extends is only valid for kind %q", spec.KindMixin)
				_, known := wellKnownTemplates[s.Artifact.Extends]
				require.True(t, known,
					"extends references unknown agent %q; known agents: %v",
					s.Artifact.Extends, wellKnownAgentNames())
			})
		}

		if len(s.Artifact.Locked) > 0 {
			t.Run("locked", func(t *testing.T) {
				require.NoError(t, spec.ValidateLocked(s.Artifact.Locked),
					"locked paths must be well-formed")
			})
		}

		if m.Resources != nil {
			t.Run("resources", func(t *testing.T) {
				require.GreaterOrEqual(t, m.Resources.CPU, 0.0,
					"resources.cpu must be non-negative")
				require.GreaterOrEqual(t, m.Resources.MemoryMB, int64(0),
					"resources.memoryMB must be non-negative")
			})
		}

		if m.AIFilename != "" {
			t.Run("ai_filename", func(t *testing.T) {
				require.True(t, strings.HasSuffix(m.AIFilename, ".md") || strings.HasSuffix(m.AIFilename, ".txt"),
					"aiFilename %q should have a .md or .txt extension", m.AIFilename)
			})
		}

		if len(m.RunOptions) > 0 {
			t.Run("run_options", func(t *testing.T) {
				for i, opt := range m.RunOptions {
					require.NotEmpty(t, opt, "runOptions[%d] must not be empty", i)
				}
			})
		}

		if s.Artifact.AgentContext != "" {
			t.Run("agentContext", func(t *testing.T) {
				require.NotEmpty(t, s.Artifact.AgentContext, "agentContext content should not be empty when declared")
			})
		}
	})
}

// RunNetworkPolicyTests verifies the artifact's network policy is consistent.
//
// Post-Phase-3 commit 7: allow/deny come from Caps.Network; service
// domains/auth come from Credentials[].ApiKey.Inject. The Suite's
// Expected* field names are preserved.
func (s *Suite) RunNetworkPolicyTests(t *testing.T) {
	caps := s.Artifact.Caps
	creds := s.Artifact.Credentials
	if caps == nil && len(creds) == 0 && len(s.ExpectedAllowedDomains) == 0 && len(s.ExpectedDeniedDomains) == 0 && len(s.ExpectedServiceDomains) == 0 {
		return
	}

	// Build the actual service-domains / service-auth maps from
	// Credentials[].ApiKey.Inject.
	actualDomains := map[string]string{}
	actualAuth := map[string]spec.ServiceAuth{}
	for _, c := range creds {
		if c.ApiKey == nil {
			continue
		}
		for _, inj := range c.ApiKey.Inject {
			if inj.Domain != "" {
				actualDomains[inj.Domain] = c.Service
			}
		}
		if len(c.ApiKey.Inject) > 0 {
			if _, exists := actualAuth[c.Service]; !exists {
				inj := c.ApiKey.Inject[0]
				actualAuth[c.Service] = spec.ServiceAuth{HeaderName: inj.Header, ValueFormat: inj.Format}
			}
		}
	}

	t.Run("network_policy", func(t *testing.T) {
		var actualAllow, actualDeny []string
		if caps != nil && caps.Network != nil {
			actualAllow = caps.Network.Allow
			actualDeny = caps.Network.Deny
		}

		if len(s.ExpectedAllowedDomains) > 0 {
			require.ElementsMatch(t, s.ExpectedAllowedDomains, actualAllow,
				"allowed domains should match")
		}

		if len(s.ExpectedDeniedDomains) > 0 {
			require.ElementsMatch(t, s.ExpectedDeniedDomains, actualDeny,
				"denied domains should match")
		}

		if len(s.ExpectedServiceDomains) > 0 {
			require.Equal(t, s.ExpectedServiceDomains, actualDomains,
				"service domains should match")
		}

		if len(s.ExpectedServiceAuth) > 0 {
			for service, expected := range s.ExpectedServiceAuth {
				actual, ok := actualAuth[service]
				require.True(t, ok, "service auth for %q not found", service)
				require.Equal(t, expected.HeaderName, actual.HeaderName,
					"headerName mismatch for service %q", service)
				require.Contains(t, actual.ValueFormat, "%s",
					"valueFormat for service %q must contain %%s", service)
				require.Equal(t, expected.ValueFormat, actual.ValueFormat,
					"valueFormat mismatch for service %q", service)
			}
		}
	})
}

// RunCredentialPolicyTests verifies the artifact's credential policy is well-formed.
func (s *Suite) RunCredentialPolicyTests(t *testing.T) {
	if s.Artifact.Credentials == nil {
		return
	}

	t.Run("credential_policy", func(t *testing.T) {
		for _, c := range s.Artifact.Credentials {
			t.Run(c.Service, func(t *testing.T) {
				require.True(t, c.ApiKey != nil || c.OAuth != nil,
					"credential entry for %q must have at least one of apiKey or oauth", c.Service)

				if c.ApiKey != nil && c.ApiKey.Name != "" {
					// "Routing-only" credentials (ApiKey.Name empty, Inject
					// non-empty) are valid under the parallel-load normalize
					// path: v1 kits that declared services in network.serviceAuth
					// + network.serviceDomains without a matching
					// credentials.sources entry produce these entries (e.g.,
					// amp, github routing in docker-agent). Skip the name
					// shape check when the credential is routing-only.
					require.True(t, shellIdentifierPattern.MatchString(c.ApiKey.Name),
						"credential apiKey.name %q for service %q is not a valid shell identifier", c.ApiKey.Name, c.Service)
				}
			})
		}
	})
}

// RunEnvironmentPolicyTests verifies the environment policy structure (pure logic).
func (s *Suite) RunEnvironmentPolicyTests(t *testing.T) {
	if s.Artifact.Environment == nil {
		return
	}

	t.Run("environment_policy", func(t *testing.T) {
		env := s.Artifact.Environment

		if len(env.Variables) > 0 {
			t.Run("variables", func(t *testing.T) {
				for key := range env.Variables {
					require.True(t, shellIdentifierPattern.MatchString(key),
						"variable key %q is not a valid shell identifier", key)
				}
			})
		}

		// Note: post-Phase-3 commit 5, environment.proxyManaged is the
		// v1-only ProxyManaged shim. The canonical place to enumerate
		// proxy-managed env-var names is Credentials[].ApiKey.Name, which
		// is validated by RunCredentialPolicyTests above. The shim is
		// validated by ValidateEnvironmentPolicy at load time.
	})
}

// RunCommandsValidationTests verifies install and startup commands are well-formed.
func (s *Suite) RunCommandsValidationTests(t *testing.T) {
	if s.Artifact.Commands == nil {
		return
	}

	t.Run("commands_validation", func(t *testing.T) {
		for i, cmd := range s.Artifact.Commands.Install {
			require.NotEmpty(t, cmd.Command,
				"install command [%d] must not be empty", i)
		}

		for i, cmd := range s.Artifact.Commands.Startup {
			require.NotEmpty(t, cmd.Command,
				"startup command [%d] must not be empty", i)
		}

		for i, f := range s.Artifact.Commands.InitFiles {
			require.NotEmpty(t, f.Path,
				"initFile [%d] path must not be empty", i)
			require.True(t, strings.HasPrefix(f.Path, "/"),
				"initFile [%d] path must be absolute (got %q)", i, f.Path)
		}
	})
}

// RunOAuthPolicyTests verifies the OAuth policy is well-formed for every
// credential that declares an oauth: sub-block. Post-Phase-3 commit 5,
// OAuth lives under Credential.OAuth (per-credential); the standalone
// top-level oauth: block is the v1 LegacyOAuth shim handled at load time.
func (s *Suite) RunOAuthPolicyTests(t *testing.T) {
	for _, c := range s.Artifact.Credentials {
		if c.OAuth == nil {
			continue
		}
		t.Run("oauth_policy/"+c.Service, func(t *testing.T) {
			oauth := c.OAuth

			t.Run("token_endpoint", func(t *testing.T) {
				require.NotEmpty(t, oauth.TokenEndpoint.Host, "oauth.tokenEndpoint.host is required")
				require.NotEmpty(t, oauth.TokenEndpoint.Path, "oauth.tokenEndpoint.path is required")
			})

			t.Run("sentinels", func(t *testing.T) {
				require.NotEmpty(t, oauth.Sentinels.AccessToken, "oauth.sentinels.accessToken is required")
				require.NotEmpty(t, oauth.Sentinels.RefreshToken, "oauth.sentinels.refreshToken is required")
			})

			if oauth.CredentialFile != nil {
				t.Run("credential_file", func(t *testing.T) {
					require.NotEmpty(t, oauth.CredentialFile.Path, "oauth.credentialFile.path is required")
					// v2 prefers Structure; v1 Template is still accepted.
					require.True(t,
						oauth.CredentialFile.Template != "" || oauth.CredentialFile.Structure != nil,
						"oauth.credentialFile must have either template (v1) or structure (v2)")
				})
			}
		})
	}
}

// startContainer creates and starts a container from the suite's image using testcontainers-go.
func (s *Suite) startContainer(t *testing.T, ctx context.Context) testcontainers.Container {
	t.Helper()

	envMap := make(map[string]string)
	if s.Artifact.Environment != nil {
		for k, v := range s.Artifact.Environment.Variables {
			envMap[k] = v
		}
	}

	ctr, err := testcontainers.Run(ctx, s.Image,
		testcontainers.WithEnv(envMap),
		testcontainers.WithTmpfs(s.ExpectedTmpfs),
		testcontainers.WithEntrypoint("sleep", "infinity"),
	)
	testcontainers.CleanupContainer(t, ctr)
	require.NoError(t, err, "failed to start container from image %s", s.Image)

	return ctr
}

// readOutput reads all output from a container exec and trims trailing whitespace.
func readOutput(t *testing.T, r io.Reader) string {
	t.Helper()

	var buf bytes.Buffer
	_, err := io.Copy(&buf, r)
	require.NoError(t, err)

	return strings.TrimRight(buf.String(), "\n\r ")
}

// containerImage returns the image to use for container tests,
// resolving well-known agent templates for mixins with extends.
func containerImage(a *spec.Artifact) (string, error) {
	if a.Manifest.Kind == spec.KindAgent {
		if a.Manifest.Template == "" {
			return "", fmt.Errorf("agent artifact %q has no template", a.Manifest.Name)
		}
		return a.Manifest.Template, nil
	}

	// kind=mixin: resolve from extends or default to shell
	if a.Extends != "" {
		if tmpl, ok := wellKnownTemplates[a.Extends]; ok {
			return tmpl, nil
		}
		return "", fmt.Errorf(
			"mixin %q extends unknown agent %q; use WithImage to specify the container image",
			a.Manifest.Name, a.Extends,
		)
	}

	return DefaultShellImage, nil
}

// wellKnownTemplates maps agent names to their published template images.
var wellKnownTemplates = map[string]string{
	"shell":        "docker/sandbox-templates:shell-docker",
	"claude":       "docker/sandbox-templates:claude-code-docker",
	"codex":        "docker/sandbox-templates:codex-docker",
	"copilot":      "docker/sandbox-templates:copilot-docker",
	"cursor":       "docker/sandbox-templates:cursor-agent-docker",
	"docker-agent": "docker/sandbox-templates:docker-agent",
	"droid":        "docker/sandbox-templates:droid-docker",
	"gemini":       "docker/sandbox-templates:gemini-docker",
	"kiro":         "docker/sandbox-templates:kiro-docker",
	"opencode":     "docker/sandbox-templates:opencode-docker",
}

func wellKnownAgentNames() []string {
	names := make([]string, 0, len(wellKnownTemplates))
	for k := range wellKnownTemplates {
		names = append(names, k)
	}
	return names
}
