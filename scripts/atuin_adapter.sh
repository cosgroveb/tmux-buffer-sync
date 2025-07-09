#!/usr/bin/env bash

# tmux-buffer-sync atuin interface
# Handles atuin command detection, KV operations, and syslog logging

if [[ -z "${SYSLOG_TAG:-}" ]]; then
    readonly SYSLOG_TAG="tmux-buffer-sync"
fi

is_atuin_available() {
    command -v atuin >/dev/null 2>&1
}


log_message() {
    local level="$1"
    local message="$2"

    logger -t "$SYSLOG_TAG" "[$level] $message"
}


atuin_kv_set() {
    local namespace="$1"
    local key="$2"
    local value="$3"

    if ! is_atuin_available; then
        log_message "error" "Atuin not available for KV set operation"
        return 1
    fi

    atuin kv set --namespace "$namespace" --key "$key" "$value" 2>/dev/null
}

atuin_kv_get() {
    local namespace="$1"
    local key="$2"

    if ! is_atuin_available; then
        log_message "error" "Atuin not available for KV get operation"
        return 1
    fi

    atuin kv get --namespace "$namespace" "$key" 2>/dev/null
}


# Validate namespace for atuin storage
validate_namespace() {
    local namespace="$1"

    # Check for invalid characters (spaces, special chars that could cause issues)
    if [[ "$namespace" =~ [[:space:]/] ]]; then
        return 1
    fi

    # Check for empty namespace
    if [ -z "$namespace" ]; then
        return 1
    fi

    return 0
}

store_buffer_to_atuin() {
    local namespace="$1"
    local buffer_index="$2"

    if ! validate_namespace "$namespace"; then
        log_message "error" "Invalid namespace for storage: $namespace"
        return 1
    fi

    # Get buffer content (handle empty buffers specially)
    local buffer_content
    if tmux list-buffers 2>/dev/null | grep -q "^$buffer_index:"; then
        buffer_content=$(tmux show-buffer -b "$buffer_index" 2>/dev/null)
    else
        log_message "error" "Buffer $buffer_index not found for storage"
        return 1
    fi

    local storage_key
    storage_key="buffer.${buffer_index}"

    atuin_kv_set "$namespace" "$storage_key" "$buffer_content"
}

store_buffer_to_atuin_by_name() {
    local namespace="$1"
    local buffer_name="$2"
    local storage_index="$3"

    # Get buffer content by name
    local buffer_content
    if ! buffer_content=$(tmux show-buffer -b "$buffer_name" 2>/dev/null); then
        log_message "error" "Buffer $buffer_name not found for storage"
        return 1
    fi

    # Generate storage key using the storage index
    local storage_key
    storage_key="buffer.${storage_index}"

    atuin_kv_set "$namespace" "$storage_key" "$buffer_content"
}

load_buffer_from_atuin() {
    local namespace="$1"
    local buffer_index="$2"

    local storage_key
    storage_key="buffer.${buffer_index}"

    local buffer_content
    if ! buffer_content=$(atuin_kv_get "$namespace" "$storage_key"); then
        log_message "error" "Failed to retrieve buffer $buffer_index from storage"
        return 1
    fi

    # Load content into tmux buffer
    echo -n "$buffer_content" | tmux load-buffer -b "$buffer_index" -
}

push_buffers_to_atuin() {
    local namespace="$1"
    local count="$2"

    if ! validate_namespace "$namespace"; then
        log_message "error" "Invalid namespace for push operation: $namespace"
        return 1
    fi

    # Get the most recent buffers
    local buffer_names
    buffer_names=$(tmux list-buffers -F "#{buffer_name}" 2>/dev/null | head -n "$count")

    local success=0
    local sync_index=0

    # Push recent buffers with sequential storage indices
    while IFS= read -r buffer_name && [ $sync_index -lt "$count" ]; do
        if [ -n "$buffer_name" ]; then
            if store_buffer_to_atuin_by_name "$namespace" "$buffer_name" "$sync_index"; then
                success=$((success + 1))
            fi
            sync_index=$((sync_index + 1))
        fi
    done <<< "$buffer_names"

    log_message "info" "Pushed $success/$count recent buffers to storage"
    return 0
}

pull_buffers_from_atuin() {
    local namespace="$1"
    local count="$2"

    if ! validate_namespace "$namespace"; then
        log_message "error" "Invalid namespace for pull operation: $namespace"
        return 1
    fi

    # Get existing buffer names to update them instead of creating new ones
    local existing_buffers
    mapfile -t existing_buffers < <(tmux list-buffers -F "#{buffer_name}" 2>/dev/null | head -n "$count")

    local success=0
    local i
    for ((i=0; i<count; i++)); do
        if [[ $i -lt ${#existing_buffers[@]} ]]; then
            # Update existing buffer by name
            local buffer_content
            if buffer_content=$(atuin_kv_get "$namespace" "buffer.$i"); then
                echo -n "$buffer_content" | tmux load-buffer -b "${existing_buffers[$i]}" -
                success=$((success + 1))
            fi
        else
            # Create new buffer if we need more than exist
            if load_buffer_from_atuin "$namespace" "$i"; then
                success=$((success + 1))
            fi
        fi
    done

    log_message "info" "Pulled $success/$count buffers from storage"
    return 0
}
