# agentmemory

Adds local persistent memory to a Docker Sandbox using [agentmemory](https://github.com/rohitg00/agentmemory), powered by [iii](https://github.com/iii-hq/iii). Claude Code and Codex receive a stdio MCP server named `agentmemory-sbx`. Other agents can use the same MCP command or the REST API.

No additional API key is required. The kit runs keyword search and explicit memory storage locally. LLM summarization, vector embeddings, and automatic capture hooks are not enabled.

## Usage

Use a current `sbx` release with schema v2 support and a Linux amd64 or arm64 base image containing Node.js 20+, npm, curl, tar, sha256sum, and flock. The standard Claude Code, Codex, and shell templates supply these tools. Authenticate your coding agent as usual; the memory service needs no credential.

After this kit is merged and published by the repository's workflow:

```console
sbx run --kit docker.io/sbx/agentmemory-kit:latest claude .
sbx run --kit docker.io/sbx/agentmemory-kit:latest codex .
```

Or load it from git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=agentmemory" claude .
```

For local development, from the repository root:

```console
sbx run --name memory-demo --kit ./agentmemory claude .
```

The published and upstream git references become available after merge. Until then, use the local path or your contribution branch's git reference.

## How it works

- Installs `@agentmemory/agentmemory@0.9.29` without optional model runtimes or package install scripts. Downloads the matching iii `0.11.2` binary and verifies its release SHA-256 checksum.
- Uses the agent CLIs to register MCP at install time. An existing `agentmemory-sbx` entry is left intact, and other MCP entries are preserved.
- Starts agentmemory on loopback port `3111`, with iii's file-backed state in `/home/agent/.local/share/agentmemory-sbx/home/.agentmemory/data`. Startup uses a lock and health check to avoid duplicate workers on repeated starts.
- Runs the memory subprocess with a private home and empty model-provider credentials. The coding agent retains its own environment and credentials.
- Uses a small stdio bridge built on `@modelcontextprotocol/sdk@1.30.1` to forward tool discovery and calls to agentmemory's REST endpoints. The upstream standalone shim can fall back to a separate local store when the service fails, even with `AGENTMEMORY_FORCE_PROXY=1`; this bridge returns an MCP error and keeps every successful save in the same service.
- Adds only npm's registry and GitHub's release download hosts to the network allow list. No host service access, model API domains, or published ports are required. The base agent's own network permissions still apply.

The memory service, stream endpoint, and viewer bind to loopback. All processes in the sandbox share access to this memory; the kit does not provide isolation between agents inside one sandbox.

For another MCP client, use:

```json
{
  "mcpServers": {
    "agentmemory-sbx": {
      "command": "sh",
      "args": ["/home/agent/.local/bin/agentmemory-sbx", "mcp"]
    }
  }
}
```

## Verify

```console
sbx kit validate ./agentmemory
./scripts/test-kit.sh agentmemory
./scripts/test-kit-e2e.sh agentmemory
sbx exec memory-demo -- sh /home/agent/.local/bin/agentmemory-sbx status
```

Ask the agent to remember a project-specific fact, allow at least five seconds for the disk write, restart the sandbox, and ask it to retrieve the fact with `memory_recall`. Check that Claude's `/mcp` or `codex mcp list` includes `agentmemory-sbx`.

For a repeatable MCP check, copy `testdata/smoke.mjs` into the sandbox and run `node smoke.mjs save <unique-marker>`. This checks the MCP response and waits for the record to appear in the on-disk store. Stop/start the sandbox and run `node smoke.mjs recall <same-marker>`. Stop the service with `sh /home/agent/.local/bin/agentmemory-sbx stop`, then run `node smoke.mjs unavailable <unique-marker>` to verify that a failed save does not fall back to temporary memory. Restart the service with `sh /home/agent/.local/share/agentmemory-sbx/start.sh`.

If startup fails, inspect `/home/agent/.local/share/agentmemory-sbx/startup.log`. Use `sbx policy log memory-demo` to find blocked install domains under a `deny-all` policy. A pre-existing `agentmemory-sbx` registration must point to this kit's launcher; remove a conflicting entry with the agent's MCP command before applying the kit.

## Persistence and cleanup

Memory is local to this sandbox and survives stop/start cycles once written to disk. The pinned iii engine flushes state every five seconds; a successful MCP save acknowledges an in-memory write, so an abrupt stop can lose recent saves. Allow at least five seconds after the last save before stopping the sandbox. The smoke check explicitly waits for the disk write before testing a restart.

Memory is not shared with the host or other sandboxes. Removing the sandbox deletes its memory. Export needed records through agentmemory before `sbx rm memory-demo`.

The kit writes under the sandbox's agent home and uses SBX's agent instructions mechanism. It does not add files to the mounted project or create a host-side daemon.
