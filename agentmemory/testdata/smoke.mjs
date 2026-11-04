import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";
import { setTimeout as delay } from "node:timers/promises";

const [mode, marker] = process.argv.slice(2);
assert(["save", "recall", "unavailable"].includes(mode) && marker,
  "Usage: node smoke.mjs <save|recall|unavailable> <unique-marker>");

const child = spawn("sh", ["/home/agent/.local/bin/agentmemory-sbx", "mcp"], {
  stdio: ["pipe", "pipe", "inherit"],
});
const pending = new Map();
let nextId = 0;
const lines = createInterface({ input: child.stdout });
lines.on("line", line => {
  const message = JSON.parse(line);
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  clearTimeout(request.timer);
  if (message.error) request.reject(new Error(JSON.stringify(message.error)));
  else request.resolve(message.result);
});
function rejectPending(error) {
  for (const { reject, timer } of pending.values()) {
    clearTimeout(timer);
    reject(error);
  }
  pending.clear();
}
child.on("error", rejectPending);
child.on("exit", code => rejectPending(new Error(`MCP process exited: ${code}`)));

function request(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`MCP ${method} timed out`));
    }, 20_000);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

try {
  await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "agentmemory-sbx-smoke", version: "1.0.0" },
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  if (mode === "unavailable") {
    await assert.rejects(request("tools/list"), "An unavailable service must fail tools/list");
  } else {
    const { tools } = await request("tools/list");
    assert(tools.some(tool => tool.name === "memory_save"));
    assert(tools.some(tool => tool.name === "memory_recall"));
    const tables = await Promise.all(
      ["/proc/net/tcp", "/proc/net/tcp6"].map(path => readFile(path, "utf8")),
    );
    const sockets = tables.flatMap(table => table.trim().split("\n").slice(1))
      .map(line => line.trim().split(/\s+/))
      .filter(columns => columns[3] === "0A");
    for (const port of [3111, 3112, 3113, 49134]) {
      const addresses = sockets
        .filter(columns => parseInt(columns[1].split(":")[1], 16) === port)
        .map(columns => columns[1].split(":")[0]);
      assert.deepEqual(addresses, ["0100007F"], `Port ${port} must listen only on 127.0.0.1`);
    }
  }

  const result = await request("tools/call", mode === "recall" ? {
    name: "memory_recall",
    arguments: { query: marker, limit: 10 },
  } : {
    name: "memory_save",
    arguments: { content: `Sandbox persistence check: ${marker}`, type: "fact", project: "sbx-smoke" },
  });
  if (mode === "unavailable") {
    assert.equal(result.isError, true, "An unavailable service must fail the save");
  } else {
    assert(!result.isError, JSON.stringify(result));
    if (mode === "recall") assert(JSON.stringify(result).includes(marker), "Saved memory not recalled");
    else {
      const saved = JSON.parse(result.content.find(item => item.type === "text").text);
      assert.equal(saved.success, true, JSON.stringify(saved));
      const store = "/home/agent/.local/share/agentmemory-sbx/home/.agentmemory/data/state_store.db/mem%3Amemories.bin";
      const deadline = Date.now() + 15_000;
      while (true) {
        const data = await readFile(store).catch(error => {
          if (error.code === "ENOENT") return Buffer.alloc(0);
          throw error;
        });
        if (data.includes(Buffer.from(marker))) break;
        assert(Date.now() < deadline, "Saved memory did not reach the file-backed store");
        await delay(250);
      }
    }
  }
  console.log(`PASS: ${mode} (${marker})`);
} finally {
  child.stdin.end();
  child.kill();
  lines.close();
}
