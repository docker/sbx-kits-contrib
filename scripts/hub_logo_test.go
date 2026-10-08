package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// fakeHub stands in for hub.docker.com: the login endpoint, the media alias
// (302 to the stored asset, 404 when there is none) and the multipart upload.
type fakeHub struct {
	mu        sync.Mutex
	logos     map[string][]byte // "ns%2Fkit" -> bytes
	uploads   []string          // repos that received a POST, in order
	rejectSVG bool              // true: the server refuses image/svg+xml, to exercise the error path
	srv       *httptest.Server
}

func newFakeHub(t *testing.T) *fakeHub {
	t.Helper()
	h := &fakeHub{logos: map[string][]byte{}}
	mux := http.NewServeMux()
	mux.HandleFunc("/v2/users/login/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method", http.StatusMethodNotAllowed)
			return
		}
		fmt.Fprint(w, `{"token":"test-jwt"}`)
	})
	mux.HandleFunc("/assets/", func(w http.ResponseWriter, r *http.Request) {
		h.mu.Lock()
		defer h.mu.Unlock()
		b, ok := h.logos[strings.TrimPrefix(r.URL.EscapedPath(), "/assets/")]
		if !ok {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(b)
	})
	mux.HandleFunc("/api/media/repos_logo/v1/", func(w http.ResponseWriter, r *http.Request) {
		repo := strings.TrimPrefix(r.URL.EscapedPath(), "/api/media/repos_logo/v1/")
		switch r.Method {
		case http.MethodGet:
			h.mu.Lock()
			_, ok := h.logos[repo]
			h.mu.Unlock()
			if !ok {
				http.NotFound(w, r)
				return
			}
			http.Redirect(w, r, "/assets/"+repo, http.StatusFound)
		case http.MethodPost:
			if r.Header.Get("Authorization") != "JWT test-jwt" {
				http.Error(w, `{"message":"unauthorized"}`, http.StatusUnauthorized)
				return
			}
			// The real endpoint takes the raw image body and judges it by Content-Type.
			ct := r.Header.Get("Content-Type")
			if ct != "image/png" && (ct != "image/svg+xml" || h.rejectSVG) {
				http.Error(w, fmt.Sprintf(`{"details":{"reason":"unsupported image type: %s"},"message":"uploaded image is invalid"}`, ct), http.StatusBadRequest)
				return
			}
			b, _ := io.ReadAll(r.Body)
			h.mu.Lock()
			h.logos[repo] = b
			h.uploads = append(h.uploads, repo)
			h.mu.Unlock()
			w.WriteHeader(http.StatusOK)
			fmt.Fprint(w, `{}`)
		default:
			http.Error(w, "method", http.StatusMethodNotAllowed)
		}
	})
	h.srv = httptest.NewServer(mux)
	t.Cleanup(h.srv.Close)
	return h
}

var pngBytes = append([]byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, []byte("fake-png-body")...)

const svgBytes = `<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>`

