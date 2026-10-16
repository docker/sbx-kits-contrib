# Serply (live search)

A `kind: mixin` kit that gives any Docker Sandboxes agent live search through
[Serply](https://serply.io): Google web results, Google News, and Google Scholar, as JSON over plain
HTTPS. It installs nothing and wires the API key through the sbx proxy, so the key never enters the
sandbox.

## Usage

Store a Serply API key once (get one at <https://serply.io>; new accounts include free credits):

```console
sbx secret set -g serply
```

Then layer the kit onto any agent. From the artifact published by this repo:

```console
sbx run --kit "docker.io/sbx/serply-kit:latest" claude
```

From this repo over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=serply" claude
```

From a local clone:

```console
sbx run --kit ./serply/ claude
```

On the first run sbx asks you to approve sending the `serply` credential to `api.serply.io`. Accept the
defaults; the value already lives in the secret store. The agent can then call the API with curl:

```console
curl -s -G https://api.serply.io/v1/search --data-urlencode "q=docker sandboxes kits" -d num=5
curl -s -G https://api.serply.io/v1/news --data-urlencode "q=model context protocol"
curl -s -G https://api.serply.io/v1/scholar --data-urlencode "q=retrieval augmented generation"
```

API reference: <https://serply.io/docs>.

## How the kit works

- **Install**: none. The sandbox templates already ship curl, and the API is plain HTTPS with JSON
  responses, so there is no SDK to pin and no package host to allow.
- **Credential**: one `apiKey` credential, `proxyManaged`, injected on `api.serply.io` only as the raw
  value of the `x-api-key` header (`format: "%s"`, the same shape other kits here use for raw-header API keys), which is how Serply authenticates. In-container
  `SERPLY_API_KEY` is the `proxy-managed` sentinel.
- **Network**: `api.serply.io` only. Nothing else is reachable, which the `agentInstructions` explain to
  the agent (for example, links in a result may be outside the policy, so it answers from titles and
  snippets and cites the links).
- **User-Agent**: the instructions steer the agent to curl, because the API's edge refuses Python
  urllib's default User-Agent; scripts using `requests` or `urllib` should send their own.

## Cleanup

The kit writes nothing to the host. Remove the stored key with `sbx secret rm serply` if you no longer
need it.
