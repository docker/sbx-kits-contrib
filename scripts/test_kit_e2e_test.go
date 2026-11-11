package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestE2EMixinWorkload(t *testing.T) {
	for _, tt := range []struct {
		name, requires, override, want string
	}{
		{"package requirements", `requires: ["deb/curl", "deb/docker-ce"]`, "", "$ROOT/scripts/testdata/e2e-workload"},
		{"named workload", `requires: ["agent"]`, "", "./agent"},
		{"explicit override", `requires: ["deb/docker-ce"]`, "dhi.io/custom:latest", "dhi.io/custom:latest"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			root := t.TempDir()
			write := func(name, content string, mode os.FileMode) {
				t.Helper()
				path := filepath.Join(root, name)
				if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(path, []byte(content), mode); err != nil {
					t.Fatal(err)
				}
			}
			for _, script := range []string{"test-kit-e2e.sh", "discover-kits.sh", "check-kit-name.sh"} {
				body, err := os.ReadFile(script)
				if err != nil {
					t.Fatal(err)
				}
				write("scripts/"+script, string(body), 0755)
			}
			write("mixin/mixin.yaml", "schemaVersion: '3'\nkind: mixin\n"+tt.requires+"\n", 0644)
			write("agent/agent.yaml", "schemaVersion: '3'\nkind: workload\nprovides: [agent]\n", 0644)
			write("claude/README.md", "This workload moved to DHI.\n", 0644)
			write("bin/sbx", "#!/bin/sh\nif [ \"$3\" = run ]; then printf '%s\\n' \"$@\" > \"$SBX_RUN_ARGS\"; fi\n", 0755)
			argsFile := filepath.Join(root, "run-args")
			cmd := exec.Command("bash", filepath.Join(root, "scripts/test-kit-e2e.sh"), "mixin")
			cmd.Dir = root
			cmd.Env = append(os.Environ(), "PATH="+filepath.Join(root, "bin")+":"+os.Getenv("PATH"), "SBX_RUN_ARGS="+argsFile, "E2E_HOST="+tt.override, "KIT_ARGS=", "KEEP_SANDBOX=", "POLICY=deny-all")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("e2e script: %v\n%s", err, out)
			}
			body, err := os.ReadFile(argsFile)
			if err != nil {
				t.Fatal(err)
			}
			args := strings.Split(strings.TrimSpace(string(body)), "\n")
			want := strings.ReplaceAll(tt.want, "$ROOT", root)
			if got := args[len(args)-2]; got != want {
				t.Fatalf("workload passed to sbx run = %q, want %q", got, want)
			}
		})
	}
}
