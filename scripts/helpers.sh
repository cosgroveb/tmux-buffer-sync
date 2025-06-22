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

get_last_sync_timestamp() {
    local session="$1"
    local namespace
    namespace=$(tmux show-option -t "$session" -v "@buffer-sync-namespace" 2>/dev/null || echo "tmux-buffers")
    [ -n "$namespace" ] || namespace="tmux-buffers"

    local stored_timestamp
    stored_timestamp=$(atuin kv get --namespace "$namespace" "_sync_timestamp_${session}" 2>/dev/null || date +%s)

    echo "$stored_timestamp"
}
