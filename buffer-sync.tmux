#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper scripts
source "$CURRENT_DIR/scripts/helpers.sh"
source "$CURRENT_DIR/scripts/atuin_adapter.sh"
source "$CURRENT_DIR/scripts/sync.sh"
source "$CURRENT_DIR/scripts/commands.sh"

# Plugin initialization
main() {
    if ! is_atuin_available; then
        log_message "error" "Atuin not available - buffer sync will not function"
        return 1
    fi

    # Register user commands globally
    if ! register_user_commands; then
        log_message "warn" "Failed to register user commands"
    fi

    # Initialize for all existing sessions
    local session
    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null); do
        initialize_session "$session"
    done

    return 0
}

setup_timer_sync() {
    local session="$1"
    local frequency
    frequency=$(get_tmux_option "$session" "@buffer-sync-frequency" "15")
    [[ "$frequency" =~ ^[0-9]+$ ]] && [ "$frequency" -gt 0 ] || frequency="15"

    # Set status interval for timer-based sync
    tmux set-option -t "$session" status-interval "$frequency"

    # Get current status-right and append our sync command
    local current_status_right
    current_status_right=$(tmux show-option -t "$session" -gqv status-right)

    # Add invisible sync trigger to status-right
    # The #() runs a shell command during each status update
    local sync_command="#(${CURRENT_DIR}/buffer-sync.tmux sync-timer \"$session\" >/dev/null 2>&1; echo -n '')"

    # Append to existing status-right
    tmux set-option -t "$session" status-right "${current_status_right}${sync_command}"

    return 0
}

initialize_session() {
    local session="$1"

    # Setup timer-based sync
    setup_timer_sync "$session"

    # Setup copy hooks if enabled
    source "$CURRENT_DIR/scripts/copy_hooks.sh"
    if [ "$(are_copy_hooks_enabled "$session")" = "true" ]; then
        if ! register_copy_hooks "$session"; then
            log_message "warn" "Failed to register copy hooks for session: $session"
        fi
    fi

    log_message "info" "tmux-buffer-sync plugin initialized for session: $session"
}

if [ $# -gt 0 ]; then
    case "$1" in
        "sync-timer" | "copy-sync")
            session="$2"
            if [ -n "$session" ]; then
                case "$1" in
                    "sync-timer")
                        sync_buffers "$session" "Timer"
                        ;;
                    "copy-sync")
                        sync_buffers "$session" "Copy"
                        ;;
                esac
            fi
            ;;
        "user-command")
            command="$2"
            session="$3"
            if [ -n "$command" ] && [ -n "$session" ]; then
                case "$command" in
                    "buffer-sync-now")
                        sync_buffers_interactive "$session"
                        ;;
                    "buffer-sync-status")
                        show_sync_status "$session"
                        ;;
                    *)
                        echo "Unknown command: $command"
                        get_command_help
                        ;;
                esac
            fi
            ;;
    esac
else
    main
fi
