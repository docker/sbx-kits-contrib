> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# google-adk

A mixin that installs [Google Agent Development Kit (ADK)](https://adk.dev/)
inside the sandbox. It creates an isolated Python virtual environment at
`/opt/google-adk`, installs the pinned `google-adk` package, and exposes the
upstream `adk` CLI plus an `adk-python` helper on `PATH`.

ADK is Google's open-source, code-first framework for building, evaluating,
and deploying agents. Use this mixin when you want to build or run ADK-based
agents from an existing sandbox agent such as `shell` or `codex`.

## Usage

Pair it with whichever sandbox agent you want to work from, from its published
OCI artifact on Docker Hub:

```console
sbx run shell --kit "docker.io/sbx/google-adk:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=google-adk" ~/my-project
sbx run codex --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=google-adk" ~/my-project
```

Or from a local checkout:

```console
sbx run shell --kit ./google-adk ~/my-project
```

Once attached, the ADK tools are available:

```console
agent@sandbox:~$ adk --help
agent@sandbox:~$ adk-python -c 'from google.adk import Agent; print(Agent)'
```

## Gemini API key setup

For Gemini Developer API usage, register your API key once with
`sbx secret set`. The sandbox proxy injects it as the `x-goog-api-key` header
for `generativelanguage.googleapis.com`, so the real key does not need to be
stored in the workspace.

```console
sbx secret set -g google "$GOOGLE_API_KEY"
```

The `google` service is the same one the other kits in this repo use for a
Gemini key, so a key you have already stored for them works here too.

Then run your ADK code normally. The kit asks the runtime to set
`GOOGLE_API_KEY` inside the container to a proxy-managed sentinel value; the
proxy replaces the outbound `x-goog-api-key` header before the request leaves
the sandbox. The credential is optional, so the kit still composes when you
use Vertex AI instead and never store a key.

## Vertex AI and ADC

The kit also allows the common Google Cloud auth hosts and
`aiplatform.googleapis.com` for users who configure Vertex AI or Application
Default Credentials. This kit does not install `gcloud` or manage ADC files;
bring those through your base sandbox, another mixin, mounted credentials, or
your own fork.

For Vertex AI, set the usual ADK / Google Cloud environment variables required
by your project, for example `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_CLOUD_PROJECT`,
and `GOOGLE_CLOUD_LOCATION`.

## What gets installed

The kit uses the workload's Python when `venv` and `ensurepip` are available.
Otherwise it installs the missing prerequisites through apt. It creates
`/opt/google-adk` and installs `google-adk==2.3.0` with pip, then checks that
the installed version matches the pin and fails sandbox creation if it does
not. The package lives in a venv rather than in system Python so project
dependencies in the workspace do not collide with the kit.

Use `adk-python` when you want to run Python snippets against the kit-managed
environment.

`GOOGLE_ADK_VENV` and `GOOGLE_ADK_PYTHON` point at that venv. A mixin's image
config is not the composed image's, so it has no `ENV` to set. Instead the
kit's overlay ships `/etc/profile.d/google-adk-env.sh`, which the base's login
shell sources, and an install hook appends the same two variables plus the
`adk-python` alias to the agent's `~/.bashrc` for interactive non-login
shells.

## Why the venv is installed at sandbox create

`google-adk.dockerfile` carries only that one `profile.d` file. The venv stays
a `lifecycle@1` install hook on purpose: `python3 -m venv` writes its packages
under `lib/python3.<minor>/site-packages` and points `bin/python3` at
`/usr/bin/python3`, so a venv is bound to the Python minor version that
created it. A mixin lands on a base the builder has never seen, so a venv baked
into the overlay would break with `ModuleNotFoundError` on any base whose
Python differs. The [`smolagents`](../smolagents) kit documents the experiment
behind this in more detail.

The apt prerequisites stay hooks because packages need the composed base's
dpkg database, and the `~/.bashrc` append stays one because an overlay file
replaces the base's `~/.bashrc` instead of adding to it.

## Network policy

The kit's allowlist is phase-scoped, and a phase that doesn't name a host
cannot reach it. The install phase is open only while the kit's install hooks
run and is closed again before the agent starts.

Install phase:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- Ubuntu, Debian, DHI, and Docker apt hosts used by supported workloads during
  `apt-get update`.

Runtime phase:

- `generativelanguage.googleapis.com` for Gemini Developer API calls.
- `aiplatform.googleapis.com` for Vertex AI model usage.
- `oauth2.googleapis.com`, `sts.googleapis.com`, `iamcredentials.googleapis.com`,
  and `www.googleapis.com` for common Google auth / ADC flows.

PyPI is not reachable at runtime. If your agent needs extra Python packages,
add them in your own fork or allow PyPI with an operator/sandbox policy rule.

ADK supports multiple models, tools, and deployment targets. If your agent calls
other providers, private MCP servers, third-party APIs, Google Cloud services,
or arbitrary websites, allow those domains explicitly in your own fork or with
an operator/sandbox policy rule. The kit does not pre-allow every possible
provider because that would hide the actual egress contract from reviewers.

## Smoke test

After creating a sandbox with this kit, run:

```console
agent@sandbox:~$ bash scripts/smoke-test.sh
```

When using a remote kit, clone this repo or mount the `google-adk` directory
as the workspace if you want the smoke-test script available inside the
sandbox:

```console
sbx run shell --kit ./google-adk ./google-adk
```

## Bumping Google ADK

To update the kit, change `GOOGLE_ADK_VERSION` in the install hook in
`google-adk.yaml` and the version in that descriptor's `provides`, then build
the kit and verify the CLI in a real sandbox:

```console
cd google-adk
docker buildx build . -f google-adk.yaml --output type=cacheonly
cd ..
sbx run shell --kit ./google-adk ~/tmp-project
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.

## Removing stored secrets

```console
sbx secret rm -g google
```
