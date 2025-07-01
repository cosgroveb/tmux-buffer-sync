# tmux-buffer-sync

[![CI](https://github.com/cosgroveb/tmux-buffer-sync/workflows/CI/badge.svg)](https://github.com/cosgroveb/tmux-buffer-sync/actions)

A tmux plugin that synchronizes copy buffers across multiple servers using [atuin](https://atuin.sh/)'s [kv storage](https://blog.atuin.sh/release-v16/). Share clipboard content between tmux sessions running on different machines.

- **Bidirectional sync**: Pushes local buffers to remote storage and pulls remote buffers
- **Automatic sync**: Periodic sync and immediate sync on copy

## Installation

### Prerequisite:

- **[atuin](https://atuin.sh/)** Magical Shell History ✨🐢

### Using TPM

1. **Add tmux-buffer-sync to your `~/.tmux.conf`** (before the `run '~/.tmux/plugins/tpm/tpm'` line):
   ```bash
   set -g @plugin 'cosgroveb/tmux-buffer-sync'
   ```

2. **Reload tmux configuration**:
   ```bash
   tmux source-file ~/.tmux.conf
   ```

3. **Install the plugin**:

    Press prefix + I (capital i, as in Install) to fetch the plugin.

### Manual Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/cosgroveb/tmux-buffer-sync ~/.tmux/plugins/tmux-buffer-sync
   ```

2. **Add to your `~/.tmux.conf`**:
   ```bash
   run '~/.tmux/plugins/tmux-buffer-sync/buffer-sync.tmux'
   ```

3. **Reload tmux configuration**:
   ```bash
   tmux source-file ~/.tmux.conf
   ```

### Verification

After installation, verify the plugin is working:

1. **Test basic functionality**:
   ```bash
   # Copy something to a buffer
   echo "test sync" | tmux load-buffer -

   # Trigger manual sync
   :buffer-sync-now

   # Check status
   :buffer-sync-status
   ```

3. **Verify cross-server sync** (on another machine with same atuin account):
   ```bash
   # Pull buffers from remote
   :buffer-sync-now

   # Check if buffer is available
   tmux show-buffer
   ```

## Configuration

Add these options to your `~/.tmux.conf` to customize the plugin:

```bash
# Number of buffers to sync (default: 10)
set -g @buffer-sync-count 15

# Sync frequency in seconds (default: 15)
set -g @buffer-sync-frequency 30

# Storage namespace for isolation (default: 'tmux-buffers')
set -g @buffer-sync-namespace 'my-buffers'

# Disable copy operation hooks for immediate sync (default: on)
set -g @buffer-sync-copy-hooks off
```

### Manual Commands

Use these tmux commands for manual control:

```bash
# Trigger immediate sync
:buffer-sync-now

# Show sync status and configuration
:buffer-sync-status
```
