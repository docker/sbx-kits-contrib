# smolagents

A mixin that installs [Hugging Face smolagents](https://huggingface.co/docs/smolagents/index)
inside the sandbox. It creates an isolated Python virtual environment at
`/opt/smolagents`, installs the pinned `smolagents[toolkit,vision]` package,
and exposes the upstream `smolagent` and `webagent` CLIs on `PATH`.

## Usage

Pair it with whichever sandbox agent you want to work from, from its published OCI artifact on Docker Hub:

```console
sbx run claude --kit "docker.io/docker/sbx-kit-smolagents:latest" ~/my-project
```

Or from a git URL targeting this repo:

```console
sbx run shell --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=smolagents" ~/my-project
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=smolagents" ~/my-project
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

`SMOLAGENTS_VENV` and `SMOLAGENTS_PYTHON` point at that venv. A mixin's image
config is not the composed image's, so it has no `ENV` to set — instead the
kit's overlay ships `/etc/profile.d/smolagents-env.sh`, which the base's login
shell sources, and an install hook appends the same two variables plus the
`smolagents-python` alias to the agent's `~/.bashrc` for the interactive
non-login shells `profile.d` never reaches. Both are fixed paths rather than kit
args: they name the venv the install hooks create.

## Why the venv is still installed at sandbox create

`smolagents.dockerfile` carries only that one `profile.d` file. Everything else
is still a `lifecycle@1` install hook, and the venv in particular stays one on
purpose.

A venv is not relocatable content. `python3 -m venv` writes its packages under
`lib/python3.<minor>/site-packages` and points `bin/python3` at the absolute
path `/usr/bin/python3`, so it is bound to the exact Python minor version that
created it. A mixin lands on a base the builder has never seen, and this kit's
own apt hook installs *that base's* `python3`. Baking the venv was tried and
composed onto three bases:

| composed base | `python3` | result |
| --- | --- | --- |
| `docker/sandbox-templates:shell-docker` | 3.14.4 | `smolagents 1.26.0` |
| `ubuntu:24.04` + `python3` | 3.12.3 | `ModuleNotFoundError: No module named 'smolagents'` |
| `ubuntu:24.04`, no `python3` | — | `/opt/smolagents/bin/python: not found` |

The second row is the whole argument. It fails in the worst available way, too:
apt succeeds, sandbox creation succeeds, the kit goes on advertising
`smolagents@1.26.0`, and the user's first `import smolagents` raises
`ModuleNotFoundError`. Creating the venv at sandbox-create time instead costs a
download per sandbox and keeps the kit working on any base — verified on
`ubuntu:24.04`, where the hook-created venv runs against the base's own Python
3.12.3 and reports `smolagents 1.26.0`.

Making the venv travel would mean shipping an interpreter and its standard
library as well. That is vendoring a Python distribution rather than moving an
install, and it would swap the Python-minor coupling for a glibc one.

The apt prerequisites stay hooks for the ordinary reason — packages need the
composed base's dpkg database and shared-library closure, which an overlay
cannot carry — and the `~/.bashrc` append stays one because a layer *replaces*
a file rather than merging into it, so shipping `/home/agent/.bashrc` would
shadow whatever the base workload put there.

## Network policy

The kit's allowlist is phase-scoped, and a phase that doesn't name a host cannot
reach it. The install phase is open only while the kit's install hooks run and is
closed again before the agent starts.

Install phase:

- `pypi.org` and `files.pythonhosted.org` for pip installs.
- Ubuntu and Docker apt hosts required by the base sandbox template during
  `apt-get update`.

Runtime phase:

- `huggingface.co`, `hf.co`, and `router.huggingface.co` for Hugging Face
  Hub and Inference Providers.
- DuckDuckGo hosts used by the toolkit search helper.

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

To update the kit, change `SMOLAGENTS_VERSION` in the install hook in
`smolagents.yaml` and the version in that descriptor's `provides`, then verify
the CLIs in a real sandbox:

```console
sbx run shell --kit ./smolagents/ ~/tmp-project
```

If the new release adds dependencies or changes provider hosts, update the
network allowlist in the same patch.
