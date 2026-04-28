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
		s.RunSettingsPolicyTests(t)
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

			err = container.CopyToContainer(ctx, f.Content, containerPath, f.Mode)
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
			require.Equal(t, spec.SchemaVersion, m.SchemaVersion, "schemaVersion must be %q", spec.SchemaVersion)
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

		if m.Persistence != "" {
			t.Run("persistence", func(t *testing.T) {
				require.Contains(t, []string{spec.PersistenceEphemeral, spec.PersistencePersistent}, m.Persistence,
					"persistence must be %q or %q", spec.PersistenceEphemeral, spec.PersistencePersistent)
			})
		}

		if m.Security != nil {
			t.Run("security", func(t *testing.T) {
				// privileged is a bool — just verify the field is reachable
				t.Logf("security.privileged=%v", m.Security.Privileged)
			})
		}

		if len(m.Volumes) > 0 {
			t.Run("volumes", func(t *testing.T) {
				for p := range m.Volumes {
					require.True(t, strings.HasPrefix(p, "/"),
						"volume path %q must be absolute", p)
				}
			})
		}

		if len(m.Tmpfs) > 0 {
			t.Run("tmpfs", func(t *testing.T) {
				for p := range m.Tmpfs {
					require.True(t, strings.HasPrefix(p, "/"),
						"tmpfs path %q must be absolute", p)
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

		if s.Artifact.Memory != "" {
			t.Run("memory", func(t *testing.T) {
				require.NotEmpty(t, s.Artifact.Memory, "memory content should not be empty when declared")
			})
		}
	})
}

// RunNetworkPolicyTests verifies the artifact's network policy is consistent.
func (s *Suite) RunNetworkPolicyTests(t *testing.T) {
	if s.Artifact.Network == nil && len(s.ExpectedAllowedDomains) == 0 && len(s.ExpectedServiceDomains) == 0 {
		return
	}

	t.Run("network_policy", func(t *testing.T) {
		net := s.Artifact.Network
		if net == nil {
			require.Empty(t, s.ExpectedAllowedDomains, "expected allowed domains but network policy is nil")
			require.Empty(t, s.ExpectedServiceDomains, "expected service domains but network policy is nil")
			return
		}

		if len(s.ExpectedAllowedDomains) > 0 {
			require.ElementsMatch(t, s.ExpectedAllowedDomains, net.AllowedDomains,
				"allowed domains should match")
		}

		if len(s.ExpectedServiceDomains) > 0 {
			require.Equal(t, s.ExpectedServiceDomains, net.ServiceDomains,
				"service domains should match")
		}

		if len(s.ExpectedServiceAuth) > 0 {
			require.NotNil(t, net.ServiceAuth)
			for service, expected := range s.ExpectedServiceAuth {
				actual, ok := net.ServiceAuth[service]
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
		for service, source := range s.Artifact.Credentials.Sources {
			t.Run(service, func(t *testing.T) {
				require.True(t, len(source.Env) > 0 || source.File != nil,
					"credential source for %q must have at least one of env or file", service)

				for i, envVar := range source.Env {
					require.True(t, shellIdentifierPattern.MatchString(envVar),
						"credential env[%d] %q for service %q is not a valid shell identifier", i, envVar, service)
				}

				if source.File != nil {
					require.NotEmpty(t, source.File.Path,
						"credential file path for %q must not be empty", service)
				}

				if source.Priority != "" {
					require.Contains(t, []string{"env-first", "file-first"}, source.Priority,
						"invalid priority %q for service %q", source.Priority, service)
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

		if len(env.ProxyManaged) > 0 {
			t.Run("proxy_managed", func(t *testing.T) {
				for _, key := range env.ProxyManaged {
					require.True(t, shellIdentifierPattern.MatchString(key),
						"proxyManaged entry %q is not a valid shell identifier", key)
				}
			})
		}
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

// RunSettingsPolicyTests verifies the settings policy is well-formed.
func (s *Suite) RunSettingsPolicyTests(t *testing.T) {
	if s.Artifact.Settings == nil {
		return
	}

	t.Run("settings_policy", func(t *testing.T) {
		require.NotNil(t, s.Artifact.Settings.ContainerSettings,
			"containerSettings map should not be nil when settings policy is present")
		for key := range s.Artifact.Settings.ContainerSettings {
			require.NotEmpty(t, key, "containerSettings key must not be empty")
		}
	})
}

// RunOAuthPolicyTests verifies the OAuth policy is well-formed.
func (s *Suite) RunOAuthPolicyTests(t *testing.T) {
	if s.Artifact.OAuth == nil {
		return
	}

	t.Run("oauth_policy", func(t *testing.T) {
		oauth := s.Artifact.OAuth

		require.NotEmpty(t, oauth.Service, "oauth.service is required")

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
				require.NotEmpty(t, oauth.CredentialFile.Template, "oauth.credentialFile.template is required")
			})
		}
	})
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
