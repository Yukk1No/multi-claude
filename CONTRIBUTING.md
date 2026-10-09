# Contributing

Thanks for helping. multi-claude stays small on purpose: plain scripts, no runtime dependencies, no
admin rights, and the official Claude app is never modified.

## Layout

```
install.ps1, install.sh   one-line installers (versioned download + SHA-256 check)
src/windows/              multi-claude.ps1 (CLI) and MultiClaude.cs (taskbar, shortcut and icon interop)
src/macos/                multi-claude (zsh CLI) and recolor.js (Core Image)
src/linux/                multi-claude (bash CLI) and recolor.py (standard-library PNG recolor)
tests/                    one suite per system; none needs Claude installed
docs/                     how it works, troubleshooting
assets/                   images for the README and the social preview
```

## Run the tests

```sh
powershell -ExecutionPolicy Bypass -File tests\windows.tests.ps1   # Windows
zsh tests/macos.sh                                                 # macOS
python3 -m unittest discover -s tests                              # any system with Python 3
bash tests/linux.sh                                                # Linux
```

CI runs all of them on every pull request, plus PSScriptAnalyzer, ShellCheck and Ruff, and installs
from the checkout on macOS and Linux.

## Guidelines

- Keep the three CLIs in step: same commands, options, messages and exit codes
  (`0` ok, `1` failure, `3` wrong context, `64` bad usage).
- Never add Claude artwork to the repository; icons are generated on the user's computer.
- When you change how profiles launch or how the taskbar behaves, test on a real machine and say
  which one in the pull request.

## Releasing

1. Move the `[Unreleased]` notes in `CHANGELOG.md` under a new version heading.
2. Set the same version in `src/windows/multi-claude.ps1`, `src/macos/multi-claude` and
   `src/linux/multi-claude`.
3. Push a tag such as `v0.2.0`. The release workflow runs the tests, checks the versions, stamps the
   installers with the version and checksums, and publishes the release with provenance.
