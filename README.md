# gdaddon - Godot EditorPlugin

Checks for addon updates and missing dependencies using the gdaddon package manager.

When enabled, the plugin waits 10 seconds after editor startup, then runs
`gdaddon list --json --updates` in a background thread. Updates or missing dependencies
give a notification.

Each project checks once every 24 hours (including failed check).
Timestamp is stored in `res://.godot/addons/gdaddon/last_check`, local to the project.

## Requires the gdaddon binary

The plugin shells out to `gdaddon`, so install that first. It looks for `gdaddon` on your
PATH, then falls back to `~/.gdaddon/bin/gdaddon`:

```bash
# on PATH (~/.local/bin by default)
curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh

# or the no-PATH location this plugin falls back to
BIN_DIR="$HOME/.gdaddon/bin" curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh
```