package tck

import (
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/stretchr/testify/require"
)

func TestDeriveEnvVars(t *testing.T) {
	t.Run("nil_env", func(t *testing.T) {
		require.Nil(t, deriveEnvVars(nil))
	})

	t.Run("empty_variables", func(t *testing.T) {
		require.Nil(t, deriveEnvVars(&spec.EnvironmentPolicy{}))
	})

	t.Run("sorted_output", func(t *testing.T) {
		env := &spec.EnvironmentPolicy{
			Variables: map[string]string{
				"Z_VAR": "z",
				"A_VAR": "a",
				"M_VAR": "m",
			},
		}
		result := deriveEnvVars(env)
		require.Equal(t, []string{"A_VAR=a", "M_VAR=m", "Z_VAR=z"}, result)
	})
}

func TestDeriveContainerFiles(t *testing.T) {
	t.Run("home_files_only", func(t *testing.T) {
		files := []spec.ArtifactFile{
			{RelativePath: "config.json", Target: spec.TargetHome},
			{RelativePath: "data.txt", Target: spec.TargetWorkspace},
		}
		result := deriveContainerFiles(files, nil)
		require.Equal(t, []string{HomeDir + "/config.json"}, result)
	})

	t.Run("includes_initfiles_with_workdir_resolved", func(t *testing.T) {
		commands := &spec.CommandsPolicy{
			InitFiles: []spec.InitFile{
				{Path: "${WORKDIR}/.config/init.sh"},
				{Path: "/home/agent/.tool/config"},
			},
		}
		result := deriveContainerFiles(nil, commands)
		require.Equal(t, []string{
			TestWorkDir + "/.config/init.sh",
			"/home/agent/.tool/config",
		}, result)
	})

	t.Run("nil_inputs", func(t *testing.T) {
		require.Nil(t, deriveContainerFiles(nil, nil))
	})
}

func TestDeriveTmpfs(t *testing.T) {
	t.Run("always_includes_run_secrets", func(t *testing.T) {
		result := deriveTmpfs(nil)
		require.Contains(t, result, "/run/secrets")
		require.Equal(t, "rw,noexec,nosuid", result["/run/secrets"])
	})

	t.Run("merges_manifest_tmpfs", func(t *testing.T) {
		result := deriveTmpfs([]spec.MountSpec{
			{Path: "/tmp", Size: "1g"},
		})
		require.Contains(t, result, "/run/secrets")
		require.Contains(t, result, "/tmp")
		require.Equal(t, "size=1g", result["/tmp"])
	})

	t.Run("composes_size_and_mode", func(t *testing.T) {
		result := deriveTmpfs([]spec.MountSpec{
			{Path: "/scratch", Size: "512m", Mode: "1777"},
		})
		require.Equal(t, "size=512m,mode=1777", result["/scratch"])
	})
}

func TestResolveWorkdir(t *testing.T) {
	require.Equal(t, "/workspace/data", resolveWorkdir("${WORKDIR}/data"))
	require.Equal(t, "/home/agent/file", resolveWorkdir("/home/agent/file"))
	require.Equal(t, "/workspace", resolveWorkdir("${WORKDIR}"))
}

func TestContainerImage(t *testing.T) {
	t.Run("sandbox_uses_template", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindSandbox, Template: "my/image:v1"},
		}
		img, err := containerImage(a)
		require.NoError(t, err)
		require.Equal(t, "my/image:v1", img)
	})

	t.Run("sandbox_without_template_errors", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindSandbox, Name: "bad"},
		}
		_, err := containerImage(a)
		require.ErrorContains(t, err, "no template")
	})

	t.Run("mixin_defaults_to_shell", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin},
		}
		img, err := containerImage(a)
		require.NoError(t, err)
		require.Equal(t, DefaultShellImage, img)
	})

	t.Run("mixin_extends_known_agent", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin},
			Extends:  "claude",
		}
		img, err := containerImage(a)
		require.NoError(t, err)
		require.Equal(t, "docker/sandbox-templates:claude-code-docker", img)
	})

	t.Run("mixin_extends_unknown_agent_errors", func(t *testing.T) {
		a := &spec.Artifact{
			Manifest: spec.Manifest{Kind: spec.KindMixin, Name: "test"},
			Extends:  "unknown-agent",
		}
		_, err := containerImage(a)
		require.ErrorContains(t, err, "unknown agent")
	})
}

