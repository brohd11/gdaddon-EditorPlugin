# gdaddon - Godot EditorPlugin

Small companion plugin for [gdaddon](https://github.com/brohd11/gdaddon) package manager. It runs a check for updates once a day per project you open.

If you don't have gdaddon:
```bash
# on PATH (~/.local/bin by default)
curl -fsSL https://raw.githubusercontent.com/brohd11/gdaddon/main/install.sh | sh
```

When enabled, the plugin waits 10 seconds after editor startup, then runs
`gdaddon list --json --updates` in a background thread. Updates or missing dependencies
give a notification.

Each project checks once every 24 hours (including failed check).
Timestamp is stored in `res://.godot/addons/gdaddon/last_check`, local to the project.

## Editor Console

If you have Editor Console in your project, you can install one copy of the plugin inside ~/.gdaddon/ instead of needing a copy in every project. It can then trigger from `~/.gdrc` a rc style file that is read everytime the editor starts.

### Quick Install
You can paste this into Editor Console v0.8+ (new lines are converted automatically) to install the script, create `~/.gdrc` if it doesn't exist, and add the command to the file if it isn't there yet. Change "check$" to "check_verbose" if you prefer the full print out.

```sh
local check_cmd=$(GDAddonPlugin call install | grep --regex check$); [ "$check_cmd" == "" ] && exit 1
echo "Installed script to $(echo $check_cmd | utils str slice call 0)"
home >discard || exit 1; local gdrc="$(home)/.gdrc"
[ -f "$gdrc" ] && cat "$gdrc" | utils str contains "$check_cmd" >discard && exit 0
echo "$check_cmd" >> "$gdrc"
echo "Added $check_cmd to $gdrc"
```

There are a couple more functions in the plugin script that are callable from the console.
```sh
GDAddonPlugin call install # adds 'check.gd' to ~/.gdaddon/editor_plugin/check.gd
GDAddonPlugin call run_check # run a verbose check
GDAddonPlugin call reset_check # reset the 24 hour timestamp
```

These are the commands returned by `GDAddonPlugin call install` and added to `~/.gdrc`.

```sh
"/home/you/.gdaddon/editor_plugin/check.gd" call check # simple notification
"/home/you/.gdaddon/editor_plugin/check.gd" call check_verbose # prints all updates or missing dependencies
```
