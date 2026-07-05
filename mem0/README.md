# Mem0 Sandbox Kit

A Docker Sandbox mixin kit that enables secure access to a hosted Mem0 MCP server for long-term memory.

The kit configures network access, proxy-managed authentication, and agent guidance so supported AI agents can use Mem0 without exposing API keys inside the sandbox.

## Features

- Secure proxy-managed authentication using MEM0_API_KEY
- Network access restricted to mcp.mem0.ai
- Agent guidance for using persistent memory
- No secrets stored inside the sandbox

## Prerequisites

- Docker Sandboxes (sbx)
- A valid Mem0 API key

Store your API key on the host:

```bash
sbx secret set MEM0_API_KEY

```

The key remains on the host and is injected by the Docker Sandboxes proxy when requests are made to the configured Mem0 endpoint.

## Usage

Run the kit. Pass the kit's name (`mem0`) as the agent argument:

```bash
$ sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=mem0" claude
```

Run a sandbox with the kit on a local clone:

```bash
$ sbx run --kit ./mem0 claude

```

or create a sandbox:

```bash
$ sbx create --name <my-sandbox> --kit ./mem0 shell ./workspace

```

## Security

This kit uses Docker Sandboxes proxy-managed credentials.

The MEM0_API_KEY is never exposed inside the sandbox as an environment variable. Instead, Docker Sandboxes injects the required Authorization header for requests to mcp.mem0.ai.

## Network Policy

The kit only allows outbound access to:

`mcp.mem0.ai`

All other outbound domains remain subject to Docker Sandboxes network policy.

## What this kit provides

* Secure proxy-managed authentication
* Network policy allowing access only to mcp.mem0.ai
* Agent instructions for using persistent memory appropriately

This kit does not install the Mem0 Python SDK, CLI, or local OpenMemory components. It is intended for use with the hosted Mem0 MCP service.

## Validation

Verified with Docker Sandboxes v0.34.0.

Verified behavior includes:

* Kit validation (sbx kit validate)
* Kit inspection (sbx kit inspect)
* Sandbox creation with --kit
* Proxy-managed secret configuration
* Network policy enforcement
* Successful MCP initialize request to the hosted Mem0 server