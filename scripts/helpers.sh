#!/usr/bin/env bash

# tmux-buffer-sync configuration helper functions
# Handles tmux option parsing and validation

# Get tmux option value, checking session-specific first, then global
get_tmux_option() {
    local session="$1"
    local option="$2"
    local default_value="$3"

    # Try session-specific option first
    local value
    value=$(tmux show-option -t "$session" -qv "$option" 2>/dev/null)

    # If not found, try global option
    if [ -z "$value" ]; then
        value=$(tmux show-option -gqv "$option" 2>/dev/null)
    fi

    # Use default if still empty
    if [ -z "$value" ]; then
        value="$default_value"
    fi

    echo "$value"
}


get_last_sync_status() {
    local session="$1"
    local namespace
    namespace=$(get_tmux_option "$session" "@buffer-sync-namespace" "tmux-buffers")

    local stored_status
    stored_status=$(atuin kv get --namespace "$namespace" "_sync_status_${session}" 2>/dev/null || echo "unknown")

    echo "$stored_status"
}

is_debug_mode_enabled() {
    local session="$1"
    local debug_value
    debug_value=$(get_tmux_option "$session" "@buffer-sync-debug" "off")

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
    local sync_status="$3"

    # Check if debug mode is enabled
    if ! is_debug_mode_enabled "$session"; then
        return 0
    fi

    # Construct the message
    local message
    if [[ "$sync_status" == "success" ]]; then
        message="${sync_type} sync successful"
    else
        # Extract reason from sync_status (format: "failed: reason")
        local reason="${sync_status#failed: }"
        message="${sync_type} sync failed: ${reason}"
    fi

    # Display the message
    tmux display-message -t "$session" "$message"

    # Also log for verification
    log_message "debug" "Debug notification: $message"
}

