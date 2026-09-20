## Claude Code: Environment Persistence

The `CLAUDE_ENV_FILE` environment variable is set to `/etc/sandbox-persistent.sh`.

According to [Claude Code Documentation](https://code.claude.com/docs/en/settings#bash-tool-behavior):

> **CLAUDE_ENV_FILE**
>
> If set, this file will be sourced before each Bash command execution. This allows environment variables to persist across multiple Bash tool invocations.

This means `/etc/sandbox-persistent.sh` is sourced before every Bash tool call you make. Any `export` statements you append to this file will be available in all subsequent commands without needing a login shell.

### Shell Completions Must NOT Be in CLAUDE_ENV_FILE

**NEVER add shell completion scripts to `/etc/sandbox-persistent.sh`.**

`CLAUDE_ENV_FILE` is sourced **before every single bash command execution**, not just during shell initialization. Completion scripts rely on special variables (`COMP_WORDS`, `COMP_CWORD`, `COMPREPLY`) that only exist during tab-completion contexts.

#### WRONG - Will Break Bash

```bash
# DO NOT ADD THESE TO /etc/sandbox-persistent.sh
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
[[ -s "$SDKMAN_DIR/etc/bash_completion.sh" ]] && source "$SDKMAN_DIR/etc/bash_completion.sh"
```

#### CORRECT - Only Load Core Functionality

```bash
# ONLY add the main initialization scripts
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
```

#### Symptoms of Broken Shell

When completion scripts are incorrectly added:
- All bash commands return no output (silent failure)
- `echo`, `pwd`, and other basic commands produce no results
- The bash tool becomes completely unusable

#### Solution

If you accidentally added completion scripts and broke the shell:
1. Remove the completion line(s) from `/etc/sandbox-persistent.sh`
2. Exit and restart the Claude Code session
3. Verify with `echo "test"` that bash works again
