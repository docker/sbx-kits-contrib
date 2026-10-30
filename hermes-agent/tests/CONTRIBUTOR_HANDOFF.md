# Contributor handoff: Docker-managed ChatGPT OAuth

Contributions to [PR #423](https://github.com/docker/sbx-kits-contrib/pull/423)
are welcome. The PR remains draft. Maintainer edits are enabled; other
contributors can branch from its head and submit a follow-up PR to the author's
fork/branch, or share a patch linked from #423. Please coordinate the task on
the PR before duplicating work. No contributor has been assigned these tasks.

The catalog fix works in the tested standalone and mixin sandboxes. See
[HOST_RESULTS.md](HOST_RESULTS.md) for exact versions, passes, failures and
attribution limits. Check this file and the linked issues for newer results
before repeating live refresh tests.

## Get the code

From your own clone/fork of sbx-kits-contrib:

```bash
git fetch https://github.com/flushloll/sbx-kits-contrib.git \
  feat/hermes-host-managed-codex-oauth
git switch -c work/hermes-managed-oauth FETCH_HEAD
```

This does not grant push access to the author's fork. Docker maintainers can
use the PR's existing maintainer-edit permission; other contributors should
push their own branch and propose it against
`flushloll:feat/hermes-host-managed-codex-oauth`. Keep changes signed off per
the repository's DCO requirements.

## Independent tasks

### 1. Determine the supported managed-refresh contract

Related: [docker/sbx-releases#642](https://github.com/docker/sbx-releases/issues/642)
is an open report of a similar symptom, not a proven identical root cause.

- Reproduce the actual Hermes resolver refresh with a test host grant. Current
  observed result on sbx 0.49.2: HTTP 401 `invalid_client`; both form and JSON
  requests fail despite working resource access.
- Trace whether the failure comes from request interception, host refresh,
  client authentication, or another layer. Endpoint, grant and public client ID
  match expectations; auth.openai.com is allowed via `forward`.
- Establish whether supported operation relies on automatic host renewal,
  sandbox-initiated refresh, or both. Do not replace a failed refresh with a
  no-op and call renewal tested.
- Preserve masked access/refresh responses if client refresh is supported. If
  host-owned renewal is the intended contract, demonstrate resource access
  across actual host-token expiry and document the client behavior.

The built-in OpenCode control has an independent curl probe that also gets 401,
but its error category is unclassified and it does not run OpenCode's own
refresh code. The native Codex kit uses an access-placeholder provider and does
not itself exercise client refresh. These controls do not identify the cause.

Completion evidence: a documented supported contract plus live renewal and
subsequent inference, with no real tokens persisted in the sandbox. A necessary
runtime fix may belong in Docker's runtime repository rather than this kit.

### 2. Resolve configured state and credential-mode transitions

- Local host-secret removal already denies both catalog and inference access.
- The rendered seed nevertheless remains after restart. The bridge therefore
  retains configured managed auth; file presence cannot prove live authorization.
- Determine an authoritative supported discriminator or document the intended
  configured-state behavior. Test OAuth -> API key -> none and explicit model
  selection persistence. Do not infer all runtime versions report OAuth mode
  identically.
- Preserve unrelated credentials and fail on independent Codex-account conflicts.
  Never delete a Docker-owned seed merely to make a validation check pass.

Completion evidence: correct provider selection/discovery for each supported
mode, denied access after removal, and documented local-state semantics. No
automatic enrollment of new global credentials into existing sandboxes.

### 3. Finish host validation and builds

- Run standalone and mixin E2E under isolated deny-all policy, including gateway
  inference/restart with an authorized test transport.
- Cover workspace/residency accounts with an appropriate test grant; do not
  fabricate account claims from the opaque placeholder.
- Exercise other-provider/API-key smoke cases without changing their catalogs.
- Repeat the latest-release host matrix independently of the release upgrade
  [PR #422](https://github.com/docker/sbx-kits-contrib/pull/422).
- Finish the launcher follow-up's mixin build after resolving local disk limits.
  Investigate the optional scanner's blocked release-asset download before
  declaring full egress conformance; avoid broad network allowances.
- Record natural expiry and provider-side revocation separately from local
  secret deletion. The original test's rendered client expiry is November 5;
  it is not a guarantee of host JWT expiry.

Report versions/commit, actual result and limits. Do not mark unavailable-account
cases passed. Fork CI lacks the full E2E/TCK credentials; see the repository's
[PR template](../../.github/pull_request_template.md) and
[CONTRIBUTING.md](../../CONTRIBUTING.md).

## Run the diagnostics

The scripts in [host/](host/) are published diagnostic tools. The recipes do not
install them as agent commands or invoke them at startup. They print model IDs, timestamps,
booleans, statuses and fixed error categories; raw token values, error bodies
and account IDs are suppressed.

Automated suites, using Python with the selected Hermes release's dependencies:

```bash
HERMES_SOURCE=/path/to/hermes-source \
  python -m unittest discover -s hermes-agent/tests -v
python -m unittest discover -s hermes-agent/tests/host -v
```

The first suite without HERMES_SOURCE skips actual-Hermes contract cases.
Run against both supported source releases. The host-tool suite requires httpx.

On a host with `sbx`, prepare kits from committed HEAD (not uncommitted work):

```bash
validation_root=$(bash hermes-agent/tests/host/prepare-kits.sh)
sbx --app-name hermes-contrib login
sbx --app-name hermes-contrib policy init deny-all
sbx --app-name hermes-contrib secret set openai --oauth
sbx --app-name hermes-contrib run -d --name hermes-contrib-single \
  --cpus 2 --memory 2g "$validation_root/check-hermes-agent" \
  "$validation_root/workspace"
sbx --app-name hermes-contrib run -d --name hermes-contrib-mixin \
  --cpus 2 --memory 2g --kit "$validation_root/check-hermes-agent-mixin" \
  "$validation_root/check-shell" "$validation_root/workspace"
HERMES_TEST_APP=hermes-contrib bash hermes-agent/tests/host/check-host.sh \
  state hermes-contrib-single
HERMES_TEST_APP=hermes-contrib bash hermes-agent/tests/host/check-host.sh \
  catalog hermes-contrib-single
```

Use your own isolated app name of at most 20 characters. If policy already
exists, inspect it rather than resetting your normal app. Approve the binding
when prompted; if detached creation cannot prompt, create interactively first.
Repeat state/catalog for the mixin. Use authorized test grants and mount only
the test workspace. These commands enroll no credential inside Hermes.

| Tool/mode | Effect |
| --- | --- |
| check-host.sh state / unbound | Inspect named seed/auth stores and expected state; no HTTP |
| check-host.sh catalog | Request live models and refresh Hermes' model cache; no requested OAuth refresh |
| check-host.sh refresh-request | Capture the actual pure-refresh request before HTTP send; no auth-store change |
| check-host.sh refresh | One real resolver refresh; guard the response before Hermes can save tokens |
| check-host.sh refresh-form-probe / refresh-json-probe | One real refresh POST per invocation; no response persistence; fixed error classification |
| check-host.sh negative-policy | Credential-free proxy/direct requests to example.com; corroborate with host policy log |
| native-refresh-control.py | One curl form refresh in an existing built-in OpenCode sandbox; exact placeholder seed required |
| native-expiry.py | Read only OpenCode's rendered expiry timestamps; no HTTP |
| profile-check.sh setup / verify | Create two fresh profiles and save choices; verify settings and run two model calls |

Run native-control/expiry scripts with `sbx exec NAME -- python3 - < SCRIPT`.
Run profile phases with `sbx exec NAME -- sh -l -s -- setup < SCRIPT` and verify
after restart. Inference and refresh helpers perform real provider operations.
Do not loop refresh attempts or follow generic native-login recovery suggestions
in a managed sandbox. For removal tests use another isolated app so you retain
the original local test state for expiry checks. Local deletion is not
provider-side revocation; a provider may affect other grants during enrollment
or revocation, regardless of local app isolation.

## Scope boundaries

Keep real credentials host-owned, preserve the credential-injecting proxy, and
keep standalone/mixin adapters consistent. No fabricated JWTs, sandbox-writable
host secret helper/store, native-token import, or static hardcoded model additions.
Google work and release-pin changes remain separate. Multiple-account routing
is deferred; [docker/sbx-releases#144](https://github.com/docker/sbx-releases/issues/144)
is related future work, not something this single-binding PR claims to resolve.
