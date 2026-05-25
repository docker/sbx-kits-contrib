package packages_through_sfw_test

import (
	"testing"

	"github.com/docker/sbx-kits-contrib/spec"
	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

func TestPackagesThroughSFWTCK(t *testing.T) {
	suite, err := tck.NewSuiteFromDir(".")
	require.NoError(t, err)
	suite.RunAll(t)
}

func TestPackagesThroughSFWSpecPinsReleaseAndWrappers(t *testing.T) {
	artifact, err := spec.LoadFromDirectory(".")
	require.NoError(t, err)

	require.Equal(t, "packages-through-sfw", artifact.Manifest.Name)
	require.NotNil(t, artifact.Commands)
	require.Len(t, artifact.Commands.Install, 4)

	installSFW := artifact.Commands.Install[1].Command
	require.Contains(t, installSFW, "SFW_VERSION=1.10.0")
	require.Contains(t, installSFW, "sfw-free-linux-x86_64")
	require.Contains(t, installSFW, "1ea16f15f1217bde66ac9c7d0262c7126b7bb1b2d60e14e8fa0982456139ae6e")
	require.Contains(t, installSFW, "sfw-free-linux-arm64")
	require.Contains(t, installSFW, "d7e969c17e6d23ac1cb0dea81ff87ef9bca2d83570270d91aab14b2a7fb66ad4")

	wrapperInstall := artifact.Commands.Install[2].Command
	require.Contains(t, wrapperInstall, "mkdir -p /usr/local/lib/packages-through-sfw/shims")
	require.Contains(t, wrapperInstall, "install -m 0755 /usr/local/lib/packages-through-sfw/shims/npm /usr/local/bin/npm")
	require.Contains(t, wrapperInstall, "install -m 0755 /usr/local/lib/packages-through-sfw/shims/pip /usr/local/bin/pip")
	require.Contains(t, wrapperInstall, "install -m 0755 /usr/local/lib/packages-through-sfw/shims/pip3 /usr/local/bin/pip3")
	require.Contains(t, wrapperInstall, "install -m 0755 /usr/local/lib/packages-through-sfw/shims/python3 /usr/local/bin/python3")
	require.Contains(t, wrapperInstall, `PATH="/usr/sbin:/usr/bin:/sbin:/bin" exec /usr/local/bin/sfw npm "$@"`)
	require.Contains(t, wrapperInstall, `exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip "$@"`)
	require.Contains(t, wrapperInstall, `exec env -u PIP_CERT -u REQUESTS_CA_BUNDLE -u SSL_CERT_FILE PATH="/usr/sbin:/usr/bin:/sbin:/bin" /usr/local/bin/sfw pip3 "$@"`)
	require.Contains(t, wrapperInstall, `if [ "$1" = "-m" ] && [ "$2" = "pip" ]; then`)
	require.Contains(t, wrapperInstall, `PATH="/usr/sbin:/usr/bin:/sbin:/bin" exec python3 "$@"`)
	require.Contains(t, wrapperInstall, "/etc/profile.d/packages-through-sfw.sh")
	require.Contains(t, wrapperInstall, `npm() { /usr/local/bin/npm "$@"; }`)
	require.Contains(t, wrapperInstall, `pip() { /usr/local/bin/pip "$@"; }`)
	require.Contains(t, wrapperInstall, `pip3() { /usr/local/bin/pip3 "$@"; }`)
	require.NotContains(t, wrapperInstall, "/usr/local/lib/packages-through-sfw/real-bin")

	bashrcInstall := artifact.Commands.Install[3]
	require.Equal(t, "1000", bashrcInstall.User)
	require.Contains(t, bashrcInstall.Command, "~/.bashrc")
	require.Contains(t, bashrcInstall.Command, "[ -f /etc/profile.d/packages-through-sfw.sh ] && . /etc/profile.d/packages-through-sfw.sh")
	require.NotContains(t, bashrcInstall.Command, "/home/agent/.bashrc")
	require.NotContains(t, bashrcInstall.Command, "chown 1000:1000")
}
