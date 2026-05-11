package git_ssh_sign_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

func TestGitSSHSignTCK(t *testing.T) {
	suite, err := tck.NewSuiteFromDir(".")
	require.NoError(t, err)
	suite.RunAll(t)
}

func TestInstallUsesDynamicKeyCommandWithoutHooksPath(t *testing.T) {
	artifact, err := spec.LoadFromDirectory(".")
	require.NoError(t, err)
	require.Len(t, artifact.Commands.Install, 1)

	systemConfig := filepath.Join(t.TempDir(), "gitconfig")
	gitConfigFile(t, systemConfig, "user.signingKey", "/home/agent/.config/git/signing_key.pub")
	gitConfigFile(t, systemConfig, "core.hooksPath", "/home/agent/.config/git/hooks")

	cmd := exec.Command("sh", "-c", artifact.Commands.Install[0].Command)
	cmd.Env = append(os.Environ(), "GIT_CONFIG_SYSTEM="+systemConfig)
	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "install command failed:\n%s", output)

	require.Equal(t, "ssh", gitConfigFile(t, systemConfig, "gpg.format"))
	require.Equal(t, "true", gitConfigFile(t, systemConfig, "commit.gpgSign"))
	require.Equal(t, "true", gitConfigFile(t, systemConfig, "tag.gpgSign"))
	require.Equal(t, "/home/agent/.config/git/ssh-signing-key-command", gitConfigFile(t, systemConfig, "gpg.ssh.defaultKeyCommand"))
	require.Equal(t, "/home/agent/.config/git/allowed_signers", gitConfigFile(t, systemConfig, "gpg.ssh.allowedSignersFile"))
	require.Empty(t, gitConfigFile(t, systemConfig, "user.signingKey"))
	require.Empty(t, gitConfigFile(t, systemConfig, "core.hooksPath"))
}

func TestSigningKeyCommandPrintsInlineKeyAndAllowedSigners(t *testing.T) {
	script := writeSigningKeyCommand(t)
	key := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@example.com"
	fakeBin := writeFakeSSHAdd(t, key)
	configDir := t.TempDir()
	repoDir := t.TempDir()

	runGit(t, repoDir, "init", "-q")
	runGit(t, repoDir, "config", "user.email", "dev@example.com")

	cmd := exec.Command(script)
	cmd.Dir = repoDir
	cmd.Env = append(os.Environ(),
		"PATH="+fakeBin+string(os.PathListSeparator)+os.Getenv("PATH"),
		"SSH_AUTH_SOCK=/tmp/fake-agent.sock",
		"GIT_SSH_SIGN_CONFIG_DIR="+configDir,
	)
	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "signing key command failed:\n%s", output)

	require.Equal(t, "key::"+key+"\n", string(output))
	allowedSigners, err := os.ReadFile(filepath.Join(configDir, "allowed_signers"))
	require.NoError(t, err)
	require.Equal(t, "dev@example.com "+key+"\n", string(allowedSigners))
}

func TestSigningKeyCommandFailsWithoutAgent(t *testing.T) {
	script := writeSigningKeyCommand(t)

	cmd := exec.Command(script)
	cmd.Env = append(os.Environ(), "SSH_AUTH_SOCK=")
	output, err := cmd.CombinedOutput()
	require.Error(t, err)
	require.Contains(t, string(output), "[git-ssh-sign] no SSH agent - cannot sign commits")
}

func gitConfigFile(t *testing.T, config string, args ...string) string {
	t.Helper()

	cmd := exec.Command("git", append([]string{"config", "--file", config}, args...)...)
	output, err := cmd.CombinedOutput()
	if len(args) >= 2 {
		require.NoErrorf(t, err, "git config --file failed:\n%s", output)
		return strings.TrimSpace(string(output))
	}
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func writeSigningKeyCommand(t *testing.T) string {
	t.Helper()

	artifact, err := spec.LoadFromDirectory(".")
	require.NoError(t, err)
	require.NotNil(t, artifact.Commands)

	for _, file := range artifact.Commands.InitFiles {
		if file.Path == "/home/agent/.config/git/ssh-signing-key-command" {
			path := filepath.Join(t.TempDir(), "ssh-signing-key-command")
			require.NoError(t, os.WriteFile(path, []byte(file.Content), 0o755))
			return path
		}
	}

	t.Fatal("ssh-signing-key-command initFile not found")
	return ""
}

func writeFakeSSHAdd(t *testing.T, key string) string {
	t.Helper()

	dir := t.TempDir()
	path := filepath.Join(dir, "ssh-add")
	content := "#!/bin/sh\nif [ \"$1\" = \"-L\" ]; then\n  printf '%s\\n' " + shellQuote(key) + "\n  exit 0\nfi\nexit 1\n"
	require.NoError(t, os.WriteFile(path, []byte(content), 0o755))
	return dir
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()

	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "git %s failed:\n%s", strings.Join(args, " "), output)
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}
