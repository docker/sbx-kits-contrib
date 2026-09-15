# google-adk

A mixin that installs [Google Agent Development Kit (ADK)](https://adk.dev/)
inside the sandbox. It creates an isolated Python virtual environment at
`/opt/google-adk`, installs the pinned `google-adk` package, and exposes the
upstream `adk` CLI plus an `adk-python` helper on `PATH`.

ADK is Google's open-source, code-first framework for building, evaluating,
and deploying agents. Use this mixin when you want to build or run ADK-based
agents from an existing sandbox agent such as `shell`, `claude`, or `codex`.

## Usage

Pair it with whichever sandbox agent you want to work from:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=google-adk" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=google-adk" ~/my-project
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
$ sbx secret set -g google-gemini "$GOOGLE_API_KEY"
```

Then run your ADK code normally. The kit asks the runtime to set
`GOOGLE_API_KEY` inside the container to a proxy-managed sentinel value; the
proxy replaces the outbound `x-goog-api-key` header before the request leaves
the sandbox.

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

The kit installs Python prerequisites from Ubuntu packages, creates
`/opt/google-adk`, and installs `google-adk==2.3.0` with pip. The package is
installed in a venv rather than into system Python so project dependencies in
the workspace do not collide with the kit.

Use `adk-python` when you want to run Python snippets against the kit-managed
environment.

## Network policy

The kit's allowlist covers the install path plus a small runtime baseline:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- `generativelanguage.googleapis.com` for Gemini Developer API calls.
- `aiplatform.googleapis.com` for Vertex AI model usage.
- `oauth2.googleapis.com`, `sts.googleapis.com`, `iamcredentials.googleapis.com`,
  and `www.googleapis.com` for common Google auth / ADC flows.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

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

When using a remote git kit, clone this repo or mount the `google-adk` directory
as the workspace if you want the smoke-test script available inside the sandbox:

```console
$ cd google-adk
$ sbx run shell --kit ./ .
```

## Bumping Google ADK

To update the kit, change `GOOGLE_ADK_VERSION` in `spec.yaml`, run the TCK,
and verify the CLI in a real sandbox:

```console
$ cd google-adk
$ ../scripts/test-kit.sh
$ sbx run shell --kit ./ .
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.

## Removing stored secrets

```console
$ sbx secret rm -g google-gemini
```
