# opencode-model-runner

A fork of the built-in `opencode` agent that routes all model API calls to a
local **[Docker Model Runner](https://docs.docker.com/ai/model-runner/)**
instance via its OpenAI-compatible endpoint. Useful for offline development,
cost-free experimentation, or testing custom local models with the OpenCode UI.

> **Prerequisites:** Docker Model Runner must be enabled on the host with TCP
> access on port 12434, and the model you want to use must be pulled:
>
> ```console
> $ docker desktop enable model-runner --tcp
> $ docker model pull qwen3
> ```
>
> **Linux hosts:** `host.docker.internal` requires Docker to be started with
> `--add-host=host.docker.internal:host-gateway`. If Model Runner is
> unreachable, verify this flag is set or use your host's LAN/bridge IP in
> place of `host.docker.internal`.

## Usage

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=opencode-model-runner" opencode-model-runner ~/my-project
$ sbx run --kit ./opencode-model-runner/ opencode-model-runner ~/my-project
```

The agent name passed to `sbx run` (`opencode-model-runner`) matches the
`name:` field in the kit's `spec.yaml`.

OpenCode opens already pointed at `model-runner/qwen3`. Switch any time with
`/models`.

## Switch models

Three values in `spec.yaml` reference the model tag (the key under `models`,
the display `name`, and the top-level default `model`). To use a different
model, save `spec.yaml` to a local directory, replace the three occurrences
of `qwen3` with the tag you want, and pass `--kit` at that path:

```console
$ mkdir opencode-model-runner
$ curl -o opencode-model-runner/spec.yaml \
    https://raw.githubusercontent.com/docker/sbx-kits-contrib/main/opencode-model-runner/spec.yaml
$ # edit opencode-model-runner/spec.yaml
$ sbx run --kit ./opencode-model-runner opencode-model-runner ~/my-project
```

The tag must match what `docker model ls` shows. For a larger context window
than the default, package a variant first:

```console
$ docker model package --from qwen3 --context-size 64000 qwen3:64k
```

then point `spec.yaml` at `qwen3:64k`.

## How it works

OpenCode reads its provider configuration from
`~/.config/opencode/opencode.json`. This kit uses `commands.initFiles` to drop
that JSON into the sandbox at startup, declaring a single
`@ai-sdk/openai-compatible` provider whose `baseURL` is
`http://host.docker.internal:12434/v1` (Model Runner's OpenAI-compatible
endpoint) and a top-level `model` of `model-runner/qwen3` so OpenCode boots
directly into the local model.

## Related

- [Docker Model Runner](https://docs.docker.com/ai/model-runner/)
- [OpenCode with Docker Model Runner for Private AI Coding](https://www.docker.com/blog/opencode-docker-model-runner-private-ai-coding/), the inspiration for this kit
