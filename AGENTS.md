# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, or similar) working in this repository.

## Keep `spec/` and `skills/kit-author/` in sync

The `kit-author` skill (`skills/kit-author/`) documents the schema, validation rules, and
lifecycle that the `spec/` package implements and `tck/` exercises. Its published `paths`
trigger deliberately excludes `spec/**` and `tck/**` — those patterns are too broad to ship to
the skill's external marketplace consumers — so editing files in `spec/` or `tck/` does not
auto-load the skill the way editing a `spec.yaml` does.

If you are changing validation rules, field names, or lifecycle behavior in `spec/`:

1. Load or invoke the `kit-author` skill before you finish the change.
2. Update the matching page under `skills/kit-author/topics/*.md` in the same change —
   `spec-anatomy.md` and `lifecycle.md` are the most likely to need an edit.
3. Check the skill's docs against what you just changed before opening a PR.

This is what would have caught the `resources.memoryMB` field-name and validation-rule drift
fixed in [#125](https://github.com/docker/sbx-kits-contrib/pull/125) at the point it was
introduced, instead of surfacing later as a hard-to-diagnose "field not found" error for anyone
following the (then-incorrect) docs.
