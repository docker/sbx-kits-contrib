## Sandbox

You are running inside a Docker sandbox (sbx). The working directory is the
user's project, mounted from the host.

MISTRAL_API_KEY holds a sentinel value, not the real key: the sandbox proxy
swaps it for the real one on requests to Mistral. Do not read, print or
reconfigure it.
