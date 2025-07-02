// Dagger module for tmux-buffer-sync CI/CD pipeline

package main

import (
	"context"
	"dagger/tmux-buffer-sync/internal/dagger"
	"fmt"
)

type TmuxBufferSync struct{}

// Test the plugin
func (m *TmuxBufferSync) TestPlugin(ctx context.Context, source *dagger.Directory) error {
	_, err := dag.Container().
		From("ubuntu:22.04").
		WithExec([]string{"apt-get", "update"}).
		WithExec([]string{"apt-get", "install", "-y", "tmux", "curl", "ca-certificates", "git"}).
		WithExec([]string{"sh", "-c", `
			ARCH=$(uname -m)
			if [ "$ARCH" = "x86_64" ]; then
				ATUIN_ARCH="x86_64-unknown-linux-gnu"
			elif [ "$ARCH" = "aarch64" ]; then
				ATUIN_ARCH="aarch64-unknown-linux-gnu"
			else
				echo "Unsupported architecture: $ARCH"
				exit 1
			fi
			curl -L "https://github.com/atuinsh/atuin/releases/latest/download/atuin-${ATUIN_ARCH}.tar.gz" | tar xz && mv atuin-*/atuin /usr/local/bin/ && chmod +x /usr/local/bin/atuin
		`}).
		WithMountedDirectory("/plugin", source).
		WithWorkdir("/plugin").
		WithExec([]string{"sh", "-c", "mkdir -p ~/.local/share/atuin && atuin init bash --disable-up-arrow --disable-ctrl-r"}).
		WithExec([]string{"sh", "-c", `
			# Install BATS
			git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
			cd /tmp/bats-core && ./install.sh /usr/local
		`}).
		WithExec([]string{"sh", "-c", `
			# Run BATS tests
			echo "✓ Running BATS end-to-end tests"
			bats tests/test_end_to_end.bats --tap
		`}).
		Stdout(ctx)

	return err
}

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

// Run all tests - main entry point for CI
func (m *TmuxBufferSync) Test(ctx context.Context, source *dagger.Directory) error {
	// Lint
	if err := m.Lint(ctx, source); err != nil {
		return fmt.Errorf("linting failed: %w", err)
	}

	// Test
	if err := m.TestPlugin(ctx, source); err != nil {
		return fmt.Errorf("plugin tests failed: %w", err)
	}

	return nil
}
