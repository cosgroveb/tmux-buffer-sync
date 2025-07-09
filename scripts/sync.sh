#!/usr/bin/env bash

# tmux-buffer-sync bidirectional sync engine
# Handles complete sync cycles with conflict resolution




store_sync_status() {
    local session="$1"
    local sync_status="$2"
    local timestamp="$3"
    local namespace
    namespace=$(get_tmux_option "$session" "@buffer-sync-namespace" "tmux-buffers")

    local storage_namespace="$namespace"

    atuin kv set --namespace "$storage_namespace" --key "_sync_status_${session}" "$sync_status" 2>/dev/null || true
    atuin kv set --namespace "$storage_namespace" --key "_sync_timestamp_${session}" "$timestamp" 2>/dev/null || true
}


# Main bidirectional sync function
sync_buffers() {
    local session="$1"
    local sync_type="${2:-Manual}"  # Default to "Manual" if not provided

    local namespace count
    namespace=$(get_tmux_option "$session" "@buffer-sync-namespace" "tmux-buffers")
    count=$(get_tmux_option "$session" "@buffer-sync-count" "10")
    [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] || count="10"

    local timestamp
    timestamp=$(date +%s)
    store_sync_status "$session" "starting" "$timestamp"

    # Push local buffers and pull remote buffers
    if push_buffers_to_atuin "$namespace" "$count" && pull_buffers_from_atuin "$namespace" "$count"; then
        store_sync_status "$session" "success" "$(date +%s)"
        debug_notify "$session" "$sync_type" "success"
        return 0
    else
        store_sync_status "$session" "failed" "$(date +%s)"
        debug_notify "$session" "$sync_type" "failed: sync operation failed"
        return 1
    fi
}
