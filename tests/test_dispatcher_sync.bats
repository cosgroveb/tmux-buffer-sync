#!/usr/bin/env bats

# Test that sync-timer and copy-sync both trigger sync operations

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
readonly PROJECT_ROOT
readonly TEST_SESSION="dispatcher-test-$$"
readonly TMUX_SOCKET="/tmp/dispatcher-test-$$"
readonly TEST_NAMESPACE="test-dispatcher-$$"

setup() {
    # Start isolated tmux server
    tmux -S "$TMUX_SOCKET" new-session -d -s "$TEST_SESSION"
    tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-namespace" "$TEST_NAMESPACE"
}

teardown() {
    # Kill test session and server
    tmux -S "$TMUX_SOCKET" kill-server 2>/dev/null || true
    # Clean up any test data in atuin
    atuin kv set --namespace "$TEST_NAMESPACE" --key "buffer.0" "" 2>/dev/null || true
}

@test "sync-timer triggers buffer sync to atuin" {
    # Create a test buffer
    echo "sync-timer-test" | tmux -S "$TMUX_SOCKET" load-buffer -
    
    # Source required scripts and run sync-timer in proper context
    (
        export TMUX_SOCKET
        cd "$PROJECT_ROOT"
        source scripts/helpers.sh
        source scripts/atuin_adapter.sh  
        source scripts/sync.sh
        # Override tmux to use our test socket
        tmux() { command tmux -S "$TMUX_SOCKET" "$@"; }
        export -f tmux
        ./buffer-sync.tmux sync-timer "$TEST_SESSION"
    )
    
    # Check if buffer was synced to atuin
    local synced_content
    synced_content=$(atuin kv get --namespace "$TEST_NAMESPACE" "buffer.0" 2>/dev/null || echo "")
    
    [[ "$synced_content" == "sync-timer-test" ]]
}

@test "copy-sync triggers buffer sync to atuin" {
    # Create a test buffer
    echo "copy-sync-test" | tmux -S "$TMUX_SOCKET" load-buffer -
    
    # Source required scripts and run copy-sync in proper context
    (
        export TMUX_SOCKET
        cd "$PROJECT_ROOT"
        source scripts/helpers.sh
        source scripts/atuin_adapter.sh  
        source scripts/sync.sh
        # Override tmux to use our test socket
        tmux() { command tmux -S "$TMUX_SOCKET" "$@"; }
        export -f tmux
        ./buffer-sync.tmux copy-sync "$TEST_SESSION"
    )
    
    # Check if buffer was synced to atuin
    local synced_content
    synced_content=$(atuin kv get --namespace "$TEST_NAMESPACE" "buffer.0" 2>/dev/null || echo "")
    
    [[ "$synced_content" == "copy-sync-test" ]]
}