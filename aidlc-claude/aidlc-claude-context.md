## AI-DLC

`bun` is on PATH and the Claude harness is installed in this workspace —
`.claude/` and its `aidlc/` sibling are copied in at startup from
`/home/agent/aidlc-workflows/dist/claude`. Run `/aidlc --doctor` to verify,
then `/aidlc <description>` to start a workflow.

The clone at `/home/agent/aidlc-workflows` is the source tree those files
came from; it stays outside the workspace, checked out to a specific commit
rather than the `main` branch tip — main moves fast enough that two sandboxes
created hours apart can otherwise get different code under the same kit
digest, and the harness's own merge scripts depend on the internal shape of
its shipped `settings.json` and `.gitignore`.

`aidlc/.aidlc-workflows-version` in the project records which commit. Empty
(a fresh project) means the first startup checks out the latest `main`
commit and records its SHA there; present means every later sandbox for
this project — this one recreated, or a teammate's once the file is
committed — reproduces that same commit. The file is an automatically
managed, immutable project lock after its initial creation; do not edit or
delete it manually.

Two files are the exception to the copy: they are *merged*, so anything the
project already had is kept.

`.claude/settings.json` keeps every value it set and only gains the AI-DLC
keys it was missing (the `aidlc-*.ts` hook wiring, the Bedrock `env` block,
the model pins, the status line). It targets AWS Bedrock and needs AWS
credentials. If the project pinned its own `model` or `AWS_REGION`, those
stand — the merge never overwrites.

`.gitignore` keeps every project rule and gains the AI-DLC commit/ignore
section in a marked block, so the per-user cursors and machine-local runtime
state under `aidlc/` stay untracked while the shared records — method
memory, state, audit shards, artifacts — are committed as intended. Rules
inside the `# >>> AI-DLC (managed by the aidlc-claude sbx kit) >>>` markers
are kit-managed and refreshed on restart; put project rules outside them.
