package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"go.yaml.in/yaml/v3"

	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	"oras.land/oras-go/v2"
	"oras.land/oras-go/v2/content/oci"
	"oras.land/oras-go/v2/registry/remote"
	"oras.land/oras-go/v2/registry/remote/auth"
	"oras.land/oras-go/v2/registry/remote/credentials"
	"oras.land/oras-go/v2/registry/remote/retry"
)

type options struct {
	layout, command, base, platforms, descriptor string
	publish                                      references
}

type references []string

func (r *references) String() string { return strings.Join(*r, ",") }

func (r *references) Set(value string) error {
	*r = append(*r, value)
	return nil
}

type dockerRunner func(context.Context, io.Reader, ...string) error

func main() {
	var opts options
	flag.StringVar(&opts.layout, "layout", "", "Built OCI layout directory")
	flag.StringVar(&opts.command, "command", "", "Public CLI command to check")
	flag.StringVar(&opts.base, "base", "", "Workload base for a mixin; empty for a workload")
	flag.StringVar(&opts.platforms, "platforms", "linux/amd64,linux/arm64", "Platforms to check")
	flag.StringVar(&opts.descriptor, "descriptor", "", "Kit descriptor; determines whether to compose onto the base")
	flag.Var(&opts.publish, "publish", "Publish the tested layout to this tagged reference; repeat for multiple tags")
	flag.Parse()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, opts, docker, publish); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func docker(ctx context.Context, input io.Reader, args ...string) error {
	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = input, os.Stdout, os.Stderr
	return cmd.Run()
}

func run(ctx context.Context, opts options, invoke dockerRunner, push func(context.Context, string, ocispec.Descriptor, string) error) error {
	if opts.layout == "" || opts.command == "" || strings.ContainsAny(opts.command, " \t\n") {
		return errors.New("--layout and a single --command are required")
	}
	if opts.descriptor != "" {
		data, err := os.ReadFile(opts.descriptor)
		if err != nil {
			return err
		}
		var descriptor struct {
			Kind string `yaml:"kind"`
		}
		if err := yaml.Unmarshal(data, &descriptor); err != nil {
			return err
		}
		switch descriptor.Kind {
		case "workload":
			opts.base = ""
		case "mixin":
			if opts.base == "" {
				return errors.New("a mixin requires --base")
			}
		default:
			return fmt.Errorf("unsupported smoke kit kind %q", descriptor.Kind)
		}
	}
	platforms := strings.Split(opts.platforms, ",")
	seen := map[string]bool{}
	for _, platform := range platforms {
		if platform != "linux/amd64" && platform != "linux/arm64" {
			return fmt.Errorf("unsupported smoke platform %q", platform)
		}
		if seen[platform] {
			return fmt.Errorf("duplicate platform %q", platform)
		}
		seen[platform] = true
	}
	layout, err := filepath.Abs(opts.layout)
	if err != nil {
		return err
	}
	indexBytes, err := os.ReadFile(filepath.Join(layout, "index.json"))
	if err != nil {
		return err
	}
	var index ocispec.Index
	if err := json.Unmarshal(indexBytes, &index); err != nil {
		return err
	}
	if len(index.Manifests) != 1 {
		return errors.New("expected one exported image in the OCI layout")
	}
	desc := index.Manifests[0]
	if err := desc.Digest.Validate(); err != nil {
		return err
	}
	available := map[string]bool{}
	if err := collectPlatforms(layout, desc, available); err != nil {
		return err
	}
	for _, platform := range platforms {
		if !available[platform] {
			return fmt.Errorf("candidate does not contain %s", platform)
		}
	}
	for _, platform := range platforms {
		if err := check(ctx, invoke, opts, layout, desc, platform); err != nil {
			return fmt.Errorf("%s smoke check: %w", platform, err)
		}
	}
	for _, target := range opts.publish {
		if err := push(ctx, layout, desc, target); err != nil {
			return err
		}
	}
	return nil
}

func readBlob(layout string, desc ocispec.Descriptor, value any) error {
	if err := desc.Digest.Validate(); err != nil {
		return err
	}
	data, err := os.ReadFile(filepath.Join(layout, "blobs", desc.Digest.Algorithm().String(), desc.Digest.Encoded()))
	if err != nil {
		return err
	}
	if desc.Digest.Algorithm().FromBytes(data) != desc.Digest {
		return fmt.Errorf("blob digest mismatch: %s", desc.Digest)
	}
	return json.Unmarshal(data, value)
}

