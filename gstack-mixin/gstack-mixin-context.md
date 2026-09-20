# gstack

This sandbox has the gstack skill pack layered on: Garry Tan's Claude Code
slash commands, registered under `~/.claude/skills`. Use them for the full AI
engineering workflow:

/office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review,
/design-consultation, /review, /ship, /land-and-deploy, /canary,
/benchmark, /browse, /qa, /qa-only, /design-review,
/setup-browser-cookies, /setup-deploy, /retro, /investigate,
/document-release, /codex, /cso, /autoplan, /careful, /freeze, /guard,
/unfreeze, /gstack-upgrade

Use the /browse skill for web browsing — it drives a local headless Chromium
daemon (loopback only, auto-started on first use). The Chromium bundle is at
`/opt/playwright-browsers`, but the system libraries it links against come
from the base image rather than from this overlay: on an Ubuntu sandbox
template /browse works, and on a base without those libraries it fails while
every other command keeps working.

This is the mixin form, so the launch command is the base workload's — run
`claude` yourself rather than expecting the sandbox to start it.
