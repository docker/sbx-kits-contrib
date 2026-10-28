# Oh My OpenAgent - personal agent for the OmO environment

A sandbox kit that runs the [Oh My OpenAgent](https://github.com/yokharian/oh-my-openagent) personal agent inside a Docker Sandbox. The kit builds its own sandbox image from the prebuilt oh-my-openagent agent image, then wires its credentials, network policy, and instructions.

Pairs with the oh-my-openagent agent image, built and published as `docker.io/sbx/oh-my-openagent-image:latest` by this repo's CI.

## Prerequisites

- An Anthropic API key. Create one under [Anthropic's API settings](https://console.anthropic.com/settings/keys), then store it:

  ```console
  sbx secret set anthropic
  ```

## How auth works

oh-my-openagent calls Anthropic's model API, which takes a single API key on the `x-api-key` header. The kit declares one `inject` rule for `api.anthropic.com`. The `ANTHROPIC_API_KEY` secret is proxy-managed: the sbx proxy injects the real key on the wire, so the sandbox filesystem and environment never hold it.

## Usage

```console
sbx run --kit ./oh-my-openagent
```

Or target this repo directly over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=oh-my-openagent"
```

CI publishes the kit artifact as `docker.io/sbx/oh-my-openagent-kit:latest`, consumable with:

```console
sbx run --kit "docker.io/sbx/oh-my-openagent-kit:latest"
```

## Network policy

The kit allows outbound only to:

- `api.anthropic.com` — Anthropic model API (inference)
- `registry.npmjs.org` — npm registry (runtime package installs)
- `platform.claude.com` — Anthropic OAuth token refresh

Any other host is blocked under CI's `deny-all` policy.

## Cleanup

```console
sbx secret rm -g --service anthropic
```
