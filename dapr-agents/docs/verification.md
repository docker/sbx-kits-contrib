# Verification and compatibility

## Selected versions

| Item | Selected evidence |
| --- | --- |
| Contrib checkout | `358a89d1cda7f47b37a5a4b60b2ce63be4eab818` |
| Docker Sandboxes | `v0.46.0` (`991967dc90ce0d9a440cd1df1bdf3e395c5a2693`) |
| Template | `docker/sandbox-templates:shell-docker@sha256:5fc81bc7a127e59d81b244a06831ae3212a0310b2e5a0349c54e29249e45e919`; amd64 `sha256:53b08fa716a1725f5a238b69e85f05f96956e621943d7a5c4466502321b07cfd`, arm64 `sha256:d353bf15d949bfb5a9de5338cc1285949a9e83d575c185958e449a19d9150190` |
| Python / uv | Python 3.11–3.13; uv `0.10.12` |
| Dapr CLI/runtime | `v1.18.2`; CLI and runtime archive SHA-256 values are verified in `install.sh`. Component manifests use `dapr.io/v1alpha1` and Conversation component version `v1`. |
| Dapr Agents | `dapr-agents==1.0.6`, resolved in `files/home/dapr-kit/example/uv.lock` |
| Default provider | OpenAI. With no `model` override, the pinned Dapr component defaults to `gpt-5-nano`. A live kit task and tool call passed with an explicit `gpt-4o-mini` override; the [official model page](https://developers.openai.com/api/docs/models/gpt-4o-mini) lists function calling as supported. |
| Bundled provider selection | The `provider` argument stages one `llm-provider` component for Anthropic, DeepSeek, Google AI, Hugging Face, Mistral, or OpenAI. For every provider, `model` is an optional override; when omitted, the pinned Dapr component supplies its own default. A component overlay can still replace the selected component without changing the agent. Optional proxy-managed credentials and egress are declared for all six. |
| Redis | `redis:7.4.1-alpine@sha256:c1e88455c85225310bbea54816e9c3f4b5295815e6dbf80c34d40afc6df28275` |
| Placement | `daprio/placement:1.18.2@sha256:b933f3c7b66745abf2b7087ce97e6b95b0b3a990a0c665e68ce6825596c6e0ee` |
| Scheduler | `daprio/scheduler:1.18.2@sha256:a26d49a0dd622f5f55f6e7b167bf2e11231ca1f10be5ad0ba42040e460773908` |
| Adapted source | `dapr/dapr-agents` commit `98b75469f4d9b0d9a091ece90bd05f88e5b03ba8`, `quickstarts/03_durable_agent_http.py` |
| Authoring host | macOS 15.4.1, arm64; Docker Engine 29.2.1, Compose v5.0.2; Go 1.27.1; real Docker Sandbox microVM ran |

Manifest, unit, and shared TCK evidence was refreshed on 2026-10-10. OpenAI-provider sandbox startup evidence was last collected on 2026-10-07, and live model-call evidence was last collected on 2026-10-03 with an explicit `gpt-4o-mini` override. The real key remained outside the VM; verification inspected only masked credential metadata and task behavior.

## Results

| ID | Result | Evidence / next command |
| --- | --- | --- |
| V01 Manifest validation | Passed | `sbx kit validate ./dapr-agents` and `sbx kit inspect --json ./dapr-agents`. |
| V01 Shared TCK | Passed | `GOCACHE=/tmp/dapr-agents-go-build GOPATH=/tmp/dapr-agents-go-path ./scripts/test-kit.sh dapr-agents`; all manifest, network, credential, environment, installer, file, and tmpfs checks passed. |
| V02–V04 Fresh sandbox, restricted network, readiness | Passed | The shared e2e created a fresh arm64 microVM against the isolated `sbx-kits-contrib-tck` daemon under deny-all. A full launcher run started Dapr runtime 1.18.2, Redis, placement, scheduler, all six components, and the bundled HTTP app. `openapi.json`, Dapr outbound health, metadata, and the ready message passed. The fresh policy audit reported no blocked hosts after adding the observed `releases.astral.sh` and `production.cloudfront.docker.com` destinations. |
| V05–V07 Live OpenAI provider, proxy credential, local tool | Passed | Docker Sandboxes reported the `openai` service credential as configured while exposing only masked metadata. The VM received the proxy sentinel, Dapr loaded `conversation.openai/v1`, and a live workflow with an explicit `gpt-4o-mini` override selected `sample_weather` with `{"city":"Lisbon"}`. Workflow `0b6a72e6271b47afa371da24bb1a8ec7` completed with the tool's deterministic 21°C result. The other five bundled provider selections pass manifest, unit, and shared TCK validation but have not received live provider calls. |
| V08 App crash recovery | Passed | A 30-second tool delay made the interruption deterministic. After the model committed a `sample_weather` call for Cape Town, the owned agent process was killed with SIGKILL. Dapr logged that activity `::4` had a recoverable error and would be retried. Reattaching the same sandbox retried the activity and completed the same workflow ID, `49c9fd27231b44c2bbb8fcdbb6fd6cd6`, without resubmitting the task. |
| V09 Sandbox restart persistence | Passed | After V08 completed, a full `sbx stop` and reattach restored the supporting services. Querying workflow `49c9fd27231b44c2bbb8fcdbb6fd6cd6` again returned `COMPLETED` with the original creation/update timestamps and Cape Town output. A separate Redis marker check also survived stop and reattach. |
| V10 Duplicate launch / signals | Passed | A second launcher in the real sandbox exited 2 with `another launcher is already running`. Native Ctrl-C forwarded SIGTERM once, reaped the Dapr/application process group, and exited promptly as `130/SIGINT` without a Python traceback. `sbx stop` delivered SIGTERM and Dapr logged that shutdown began before the VM stopped. |
| V11 Custom locked project | Passed | A real sandbox launched a locked project from a host path containing spaces, used `/home/agent/.local/share/dapr-kit/venvs/custom`, reached API readiness, and left no `.venv` in the mounted project. |
| V12–V13 Error paths / host boundary | Passed | Twenty-three unit tests cover provider mappings and selection, optional model delegation and overrides, overlay precedence, dependency compatibility, component versions, Dapr environment references, entrypoint-only fallback, traversal and type rejection, service readiness, shutdown escalation, path handling, and bounded recovery delay. In the real sandbox, Compose bound services only to VM loopback and `sbx ports` reported `No published ports`. |
| V14 Architecture coverage | Partially covered | The real-sandbox e2e and checksum-verified CLI/runtime smoke passed on arm64; the pinned multi-platform container images passed container checks. amd64 remains pending. |

## Deliberate deviations from the handoff

The implementation uses the Dapr CLI with a separately checksum-verified `daprd` binary instead of invoking broad `dapr init`. This avoids installing unrelated default components and lets the kit own only Redis, placement, and scheduler. The current version matrix is pinned to released package and image references. Local real-sandbox coverage is arm64; amd64 remains a CI verification item.
