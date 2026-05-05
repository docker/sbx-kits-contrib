# claude-model-runner

A mixin that points the built-in `claude` agent at a local
**[Docker Model Runner](https://docs.docker.com/ai/model-runner/)** instance
via its Anthropic-compatible endpoint. Useful for offline development,
cost-free experimentation, or testing custom local models with Claude Code.

> **Prerequisites:** Docker Model Runner must be enabled on the host with TCP
> access on port 12434, and the model you want to use must be pulled:
>
> ```console
> $ docker desktop enable model-runner --tcp
> $ docker model pull gpt-oss
> ```
>
> **Linux hosts:** `host.docker.internal` requires Docker to be started with
> `--add-host=host.docker.internal:host-gateway`. If Model Runner is
> unreachable, verify this flag is set or use your host's LAN/bridge IP in
> place of `host.docker.internal`.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-model-runner" claude ~/my-project
$ sbx run --kit ./claude-model-runner/ claude ~/my-project
```

The agent name passed to `sbx run` (`claude`) is the base agent the mixin
extends.

The default model is `gpt-oss`; Claude Code boots into it without any
`--model` argument. To switch models, save `spec.yaml` to a local
directory, change the anchored value at `&model "gpt-oss"`, and pass
`--kit` at that path:

```console
$ mkdir claude-model-runner
$ curl -o claude-model-runner/spec.yaml \
    https://raw.githubusercontent.com/docker/sbx-kits-contrib/main/claude-model-runner/spec.yaml
$ # edit `&model "gpt-oss"` in claude-model-runner/spec.yaml
$ sbx run --kit ./claude-model-runner claude ~/my-project
```

For a larger context window than the default, package a variant first:

```console
$ docker model package --from gpt-oss --context-size 32000 gpt-oss:32k
```

then point the anchored value at `gpt-oss:32k`.

## How it works

The mixin sets `ANTHROPIC_BASE_URL` to `http://host.docker.internal:12434`,
so Claude Code's Anthropic-shaped requests reach Docker Model Runner instead
of `api.anthropic.com`. It also pins every Claude Code model alias
(`ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`,
`ANTHROPIC_DEFAULT_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`) to the same
local model via a single YAML anchor, so the default Sonnet/Opus/Haiku/sub-agent
picks all land on whatever you've pulled into Model Runner.

## Related

- [Docker Model Runner](https://docs.docker.com/ai/model-runner/)
- [Run Claude Code locally with Docker Model Runner](https://www.docker.com/blog/run-claude-code-locally-docker-model-runner/), the inspiration for this kit
