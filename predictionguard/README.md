# Prediction Guard + Docker SBX

Run autonomous agents (OpenCode, Hermes, etc.) inside the Prediction Guard Docker verified sandbox. Maintain least agency for these agents and limit the blast radius by restricting network access to an instance of the [Prediction Guard](https://predictionguard.com) control plane. 

The Prediction Guard control plane allows you to manage the supply chain on which the agents operate, scope model & tool access, and enforce agent behavioral controls. The Docker sandbox ensures that there is not a workaround to this scoping and the Prediction Guard controls. 

To spin up autonomous agents via these "two gates of defense" grab your [evaluation license for Prediction Guard](https://predictionguard.com/docker-x-prediction-guard-evaluation-license).

## How it works

Ensure "two gates of defense" for autonomous agents:

**Gate #1: Docker Sandbox (SBX)** This SBX "kit" isolates the local runtime layer. The agent harness runs inside a microVM sandbox with its own kernel, filesystem, and network stack. It is locked down to only those resources that are explicitly allowed (least agency). 

**Gate #2: Prediction Guard (PG)** This "control plane" manages and controls the supply chain of allowed resources (models and tools) and how the agent behaves as it operates on those resources. Every agent action (and traces of agent behavior over time) are analyzed in real time to enforce: (a) proper agent scoping to only certain MCP servers, tools within MCP servers, and model endpoints; (b) agent behavioral controls bound to the agent's identity protecting against risks such as memory poisoning, tool misuse, runaway token use, and privilege escalation; and (c) component input and output policies for how PII, injections, and other potentially harmful context is handled in API handshakes. 

| Gate #1: Docker Verified Prediction Guard SBX Sandbox | Gate #2: Self-hosted Prediction Guard Control Plane |
|---|---|
| MicroVM runtime isolation (own kernel, filesystem, network stack) | — |
| Default-deny egress, with only the Prediction Guard API allowed | — |
| Host credential proxy, so the Prediction Guard API keys never enters the sandbox | — |
| Filesystem isolation to the mounted workspace only | — |
| Read-only host source via clone mode | — |
| Blocks package installs and capability expansion | — |
| Org-wide filesystem/network policy sync (Docker Business) | — |
| — | Scoping of model endpoints, MCP servers, and individual tools |
| — | Agent tracing bound to unique agent identities, immutable audit logs |
| — | Component input/ output policy enforcement (for prompt injection, toxicity blocking, PII processing, etc.) |
| — | Behavioral controls tied to agent identity (privilege escalation, tool misuse, memory poisoning, runaway token use) |
| — | Agent kill switches |
| — | AIBOM export in CycloneDX format (with identified supply chain risks) |
| — | Configure human-in-the-loop approvals for tool access |
| — | AI security events with SIEM integration |

Read the full writeup on this combined solution here: [Two Gates of Defense — predictionguard.com/blog](https://predictionguard.com/blog/two-gates-of-defense-running-ai-agents-safely-with-docker-sandbox-and-prediction-guard)

Architecturally, this provides a pathway to run autonomous agents at scale without losing control. A fleet of agents operating with these two gates of defense would look like the following:

```
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ Docker SBX (Gate 1)  │  │ Docker SBX (Gate 1)  │  │ Docker SBX (Gate 1)  │
│ • egress: PG only    │  │ • egress: PG only    │  │ • egress: PG only    │
│ • creds: proxied     │  │ • creds: proxied     │  │ • creds: proxied     │
│ • fs: workspace only │  │ • fs: workspace only │  │ • fs: workspace only │
│ • no pkg installs    │  │ • no pkg installs    │  │ • no pkg installs    │
│ ┌──────────────────┐ │  │ ┌──────────────────┐ │  │ ┌──────────────────┐ │
│ │ Agent 1          │ │  │ │ Agent 2          │ │  │ │ Agent N          │ │
│ │ (OpenCode)       │ │  │ │ (Hermes)         │ │  │ │ (any harness)    │ │
│ └────────┬─────────┘ │  │ └────────┬─────────┘ │  │ └────────┬─────────┘ │
└──────────┼───────────┘  └──────────┼───────────┘  └──────────┼───────────┘
           │                         │                         │
           └─────────────────────────┼─────────────────────────┘
                                     │  (only reachable endpoint)
                                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  Self-hosted Prediction Guard control plane (Gate 2)                     │
│                                                                          │
│  • Model endpoint, MCP server & tool scoping                             │
│  • Agent tracing bound to unique agent identities                        │
│  • Immutable audit logs                                                  │
│  • Component input/output policy enforcement (prompt injection,          │
│    toxicity, PII processing, etc.)                                       │
│  • Behavioral controls tied to agent identity (privilege                 │
│    escalation, tool misuse, memory poisoning, runaway token use)         │
│  • Agent kill switches                                                   │
│  • AIBOM export in CycloneDX format (with supply chain risks)            │
│  • Human-in-the-loop approvals for tool access                           │
│  • AI security events with SIEM integration                              │
│                                                                          │
└───────┬───────────────────┬───────────────────┬───────────────────┬──────┘
        │                   │                   │                   │
        ▼                   ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Model 1      │    │ Model N      │    │ MCP server 1 │    │ MCP server N │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

## Quick start

Register your Prediction Guard API token once:

```bash
echo "$PREDICTIONGUARD_TOKEN" | sbx secret set-custom -g \
  --host pg.yourcompany.com \
  --env PREDICTIONGUARD_TOKEN \
  --placeholder sk-pg-placeholder
```

Then run:

```bash
sbx run --kit docker.io/predictionguard/sbx-predictionguard:latest predictionguard
```

Replace `pg.yourcompany.com` with your Prediction Guard deployment URL.

Need a Prediction Guard deployment? [Get your evaluation license →](https://predictionguard.com/docker-x-prediction-guard-evaluation-license)

## What this kit does for developers

- **Control plane integration:** supply chain management of an agent's underlying system, runtime controls for components of that system (e.g., models) and agents themselves, rate and token budget controls, and full observability into agent behavior and model/tool calls
- **MCP tool scoping:** control of registered MCP servers, with scoping per agent identity, logging of every tool call, built-in MCP proxy, and configurable human-in-the-loop approvals
- **Runtime controls:** standards-aligned policies for component input and output (including PII processing and redaction, prompt injection detection, and credential scrubbing among others) and agent behavior controls (for detection of memory poisoning, runaway token use, goal drift, etc.), which are applied on live agent behavior rather than after the fact
- **Compatible API surface:** OpenAI, Anthropic, MCP, and agent SDK compatible endpoints, so existing agent implementations (such as LangGraph, Pydantic AI, CrewAI, OpenCode and Claude Code) operate with zero refactoring
- **Verified provenance:** signed images, Docker Scout vulnerability scanning, and the Docker Verified Publisher badge

## Meet us at WeAreDevelopers World Congress

We will be at the Docker Pavilion, Sep 23-25, San Jose. Come see a live demo of both gates in action — Docker Sandbox + Prediction Guard running together.

[Book time with us at the conference →](https://meetings.hubspot.com/steve1863/we-are-developers-conference)

## Source

[github.com/predictionguard/docker-pg-experiment](https://github.com/predictionguard/docker-pg-experiment)
