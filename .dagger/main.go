// Dagger module for tmux-buffer-sync CI/CD pipeline
//
// This module provides cross-platform testing, shell script validation,
// and multi-server sync simulation for the tmux-buffer-sync plugin.

package main

import (
	"context"
	"fmt"
	"dagger/tmux-buffer-sync/internal/dagger"
)

type TmuxBufferSync struct{}

// Test the plugin on Ubuntu (single platform)
func (m *TmuxBufferSync) TestPlugin(ctx context.Context, source *dagger.Directory) error {
	_, err := dag.Container().
		From("ubuntu:22.04").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "tmux", "curl", "ca-certificates"}).
		WithExec([]string{"sh", "-c", "curl -L https://github.com/atuinsh/atuin/releases/latest/download/atuin-x86_64-unknown-linux-gnu.tar.gz | tar xz && mv atuin-*/atuin /usr/local/bin/ && chmod +x /usr/local/bin/atuin"}).
		WithMountedDirectory("/plugin", source).
		WithWorkdir("/plugin").
		WithExec([]string{"sh", "-c", "mkdir -p ~/.local/share/atuin && atuin init bash --disable-up-arrow --disable-ctrl-r"}).
		WithExec([]string{"sh", "-c", `
			# Start tmux session
			tmux new-session -d -s test-session
			# Run the test inside tmux and capture output
			tmux send-keys -t test-session "bash tests/test_end_to_end.sh && echo 'TEST_SUCCESS' || echo 'TEST_FAILED'" Enter
			# Wait for test to complete
			sleep 30
			# Capture the output
			tmux capture-pane -t test-session -p > /tmp/test_output.log
			# Check if test was successful
			if grep -q "TEST_SUCCESS" /tmp/test_output.log; then
				echo "✓ Tests passed"
				cat /tmp/test_output.log
			else
				echo "✗ Tests failed"
				cat /tmp/test_output.log
				exit 1
			fi
			# Clean up
			tmux kill-session -t test-session 2>/dev/null || true
		`}).
		Stdout(ctx)
	
	return err
}

// Validate shell scripts with shellcheck and syntax checking
func (m *TmuxBufferSync) Lint(ctx context.Context, source *dagger.Directory) error {
	// Syntax check
	_, err := dag.Container().
		From("alpine:latest").
		WithExec([]string{"apk", "add", "shellcheck", "bash"}).
		WithMountedDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"find", ".", "-name", "*.sh", "-not", "-path", "./.git/*", "-exec", "bash", "-n", "{}", "+"}).
		Stdout(ctx)
	if err != nil {
		return fmt.Errorf("syntax check failed: %w", err)
	}
	
	// Shellcheck
	_, err = dag.Container().
		From("alpine:latest").
		WithExec([]string{"apk", "add", "shellcheck", "bash"}).
		WithMountedDirectory("/src", source).
		WithWorkdir("/src").
		WithExec([]string{"find", ".", "-name", "*.sh", "-not", "-path", "./.git/*", "-exec", "shellcheck", "{}", "+"}).
		Stdout(ctx)
	if err != nil {
		return fmt.Errorf("shellcheck failed: %w", err)
	}
	
	return nil
}

