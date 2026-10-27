package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestPublishKitSmokeGate(t *testing.T) {
	for _, tc := range []struct {
		name, kit, dryRun, moveLatest, buildExit, smokeExit string
	}{
		{name: "version and latest", moveLatest: "true"},
		{name: "version only", moveLatest: "false"},
		{name: "dry run", dryRun: "1", moveLatest: "true"},
		{name: "failed build", moveLatest: "true", buildExit: "17"},
		{name: "failed smoke", moveLatest: "true", smokeExit: "23"},
		{name: "unconfigured kit", kit: "shell", dryRun: "1", moveLatest: "true"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			kit := tc.kit
			if kit == "" {
				kit = "opencode-mixin"
			}
			require.NoError(t, os.MkdirAll(filepath.Join(dir, "scripts"), 0o700))
			require.NoError(t, os.MkdirAll(filepath.Join(dir, kit), 0o700))
			for _, script := range []string{"publish-kit.sh", "kit-version.sh", "check-kit-name.sh"} {
				data, err := os.ReadFile(script)
				require.NoError(t, err)
				require.NoError(t, os.WriteFile(filepath.Join(dir, "scripts", script), data, 0o700))
			}
			require.NoError(t, os.WriteFile(filepath.Join(dir, kit, kit+".yaml"), []byte("schemaVersion: \"3\"\nkind: mixin\nversion: \"1.18.31\"\n"), 0o600))
			bin := filepath.Join(dir, "bin")
			require.NoError(t, os.Mkdir(bin, 0o700))
			require.NoError(t, os.WriteFile(filepath.Join(bin, "docker"), []byte("#!/bin/sh\nprintf 'docker %s\\n' \"$*\" >> \"$CALL_LOG\"\nexit \"${BUILD_EXIT:-0}\"\n"), 0o700))
			require.NoError(t, os.WriteFile(filepath.Join(bin, "go"), []byte("#!/bin/sh\nprintf 'go %s\\n' \"$*\" >> \"$CALL_LOG\"\nexit \"${SMOKE_EXIT:-0}\"\n"), 0o700))
			log := filepath.Join(dir, "calls")
			cmd := exec.Command("bash", filepath.Join(dir, "scripts", "publish-kit.sh"), kit)
			cmd.Env = []string{"PATH=" + bin + ":/usr/bin:/bin", "CALL_LOG=" + log,
				"DRY_RUN=" + tc.dryRun, "MOVE_LATEST=" + tc.moveLatest, "BUILD_EXIT=" + tc.buildExit, "SMOKE_EXIT=" + tc.smokeExit}
			var stdout, stderr bytes.Buffer
			cmd.Stdout, cmd.Stderr = &stdout, &stderr
			err := cmd.Run()
			if tc.buildExit != "" || tc.smokeExit != "" {
				require.Error(t, err, stderr.String())
				require.Empty(t, stdout.String())
			} else {
				require.NoError(t, err, stderr.String())
				require.Contains(t, stdout.String(), "ref=docker.io/sbx/"+kit+"\n")
			}
			data, err := os.ReadFile(log)
			require.NoError(t, err)
			calls := string(data)
			if kit == "shell" {
				require.Contains(t, calls, "--output type=cacheonly")
				require.Contains(t, calls, "-t docker.io/sbx/shell:latest")
				require.NotContains(t, calls, "go run")
				return
			}
			require.Contains(t, calls, "type=oci,")
			require.NotContains(t, calls, "--push")
			require.NotContains(t, strings.Split(calls, "\n")[0], " -t ")
			if tc.buildExit != "" {
				require.NotContains(t, calls, "go run")
				return
			}
			require.Contains(t, calls, "go run ./tools/kit-smoke")
			if tc.dryRun != "" {
				require.NotContains(t, calls, "--publish")
				require.Contains(t, stdout.String(), "pushed=false\n")
			} else {
				require.Contains(t, calls, "--publish docker.io/sbx/opencode-mixin:1.18.31")
				if tc.moveLatest == "true" {
					require.Contains(t, calls, "--publish docker.io/sbx/opencode-mixin:latest")
				} else {
					require.NotContains(t, calls, "--publish docker.io/sbx/opencode-mixin:latest")
				}
			}
		})
	}
}
