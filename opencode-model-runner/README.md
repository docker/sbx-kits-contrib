# opencode-model-runner

A fork of the built-in `opencode` agent that routes all model API calls to a
local **[Docker Model Runner](https://docs.docker.com/ai/model-runner/)**
instance via its OpenAI-compatible endpoint. Useful for offline development,
cost-free experimentation, or testing custom local models with the OpenCode UI.

> **Prerequisites:** Docker Model Runner must be enabled on the host with TCP
> access on port 12434, and at least one model must be pulled:
>
> ```console
> $ docker desktop enable model-runner --tcp
> $ docker model pull <model>
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

All models available via `docker model ls` are automatically discovered and
selectable in OpenCode via `/models`.

## How it works

OpenCode reads its provider configuration from
`~/.config/opencode/opencode.json`. This kit uses `commands.initFiles` to drop
that JSON into the sandbox at startup, declaring:

- An `@ai-sdk/openai-compatible` provider (`dmr`) whose `baseURL` is
  `http://host.docker.internal:12434/v1` (Model Runner's OpenAI-compatible
  endpoint), with `modelsDiscovery.enabled: true` so the provider queries
  Model Runner's `/models` endpoint at startup.
- The `opencode-models-discovery` plugin (with `smartModelName: false`) which
  surfaces the discovered models in OpenCode's model picker.

Any model pulled with `docker model pull` appears automatically — no manual
config edits needed.

## Related

- [Docker Model Runner](https://docs.docker.com/ai/model-runner/)
- [OpenCode with Docker Model Runner for Private AI Coding](https://www.docker.com/blog/opencode-docker-model-runner-private-ai-coding/), the inspiration for this kit
