# OpenCode (Docker Model Runner)

This sandbox carries [OpenCode](https://github.com/sst/opencode) as a mixin,
wired to a local [Docker Model
Runner](https://docs.docker.com/ai/model-runner/) instead of a hosted provider.
The sandbox's launch command belongs to the base workload, so start the agent
yourself with `opencode`, or run one prompt with `opencode run "<prompt>"`.

Every model request goes to `http://host.docker.internal:12434/v1`, the host's
OpenAI-compatible Model Runner endpoint. No provider credential is bound and
none is needed — nothing here talks to a hosted API.

Models are discovered automatically: the `opencode-models-discovery` plugin
queries Model Runner's `/models` endpoint at startup, so anything the user has
pulled with `docker model pull` shows up under `/models` in the OpenCode UI. If
the picker is empty, Model Runner is probably not reachable — it has to be
enabled on the host with TCP access on port 12434, and at least one model has
to be pulled.
