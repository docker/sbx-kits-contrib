#!/bin/sh
# Stream into the disposable standalone sandbox with sh -l -s -- setup|verify.
set -eu
phase=${1:?Supply setup or verify}

verify_settings() {
    [ "$(hermes -p sbx-validation-a config get model.provider)" = openai-codex ]
    [ "$(hermes -p sbx-validation-a config get model.default)" = gpt-6.1-sol ]
    [ "$(hermes -p sbx-validation-b config get model.provider)" = openai-codex ]
    [ "$(hermes -p sbx-validation-b config get model.default)" = gpt-6-sol ]
    printf 'profile_settings_passed=true\n'
}

case "$phase" in
    setup)
        # Preserve the default profile's explicit settings; no login/auth copy.
        initial_provider=$(hermes config get model.provider)
        initial_model=$(hermes config get model.default)
        hermes profile create sbx-validation-a --no-alias --no-skills
        hermes profile create sbx-validation-b --no-alias --no-skills
        hermes -p sbx-validation-a config set model.provider openai-codex
        hermes -p sbx-validation-a config set model.default gpt-6.1-sol
        hermes -p sbx-validation-b config set model.provider openai-codex
        hermes -p sbx-validation-b config set model.default gpt-6-sol
        verify_settings
        [ "$(hermes config get model.provider)" = "$initial_provider" ]
        [ "$(hermes config get model.default)" = "$initial_model" ]
        printf 'default_profile_selection_unchanged=true\n'
        ;;
    verify)
        # Check persistence before any writes, then rely on each saved selection.
        verify_settings
        hermes -p sbx-validation-a chat -q 'Reply with OK only. Do not use tools.'
        hermes -p sbx-validation-b chat -q 'Reply with OK only. Do not use tools.'
        ;;
    *) exit 2 ;;
esac
