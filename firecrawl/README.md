# Firecrawl (live web access)

A `kind: mixin` kit that gives any Docker Sandboxes agent live web access through
[Firecrawl](https://www.firecrawl.dev/): search the web, scrape a page to clean markdown, crawl a site,
and reach structured third-party data through Alexandria. It installs the `firecrawl-py` SDK as the agent
user and wires the API key through the sbx proxy, so the key never enters the sandbox.

Firecrawl maintains this kit at [firecrawl/firecrawl-docker-sandbox](https://github.com/firecrawl/firecrawl-docker-sandbox),
which also publishes it as `docker.io/firecrawl/firecrawl-docker-sandbox`. The copy here tracks that
repository so the kit is discoverable alongside the other community kits.

## Usage

Store a Firecrawl API key once (get one at <https://www.firecrawl.dev/app/api-keys>):

```console
sbx secret set -g firecrawl
```

Then layer the kit onto any agent. From the artifact published by this repo:

```console
sbx run --kit "docker.io/sbx/firecrawl-kit:latest" claude
```

From this repo over git:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=firecrawl" claude
```

From a local clone:

```console
sbx run --kit ./firecrawl/ claude
```

On the first run sbx asks you to approve sending the `firecrawl` credential to `api.firecrawl.dev`. Accept
the defaults; the value already lives in the secret store. The agent can then call the SDK directly:

```python
from firecrawl import Firecrawl
fc = Firecrawl()                                          # key handled by the proxy
fc.scrape("https://example.com", formats=["markdown"])    # one page -> clean markdown
fc.search("docker sandboxes mixin kit", limit=5)          # search the web, get page content
fc.crawl("https://docs.example.com", limit=20)            # crawl a site/section
fc.search("flight prices", sources=["alexandria"])        # Alexandria (beta): discover providers/tools
```

## How the kit works

- **Install**: `pip install --user firecrawl-py==<pinned>` as user `1000`, followed by an import check, so a
  broken install fails sandbox creation instead of surfacing as a missing module mid-task. The pin lives in
  `spec.yaml` (`SDK_VERSION`).
- **Credential**: one `apiKey` credential, `proxyManaged`, injected as a bearer token on `api.firecrawl.dev`
  only. In-container `FIRECRAWL_API_KEY` is the `proxy-managed` sentinel.
- **Network**: `pypi.org` and `files.pythonhosted.org` at install time, `api.firecrawl.dev` at runtime.
  Nothing else is reachable, which the `agentInstructions` explain to the agent (for example, URLs found in
  a scrape result must be fetched through Firecrawl, not with `curl`).
- **Alexandria** is in beta and needs an API key enabled for it; on other keys the calls return an
  authorization error rather than data.

## Cleanup

The kit writes nothing to the host. Remove the stored key with `sbx secret rm firecrawl` if you no longer
need it.
