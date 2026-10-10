import { Server } from "./runtime/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js";
import { StdioServerTransport } from "./runtime/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "./runtime/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js";

const server = new Server(
  { name: "agentmemory-sbx", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

async function callService(path, body) {
  const response = await fetch(`http://127.0.0.1:3111/agentmemory/mcp/${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`agentmemory returned HTTP ${response.status}`);
  return response.json();
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  const result = await callService("tools");
  if (!Array.isArray(result?.tools)) throw new Error("Invalid agentmemory tools response");
  return result;
});

server.setRequestHandler(CallToolRequestSchema, async request => {
  try {
    const result = await callService("call", {
      name: request.params.name,
      arguments: request.params.arguments ?? {},
    });
    if (!Array.isArray(result?.content)) throw new Error("Invalid agentmemory tool response");
    return result;
  } catch (error) {
    return {
      isError: true,
      content: [{ type: "text", text: `agentmemory service call failed: ${error.message}` }],
    };
  }
});

await server.connect(new StdioServerTransport());
