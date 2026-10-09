## Claude Code on Vertex AI

Claude Code in this sandbox talks to Claude on Google Vertex AI, not to
Anthropic's API. `CLAUDE_CODE_USE_VERTEX=1` is set, and the project and region
come from `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`.

Authentication uses the host's gcloud Application Default Credentials. The file
at `~/.config/gcloud/application_default_credentials.json` holds placeholder
tokens, not real ones, and the proxy swaps in the real values on outbound
requests. Do not try to log in here: `gcloud auth application-default login`
runs on the host.

Only `aiplatform.googleapis.com`, `oauth2.googleapis.com` and the region's
Vertex hosts are reachable. Storage, BigQuery and the rest of `googleapis.com`
are blocked.

The workspace is mounted at its absolute host path. `sudo` is passwordless; use
it for package installs.
