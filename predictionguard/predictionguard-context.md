# Prediction Guard

Your LLM calls are routed through a Prediction Guard control plane. This means:

- **Only `$PG_BASE_URL`** is reachable for model inference. Direct calls to
  `api.anthropic.com`, `api.openai.com` or any other provider will be blocked.
- **Your API token is never in this sandbox.** It is injected by the host proxy
  at the TLS layer; `$PREDICTIONGUARD_TOKEN` resolves to a placeholder inside
  the container.
- **All calls are governed.** Prompt injection detection, PII handling and audit
  logging apply to every request automatically.

## Connecting to Prediction Guard

```bash
# OpenAI-compatible endpoint
curl "$PG_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $PREDICTIONGUARD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"<model-id>","messages":[{"role":"user","content":"hello"}]}'

# List available models
curl "$PG_BASE_URL/v1/models" -H "Authorization: Bearer $PREDICTIONGUARD_TOKEN"
```

Check `/v1/models` first — available models differ per deployment.
