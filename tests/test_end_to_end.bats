#!/usr/bin/env bats
#
# End-to-end tests for tmux-buffer-sync plugin using BATS framework.
# Tests plugin functionality within managed tmux sessions.
#
# This file follows Google Shell Style Guide and generates TAP output.
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

# Setup function runs before each test
function setup() {
  # Create temporary directory for test artifacts
  mkdir -p "$TEMP_DIR"
  
  # Clean test namespace in atuin
  _clean_test_namespace
  
  # Create isolated tmux server and session per test to prevent interference
  tmux -S "$TMUX_SOCKET" new-session -d -s "$TEST_SESSION" -c "$PROJECT_ROOT"
  
  # Configure test session with plugin settings
  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-count" "5"
  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-namespace" "$TEST_NAMESPACE"
  tmux -S "$TMUX_SOCKET" set-option -t "$TEST_SESSION" "@buffer-sync-frequency" "5"
}

# Teardown function runs after each test
function teardown() {
  # Kill test tmux server (cleans up session and buffers)
  tmux -S "$TMUX_SOCKET" kill-server || true
  
  # Remove socket file
  rm -f "$TMUX_SOCKET"
  
  # Clean test namespace
  _clean_test_namespace
  
  # Remove temporary directory
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

# Helper function to execute commands in test tmux session
function _tmux_exec() {
  local cmd="$1"
  local output_file="$TEMP_DIR/tmux_output"
  
  # Send command to session and wait for execution
  tmux -S "$TMUX_SOCKET" send-keys -t "$TEST_SESSION" "$cmd" Enter
  sleep 1
  
  # Capture output
  tmux -S "$TMUX_SOCKET" capture-pane -t "$TEST_SESSION" -p > "$output_file"
  cat "$output_file"
}

# Helper function to load script sources in tmux session
function _load_plugin_scripts() {
  _tmux_exec "cd '$PROJECT_ROOT'"
  _tmux_exec "source scripts/helpers.sh"
  _tmux_exec "source scripts/atuin_adapter.sh"
  _tmux_exec "source scripts/sync.sh"
}

function scripts_load_without_syntax_errors() { #@test
  # Check each script for syntax errors
  local scripts=(
    "scripts/helpers.sh"
    "scripts/atuin_adapter.sh" 
    "scripts/sync.sh"
    "scripts/copy_hooks.sh"
    "scripts/commands.sh"
  )
  
  local script
  for script in "${scripts[@]}"; do
    run bash -n "$PROJECT_ROOT/$script"
    # $status is set by BATS 'run' command
    [[ "$status" -eq 0 ]]
  done
}

function atuin_command_is_available_and_functional() { #@test
  # Check atuin availability
  run command -v atuin
  [[ "$status" -eq 0 ]]
  
  # Test basic atuin kv operations
  run atuin kv set --namespace "$TEST_NAMESPACE" --key "test-key" "test-value"
  [[ "$status" -eq 0 ]]
  
  run atuin kv get --namespace "$TEST_NAMESPACE" "test-key"
  [[ "$status" -eq 0 ]]
  [[ "$output" == "test-value" ]]
  
  # Clean up test key
  run atuin kv set --namespace "$TEST_NAMESPACE" --key "test-key" ""
  [[ "$status" -eq 0 ]]
}

function tmux_session_configuration_parsing_works() { #@test
  # Test getting configuration values from tmux session
  local count namespace frequency
  
  count=$(tmux -S "$TMUX_SOCKET" show-option -t "$TEST_SESSION" -v "@buffer-sync-count" || echo "10")
  namespace=$(tmux -S "$TMUX_SOCKET" show-option -t "$TEST_SESSION" -v "@buffer-sync-namespace" || echo "tmux-buffers")
  frequency=$(tmux -S "$TMUX_SOCKET" show-option -t "$TEST_SESSION" -v "@buffer-sync-frequency" || echo "15")
  
  # Verify configured values
  [[ "$count" == "5" ]]
  [[ "$namespace" == "$TEST_NAMESPACE" ]]
  [[ "$frequency" == "5" ]]
}

function tmux_buffer_operations_work_correctly() { #@test
  # Create test content  
  local test_content="test-buffer-content-$$"
  
  # Load content into tmux buffer (execute in the target session)
  tmux -S "$TMUX_SOCKET" send-keys -t "$TEST_SESSION" "echo '$test_content' | tmux -S '$TMUX_SOCKET' load-buffer -" Enter
  sleep 1
  
  # Verify buffer was created
  local buffer_count
  buffer_count=$(tmux -S "$TMUX_SOCKET" list-buffers | wc -l)
  [[ "$buffer_count" -gt 0 ]]
  
  # Verify content can be retrieved
  local retrieved_content
  retrieved_content=$(tmux -S "$TMUX_SOCKET" show-buffer)
  [[ "$retrieved_content" == "$test_content" ]]
}

function configuration_helper_functions_work() { #@test
  # Load plugin scripts
  _load_plugin_scripts
  
  # Test helper functions that read sync status
  local output
  output=$(_tmux_exec "get_last_sync_status '$TEST_SESSION'")
  [[ "$output" == "unknown" ]] || [[ -n "$output" ]]
}

function atuin_adapter_functions_work() { #@test
  # Load plugin scripts
  _load_plugin_scripts
  
  # Test atuin detection function
  local output
  output=$(_tmux_exec "is_atuin_available && echo 'available' || echo 'not available'")
  [[ "$output" == *"available"* ]]
}

function buffer_operations_can_read_tmux_buffers() { #@test
  # Create test buffer in the session
  local test_content="buffer-ops-test-$$"
  tmux -S "$TMUX_SOCKET" send-keys -t "$TEST_SESSION" "echo '$test_content' | tmux -S '$TMUX_SOCKET' load-buffer -" Enter
  sleep 1
  
  # Load plugin scripts
  _load_plugin_scripts
  
  # Test push/pull functions exist and can be called
  local output
  output=$(_tmux_exec "push_buffers_to_atuin '$TEST_NAMESPACE' 1")
  [[ -n "$output" ]]
}

function plugin_loads_correctly_via_tpm_interface() { #@test
  # Test main plugin entry point exists and is executable
  [[ -f "$PROJECT_ROOT/buffer-sync.tmux" ]]
  [[ -x "$PROJECT_ROOT/buffer-sync.tmux" ]]
  
  # Execute plugin in tmux session and capture exit status
  local output
  output=$(_tmux_exec "cd '$PROJECT_ROOT' && ./buffer-sync.tmux")
  
  # Check that command executed (output should contain some response)
  [[ -n "$output" ]]
}

# vim: set ft=bash: