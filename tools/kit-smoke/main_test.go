package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/opencontainers/go-digest"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	"github.com/stretchr/testify/require"
	"oras.land/oras-go/v2/content/oci"
)

func TestPublishRequiresEveryPlatformToPass(t *testing.T) {
	for _, failure := range []string{"", "linux/amd64", "linux/arm64"} {
		t.Run("failure="+failure, func(t *testing.T) {
			layout, desc := candidateLayout(t, "amd64", "arm64")
			var checked []string
			invoke := func(_ context.Context, input io.Reader, args ...string) error {
				if args[0] == "buildx" {
					body, err := io.ReadAll(input)
					require.NoError(t, err)
					require.Contains(t, string(body), "COPY --from=candidate / /")
					require.Contains(t, args, "candidate=oci-layout://"+layout+"@"+desc.Digest.String())
				}
				if args[0] == "run" {
					platform := args[5]
					checked = append(checked, platform)
					require.Contains(t, args, "none")
					require.Contains(t, args, "1000:1000")
					if platform == failure {
						return errors.New("CLI launcher failed")
					}
				}
				return nil
			}
			var pushed []string
			push := func(_ context.Context, _ string, got ocispec.Descriptor, target string) error {
				pushed = append(pushed, target)
				require.Equal(t, desc, got)
				require.Equal(t, []string{"linux/amd64", "linux/arm64"}, checked)
				return nil
			}
			err := run(context.Background(), options{layout: layout, command: "opencode", base: "base@sha256:123",
				platforms: "linux/amd64,linux/arm64", publish: references{"example.com/kits/opencode:1.18.31", "example.com/kits/opencode:latest"}}, invoke, push)
			if failure == "" {
				require.NoError(t, err)
				require.Equal(t, []string{"example.com/kits/opencode:1.18.31", "example.com/kits/opencode:latest"}, pushed)
			} else {
				require.ErrorContains(t, err, "CLI launcher failed")
				require.Empty(t, pushed)
			}
		})
	}
}

func candidateLayout(t *testing.T, architectures ...string) (string, ocispec.Descriptor) {
	t.Helper()
	layout := t.TempDir()
	store, err := oci.New(layout)
	require.NoError(t, err)
	push := func(mediaType string, value any) ocispec.Descriptor {
		data, err := json.Marshal(value)
		require.NoError(t, err)
		desc := ocispec.Descriptor{MediaType: mediaType, Digest: digest.FromBytes(data), Size: int64(len(data))}
		require.NoError(t, store.Push(context.Background(), desc, bytes.NewReader(data)))
		return desc
	}
	var index ocispec.Index
	index.SchemaVersion = 2
	for _, arch := range architectures {
		config := push(ocispec.MediaTypeImageConfig, ocispec.Image{Platform: ocispec.Platform{OS: "linux", Architecture: arch}})
		manifest := ocispec.Manifest{Config: config}
		manifest.SchemaVersion = 2
		index.Manifests = append(index.Manifests, push(ocispec.MediaTypeImageManifest, manifest))
	}
	desc := push(ocispec.MediaTypeImageIndex, index)
	root, err := json.Marshal(ocispec.Index{Manifests: []ocispec.Descriptor{desc}})
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(layout, "index.json"), root, 0o600))
	return layout, desc
}

func TestMissingPlatformCannotPublish(t *testing.T) {
	layout, _ := candidateLayout(t, "amd64")
	invoke := func(context.Context, io.Reader, ...string) error {
		t.Fatal("must reject a missing architecture before invoking Docker")
		return nil
	}
	push := func(context.Context, string, ocispec.Descriptor, string) error {
		t.Fatal("must not publish an incomplete candidate")
		return nil
	}
	err := run(context.Background(), options{layout: layout, command: "opencode", platforms: "linux/amd64,linux/arm64", publish: references{"example.com/agent:latest"}}, invoke, push)
	require.ErrorContains(t, err, "does not contain linux/arm64")
}

func TestDescriptorControlsComposition(t *testing.T) {
	for _, tc := range []struct{ kind, base, want string }{
		{kind: `"workload" # comment`, base: "example.com/base:latest", want: "FROM candidate\n"},
		{kind: `'mixin' # comment`, base: "example.com/base:latest", want: "FROM workload\nCOPY --from=candidate / /\n"},
	} {
		t.Run(tc.kind, func(t *testing.T) {
			layout, _ := candidateLayout(t, "amd64")
			file := filepath.Join(t.TempDir(), "kit.yaml")
			require.NoError(t, os.WriteFile(file, []byte("kind: "+tc.kind+"\n"), 0o600))
			invoke := func(_ context.Context, input io.Reader, args ...string) error {
				if args[0] == "buildx" {
					data, err := io.ReadAll(input)
					require.NoError(t, err)
					require.Equal(t, tc.want, string(data))
				}
				return nil
			}
			err := run(context.Background(), options{layout: layout, command: "tool", platforms: "linux/amd64", descriptor: file, base: tc.base}, invoke, nil)
			require.NoError(t, err)
		})
	}
}

