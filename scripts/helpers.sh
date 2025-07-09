#!/usr/bin/env bash

# tmux-buffer-sync configuration helper functions
# Handles tmux option parsing and validation


get_last_sync_status() {
    local session="$1"
    local namespace
    namespace=$(tmux show-option -t "$session" -v "@buffer-sync-namespace" 2>/dev/null || echo "tmux-buffers")
    [ -n "$namespace" ] || namespace="tmux-buffers"

    local stored_status
    stored_status=$(atuin kv get --namespace "$namespace" "_sync_status_${session}" 2>/dev/null || echo "unknown")

    echo "$stored_status"
}

is_debug_mode_enabled() {
    local session="$1"
    local debug_value
    debug_value=$(tmux show-option -t "$session" -v "@buffer-sync-debug" 2>/dev/null || echo "off")
    
    # Convert to lowercase for case-insensitive comparison
    debug_value=$(echo "$debug_value" | tr '[:upper:]' '[:lower:]')
    
    case "$debug_value" in
        "on"|"true"|"1"|"yes"|"enabled")
            return 0  # true
            ;;
        *)
            return 1  # false
            ;;
    esac
}

debug_notify() {
    local session="$1"
    local sync_type="$2"
    local status="$3"
    
    # Check if debug mode is enabled
    if ! is_debug_mode_enabled "$session"; then
        return 0
    fi
    
    # Construct the message
    local message
    if [[ "$status" == "success" ]]; then
        message="${sync_type} sync successful"
    else
        # Extract reason from status (format: "failed: reason")
        local reason="${status#failed: }"
        message="${sync_type} sync failed: ${reason}"
    fi
    
    # Display the message
    tmux display-message -t "$session" "$message"
    
    # Also log for verification
    log_message "debug" "Debug notification: $message"
}

