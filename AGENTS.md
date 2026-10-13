# AGENTS.md

Guidance for coding agents working on this repository. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md).

## What this is

multi-claude runs several Claude Desktop accounts side by side. A profile is the official app started
with its own `--user-data-dir`; icons are recolored from the installed logo; on Windows a hidden
watcher tags the profile's windows with AppUserModelID `MultiClaude.<name>`. Read
[docs/how-it-works.md](docs/how-it-works.md) before changing behavior.

## Commands

```sh
powershell -ExecutionPolicy Bypass -File tests\windows.tests.ps1   # Windows tests
zsh tests/macos.sh                                                 # macOS tests
python3 -m unittest discover -s tests                              # recolor unit tests
bash tests/linux.sh                                                # Linux end-to-end tests
ruff check .                                                       # Python lint
shellcheck install.sh src/linux/multi-claude tests/linux.sh
```

## Rules

- The three CLIs (`src/windows`, `src/macos`, `src/linux`) expose the same commands, options, messages
  and exit codes (`0` ok, `1` failure, `64` bad usage, and on Windows `3` for a terminal inside an app
  package). Change them together.
- No runtime dependencies: PowerShell 5.1 + C# 5 on Windows, zsh and built-in tools on macOS, bash and
  `python3` (standard library) on Linux.
- Never commit Claude artwork, icons generated from it, or anything identifying a user.
- `install.ps1` and `install.sh` must keep their `__VERSION__` and `__SHA256__` placeholders; the
  release workflow fills them in.
- Keep the README short. Details belong in `docs/`.
