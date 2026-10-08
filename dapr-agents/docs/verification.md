# Verification and compatibility

## Version matrix

| Item | Selection |
| --- | --- |
| Kit format | Sandbox Kit v3 workload plus `dapr-agents-mixin` overlay |
| Workload base | `dhi.io/sbx-templates:shell-docker`; the resolved base is recorded in the workload image label |
| Python / uv / Docker | Supplied by the v3 shell-docker platform base |
| Dapr CLI/runtime | `1.18.2`; both release archives are SHA-256 verified by `install.sh` on amd64 and arm64 |
| Dapr Agents | `1.0.6`; the image build asserts the descriptor version against `example/uv.lock` |
| Dapr components | `dapr.io/v1alpha1`; Conversation components use version `v1` |
| Redis | `redis:7.4.1-alpine@sha256:c1e88455c85225310bbea54816e9c3f4b5295815e6dbf80c34d40afc6df28275` |
| Placement | `daprio/placement:1.18.2@sha256:b933f3c7b66745abf2b7087ce97e6b95b0b3a990a0c665e68ce6825596c6e0ee` |
| Scheduler | `daprio/scheduler:1.18.2@sha256:a26d49a0dd622f5f55f6e7b167bf2e11231ca1f10be5ad0ba42040e460773908` |
| Adapted source | `dapr/dapr-agents` commit `98b75469f4d9b0d9a091ece90bd05f88e5b03ba8`, `quickstarts/03_durable_agent_http.py` |

## Local checks

Building is the v3 descriptor validation step:

```console
cd dapr-agents
docker buildx build . -f dapr-agents.yaml --output type=cacheonly

cd ../dapr-agents-mixin
docker buildx build . -f dapr-agents-mixin.yaml --output type=cacheonly
```

Run the Python behavior tests from the repository root:

```console
python3 -m unittest discover -s dapr-agents/tests -v
```

Verify that the workload and mixin carry identical runtime assets:

```console
diff -r dapr-agents/files dapr-agents-mixin/files
```

With a v3-capable `sbx`, inspect and run the workload, then compose and run the
mixin on the Docker-enabled shell workload:

```console
sbx kit inspect ./dapr-agents
sbx run ./dapr-agents .

sbx kit inspect ./dapr-agents-mixin
sbx run ./shell --kit ./dapr-agents-mixin .
# inside the shell sandbox:
python3 /home/agent/dapr-kit/launcher.py
```

The repository CI builds each changed kit into an OCI layout and runs the v3
conformance suite against the artifact. A real-sandbox e2e additionally runs
under a deny-all network baseline when the required repository credentials are
available.

## Runtime coverage

The launcher unit suite covers provider selection, optional model delegation,
component overlay precedence, dependency-lock compatibility, path validation,
service readiness, duplicate-launch prevention, and signal escalation. The
original workload was also exercised in a real arm64 Docker Sandbox for Dapr
startup, a live proxied OpenAI tool call, workflow recovery after application
termination, restart persistence, a custom locked project, and loopback-only
service binding.

The implementation uses the Dapr CLI with a separately checksum-verified
`daprd` binary instead of `dapr init`. That avoids installing unrelated default
components and leaves Redis, placement, and scheduler under the kit's explicit
Compose lifecycle.
