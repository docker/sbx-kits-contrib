# supabase - Supabase CLI + data API

A mixin kit that installs the official [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), pre-wired to a Supabase project's **data API** (PostgREST, Auth, Storage) via proxy-injected credentials. The official [`supabase-py`](https://github.com/supabase/supabase-py) client is installed too.

Pairs with any base agent.

## Prerequisites

A Supabase project and its API key (anon or service_role - your choice; Supabase's docs call this family of keys "legacy API keys", but it's still the documented, working auth path at the time of writing). Find both on the project's **Settings → API** page.

## Usage

```console
sbx run --kit "docker.io/sbx/supabase-kit:latest" \
  --kit-arg supabase.project_ref=abcdefghijklmnop \
  claude
```

Or target this repo directly over git, or a local clone:

```console
sbx run --kit "git+https://github.com/docker/sbx-kits-contrib.git#dir=supabase" --kit-arg supabase.project_ref=abcdefghijklmnop claude
sbx run --kit ./supabase/ --kit-arg supabase.project_ref=abcdefghijklmnop claude
```

Left at its default, the kit still installs, but the data-API credential and egress allowlist have no real host to reach until `supabase.project_ref` is set.

## How auth works

The kit declares two **independent** credentials - set the one(s) you actually need:

**`supabase-project`** (required) - your project's own API key, for data-API access (tables, auth, storage). Produce it from the project's Settings → API page, then:

```console
sbx secret set supabase-project
```

`supabase-project` is a custom service, so the key is never exported into the container: sbx only sets a placeholder, and requests leave the sandbox carrying `apikey: <placeholder>` and `Authorization: Bearer <placeholder>`, which the proxy overwrites with your real key on the wire for `<project_ref>.supabase.co`. Both headers are injected from the one secret because different Supabase client libraries read different ones.

**`supabase-access-token`** (optional) - a personal access token from your [account's access tokens page](https://supabase.com/dashboard/account/tokens), needed only for the CLI's platform commands (`supabase link`, `supabase db push`, `supabase projects list`), which talk to the Management API rather than your project's data API:

```console
sbx secret set supabase-access-token
```

Without it, plain data-API access (the Python client, the `query.py` runbook) still works fine; only those specific CLI commands need it.

## Runbooks

`~/runbooks/query.py` runs a `SELECT * LIMIT 10` against a table, using the same proxy-injected key as the Python client:

```console
python3 ~/runbooks/query.py your_table_name
```

## Cleanup

```console
sbx secret rm -g --service supabase-project
sbx secret rm -g --service supabase-access-token
```
