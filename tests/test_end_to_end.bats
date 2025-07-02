#!/usr/bin/env bats
#
# Tests plugin functionality within managed tmux sessions.
#
# BATS provides these variables: $status, $output, $lines
# shellcheck disable=SC2154

# Use process ID to ensure unique session and directory names per test run
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
readonly PROJECT_ROOT
readonly TEST_NAMESPACE="tmux-buffers-test"
readonly TEST_SESSION="bats-test-$$"
readonly TEMP_DIR="${TMPDIR:-/tmp}/tmux-buffer-sync-test-$$"
readonly TMUX_SOCKET="/tmp/bats-tmux-$$"
readonly TMUX_SOCKET_2="/tmp/bats-tmux-2-$$"
readonly TEST_SESSION_2="bats-test-2-$$"
readonly FIRST_TMUX="first_tmux"
readonly SECOND_TMUX="second_tmux"

# Setup function runs before each test
function setup() {
  mkdir -p "$TEMP_DIR"

  # Clean test namespace in atuin
  _clean_test_namespace

  # Create isolated tmux server and session per test
  tmux -S "$TMUX_SOCKET" new-session -d -s "$TEST_SESSION" -c "$PROJECT_ROOT"

  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-count" "5"
  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-namespace" "$TEST_NAMESPACE"
  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-frequency" "5"
}

# Teardown function runs after each test
function teardown() {
  tmux -S "$TMUX_SOCKET" kill-server || true

  rm -f "$TMUX_SOCKET"

  # Clean test namespace in atuin
  _clean_test_namespace

  rm -rf "$TEMP_DIR"
}

# Helper function to clean atuin test namespace
function _clean_test_namespace() {
  if command -v atuin >/dev/null; then
    local keys
    keys=$(atuin kv list --namespace "$TEST_NAMESPACE" || echo "")
    if [[ -n "$keys" ]]; then
      while IFS= read -r key; do
        if [[ -n "$key" ]]; then
          atuin kv set --namespace "$TEST_NAMESPACE" --key "$key" "" || true
        fi
      done <<< "$keys"
    fi
  fi
}

# Execute commands in test tmux session
function _tmux_exec() {
  local cmd="$1"
  local server="${2:-$FIRST_TMUX}"  # Default to first tmux

  local socket session
  if [[ "$server" == "$SECOND_TMUX" ]]; then
    socket="$TMUX_SOCKET_2"
    session="$TEST_SESSION_2"
  else
    socket="$TMUX_SOCKET"
    session="$TEST_SESSION"
  fi

  # Create a temporary script and run it
  local temp_script="$TEMP_DIR/tmux_cmd_$$"
  {
    echo "#!/bin/bash"
    echo "cd '$PROJECT_ROOT'"
    echo "source scripts/helpers.sh >/dev/null 2>&1"
    echo "source scripts/atuin_adapter.sh >/dev/null 2>&1"
    echo "source scripts/sync.sh >/dev/null 2>&1"
    echo "$cmd"
  } > "$temp_script"
  chmod +x "$temp_script"

  # Run the script in the tmux session
  tmux -S "$socket" send-keys -t "$session" "bash '$temp_script'" Enter
  sleep 1

  # Capture just the last line of output
  tmux -S "$socket" capture-pane -t "$session" -p | grep -v "^.*%" | grep -v "bash " | tail -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'

  # Clean up
  rm -f "$temp_script"
}

function _load_plugin_scripts() {
  local setup_second_server="${1:-false}"

  # Load scripts on first server
  _tmux_exec "cd '$PROJECT_ROOT'"
  _tmux_exec "source scripts/helpers.sh"
  _tmux_exec "source scripts/atuin_adapter.sh"
  _tmux_exec "source scripts/sync.sh"

  # Optionally create and configure second server
  if [[ "$setup_second_server" == "true" ]]; then
    tmux -S "$TMUX_SOCKET_2" new-session -d -s "$TEST_SESSION_2" -c "$PROJECT_ROOT"
    tmux -S "$TMUX_SOCKET_2" set-option -t "$TEST_SESSION_2" "@buffer-sync-count" "5"
    tmux -S "$TMUX_SOCKET_2" set-option -t "$TEST_SESSION_2" "@buffer-sync-namespace" "$TEST_NAMESPACE"

    # Load scripts on second server
    _tmux_exec "cd '$PROJECT_ROOT'" "$SECOND_TMUX"
    _tmux_exec "source scripts/helpers.sh" "$SECOND_TMUX"
    _tmux_exec "source scripts/atuin_adapter.sh" "$SECOND_TMUX"
    _tmux_exec "source scripts/sync.sh" "$SECOND_TMUX"
  fi
}