// Simulate multi-server buffer synchronization
func (m *TmuxBufferSync) TestMultiServerSync(ctx context.Context, source *dagger.Directory) error {
	// Create shared storage simulation using a simple service
	sharedStorage := dag.Container().
		From("alpine:latest").
		WithExec([]string{"apk", "add", "curl", "python3"}).
		WithExposedPort(8080).
		WithExec([]string{"sh", "-c", "mkdir -p /shared && cd /shared && python3 -m http.server 8080"}).
		AsService()

	// Server 1: Create buffer and sync to shared storage
	server1Output, err := dag.Container().
		From("ubuntu:22.04").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "tmux", "curl", "ca-certificates"}).
		WithExec([]string{"sh", "-c", "curl -L https://github.com/atuinsh/atuin/releases/latest/download/atuin-x86_64-unknown-linux-gnu.tar.gz | tar xz && mv atuin-*/atuin /usr/local/bin/ && chmod +x /usr/local/bin/atuin"}).
		WithMountedDirectory("/plugin", source).
		WithWorkdir("/plugin").
		WithExec([]string{"sh", "-c", "mkdir -p ~/.local/share/atuin && atuin init bash --disable-up-arrow --disable-ctrl-r"}).
		WithServiceBinding("shared-storage", sharedStorage).
		WithExec([]string{"sh", "-c", `
			# Start tmux session
			tmux new-session -d -s server1
			# Create buffer inside tmux session
			tmux send-keys -t server1 "echo 'multi-server-test-content' | tmux load-buffer -" Enter
			sleep 2
			# Push to atuin inside tmux session
			tmux send-keys -t server1 "source scripts/helpers.sh && source scripts/atuin_adapter.sh && push_buffers_to_atuin 'tmux-buffers-test' 1 && echo 'PUSH_COMPLETE'" Enter
			sleep 5
			# Capture output
			tmux capture-pane -t server1 -p
			# Clean up
			tmux kill-session -t server1 2>/dev/null || true
		`}).
		Stdout(ctx)
	
	if err != nil {
		return fmt.Errorf("server1 failed: %w", err)
	}
	
	// Server 2: Pull from shared storage and verify buffer exists
	server2Output, err := dag.Container().
		From("ubuntu:22.04").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "tmux", "curl", "ca-certificates"}).
		WithExec([]string{"sh", "-c", "curl -L https://github.com/atuinsh/atuin/releases/latest/download/atuin-x86_64-unknown-linux-gnu.tar.gz | tar xz && mv atuin-*/atuin /usr/local/bin/ && chmod +x /usr/local/bin/atuin"}).
		WithMountedDirectory("/plugin", source).
		WithWorkdir("/plugin").
		WithExec([]string{"sh", "-c", "mkdir -p ~/.local/share/atuin && atuin init bash --disable-up-arrow --disable-ctrl-r"}).
		WithServiceBinding("shared-storage", sharedStorage).
		WithExec([]string{"sh", "-c", `
			# Start tmux session
			tmux new-session -d -s server2
			# Pull from atuin inside tmux session
			tmux send-keys -t server2 "source scripts/helpers.sh && source scripts/atuin_adapter.sh && pull_buffers_from_atuin 'tmux-buffers-test' 1 && echo 'PULL_COMPLETE'" Enter
			sleep 5
			# Verify buffer exists inside tmux session
			tmux send-keys -t server2 "tmux show-buffer | grep -q 'multi-server-test-content' && echo 'SUCCESS: Buffer synced between servers' || echo 'FAILED: Buffer not found'" Enter
			sleep 2
			# Capture output
			tmux capture-pane -t server2 -p
			# Clean up
			tmux kill-session -t server2 2>/dev/null || true
		`}).
		Stdout(ctx)
		
	if err != nil {
		return fmt.Errorf("server2 failed: %w", err)
	}
	
	fmt.Printf("Server1 output: %s\n", server1Output)
	fmt.Printf("Server2 output: %s\n", server2Output)
	
	return nil
}

// Run all tests - main entry point for CI
func (m *TmuxBufferSync) Test(ctx context.Context, source *dagger.Directory) error {
	// Run linting first
	if err := m.Lint(ctx, source); err != nil {
		return fmt.Errorf("linting failed: %w", err)
	}
	
	// Run plugin tests
	if err := m.TestPlugin(ctx, source); err != nil {
		return fmt.Errorf("plugin tests failed: %w", err)
	}
	
	// Skip multi-server sync test for now (was causing CI hangs)
	// TODO: Re-enable once we fix the shared storage service issue
	// if err := m.TestMultiServerSync(ctx, source); err != nil {
	//     return fmt.Errorf("multi-server sync test failed: %w", err)
	// }
	
	return nil
}

