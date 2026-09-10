# aws-strands-agent

Mixin kit that drops the [AWS Strands Agents SDK](https://strandsagents.com/) into your sandbox. Installs into a venv at `/opt/strands` so it doesn't mess with anything else in your workspace.

Model provider is Amazon Bedrock, usable in any commercial AWS region — you'll need AWS credentials and a region-appropriate inference profile (see [Region and model IDs](#region-and-model-ids)).

## Getting started

Pair it with whichever agent you prefer, from its published OCI artifact on Docker Hub:

```bash
sbx run claude --kit "docker.io/sbx/aws-strands-agent-kit:latest" ~/my-project
```

Or from a git URL targeting this repo:

```bash
sbx run claude --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=aws-strands-agent" ~/my-project
```

Inside the sandbox, export your AWS credentials and use `strands-python` to run your agent scripts:

```bash
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
strands-python my_agent.py
```

> SBX's `sbx secret set-custom` uses proxy-based injection and doesn't set environment variables — the AWS SDK needs the keys in the process environment to sign requests. Use an IAM role if you're running on AWS infrastructure.

## What's in the venv

- `strands-agents` 1.44.0
- `strands-agents-tools` 0.8.1
- `boto3`

You'll also need Bedrock model access enabled in your AWS account for whichever model you call — [here's how](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access-modify.html).

## Models and subscriptions

Anthropic (Claude) models on Bedrock are provisioned through an **AWS Marketplace subscription**, which requires a valid payment method on the account. Without one you'll get `AccessDeniedException: ... INVALID_PAYMENT_INSTRUMENT` even though signing and the model ID are correct.

Amazon's own models (the **Nova** family) don't need a Marketplace subscription, so they're the quickest way to verify the kit end-to-end:

```bash
strands-python - <<'EOF'
from strands import Agent
from strands.models import BedrockModel
agent = Agent(model=BedrockModel(model_id="apac.amazon.nova-micro-v1:0"))
print(agent("Reply with exactly three words."))
EOF
```

Swap in the inference-profile ID for your region (see below).

## Region and model IDs

The kit does not pin a region — boto3 reads `AWS_DEFAULT_REGION` from your environment (or `~/.aws/config`). Set it to wherever you have Bedrock access:

```bash
export AWS_DEFAULT_REGION=ap-southeast-1
```

Outside `us-east-1`/`us-west-2`, Bedrock requires a **cross-region inference profile ID**, not the bare model ID — on-demand invocation of the base ID returns `ValidationException`. Use the regional prefix that matches your region (`us.`, `eu.`, `apac.`, or `global.`). For Asia Pacific (e.g. `ap-southeast-1`) the prefix is **`apac.`**:

```python
from strands import Agent
from strands.models import BedrockModel

agent = Agent(model=BedrockModel(model_id="apac.anthropic.claude-sonnet-4-20250514-v1:0"))
```

Don't guess the ID — list what's actually active in your region and copy the exact `inferenceProfileId`:

```bash
strands-python - <<'EOF'
import boto3, os
c = boto3.client('bedrock', region_name=os.environ['AWS_DEFAULT_REGION'])
for p in c.list_inference_profiles()['inferenceProfileSummaries']:
    print(p['inferenceProfileId'], '-', p['status'])
EOF
```

The `permissions.network.allow` list in `spec.yaml` enumerates Bedrock runtime/control-plane and STS endpoints for all commercial regions (GovCloud/China are intentionally excluded).

## Known issue: Python 3.14 + SigV4 signing

Inference-profile model IDs contain a colon (`...-v1:0`). On Python 3.14, botocore leaves that colon unencoded in the request URL, the transport then sends `%3A` on the wire, and the SigV4 signature — computed over the raw colon — no longer matches. Every Bedrock call fails with `InvalidSignatureException`.

The kit ships a small, self-contained botocore patch (auto-loaded inside the venv via a `.pth` file) that normalizes the URL path before signing. It is gated to Python 3.14+ so it never touches the already-correct signing on ≤3.13, and is scoped to the exact `SigV4Auth` class so S3 is untouched. The install step in `spec.yaml` runs an offline guard — exercising boto3's real serializer and SigV4 signer with the network short-circuited — that asserts the signed canonical path is double-encoded, so the regression can't return silently. That guard runs on every install, including in the TCK (below).

## Using a different model

Strands supports OpenAI, Anthropic direct, Ollama, and others. Just pass a different model to `Agent()`:

```python
from strands import Agent
from strands.models.anthropic import AnthropicModel

agent = Agent(model=AnthropicModel(model_id="claude-sonnet-4-6"))
```

If you do this, you'll need to add that provider's domain to `permissions.network.allow` in `spec.yaml` (e.g. `api.anthropic.com:443`).

## Testing

Two levels, run them in order:

**1. Validate the spec**

```bash
sbx kit validate ./
```

**2. TCK (Go tests against a container)**

```bash
cd aws-strands-agent && ../scripts/test-kit.sh
```

The TCK's `post_install_checks` (see `testdata/tck.yaml`) verify the venv layout and that `strands`, `strands_tools`, and `boto3` all import cleanly; the SigV4 colon-encoding guard runs as part of `install_execution` (see above).

## Bumping versions

Change `STRANDS_VERSION` / `STRANDS_TOOLS_VERSION` in `spec.yaml`. If the new release pulls in packages that reach new hosts, update `permissions.network.allow` in the same commit — CI runs under `deny-all` so anything missing will fail.
