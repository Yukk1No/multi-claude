#!/bin/zsh
# macOS tests: argument handling and the Core Image recolor; no Claude needed. Run: zsh tests/macos.sh
set -uo pipefail
repo=${0:A:h:h}
cli=$repo/src/macos/multi-claude
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
check()   { if eval "$2"; then print "  ok   $1"; else print "  FAIL $1"; failed=1; fi; }
exit_is() { zsh "$cli" "${@:2}" >/dev/null 2>&1; [[ $? -eq $1 ]]; }

print macos
check 'script parses'                       'zsh -n "$cli"'
check 'help exits 0'                        'exit_is 0 help'
check 'version works in any position'       'exit_is 0 add -v'
check 'unknown command exits 64'            'exit_is 64 frobnicate'
check 'unknown option exits 64'             'exit_is 64 add Work --bogus'
check 'invalid name exits 64'               'exit_is 64 add "a b"'
check 'invalid color exits 64'              'exit_is 64 add Work --color banana'
check 'missing color exits 64'              'exit_is 64 add Work --color'
check 'extra argument exits 64'             'exit_is 64 add Work extra'
check 'removing an unknown profile exits 1' 'exit_is 1 remove NoSuchProfile'

# Recolor a synthetic orange PNG and check that the background lands near the target hue.
python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import recolor; \
recolor.write_png(sys.argv[2], 32, 32, [[(217, 119, 87, 255)] * 32 for _ in range(32)])" \
  "$repo/src/linux" "$tmp/source.png"
check 'recolor.js writes a PNG' 'osascript -l JavaScript "$repo/src/macos/recolor.js" "$tmp/source.png" "$tmp/out.png" 1F4E8C && [[ -s $tmp/out.png ]]'
check 'recolor reaches the target hue' 'python3 - "$repo/src/linux" "$tmp/out.png" <<"PY"
import colorsys, sys
sys.path.insert(0, sys.argv[1])
import recolor
r, g, b, _ = recolor.read_png(sys.argv[2])[2][16][16]
hue = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0] * 360
print(f"       background hue {hue:.0f}, target 214")
sys.exit(0 if abs(hue - 214) < 25 else 1)
PY'
(( failed == 0 )) && print 'all tests passed'
exit $failed