func collectPlatforms(layout string, desc ocispec.Descriptor, available map[string]bool) error {
	switch desc.MediaType {
	case ocispec.MediaTypeImageIndex, "application/vnd.docker.distribution.manifest.list.v2+json":
		var index ocispec.Index
		if err := readBlob(layout, desc, &index); err != nil {
			return err
		}
		for _, child := range index.Manifests {
			if err := collectPlatforms(layout, child, available); err != nil {
				return err
			}
		}
	default:
		var manifest ocispec.Manifest
		if err := readBlob(layout, desc, &manifest); err != nil {
			return err
		}
		var config ocispec.Image
		if err := readBlob(layout, manifest.Config, &config); err != nil {
			return err
		}
		available[config.OS+"/"+config.Architecture] = true
	}
	return nil
}

func check(ctx context.Context, invoke dockerRunner, opts options, layout string, desc ocispec.Descriptor, platform string) error {
	dir, err := os.MkdirTemp("", "kit-smoke-")
	if err != nil {
		return err
	}
	defer func() { _ = os.RemoveAll(dir) }()
	name := filepath.Base(dir)
	image := name + ":check"
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		_ = invoke(cleanup, nil, "rm", "-f", name)
		_ = invoke(cleanup, nil, "image", "rm", image)
	}()
	dockerfile := "FROM candidate\n"
	if opts.base != "" {
		dockerfile = "FROM workload\nCOPY --from=candidate / /\n"
	}
	args := []string{"buildx", "build", "--platform", platform, "--load", "--provenance=false", "--sbom=false", "-t", image,
		"--build-context", "candidate=oci-layout://" + layout + "@" + desc.Digest.String()}
	if opts.base != "" {
		args = append(args, "--build-context", "workload=docker-image://"+opts.base)
	}
	args = append(args, "-f", "-", dir)
	if err := invoke(ctx, strings.NewReader(dockerfile), args...); err != nil {
		return err
	}
	runtime, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	// No host credentials, mounts or network are available to the checked CLI.
	return invoke(runtime, nil, "run", "--rm", "--name", name, "--platform", platform, "--network", "none",
		"--user", "1000:1000", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
		"--entrypoint", "/bin/sh", image, "-ec", smokeScript, "kit-smoke", opts.command)
}

const smokeScript = `
command -v "$1"
if version=$("$1" --version 2>&1); then
  test -n "$version"
else
  status=$?
  printf '%s\n' "$version" >&2
  exit "$status"
fi
printf '%s\n' "$version"
if "$1" --help > /tmp/kit-smoke-help 2>&1; then
  test -s /tmp/kit-smoke-help
else
  status=$?
  cat /tmp/kit-smoke-help >&2
  exit "$status"
fi
`

func publish(ctx context.Context, layout string, desc ocispec.Descriptor, target string) error {
	repo, err := remote.NewRepository(target)
	if err != nil {
		return err
	}
	if repo.Reference.Reference == "" || strings.Contains(repo.Reference.Reference, ":") {
		return errors.New("--publish requires a tag, not a digest")
	}
	repo.PlainHTTP = loopbackRegistry(repo.Reference.Registry)
	store, err := credentials.NewStoreFromDocker(credentials.StoreOptions{})
	if err != nil {
		return err
	}
	repo.Client = &auth.Client{Client: retry.DefaultClient, Cache: auth.NewCache(), Credential: credentials.Credential(store)}
	src, err := oci.New(layout)
	if err != nil {
		return err
	}
	return copyCheckedLayout(ctx, src, desc, repo, repo.Reference.Reference)
}

func loopbackRegistry(registry string) bool {
	host, _, err := net.SplitHostPort(registry)
	if err != nil {
		host = registry
	}
	host = strings.Trim(host, "[]")
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func copyCheckedLayout(ctx context.Context, src *oci.Store, desc ocispec.Descriptor, dst oras.Target, tag string) error {
	// Copy the checked index, including its descriptor annotations and attestations.
	_, err := oras.Copy(ctx, src, desc.Digest.String(), dst, tag, oras.DefaultCopyOptions)
	return err
}
