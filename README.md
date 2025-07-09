# tmux-buffer-sync

**NOTE THIS IS NOT FULLY FUNCTIONAL**

[![CI](https://github.com/cosgroveb/tmux-buffer-sync/workflows/CI/badge.svg)](https://github.com/cosgroveb/tmux-buffer-sync/actions)

A tmux plugin that synchronizes copy buffers across multiple servers using [atuin](https://atuin.sh/)'s [kv storage](https://blog.atuin.sh/release-v16/). Share clipboard content between tmux sessions running on different machines.

- 🔄 **Bidirectional sync**: Pushes local buffers to remote storage and pulls remote buffers
- ⚡ **Automatic sync**: Periodic sync and immediate sync on copy

## Install

### First make sure you have:

- ✨🐢 **[atuin](https://atuin.sh/)** Magical Shell History

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

1.  **Test basic functionality**:
   ```bash
   # Copy something to a buffer
   echo "test sync" | tmux load-buffer -

   # Trigger manual sync
   :buffer-sync-now

   # Check status
   :buffer-sync-status
   ```

3.  **Verify cross-server sync** (on another machine with same atuin account):
   ```bash
   # Pull buffers from remote
   :buffer-sync-now

   # Check if buffer is available
   tmux show-buffer
   ```

## How Sync Works

### Buffer Sync Behavior

tmux-buffer-sync follows a **"last writer wins"** strategy:

- **Push**: Copies your local tmux buffers to remote storage, **overwriting** any existing remote buffers
- **Pull**: Copies remote buffers to your local tmux, **adding** to your existing buffers
- **Bidirectional sync**: Performs both push and pull operations

### Important Notes

⚠️ **No merging**: When you push buffers, remote buffers from other servers are completely replaced with your local buffers. This means:

- If **Server A** pushes 3 buffers, then **Server B** pushes 2 buffers → remote storage only contains Server B's 2 buffers
- **Server A's buffers are lost** unless Server A pulls before pushing again
- For best experience, sync frequently or use automatic sync to minimize buffer loss

### Sync Triggers

- **Automatic**: Every `@buffer-sync-frequency` seconds (default: 15s)
- **Copy hooks**: Immediate sync when you copy content (can be disabled)
- **Manual**: Use `:buffer-sync-now` command anytime

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

# Enable debug mode to see sync notifications (default: off)
set -g @buffer-sync-debug on
```

### Debug Mode

The plugin includes a debug mode that displays notifications when sync operations occur:

```bash
# Enable debug mode in tmux.conf
set -g @buffer-sync-debug on
```

When debug mode is enabled, you'll see tmux notifications for:
- **Manual sync**: Triggered by `:buffer-sync-now`
- **Timer sync**: Automatic periodic synchronization
- **Copy sync**: Immediate sync after copy operations

### Manual Commands

Use these tmux commands for manual control:

```bash
# ⚡ Trigger immediate sync
:buffer-sync-now

# Show sync status and configuration
:buffer-sync-status
```
