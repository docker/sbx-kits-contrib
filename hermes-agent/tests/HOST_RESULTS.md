# Host validation checkpoint — 2026-10-26

PR remains draft. Catalog discovery and several lifecycle properties pass;
refresh and the remaining account/runtime matrix are unresolved.

## Scope

User-run macOS tests used Docker Sandboxes 0.49.2. Standalone and shell+mixin kits
were exported from `1bf4322ddc8c`, excluding uncommitted Google work. Only kit
directory/descriptor/recipe filenames were renamed. Both retain Hermes 0.21.3.
Separate app namespaces isolated normal tests from credential-removal tests.

The subsequent interpreter-launcher fix, `774ba1acc709`, passes the actual recipe
launcher test for both kits. Its exact committed suite passes against 0.21.3
(29 passed, one version skip) and 0.22.5 (24 passed, six legacy skips).
Standalone build-to-cache passes; the latest mixin rebuild ran out of Docker
disk during upstream installation, before the launcher step. Prior mixin builds
and original host composition passed. Existing host sandboxes used a diagnostic
workaround for the old interpreter symlink, not a rebuild.

## Observed passes

| Check | Observation | Limit |
| --- | --- | --- |
| Unbound baseline | No Codex credentials in inspected stores | Interactive missing-auth UX not established |
| Bound standalone/mixin | Exact rendered/Hermes placeholder pairs; 0600 auth store | Named stores, not every file/environment/log |
| Live catalog/picker | Eight live model IDs all in refreshed picker; twelve IDs with existing context variants | One account; not inference entitlement to every model |
| Inference/restart | Both kits return OK with gpt-6.1-sol before and after stop/start | Not natural expiry or gateway restart |
| Named profiles | Saved gpt-6.1-sol and gpt-6-sol choices survive restart; both return OK; default selection unchanged during setup | Same managed-account fallback, not multiple host-managed accounts |
| No automatic enrollment | Original unbound sandbox stays unbound after global OAuth enrollment | This configuration only |
| Negative network policy | Standalone example.com proxy request denied; direct failure corroborated by host DNS-policy denials | Not arbitrary IP/protocol coverage or universal credential non-disclosure |
| Local secret removal | Both kits get HTTP 401 on catalog and inference after deleting the removal app's global OAuth secret and restarting; no model answer | Local removal, not provider-side grant revocation |

Live IDs: gpt-5.6-luna, gpt-5.6-sol, gpt-5.6-terra, gpt-6-astra, gpt-6-luna,
gpt-6-sol, gpt-6.1-sol, gpt-6.1-terra. These are observed results, not a new
static catalog in the kit.

## Refresh failure

Forced refresh returned HTTP 401 while ordinary catalog/inference worked.
Separate form and JSON probes both returned `invalid_client`. The public client
ID matched the host authorization URL; Hermes used the expected endpoint,
grant and managed refresh placeholder. Host policy showed auth.openai.com allowed
via `forward`. Guarded probes persisted no response and left auth.json unchanged.

An independent curl form probe in a fresh built-in OpenCode sandbox, using the
same host credential and verified native placeholders, also returned HTTP 401
through allowed `forward` routing. Its OAuth error category was unclassified.
This reproduces an endpoint failure outside Hermes, not necessarily the same
cause, and does not exercise OpenCode's own refresh implementation.

Related report: [docker/sbx-releases#642](https://github.com/docker/sbx-releases/issues/642).
The exact failing operation remains unidentified. Do not claim successful renewal
or an encoding fix. The native Codex kit's access-placeholder API-style provider
does not itself exercise client refresh and is not such a control.

## Local state after removal

The rendered seed remains after global secret deletion and stop/start in both
kits. The adapter therefore retains managed local state and may still advertise
configured OAuth. Cleanup checks failed with `rendered_seed_still_present`; files
were not deleted to manufacture a pass.

Real catalog and inference requests were then denied with HTTP 401. Inference
said the authentication token could not be parsed, consistent with the placeholder
no longer being replaced by a usable credential. This is access denial, not proof
that the proxy rejected HTTP before forwarding. Retained placeholders are not
leaked real tokens. File presence establishes configured state, not authorization.
Automatic cleanup and OAuth/API-key transitions remain unresolved. The generic
error suggesting native Codex/Hermes login is not this kit's enrollment workflow.

## Pending

- Natural expiry: rendered OpenCode client metadata says November 5 at
  19:09:44.515 UTC, about ten days after observation. This is not independently
  verified host JWT expiry or a renewal test.
- Provider-side revocation and OAuth -> API key -> none transitions.
- Workspace/account/residency metadata; gateway inference/restart.
- Other-provider/API-key smoke tests and full latest-release host matrix.
- Full deny-all E2E: an optional scanner attempted a blocked GitHub release-asset
  download and used pattern matching instead. Provider inference success does
  not establish the complete declared-egress contract.
- The launcher follow-up's full mixin rebuild after resolving local disk limits.

No multi-account routing, real-token copying, proxy bypass, or automatic enrollment
into existing sandboxes was added to resolve these observations.
