.PHONY: test check help

# Default target
help:
	@echo "tmux-buffer-sync Makefile targets:"
	@echo "  make test   - Run end-to-end tests"
	@echo "  make check  - Run shellcheck on all shell scripts"
	@echo "  make help   - Show this help message"

test:
	@echo "Running end-to-end tests..."
	@bash tests/test_end_to_end.sh

check:
	@echo "Running shellcheck..."
	@find . -name "*.sh" -type f | xargs shellcheck
	@shellcheck buffer-sync.tmux
	@echo "✓ All shell scripts passed shellcheck"
