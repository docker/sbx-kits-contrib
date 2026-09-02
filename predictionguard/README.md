# Prediction Guard

Run AI coding agents (OpenCode, Hermes Agent) inside a Docker Sandbox with [Prediction Guard](https://predictionguard.com) as the model provider.

This kit enforces two gates of defense:

- **Docker Sandbox** — network isolation (only the Prediction Guard endpoint is reachable), credential proxy (API key never enters the VM), filesystem isolation via mounted workspaces
- **Prediction Guard** — prompt injection detection, toxicity blocking, PII obfuscation at the model layer

## Prerequisites

- Docker Sandbox CLI: `brew install docker/tap/sbx`
- A running Prediction Guard deployment (self-hosted or cloud)
- Your Prediction Guard API token

## Usage

Register your API token as a sandbox credential:

```bash
echo "$PREDICTIONGUARD_TOKEN" | sbx secret set-custom -g \
  --host pg.yourcompany.com \
  --env PREDICTIONGUARD_TOKEN \
  --placeholder sk-pg-placeholder
```

Run OpenCode with this kit:

```bash
sbx run --kit predictionguard --name pg-opencode opencode
```

Replace `pg.yourcompany.com` with your Prediction Guard deployment URL.

## What the kit does

- Restricts all outbound network traffic to `pg.yourcompany.com` (default deny for everything else)
- Injects `PREDICTIONGUARD_TOKEN` via the credential proxy — the real API key stays on the host and is never exposed inside the VM
- Compatible with OpenCode and any agent that reads `PREDICTIONGUARD_TOKEN` from the environment

## Reference implementation

Full setup guide, test fixtures, and blog post:
[github.com/predictionguard/docker-pg-experiment](https://github.com/predictionguard/docker-pg-experiment)