// repoFixture lays out a repository root with the kits a test needs. A kit's
// map holds extra files; its descriptor is written for it unless provided.
func repoFixture(t *testing.T, kits map[string]map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for kit, files := range kits {
		dir := filepath.Join(root, kit)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if _, ok := files[kit+".yaml"]; !ok {
			files[kit+".yaml"] = "schemaVersion: \"3\"\nkind: mixin\n"
		}
		for name, content := range files {
			if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	return root
}

// withIcon returns a descriptor whose iconUrl points at an asset the fake hub serves.
func withIcon(hub *fakeHub, asset string) map[string]string {
	return map[string]string{"k.yaml": fmt.Sprintf("schemaVersion: \"3\"\nkind: mixin\niconUrl: %s/assets/%s\n", hub.srv.URL, asset)}
}

type result struct {
	outputs map[string]string
	stderr  string
	code    int
}

func runHubLogo(t *testing.T, hub *fakeHub, root, kit string, env ...string) result {
	t.Helper()
	script, err := filepath.Abs("hub-logo.sh")
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(script, kit)
	cmd.Env = append(os.Environ(),
		"REPO_ROOT="+root,
		"HUB_API="+hub.srv.URL,
		"IMAGE_NAMESPACE=sbx",
		"HUB_USERNAME=bot",
		"HUB_TOKEN=secret",
		"DRY_RUN=false",
		"FORCE=false",
	)
	cmd.Env = append(cmd.Env, env...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err = cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatalf("run: %v\n%s", err, stderr.String())
	}
	outs := map[string]string{}
	for _, line := range strings.Split(strings.TrimSpace(stdout.String()), "\n") {
		if k, v, ok := strings.Cut(line, "="); ok {
			outs[k] = v
		}
	}
	return result{outputs: outs, stderr: stderr.String(), code: code}
}

func TestHubLogo_UploadsAndIsIdempotent(t *testing.T) {
	hub := newFakeHub(t)
	hub.logos["src-png"] = pngBytes
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": withIcon(hub, "src-png")["k.yaml"]}})

	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "uploaded" || r.outputs["source"] != "iconUrl" {
		t.Fatalf("first run: code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
	if got := hub.logos["sbx%2Fvale"]; !bytes.Equal(got, pngBytes) {
		t.Fatalf("hub stored %q", got)
	}

	r = runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "unchanged" {
		t.Fatalf("second run: code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
	if len(hub.uploads) != 1 {
		t.Fatalf("expected exactly one upload, got %d", len(hub.uploads))
	}

	r = runHubLogo(t, hub, root, "vale", "FORCE=true")
	if r.code != 0 || r.outputs["action"] != "uploaded" || len(hub.uploads) != 2 {
		t.Fatalf("forced run: code=%d outputs=%v uploads=%d stderr=%s", r.code, r.outputs, len(hub.uploads), r.stderr)
	}
}

func TestHubLogo_ReplacesADifferentLogo(t *testing.T) {
	hub := newFakeHub(t)
	hub.logos["sbx%2Fvale"] = []byte(svgBytes)
	hub.logos["src-png"] = pngBytes
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": withIcon(hub, "src-png")["k.yaml"]}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "uploaded" {
		t.Fatalf("code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
	if !bytes.Equal(hub.logos["sbx%2Fvale"], pngBytes) {
		t.Fatal("hub logo was not replaced")
	}
}

func TestHubLogo_SVGIsAccepted(t *testing.T) {
	hub := newFakeHub(t)
	hub.logos["src-svg"] = []byte(svgBytes)
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": withIcon(hub, "src-svg")["k.yaml"]}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "uploaded" {
		t.Fatalf("code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
}

func TestHubLogo_UploadsFromIconURL(t *testing.T) {
	hub := newFakeHub(t)
	// an external image: served by the fake hub under /assets, unrelated to the repo alias
	hub.logos["external"] = pngBytes
	desc := fmt.Sprintf("schemaVersion: \"3\"\nkind: mixin\niconUrl: %s/assets/external\n", hub.srv.URL)
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": desc}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "uploaded" || r.outputs["source"] != "iconUrl" {
		t.Fatalf("code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
	if !bytes.Equal(hub.logos["sbx%2Fvale"], pngBytes) {
		t.Fatal("iconUrl bytes were not uploaded")
	}
}

func TestHubLogo_OwnHubAliasIsNotMirrored(t *testing.T) {
	hub := newFakeHub(t)
	desc := fmt.Sprintf("schemaVersion: \"3\"\nkind: mixin\niconUrl: %s/api/media/repos_logo/v1/sbx%%2Fvale\n", hub.srv.URL)
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": desc}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "skipped" || len(hub.uploads) != 0 {
		t.Fatalf("code=%d outputs=%v uploads=%d stderr=%s", r.code, r.outputs, len(hub.uploads), r.stderr)
	}
}

func TestHubLogo_NothingToSyncIsASkip(t *testing.T) {
	hub := newFakeHub(t)
	// A logo file lying in the kit directory is NOT a source: logos are not kept in this repository.
	root := repoFixture(t, map[string]map[string]string{"vale": {"logo.png": string(pngBytes)}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 0 || r.outputs["action"] != "skipped" || r.outputs["source"] != "none" {
		t.Fatalf("code=%d outputs=%v stderr=%s", r.code, r.outputs, r.stderr)
	}
}

func TestHubLogo_RefusesBadInputs(t *testing.T) {
	hub := newFakeHub(t)
	hub.logos["junk"] = []byte("this is not an image")
	hub.logos["large"] = append(append([]byte{}, pngBytes...), []byte(strings.Repeat("x", 2048))...)
	root := repoFixture(t, map[string]map[string]string{
		"junk":    {"junk.yaml": withIcon(hub, "junk")["k.yaml"]},
		"large":   {"large.yaml": withIcon(hub, "large")["k.yaml"]},
		"missing": {"missing.yaml": withIcon(hub, "no-such-asset")["k.yaml"]},
	})
	for kit, want := range map[string]string{"junk": "neither PNG nor SVG", "large": "over the", "missing": "could not download"} {
		env := []string{}
		if kit == "large" {
			env = append(env, "MAX_LOGO_BYTES=1024")
		}
		r := runHubLogo(t, hub, root, kit, env...)
		wantCode := 2
		if kit == "missing" {
			wantCode = 1 // a download failure is a transport error, not a kit error
		}
		if r.code != wantCode || !strings.Contains(r.stderr, want) {
			t.Errorf("%s: code=%d stderr=%q, want exit %d mentioning %q", kit, r.code, r.stderr, wantCode, want)
		}
	}
	if len(hub.uploads) != 0 {
		t.Fatalf("nothing should have been uploaded, got %v", hub.uploads)
	}
}

func TestHubLogo_DryRunNeverLogsInOrUploads(t *testing.T) {
	hub := newFakeHub(t)
	hub.logos["src-png"] = pngBytes
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": withIcon(hub, "src-png")["k.yaml"]}})
	r := runHubLogo(t, hub, root, "vale", "DRY_RUN=true", "HUB_USERNAME=", "HUB_TOKEN=")
	if r.code != 0 || r.outputs["action"] != "dry-run" || len(hub.uploads) != 0 {
		t.Fatalf("code=%d outputs=%v uploads=%d stderr=%s", r.code, r.outputs, len(hub.uploads), r.stderr)
	}
}

func TestHubLogo_ReportsHubUploadErrors(t *testing.T) {
	hub := newFakeHub(t)
	hub.rejectSVG = true
	hub.logos["src-svg"] = []byte(svgBytes)
	root := repoFixture(t, map[string]map[string]string{"vale": {"vale.yaml": withIcon(hub, "src-svg")["k.yaml"]}})
	r := runHubLogo(t, hub, root, "vale")
	if r.code != 1 || !strings.Contains(r.stderr, "HTTP 400") || !strings.Contains(r.stderr, "unsupported image type") {
		t.Fatalf("code=%d stderr=%q", r.code, r.stderr)
	}
	if len(hub.uploads) != 0 {
		t.Fatalf("a rejected upload must not be recorded, got %v", hub.uploads)
	}
}
