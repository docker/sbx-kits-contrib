# Kimchi

[Kimchi Coding](https://kimchi.dev) — the terminal coding agent by Cast AI, with multi-model orchestration across open-source models served by Kimchi Inference.

## Usage

```console
$ sbx run --kit docker.io/sbx/kimchi-kit:latest ./my-project
```

Or straight from this repository:

```console
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=kimchi" ./my-project
```

### Authentication

Two paths, picked automatically:

- **API key.** Store it once on the host and the sandbox receives it as
  `KIMCHI_API_KEY`:

  ```console
  $ sbx secret set kimchi
  ```

- **Interactive login.** With no credential bound, the CLI shows its login
  method selector on first run — Kimchi account via browser, or a
  subscription provider (for example GitHub Copilot). The key is saved to
  `~/.config/kimchi` inside the sandbox.

## How this kit works

- **Image** (`Dockerfile`): extends `docker.io/sbx/shell-docker-image` and runs
  the official installer
  (`github.com/getkimchi/kimchi/releases/latest/download/install.sh`) as the
  `agent` user, landing the CLI in `~/.local/bin` and its share files in
  `~/.local/share/kimchi`. The binary locates its share directory relative to
  its own path, so both stay under one prefix. The version floats with the
  latest release; the image rebuilds nightly.
- **Entrypoint** (`spec.yaml`): plain `kimchi` — the interactive harness. Pass
  a prompt through with `sbx run --kit ... -- "your task"`, or use
  `kimchi -p` inside the sandbox for non-interactive runs; `kimchi --mode acp`
  serves the Agent Client Protocol over stdio for editor integrations.
- **Credential** (`spec.yaml`): service `kimchi`, env var `KIMCHI_API_KEY`,
  injected as a `Bearer` token on requests to `llm.kimchi.dev`. Not marked
  required, because the interactive login selector is the documented
  onboarding path for users without an API key at hand.
- **Network policy**: the inference API and console host (`llm.kimchi.dev`,
  `app.kimchi.dev`), the GitHub release hosts used at install and for the
  CLI's self-update probe, and the apt sources of the base image.

## Cleanup

Nothing is written to the host. Removing the sandbox removes everything:

```console
$ sbx rm <sandbox-name>
```
