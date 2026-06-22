# smolagents

A mixin that installs [Hugging Face smolagents](https://huggingface.co/docs/smolagents/index)
inside the sandbox. It creates an isolated Python virtual environment at
`/opt/smolagents`, installs the pinned `smolagents[toolkit,vision]` package,
and exposes the upstream `smolagent` and `webagent` CLIs on `PATH`.

## Usage

Pair it with whichever sandbox agent you want to work from:

```console
$ sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=smolagents" ~/my-project
$ sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=smolagents" ~/my-project
```

Once attached, the command-line tools are available:

```console
agent@sandbox:~$ smolagent --help
agent@sandbox:~$ smolagents-python -c 'from smolagents import CodeAgent, InferenceClientModel'
```

For a Hugging Face-hosted model, set `HF_TOKEN` in the sandbox or rely on
whatever credential flow your base agent provides:

```console
agent@sandbox:~$ HF_TOKEN=... smolagent "Summarize this repository" \
  --model-type InferenceClientModel \
  --model-id Qwen/Qwen3-Next-80B-A3B-Thinking
```

## What gets installed

The kit installs Python prerequisites from Ubuntu packages, creates
`/opt/smolagents`, and installs `smolagents[toolkit,vision]==1.26.0` with
pip. The `toolkit` extra matches the upstream quickstart path and provides
the default search/webpage tools used by common `smolagent` examples. The
`vision` extra brings in the upstream browser dependencies required by the
`webagent` entry point.

The package is intentionally installed in a venv rather than into system
Python so project dependencies in the workspace do not collide with the kit.
Use `smolagents-python` when you want to run Python snippets against the
kit-managed environment.

## Network policy

The kit's allowlist covers the install path plus a small runtime baseline:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- `huggingface.co`, `hf.co`, and `router.huggingface.co` for Hugging Face
  Hub and Inference Providers.
- DuckDuckGo hosts used by the toolkit search helper.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

smolagents is model-agnostic. If you point it at OpenAI, Anthropic,
OpenRouter, Bedrock, a private MCP server, or arbitrary websites through
`VisitWebpageTool`, allow those domains explicitly in your own fork or with
an operator/sandbox policy rule. The kit does not pre-allow every possible
provider because that would hide the actual egress contract from reviewers.

## Docker code execution

smolagents supports Docker-backed code execution as one of its secure
executor options, but this mixin does not mount a host Docker socket or
change sandbox privileges. If your base sandbox already has access to a
Docker daemon, install any additional Python extras you need from inside
the sandbox, or fork this kit and add `smolagents[docker]` plus the matching
daemon access policy.

## Bumping smolagents

To update the kit, change `SMOLAGENTS_VERSION` in `spec.yaml`, run the TCK,
and verify the CLIs in a real sandbox:

```console
$ cd smolagents
$ ../scripts/test-kit.sh
$ sbx run shell --kit ./ ~/tmp-project
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.
