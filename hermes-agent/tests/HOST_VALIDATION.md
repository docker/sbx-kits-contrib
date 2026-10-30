# Docker Sandboxes host validation — remaining checks before ready for review

The local Python tests exercise store reconciliation and startup credential
selection. A plain Docker Engine is insufficient to prove host OAuth injection.
Use an isolated test sandbox and an authorized test account. Never log token
values, the full auth store, process environments, or OAuth response bodies.

Current observations and limits are recorded in [HOST_RESULTS.md](HOST_RESULTS.md).
Refresh is unresolved; the PR remains draft.
For independent tasks, contribution instructions and runnable diagnostics, see
[CONTRIBUTOR_HANDOFF.md](CONTRIBUTOR_HANDOFF.md).

1. Build both kits using `scripts/test-kit.sh` and run each under the repository's
   deny-all E2E setup. Keep release pins unchanged; also repeat runtime tests
   with the Hermes v0.22.5 release separately, without mixing its upgrade diff.
2. With no OpenAI credential, confirm no managed Codex singleton appears and
   missing authentication is reported clearly. Confirm other providers work.
3. On the trusted host, run `sbx secret set openai --oauth`. Create fresh
   standalone and mixin sandboxes, approving the declared binding. Confirm the
   rendered seed and Hermes' Codex tokens contain the two declared sentinels
   by equality checks that output booleans only. Confirm no real bearer or
   refresh token is visible in sandbox files, environment or logs.
4. Open `/model` and confirm the bound Codex provider is visible without
   logging in inside Hermes. Local contract tests verify its fallback model
   choices; verify the host-backed live list separately. In v0.22.5 the
   catalog JWT-only probe gate is adapted only for the exact bound Docker
   sentinel and canonical route. The current pinned-kit backport instead
   requests client_version=99.0.0 first; confirm newer entitled models appear
   after `/model --refresh`, rather than only Astra and the 5.6 trio. Choose `openai-codex` and an account-supported model with `hermes model`.
   Exercise inference directly and through the detached gateway. Check
   `sbx policy log`: resource and token requests must use the forward proxy.
   An unsupported model should report a model error, not initiate login.
5. Exercise a residency-enforced/workspace account. The sentinels cannot provide
   `ChatGPT-Account-ID` or residency headers to Hermes. If required headers are
   missing, stop: a trusted metadata bridge or host-side header injection is
   needed, not fabricated JWT claims or copying the real JWT into the sandbox.
6. With a test grant near expiry, verify inference still works after expiry,
   gateway restart, and sandbox restart. Trigger Hermes' forced refresh
   through its resolver and assert that both resulting tokens are sentinels.
   Verify the host grant stays usable and no real response token is persisted.
7. Remove the host credential in a separate test app and verify actual catalog
   and inference access is denied. Inspect local cleanup separately: on 0.49.2,
   global secret deletion plus restart leaves the rendered seed and managed
   entries present, although catalog/inference are denied. File presence is not
   proof of current authorization. Do not delete files to make cleanup pass.
   Resolve the stale-state/mode-discriminator contract before shipping; test
   OAuth -> API key -> none transitions. Provider-side grant revocation is a
   separate test, not equivalent to deleting a local host secret.
8. Run OpenAI API-key inference at api.openai.com; repeat Anthropic API-key and
   OAuth, OpenRouter, and Copilot smoke tests. Test explicit provider/model
   choices survive restarts and credential changes.
9. Test separate Hermes profiles and independent Codex credentials. A fresh
   managed sandbox is required by the adapter; account conflicts must fail
   without modifying credentials. Verify profile fallback and pool precedence.
10. Confirm an unrelated, disallowed host fails through normal and direct paths.
    Confirm unrelated domains receive no OpenAI credential. Test a sandbox
    without the OpenAI binding separately from global credential storage scope.

The host-command enrollment UX and strict per-sandbox OAuth grants remain a
separate Docker broker/daemon feature. No in-sandbox writable host helper or
host-secret-store access is introduced by this adapter.

## Results already observed

The user confirmed newer-model inference in a fresh old-pin sandbox after the
catalog-query backport. A fresh v0.22.5 sandbox with the managed gate adapter
selected gpt-6.1-sol and returned the requested OK response. Subsequent
standalone/mixin catalog, restart, profile, policy and removal tests appear in
HOST_RESULTS.md, including failed refresh and stale local-state observations.
Gateway, natural expiry, workspace metadata and broader entitlement remain pending.

## Native-account mutation tests (offline)

`test_codex_account_conflicts.py` exercises actual Hermes login and auth-add
command/store paths against both 0.21.3 and 0.22.5 with simulated OAuth results
and socket connections forbidden. A forced native login can replace the
managed singleton; auth-add can persist an independent pool entry while
retaining it. The next bridge invocation rejects either conflict without
rewriting credentials. This guard is at startup, not at the point of login.
These tests do not validate a live second-account OAuth exchange, Docker proxy
credential/response substitution, request-account identity, failover, or refresh.
Do not use real second-account credentials in a managed sandbox as an ordinary
validation step; that needs a separately scoped host test and test accounts.