function configuration_helper_functions_work() { #@test
  # Load plugin scripts
  _load_plugin_scripts

  # Add content to buffers for sync
  tmux -S "$TMUX_SOCKET" send-keys -t "$TEST_SESSION" "echo 'test-sync-content' | tmux -S '$TMUX_SOCKET' load-buffer -" Enter
  sleep 1

  # Perform sync
  _tmux_exec "sync_buffers '$TEST_SESSION'"

  # Assert sync
  local status_output
  status_output=$(_tmux_exec "get_last_sync_status '$TEST_SESSION'")
  [[ "$status_output" == "success" ]]

  # Assert timestamp also recorded
  local timestamp_output
  timestamp_output=$(_tmux_exec "get_last_sync_timestamp '$TEST_SESSION'")
  [[ -n "$timestamp_output" ]] && [[ "$timestamp_output" =~ ^[0-9]+$ ]]
}

function buffer_operations_can_read_tmux_buffers() { #@test
  # Load plugin scripts on both servers
  _load_plugin_scripts true

  # Step 1: Server 1 creates buffer and pushes
  local server1_content="server1-buffer-$$"
  _tmux_exec "echo '$server1_content' | tmux -S '$TMUX_SOCKET' load-buffer -"
  _tmux_exec "push_buffers_to_atuin '$TEST_NAMESPACE' 2"

  # Step 2: Server 2 pulls and should see Server 1's buffer
  _tmux_exec "pull_buffers_from_atuin '$TEST_NAMESPACE' 2" "$SECOND_TMUX"
  local server2_buffers_after_pull
  server2_buffers_after_pull=$(tmux -S "$TMUX_SOCKET_2" list-buffers -F "#{buffer_sample}")
  [[ "$server2_buffers_after_pull" == *"$server1_content"* ]]

  # Step 3: Server 2 creates its own buffer and pushes (pushes Server 1's down the list)
  local server2_content="server2-buffer-$$"
  _tmux_exec "echo '$server2_content' | tmux -S '$TMUX_SOCKET_2' load-buffer -" "$SECOND_TMUX"
  _tmux_exec "push_buffers_to_atuin '$TEST_NAMESPACE' 2" "$SECOND_TMUX"

  # Step 4: Server 1 pulls and should see both buffers (Server 2's first, Server 1's pushed down)
  _tmux_exec "pull_buffers_from_atuin '$TEST_NAMESPACE' 2"
  local server1_buffers_after_pull
  server1_buffers_after_pull=$(tmux -S "$TMUX_SOCKET" list-buffers -F "#{buffer_sample}")
  # Should contain both: Server 2's content (newest) and Server 1's content (pushed down)
  [[ "$server1_buffers_after_pull" == *"$server2_content"* ]]
  [[ "$server1_buffers_after_pull" == *"$server1_content"* ]]

  # Clean up second server
  tmux -S "$TMUX_SOCKET_2" kill-server || true
  rm -f "$TMUX_SOCKET_2"
}

function plugin_loads_correctly_via_tpm_interface() { #@test
  # Test main plugin entry point exists and is executable
  [[ -f "$PROJECT_ROOT/buffer-sync.tmux" ]]
  [[ -x "$PROJECT_ROOT/buffer-sync.tmux" ]]

  # Execute plugin in tmux session
  _tmux_exec "cd '$PROJECT_ROOT' && ./buffer-sync.tmux"
}

# vim: set ft=bash:
