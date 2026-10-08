## Firecrawl (live web access)

The firecrawl-py SDK is installed and the FIRECRAWL_API_KEY credential is
injected by the sbx proxy on requests to api.firecrawl.dev. Reach for it
whenever a task needs facts beyond your knowledge cutoff, the contents of a
specific URL, or a sweep across a documentation site.

    from firecrawl import Firecrawl
    fc = Firecrawl()                                         # key handled by the proxy

    fc.scrape("https://example.com", formats=["markdown"])   # one page -> clean markdown
    fc.search("docker sandboxes mixin kit", limit=5)         # search the web, get page content
    fc.crawl("https://docs.example.com", limit=20)           # crawl a site/section

Alexandria (beta) reaches structured third-party data through the same
API host. Discover a provider or tool first, then execute it. Skip this on
an API key that has not been enabled for Alexandria; the call returns an
authorization error rather than data.

    fc.search("flight prices", sources=["alexandria"])        # discover providers/tools
    fc.find_tools(level="tools", capabilities=["search"], limit=10)   # browse the catalogue
    fc.scrape_alexandria({"provider": "<provider>", "capability": "<capability>", "options": {...}})

Constraints that come from the sandbox, not from Firecrawl:

- This kit adds `api.firecrawl.dev` to the sandbox network policy; it does
  not open the web. Hosts outside the policy return a proxy 403 to curl or
  requests, so scrape any URL you find in a result through Firecrawl instead.
  Under a deny-all policy, api.firecrawl.dev is the only web host.
- Skip `formats=["screenshot"]` and other media formats. They return links
  on Firecrawl's storage host, which is outside the allow list, so the file
  cannot be downloaded from here.
- `crawl` spends one credit per page. Prefer `search` plus a targeted
  `scrape` for a single fact, and keep `limit` low when you do crawl.
- `PaymentRequiredError` (HTTP 402) means the account is out of credits, not
  that the kit is misconfigured. Report it and stop rather than retrying.
