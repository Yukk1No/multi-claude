# How it works

## One app, one data folder per profile

Claude Desktop is an Electron app. Electron allows one running instance per **data folder** and keeps
the sign-in inside that folder. Starting the official app with `--user-data-dir=<folder>` therefore
gives a second, fully separate instance with its own login. That is all a profile is.

| System  | Profile data                                  | Launcher                                                  |
|---------|-----------------------------------------------|-----------------------------------------------------------|
| Windows | `%LOCALAPPDATA%\Claude-<name>`                | Start menu shortcut `Claude <name>`                       |
| macOS   | `~/Library/Application Support/Claude-<name>` | `~/Applications/Claude <name>.app`                        |
| Linux   | `~/.config/Claude-<name>`                     | `~/.local/share/applications/multi-claude-<name>.desktop` |

Nothing inside Claude changes, so app updates apply to every profile.

## Colored icons

`add` takes the Claude icon already installed on the computer and recolors it, so no artwork ships
with this project.

- **Windows and Linux** use the same algorithm: every colored pixel takes the target hue, saturation
  and brightness are scaled so the logo's brand color lands exactly on the target, and the white
  glyph stays white. Windows does it in C# (`System.Drawing`, compiled in memory) and writes a
  multi-size `.ico`; Linux does it with a small standard-library Python PNG reader and writer.
- **macOS** gets close with built-in Core Image filters (hue, saturation, gamma), run through
  JavaScript for Automation, then builds the `.icns` with `sips` and `iconutil`.

## Its own taskbar button (Windows)

Windows groups taskbar buttons by **AppUserModelID**, and every Claude window declares the same one,
so a second profile would otherwise stack onto the regular Claude button. A profile's Start menu
shortcut carries the ID `MultiClaude.<name>` and runs `multi-claude open <name>`, which:

1. starts Claude with the profile's data folder (if the profile is already open, Claude focuses it);
2. keeps running, hidden, and gives the profile's windows the same ID and relaunch properties, so
   the window and its pinned button become one colored button;
3. exits when the profile closes. Each profile has at most one watcher.

If tagging ever fails, the window simply appears under the regular Claude button.

## Sign-in

Sign-in finishes in the browser and returns through a `claude://` link. The system gives that link
to the Claude that registered it, usually the regular one, so the regular Claude must be closed
during a profile's first sign-in. After that, each profile keeps its own login.

## Installation

The install commands download a versioned release archive. The release workflow writes that version
and the archive's SHA-256 into the installer itself, so the installer only accepts the exact archive
it was published with, and the release carries a build provenance attestation. Everything installs
in your user folder; nothing needs admin rights.

Plain scripts were chosen over a compiled installer: an unsigned executable triggers SmartScreen and
antivirus heuristics, and every new build starts with no reputation. Scripts can be read before they
run.
