> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit v3 specification](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# dapr-agents-mixin

[Dapr Agents](https://docs.dapr.io/developing-ai/dapr-agents/) as a mixin: the
same Dapr runtime, launcher, local-service configuration, and six model-provider
credentials as the [`dapr-agents`](../dapr-agents) workload, packaged as an
overlay for another workload.

## Usage

Layer the published mixin onto the Docker-enabled shell workload:

```console
sbx run "docker.io/sbx/shell:latest" \
  --kit "docker.io/sbx/dapr-agents-mixin:latest" \
  --kit-arg dapr-agents-mixin.mode=custom \
  --kit-arg dapr-agents-mixin.entrypoint=agent.py \
  ~/my-dapr-agent
```

Or consume the mixin from this repository:

```console
sbx run "docker.io/sbx/shell:latest" \
  --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=dapr-agents-mixin" \
  --kit-arg dapr-agents-mixin.mode=custom \
  --kit-arg dapr-agents-mixin.entrypoint=agent.py \
  ~/my-dapr-agent
```

From a local clone:

```console
sbx run ./shell/ \
  --kit ./dapr-agents-mixin/ \
  --kit-arg dapr-agents-mixin.mode=custom \
  --kit-arg dapr-agents-mixin.entrypoint=agent.py \
  ~/my-dapr-agent
```

The base workload keeps its own entrypoint. Start Dapr Agents from the attached
shell:

```console
python3 /home/agent/dapr-kit/launcher.py
```

Set the selected provider credential before creating the sandbox. For example:

```console
sbx secret set anthropic
```

Then add `--kit-arg dapr-agents-mixin.provider=anthropic`. The supported
provider values and all other arguments match the workload README.

## What the overlay carries

- Checksum-verified Dapr CLI and `daprd` 1.18.2 binaries.
- The `uv` package manager used to create the selected project's locked Python
  environment.
- The launcher, pinned Compose services, Dapr configuration, bundled provider
  components, and locked smoke-agent project.
- Optional proxy-managed credentials and matching runtime egress for OpenAI,
  Anthropic, DeepSeek, Google AI, Hugging Face, and Mistral.
- Runtime egress for locked Python dependency resolution and the private
  engine's pinned service-image pulls.

The overlay requires the base workload to provide Python 3, Docker Engine, and
the Docker Compose plugin. These are declared as v3 `requires` entries, so
composition fails early on an incompatible base.

## What stays with the base workload

- The entrypoint, command, user, working directory, and sandbox identity.
- The private Docker Engine startup label. Use a Docker-enabled workload such
  as `shell`; a plain workload cannot run the local Dapr services.
- Resource sizing. Kit v3 has no descriptor resource field, so the runtime or
  operator owns the memory limit.

`files/` is a byte-identical copy of `../dapr-agents/files/`. Each Kit's build
context is rooted at its own directory and cannot read sibling assets, so the
workload and mixin keep their copies together and verify them with `diff -r`.
