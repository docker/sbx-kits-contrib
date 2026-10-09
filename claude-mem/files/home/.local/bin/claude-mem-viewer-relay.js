"use strict";

// Bridges the sandbox's published port to the loopback-bound claude-mem worker.
//
// The worker has to stay on 127.0.0.1: claude-mem reads CLAUDE_MEM_WORKER_HOST
// as *both* the address the worker binds and the address every client (the
// hooks, the mcp-search MCP server, the CLI) connects to. The runtime's
// NO_PROXY exempts loopback only (`localhost,127.0.0.1,::1,gateway.docker.internal`)
// and NODE_USE_ENV_PROXY=1 is injected, so a worker on 0.0.0.0 sends every
// client request to the egress proxy, which denies `0.0.0.0:<port>` -- and
// Node's fetch hangs on that denial rather than failing. The measured result
// is that the worker never comes up at all: claude-mem's SessionStart hook
// reports {"status":"error","message":"Failed to start worker"}.
//
// Inbound connections arriving through a published port never go near that
// proxy, so bridging them here keeps the viewer reachable from the host
// without moving the worker off loopback.

const net = require("net");

// Startup commands run with a minimal environment, so fall back to the port
// the kit pins in spec.yaml rather than trusting the variable to be present.
const WORKER_PORT = Number(process.env.CLAUDE_MEM_WORKER_PORT) || 37700;
// Kept in sync by hand with `ports:` in spec.yaml. Deliberately outside
// claude-mem's own default range (37700 + uid % 100 spans 37700-37799) so it
// cannot collide with a worker that lands on a port other than the pinned one.
const RELAY_PORT = 37800;
// `::` accepts both families (Node leaves ipv6Only off), which a published port
// needs: `sbx ports --publish <host>:37800/tcp` binds the host dual-stack and
// forwards an IPv6 connection to the sandbox's IPv6 address, so an IPv4-only
// relay resets every request a browser makes to `http://localhost:37800` --
// `localhost` resolves to `::1` first, and the host side is listening, so
// nothing falls back to IPv4. 0.0.0.0 is the fallback for an image or host
// without IPv6, where binding `::` fails outright.
const BIND_HOSTS = ["::", "0.0.0.0"];

let bindIndex = 0;

const server = net.createServer((client) => {
  const worker = net.connect(WORKER_PORT, "127.0.0.1");
  const drop = () => {
    client.destroy();
    worker.destroy();
  };
  // claude-mem spawns the worker lazily from its hooks, so a connection that
  // arrives before the worker is up simply fails: drop both ends and keep
  // serving instead of taking the relay down with it.
  client.on("error", drop);
  worker.on("error", drop);
  client.pipe(worker);
  worker.pipe(client);
});

server.on("error", (err) => {
  // startup runs on every container start; a relay from an earlier start in the
  // same container already owns the port. Exit quietly instead of crash-looping.
  if (err.code === "EADDRINUSE") {
    console.error("[claude-mem-viewer-relay] " + err.message);
    process.exit(0);
  }
  if (bindIndex < BIND_HOSTS.length - 1) {
    bindIndex += 1;
    console.error(
      "[claude-mem-viewer-relay] " + err.message + "; retrying on " + BIND_HOSTS[bindIndex]
    );
    server.listen(RELAY_PORT, BIND_HOSTS[bindIndex]);
    return;
  }
  console.error("[claude-mem-viewer-relay] " + err.message);
  process.exit(1);
});

server.listen(RELAY_PORT, BIND_HOSTS[bindIndex], () => {
  console.log(
    "[claude-mem-viewer-relay] " +
      BIND_HOSTS[bindIndex] +
      ":" +
      RELAY_PORT +
      " -> 127.0.0.1:" +
      WORKER_PORT
  );
});
