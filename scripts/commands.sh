#!/usr/bin/env bash

# tmux-buffer-sync user commands
# Handles manual tmux commands for user interaction

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR


# Register user commands globally
register_user_commands() {
    # Register commands using tmux command alias system globally
    # Commands will detect current session automatically using #{session_name}
    local plugin_script
    plugin_script="$(cd "$SCRIPT_DIR/.." && pwd)/buffer-sync.tmux"

    # NOTE: Using -ag (append) means reloading the plugin will create duplicate aliases.
    # This is a known limitation - tmux command-alias is an array option without built-in
    # deduplication. To properly handle this would require using indexed array notation
    # like command-alias[100], but that risks conflicts with other plugins.
    tmux set-option -ag command-alias "buffer-sync-now=run-shell '$plugin_script user-command buffer-sync-now #{session_name}'"
    tmux set-option -ag command-alias "buffer-sync-status=run-shell '$plugin_script user-command buffer-sync-status #{session_name}'"

    return 0
}

get_command_help() {
    cat <<'EOF'
tmux-buffer-sync User Commands:

:buffer-sync-now
    Manually trigger immediate buffer synchronization
    Performs bidirectional sync (push local buffers, pull remote buffers)
    Returns: sync status and buffer counts

:buffer-sync-status
    Display current sync configuration and status
    Shows: namespace, frequency, buffer count, copy hooks status
    Returns: formatted configuration information

Configuration:
    @buffer-sync-count <number>        - Number of buffers to sync (default: 10)
    @buffer-sync-frequency <seconds>   - Sync frequency in seconds (default: 15)
    @buffer-sync-namespace <string>    - Storage namespace (default: tmux-buffers)
    @buffer-sync-copy-hooks <on|off>   - Copy operation hooks (default: on)
    @buffer-sync-status-display <mode> - Status display mode (default: compact)
EOF
}

format_sync_command_output() {
    local status="$1"

    case "$status" in
        "success")
            echo "✓ Sync completed successfully"
            ;;
        "push_failed")
            echo "✗ Sync failed - unable to push/pull buffers"
            ;;
        "pull_failed")
            echo "✗ Sync failed - unable to push/pull buffers"
            ;;
        "partial_failure")
            echo "⚠ Sync completed with warnings"
            ;;
        *)
            echo "? Sync status unknown - Check configuration and atuin availability"
            ;;
    esac
}

format_status_command_output() {
    local session="$1"
    local ns count freq status
    ns=$(get_tmux_option "$session" "@buffer-sync-namespace" "tmux-buffers")
    count=$(get_tmux_option "$session" "@buffer-sync-count" "10")
    freq=$(get_tmux_option "$session" "@buffer-sync-frequency" "15")
    status=$(get_last_sync_status "$session")

    echo "buffer-sync: namespace=$ns, count=$count, freq=${freq}s, status=$status"
}

sync_buffers_interactive() {
    local session="$1"

    if ! is_atuin_available; then
        echo "✗ Buffer sync unavailable - atuin not found"
        return 1
    fi

    local count
    count=$(get_tmux_option "$session" "@buffer-sync-count" "10")
    [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] || count="10"

    # timing
    local start_time
    start_time=$(date +%s)

    if perform_sync "$session" "Manual"; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        format_sync_command_output "success"
        echo "Completed in ${duration}s"
        return 0
    else
        format_sync_command_output "push_failed"
        return 1
    fi
}

show_sync_status() {
    local session="$1"
    local status_output
    status_output=$(format_status_command_output "$session")

    tmux display-message -t "$session" "$status_output"
    echo "$status_output"
}
