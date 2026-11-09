## Serply (live search)

The sbx proxy adds your Serply API key as the `X-Api-Key` header on every
request to api.serply.io, so calls need no auth of their own. Reach for it
whenever a task needs facts beyond your knowledge cutoff, recent news, or
academic sources. Each endpoint takes the query as `q` in the query string
and returns JSON.

    # Google web results: results[] with title, link, description
    curl -s -G https://api.serply.io/v1/search --data-urlencode "q=docker sandboxes kits" -d num=5

    # Google News: entries[] with title, link, published, source
    curl -s -G https://api.serply.io/v1/news --data-urlencode "q=model context protocol"

    # Google Scholar: articles[] with title, link, author, description
    curl -s -G https://api.serply.io/v1/scholar --data-urlencode "q=retrieval augmented generation"

Useful parameters: `num` (keep it at 10 or below), `start` for the next page,
`hl` / `gl` for language and country, and `tbs=qdr:d|w|m|y` for a time filter.
Google operators such as `site:` and quoted phrases pass through inside `q`.

Constraints that come from the sandbox, not from Serply:

- This kit adds `api.serply.io` to the sandbox network policy; it does not
  open the web. A link found in a result may return a proxy 403 if its host
  is outside the policy, so answer from titles and snippets, and cite the
  links rather than claiming you read the page.
- Prefer curl. Python's urllib default User-Agent is refused by the API's
  edge; with `requests` or `urllib`, send an explicit `User-Agent` header.
- Each call spends one credit. A `401` means the key is missing or invalid;
  another error status usually means the credits are spent. Report it and stop rather
  than retrying.
