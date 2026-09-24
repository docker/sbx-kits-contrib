> NOTE — Experimental Sandbox Kit v3. This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

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
sbx run --kit "docker.io/docker/sbx-kit-claude-model-runner:latest" claude ~/my-project
```

Or from a git URL or a local clone of this repo:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=claude-model-runner" claude ~/my-project
sbx run --kit ./claude-model-runner/ claude ~/my-project
```

The agent name passed to `sbx run` (`claude`) is the base agent the mixin layers
onto — the name it declares in `requires: ["claude"]`, which either the
[`claude`](../claude) workload or [`claude-mixin`](../claude-mixin) provides.

The default model is `gpt-oss`; Claude Code boots into it without any
`--model` argument.

To switch models, set the kit's `model` arg. Under v2 the value was a YAML anchor
(`&model "gpt-oss"`, referenced four times) and switching it meant downloading
`spec.yaml`, editing the anchor and pointing `--kit` at your copy. v3 declares it
as an arg wired to the recipe's `MODEL` build arg, so the "edit one place"
property is kept and no fork is needed — one value still fans out across all four
Claude Code aliases (Opus, Sonnet, Haiku, and the sub-agent picker).

For a larger context window than the default, package a variant first:

```console
docker model package --from gpt-oss --context-size 32000 gpt-oss:32k
```

then set the kit's `model` arg to `gpt-oss:32k`.

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