func TestNewSuiteFromDir(t *testing.T) {
	t.Run("sample_mixin", func(t *testing.T) {
		suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
		require.NoError(t, err)

		require.Equal(t, DefaultShellImage, suite.Image)
		require.NotEmpty(t, suite.ExpectedEnvVars)
		require.NotEmpty(t, suite.ExpectedContainerFiles)
		require.NotEmpty(t, suite.ExpectedAllowedDomains)
		require.Contains(t, suite.ExpectedTmpfs, "/run/secrets")
	})

	t.Run("sample_agent", func(t *testing.T) {
		suite, err := NewSuiteFromDir("../spec/testdata/sample-agent")
		require.NoError(t, err)

		require.Equal(t, "docker/sandbox-templates:shell-docker", suite.Image)
		require.NotEmpty(t, suite.ExpectedEnvVars)
		require.NotEmpty(t, suite.ExpectedContainerFiles)
	})

	t.Run("with_image_override", func(t *testing.T) {
		suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin", WithImage("custom:latest"))
		require.NoError(t, err)

		require.Equal(t, "custom:latest", suite.Image)
	})

	t.Run("invalid_dir", func(t *testing.T) {
		_, err := NewSuiteFromDir("../spec/testdata/does-not-exist")
		require.Error(t, err)
	})
}

// Test the pure-logic Run*Tests methods by constructing Suites directly.
// These don't need Docker — they just call the assertion methods with a *testing.T.

func TestRunValidationTests(t *testing.T) {
	t.Run("mixin", func(t *testing.T) {
		suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
		require.NoError(t, err)
		suite.RunValidationTests(t)
	})

	t.Run("agent", func(t *testing.T) {
		suite, err := NewSuiteFromDir("../spec/testdata/sample-agent")
		require.NoError(t, err)
		suite.RunValidationTests(t)
	})
}

func TestRunNetworkPolicyTests(t *testing.T) {
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	suite.RunNetworkPolicyTests(t)
}

func TestRunCredentialPolicyTests(t *testing.T) {
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	suite.RunCredentialPolicyTests(t)
}

func TestRunEnvironmentPolicyTests(t *testing.T) {
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	suite.RunEnvironmentPolicyTests(t)
}

func TestRunCommandsValidationTests(t *testing.T) {
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	suite.RunCommandsValidationTests(t)
}

func TestRunOAuthPolicyTests(t *testing.T) {
	// sample-mixin has no OAuth — verify it's a no-op
	suite, err := NewSuiteFromDir("../spec/testdata/sample-mixin")
	require.NoError(t, err)
	suite.RunOAuthPolicyTests(t)

	// Test with an artifact that has OAuth under a v2 credentials[] entry.
	suite2 := &Suite{
		Artifact: &spec.Artifact{
			Manifest: spec.Manifest{
				SchemaVersion: spec.SchemaVersion,
				Kind:          spec.KindMixin,
				Name:          "oauth-test",
			},
			Credentials: []spec.Credential{{
				Service: "test-svc",
				OAuth: &spec.OAuth{
					TokenEndpoint: spec.OAuthTokenEndpoint{Host: "auth.example.com", Path: "/token"},
					Sentinels:     spec.OAuthSentinels{AccessToken: "at", RefreshToken: "rt"},
				},
			}},
		},
	}
	suite2.RunOAuthPolicyTests(t)
}

func TestRunNetworkPolicyTests_NoNetwork(t *testing.T) {
	suite := &Suite{
		Artifact: &spec.Artifact{
			Manifest: spec.Manifest{
				SchemaVersion: spec.SchemaVersion,
				Kind:          spec.KindMixin,
				Name:          "no-net",
			},
		},
	}
	// Should be a no-op, not panic
	suite.RunNetworkPolicyTests(t)
}

func TestRunCredentialPolicyTests_NoCredentials(t *testing.T) {
	suite := &Suite{
		Artifact: &spec.Artifact{
			Manifest: spec.Manifest{
				SchemaVersion: spec.SchemaVersion,
				Kind:          spec.KindMixin,
				Name:          "no-creds",
			},
		},
	}
	suite.RunCredentialPolicyTests(t)
}

func TestRunCommandsValidationTests_NoCommands(t *testing.T) {
	suite := &Suite{
		Artifact: &spec.Artifact{
			Manifest: spec.Manifest{
				SchemaVersion: spec.SchemaVersion,
				Kind:          spec.KindMixin,
				Name:          "no-cmds",
			},
		},
	}
	suite.RunCommandsValidationTests(t)
}
