> [!NOTE]
> <strong>Experimental: Sandbox Kit v3</strong>
>
> This kit uses the experimental [Sandbox Kit specification](https://github.com/docker/sandbox-kit-spec), specifically [v3](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md). The format and runtime behavior may change before v3 is stable.

# agentmemory

A mixin that adds local persistent memory to a sandbox with [agentmemory](https://github.com/rohitg00/agentmemory). Claude Code and Codex get a stdio MCP server named `agentmemory-sbx`. Other agents can use the same MCP command or the loopback REST API.

No API key is needed. The service does keyword search and explicit memory storage locally. LLM summarization, vector embeddings and automatic capture hooks are off.

## Usage

From the published image on Docker Hub:

```console
sbx run claude --kit docker.io/sbx/agentmemory:latest .
sbx run codex --kit docker.io/sbx/agentmemory:latest .
```

From this repository over git:

```console
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=agentmemory" .
```

From a local checkout, at the repository root:

```console
sbx run --name memory-demo claude --kit ./agentmemory .
```

The kit works on any Linux amd64 or arm64 base. It ships its own Node.js, so the base does not need one.

## How it works

- **Everything is in the overlay.** The recipe installs `@agentmemory/agentmemory@0.9.33` with npm (no optional dependencies, no install scripts), the iii engine `0.25.1` that release pins, the `state` `0.22.22` and `http` `0.22.8` workers that its Worker Compose project runs, and Node.js `24.22.2`. Every download is checked against a SHA-256 pinned in the recipe: the iii values are the ones agentmemory 0.9.33 pins, and the worker values are the ones the iii worker registry publishes. The tree lands in `/opt/agentmemory-sbx`, owned by root, with a launcher at `/usr/local/bin/agentmemory-sbx`. Nothing is written under `/home/agent` at build time.
- **No sandbox egress.** agentmemory finds the pinned iii on `PATH`, so it does not download an engine, and `AGENTMEMORY_WORKER_BIN_DIR` points Worker Compose at the bundled workers, so it does not contact the worker registry. All downloads happen when the kit is built, so the kit declares no `network-policy@1` and adds no host to the sandbox allow list. The base agent's own network policy still applies.
- **Loopback only.** The REST API listens on `127.0.0.1:3111`, the viewer on `127.0.0.1:3113` and the iii engine on `127.0.0.1:49134`. The kit publishes no port.
- **Persistent, file-backed state.** State lives in `/home/agent/.local/share/agentmemory-sbx/data` and the service runs with a private home in the same directory. The state worker writes to disk every two seconds.
- **Idempotent start.** A `startup` hook runs `/opt/agentmemory-sbx/start.sh` on every boot. It takes a lock, returns at once when `GET /agentmemory/livez` already answers, and otherwise starts the service and waits for that health check.
- **MCP registration.** A second `startup` hook registers `agentmemory-sbx` with `claude mcp add --scope user` and `codex mcp add` when those CLIs exist. An existing `agentmemory-sbx` entry is left as it is, and other MCP entries are preserved.
- **No silent fallback.** The MCP server is agentmemory's own `mcp` command with `AGENTMEMORY_FORCE_PROXY=1`. When the service is down, `tools/list` fails and every tool call returns an MCP error, so a save never lands in a temporary store.
- **No model credentials.** The launcher clears model-provider keys and provider selections in the memory process. The coding agent keeps its own environment.

All processes in the sandbox share this memory; the kit does not isolate agents inside one sandbox from each other.

For another MCP client:

```json
{
  "mcpServers": {
    "agentmemory-sbx": {
      "command": "/usr/local/bin/agentmemory-sbx",
      "args": ["mcp"]
    }
  }
}
```

## Verify

```console
cd agentmemory && docker buildx build . -f agentmemory.yaml --output type=cacheonly
sbx kit inspect ./agentmemory
sbx exec memory-demo -- agentmemory-sbx status
```

For a repeatable MCP check, copy `testdata/smoke.mjs` into the sandbox and run it with the bundled Node.js:

1. `/opt/agentmemory-sbx/node/bin/node smoke.mjs save <marker>` saves a memory and waits until it is on disk.
2. Stop and start the sandbox, then run `/opt/agentmemory-sbx/node/bin/node smoke.mjs recall <marker>`.
3. Stop the service with `agentmemory-sbx stop`, then run `/opt/agentmemory-sbx/node/bin/node smoke.mjs unavailable <marker>` to confirm that a save fails while the service is down.
4. Start it again with `sh /opt/agentmemory-sbx/start.sh`.

If startup fails, read `/home/agent/.local/share/agentmemory-sbx/startup.log`.

## Persistence and cleanup

Memory is local to the sandbox and survives stop and start once it is on disk. A successful save is acknowledged before the next two-second disk write, so wait a few seconds after the last save before stopping the sandbox.

Memory is not shared with the host or with other sandboxes. Removing the sandbox removes its memory; export what you need through agentmemory first. The kit adds nothing to the mounted project and starts nothing on the host.
