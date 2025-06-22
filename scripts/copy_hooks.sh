#!/usr/bin/env bash

# tmux-buffer-sync copy operation integration
# Handles immediate sync triggers on copy operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR


register_copy_hooks() {
    local session="$1"

    local copy_hooks_enabled
    local value
    value=$(tmux show-option -t "$session" -v "@buffer-sync-copy-hooks" 2>/dev/null || echo "")
    case "$(echo "$value" | tr '[:upper:]' '[:lower:]')" in
        "off"|"false"|"0"|"no"|"disabled") copy_hooks_enabled="off" ;;
        *) copy_hooks_enabled="on" ;;
    esac

    if [ "$copy_hooks_enabled" = "off" ]; then
        return 1
    fi

    # Register copy-mode hook to trigger sync on copy operations
    tmux set-hook -t "$session" after-copy-mode "run-shell '$SCRIPT_DIR/../buffer-sync.tmux copy-sync \"$session\" \"#{pane_id}\"'"


    return 0
}

unregister_copy_hooks() {
    local session="$1"

    tmux set-hook -u -t "$session" after-copy-mode


    return 0
}

on_copy_event() {
    local session="$1"

    local copy_hooks_enabled
    local value
    value=$(tmux show-option -t "$session" -v "@buffer-sync-copy-hooks" 2>/dev/null || echo "")
    case "$(echo "$value" | tr '[:upper:]' '[:lower:]')" in
        "off"|"false"|"0"|"no"|"disabled") copy_hooks_enabled="off" ;;
        *) copy_hooks_enabled="on" ;;
    esac

    if [ "$copy_hooks_enabled" != "on" ]; then
        return 1
    fi

    sync_buffers "$session"

    return $?
}

are_copy_hooks_enabled() {
    local session="$1"
    local copy_hooks_enabled
    local value
    value=$(tmux show-option -t "$session" -v "@buffer-sync-copy-hooks" 2>/dev/null || echo "")
    case "$(echo "$value" | tr '[:upper:]' '[:lower:]')" in
        "off"|"false"|"0"|"no"|"disabled") copy_hooks_enabled="off" ;;
        *) copy_hooks_enabled="on" ;;
    esac

    if [ "$copy_hooks_enabled" = "on" ]; then
        echo "true"
    else
        echo "false"
    fi
}


unregister_all_hooks() {
    local session="$1"

    unregister_copy_hooks "$session"

    if command -v stop_timer_sync >/dev/null 2>&1; then
        stop_timer_sync "$session"
    fi

    return 0
}
