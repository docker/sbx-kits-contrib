package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// runKitDependents runs scripts/kit-dependents.sh over the fixture root and
// returns stdout, stderr and the exit code. A nil error from Run is exit 0.
func runKitDependents(t *testing.T, env []string, args ...string) (string, string, int) {
	t.Helper()
	script, err := filepath.Abs("kit-dependents.sh")
	if err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs(filepath.Join("testdata", "kit-dependents", "root"))
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(script, args...)
	cmd.Env = append(os.Environ(), "KIT_ROOT="+root, "REGISTRY=", "IMAGE_NAMESPACE=")
	cmd.Env = append(cmd.Env, env...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	code := 0
	if err := cmd.Run(); err != nil {
		ee, ok := err.(*exec.ExitError)
		if !ok {
			t.Fatalf("run %s: %v", script, err)
		}
		code = ee.ExitCode()
	}
	return stdout.String(), stderr.String(), code
}

func TestKitDependents(t *testing.T) {
	cases := []struct {
		name string
		env  []string
		base string
		want []string
	}{
		{
			// Covers: ARG with no quote, double quote and single quote,
			// an image name that ends at its closing quote (`qshell`),
			// FROM --platform, lowercase from, leading spaces, a bare
			// `sbx/shell`, a `docker.io/` prefix, a kit literally named
			// `scripts`, and a kit with recipe files for both bases. `idx`
			// is shell-docker only, `ghcr` needs REGISTRY=ghcr.io, `foons`
			// needs IMAGE_NAMESPACE=foo, and `cred`, `qcred` and `stray`
			// never match. `inline` has a `build:` block and `recipedf` a
			// quoted `dockerfile: recipe/Dockerfile` with a trailing
			// comment; `inlinecred` builds on shell-credentials in its
			// block and `nofile` names a recipe that does not exist.
			name: "shell, default registry and namespace",
			base: "shell",
			want: []string{"bare", "both", "dockio", "dq", "inline", "lead", "lower", "plainarg", "plat", "qshell", "recipedf", "scripts", "sq"},
		},
		{
			name: "shell-credentials, from an inline build block",
			base: "shell-credentials",
			want: []string{"cred", "inlinecred", "qcred"},
		},
		{
			name: "shell-docker, including index.docker.io, a closing quote and a second recipe file",
			base: "shell-docker",
			want: []string{"both", "dockerbuild", "idx", "qdock"},
		},
		{
			name: "ghcr.io registry takes only ghcr.io, not docker.io or a bare name",
			env:  []string{"REGISTRY=ghcr.io"},
			base: "shell",
			want: []string{"ghcr"},
		},
		{
			name: "ghcr.io does not accept index.docker.io or a bare name",
			env:  []string{"REGISTRY=ghcr.io"},
			base: "shell-docker",
			want: []string{},
		},
		{
			name: "index.docker.io counts as the docker.io registry",
			env:  []string{"REGISTRY=index.docker.io"},
			base: "shell-docker",
			want: []string{"both", "dockerbuild", "idx", "qdock"},
		},
		{
			name: "namespace foo",
			env:  []string{"IMAGE_NAMESPACE=foo"},
			base: "shell",
			want: []string{"foons"},
		},
		{
			name: "no kit builds on this base",
			base: "nothing",
			want: []string{},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			stdout, stderr, code := runKitDependents(t, tc.env, tc.base)
			if code != 0 {
				t.Fatalf("exit %d, stderr: %s", code, stderr)
			}
			var got []string
			if err := json.Unmarshal([]byte(stdout), &got); err != nil {
				t.Fatalf("stdout is not a JSON array: %q: %v", stdout, err)
			}
			if got == nil {
				got = []string{}
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %v, want %v", got, tc.want)
			}
		})
	}
}

// Compact output, so a workflow can embed it as-is.
func TestKitDependents_CompactOutput(t *testing.T) {
	stdout, _, _ := runKitDependents(t, nil, "nothing")
	if stdout != "[]\n" {
		t.Errorf("empty result = %q, want %q", stdout, "[]\n")
	}
	stdout, _, _ = runKitDependents(t, []string{"IMAGE_NAMESPACE=foo"}, "shell")
	if stdout != "[\"foons\"]\n" {
		t.Errorf("one result = %q", stdout)
	}
}

// A directory with a dockerfile but no <dir>/<dir>.yaml is not a kit.
func TestKitDependents_StrayDirectoryIsNeverReturned(t *testing.T) {
	stdout, _, _ := runKitDependents(t, nil, "shell")
	var got []string
	if err := json.Unmarshal([]byte(stdout), &got); err != nil {
		t.Fatal(err)
	}
	for _, k := range got {
		if k == "stray" {
			t.Errorf("stray directory returned: %v", got)
		}
	}
}

// A `dockerfile:` naming a missing file (the `nofile` fixture) is the
// frontend's error to report, so the script stays silent about it.
func TestKitDependents_MissingRecipeIsSilent(t *testing.T) {
	for _, base := range []string{"shell", "shell-docker", "shell-credentials"} {
		stdout, stderr, code := runKitDependents(t, nil, base)
		if code != 0 {
			t.Errorf("%s: exit %d, stderr: %s", base, code, stderr)
		}
		if stderr != "" {
			t.Errorf("%s: stderr = %q, want empty", base, stderr)
		}
		if strings.Contains(stdout, "nofile") {
			t.Errorf("%s: nofile returned: %s", base, stdout)
		}
	}
}

func TestKitDependents_UsageErrors(t *testing.T) {
	for name, args := range map[string][]string{
		"no argument":    {},
		"two arguments":  {"shell", "shell-docker"},
		"empty argument": {""},
	} {
		t.Run(name, func(t *testing.T) {
			stdout, stderr, code := runKitDependents(t, nil, args...)
			if code != 2 {
				t.Errorf("exit %d, want 2", code)
			}
			if stdout != "" {
				t.Errorf("stdout = %q, want empty", stdout)
			}
			if stderr == "" {
				t.Error("no usage message on stderr")
			}
		})
	}
}

// A reserved kit name makes discovery refuse the whole listing, and the script
// must pass that on: exit 1, the reason on stderr, nothing on stdout.
func TestKitDependents_DiscoveryFailureIsExit1(t *testing.T) {
	root := t.TempDir()
	for _, kit := range []string{"ok", "foo-kit"} {
		dir := filepath.Join(root, kit)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, kit+".yaml"), []byte("# syntax=docker/sandbox-kit:3\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, kit+".dockerfile"), []byte("FROM sbx/shell\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	stdout, stderr, code := runKitDependents(t, []string{"KIT_ROOT=" + root}, "shell")
	if code != 1 {
		t.Errorf("exit %d, want 1", code)
	}
	if stdout != "" {
		t.Errorf("stdout = %q, want empty", stdout)
	}
	if !strings.Contains(stderr, "foo-kit") {
		t.Errorf("stderr does not name the refused kit: %q", stderr)
	}
}
