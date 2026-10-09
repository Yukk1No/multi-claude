#!/usr/bin/env bash
# Linux end-to-end tests with a fake Claude desktop entry; no Claude needed. Run: bash tests/linux.sh
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cli=$repo/src/linux/multi-claude
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_DATA_HOME=$tmp/data XDG_CONFIG_HOME=$tmp/config
failed=0
check()   { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; failed=1; fi; }
exit_is() { "$cli" "${@:2}" >/dev/null 2>&1; [ $? -eq "$1" ]; }

# A fake Claude: a desktop entry and a synthetic orange icon.
mkdir -p "$XDG_DATA_HOME/applications"
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import recolor; \
recolor.write_png(sys.argv[2], 32, 32, [[(217, 119, 87, 255)] * 32 for _ in range(32)])" \
  "$repo/src/linux" "$tmp/claude.png"
printf '[Desktop Entry]\nName=Claude\nExec=/usr/bin/claude-desktop %%U\nIcon=%s\n' "$tmp/claude.png" \
  > "$XDG_DATA_HOME/applications/claude-desktop.desktop"
entry=$XDG_DATA_HOME/applications/multi-claude-work.desktop

echo linux
check 'help exits 0'                        'exit_is 0 help'
check 'version works in any position'       'exit_is 0 add -v'
check 'unknown command exits 64'            'exit_is 64 frobnicate'
check 'unknown option exits 64'             'exit_is 64 add Work --bogus'
check 'invalid name exits 64'               'exit_is 64 add "a b"'
check 'invalid color exits 64'              'exit_is 64 add Work --color banana'
check 'missing color exits 64'              'exit_is 64 add Work --color'
check 'extra argument exits 64'             'exit_is 64 add Work extra'
check 'add creates the desktop entry'       'exit_is 0 add Work --color blue && [ -f "$entry" ]'
check 'entry uses its own data folder'      'grep -q -- "--user-data-dir=$XDG_CONFIG_HOME/Claude-Work" "$entry"'
check 'entry drops field codes'             '! grep -q "%U" "$entry"'
check 'entry id matches its window class'   'grep -q "^StartupWMClass=multi-claude-work$" "$entry" && grep -q -- "--class=multi-claude-work" "$entry"'
check 'icon was recolored'                  '[ -f "$XDG_DATA_HOME/multi-claude/profiles/Work/icon.png" ]'
check 'same name in another case is refused' 'exit_is 64 add work'
check 'list shows the profile'              '"$cli" list | grep -q "^Work "'
check 'removing an unknown profile exits 1' 'exit_is 1 remove Nope'
check 'remove finds the profile in any case' 'exit_is 0 remove work && [ ! -f "$entry" ] && [ ! -d "$XDG_DATA_HOME/multi-claude/profiles/Work" ]'
check 'uninstall cleans up'                 'exit_is 0 add Two && exit_is 0 uninstall && [ ! -d "$XDG_DATA_HOME/multi-claude" ] && ! ls "$XDG_DATA_HOME/applications" | grep -q multi-claude'
if [ $failed -eq 0 ]; then echo 'all tests passed'; fi
exit $failed