func TestCopyPreservesCheckedManifest(t *testing.T) {
	ctx := context.Background()
	src, err := oci.New(t.TempDir())
	require.NoError(t, err)
	dst, err := oci.New(t.TempDir())
	require.NoError(t, err)
	config := []byte(`{"architecture":"arm64","os":"linux"}`)
	configDesc := ocispec.Descriptor{MediaType: ocispec.MediaTypeImageConfig, Digest: digest.FromBytes(config), Size: int64(len(config))}
	require.NoError(t, src.Push(ctx, configDesc, bytes.NewReader(config)))
	manifest := ocispec.Manifest{MediaType: ocispec.MediaTypeImageManifest, Config: configDesc,
		Annotations: map[string]string{"vnd.docker.sandbox.kit.descriptor": `{"kind":"mixin"}`}}
	manifest.SchemaVersion = 2
	data, err := json.Marshal(manifest)
	require.NoError(t, err)
	desc := ocispec.Descriptor{MediaType: ocispec.MediaTypeImageManifest, Digest: digest.FromBytes(data), Size: int64(len(data))}
	require.NoError(t, src.Push(ctx, desc, bytes.NewReader(data)))
	require.NoError(t, copyCheckedLayout(ctx, src, desc, dst, "latest"))
	got, err := dst.Resolve(ctx, "latest")
	require.NoError(t, err)
	require.Equal(t, desc.Digest, got.Digest)
	body, err := dst.Fetch(ctx, got)
	require.NoError(t, err)
	defer func() { _ = body.Close() }()
	copied, err := io.ReadAll(body)
	require.NoError(t, err)
	require.Equal(t, data, copied)
	exists, err := dst.Exists(ctx, configDesc)
	require.NoError(t, err)
	require.True(t, exists)
}

func TestPublishRequiresTaggedReference(t *testing.T) {
	for _, target := range []string{"example.com/kits/agent", "example.com/kits/agent@" + digest.FromString("candidate").String()} {
		require.ErrorContains(t, publish(context.Background(), "", ocispec.Descriptor{}, target), "requires a tag")
	}
}

func TestPlainHTTPIsLimitedToLoopback(t *testing.T) {
	for _, host := range []string{"localhost:5000", "127.0.0.1:5000", "[::1]:5000"} {
		require.True(t, loopbackRegistry(host), host)
	}
	for _, host := range []string{"registry.example.com", "registry.example.com:5000", "192.168.1.1:5000"} {
		require.False(t, loopbackRegistry(host), host)
	}
}
func TestSmokeRejectsMissingOrBrokenCLI(t *testing.T) {
	for _, tc := range []struct {
		name, body, diagnostic string
		ok                     bool
		exit                   int
	}{
		{name: "missing"},
		{name: "broken wrapper", body: "#!/bin/sh\nexec /missing/package/bin/opencode \"$@\"\n"},
		{name: "empty successful install", body: "#!/bin/sh\nexit 0\n"},
		{name: "broken help", body: "#!/bin/sh\nif [ \"$1\" = --version ]; then echo 1.18.33; else echo help-failed >&2; exit 23; fi\n", diagnostic: "help-failed", exit: 23},
		{name: "broken version", body: "#!/bin/sh\necho version-failed; exit 42\n", diagnostic: "version-failed", exit: 42},
		{name: "working", body: "#!/bin/sh\necho \"opencode $1\"\n", ok: true},
		{name: "help on stderr", body: "#!/bin/sh\necho \"opencode $1\" >&2\n[ \"$1\" != --version ] || echo 1.18.33\n", ok: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if tc.body != "" {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "smoke-fixture"), []byte(tc.body), 0o700))
			}
			// The host fixture uses a private output path; the image check uses its isolated /tmp.
			script := strings.ReplaceAll(smokeScript, "/tmp/kit-smoke-help", filepath.Join(dir, "help"))
			cmd := exec.Command("sh", "-ec", script, "smoke", "smoke-fixture")
			cmd.Env = []string{"PATH=" + dir + ":/usr/bin:/bin"}
			output, err := cmd.CombinedOutput()
			if tc.ok {
				require.NoError(t, err, string(output))
			} else {
				require.Error(t, err, string(output))
				if tc.diagnostic != "" {
					require.Contains(t, string(output), tc.diagnostic)
					var exitErr *exec.ExitError
					require.ErrorAs(t, err, &exitErr)
					require.Equal(t, tc.exit, exitErr.ExitCode())
				}
			}
		})
	}
}
