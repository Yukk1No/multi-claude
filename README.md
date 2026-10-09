<div align="center">

<img src="assets/social-preview.png" alt="multi-claude: several Claude Desktop accounts, side by side" width="720">

# multi-claude

**Run multiple Claude Desktop accounts at once.**<br>
Work and personal, each with its own sign-in, its own colored icon and its own taskbar button.<br>
Like browser profiles, for Claude.

[![CI](https://github.com/thomasog/multi-claude/actions/workflows/ci.yml/badge.svg)](https://github.com/thomasog/multi-claude/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/thomasog/multi-claude)](https://github.com/thomasog/multi-claude/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
<br>
![Windows: stable](https://img.shields.io/badge/Windows-stable-0078D4)
![macOS: beta](https://img.shields.io/badge/macOS-beta-555555)
![Linux: experimental](https://img.shields.io/badge/Linux-experimental-E95420)

</div>

<!-- Screenshot: the taskbar with two or three colored profile buttons pinned next to Claude.
     Add it as assets/taskbar.png and show it here. -->

Claude Desktop signs in to one account at a time. multi-claude adds **profiles**: each profile is the
official app opened with its own data folder, so it keeps its own login. Open them side by side, pin
them next to each other, tell them apart by color.

- **The official app, untouched.** Nothing is patched or copied, so Claude's updates keep working.
- **No artwork shipped.** Each icon is recolored from the Claude logo already on your computer.
- **Its own taskbar button on Windows**, instead of one more window stacked on the regular Claude.
- **Small and readable.** Plain scripts, no dependencies, no admin rights.

## Requirements

- **Windows 10 or 11** with Claude Desktop from [claude.ai/download](https://claude.ai/download).
- **macOS** with Claude in `/Applications`.
- **Linux** with the official Claude Desktop package for Ubuntu or Debian, and `python3`.

## Install

**Windows**, in PowerShell:

```powershell
irm https://github.com/thomasog/multi-claude/releases/latest/download/install.ps1 | iex
```

**macOS and Linux**, in a terminal:

```sh
curl -fsSL https://github.com/thomasog/multi-claude/releases/latest/download/install.sh | sh
```

The installer asks for your first profile's name and color. It installs for your user only, and
checks the download against the SHA-256 recorded in the release. Every script is in this repository
if you'd like to read it first.

## Use

```sh
multi-claude add Work --color blue    # a new profile, in the Start menu, Applications or app launcher
multi-claude list                     # your profiles
multi-claude open Work                # open one (its launcher does the same)
multi-claude remove Work              # remove it; its sign-in data is kept
multi-claude doctor                   # check this computer (Windows: doctor --selftest)
```

Colors: `green` `blue` `purple` `red` `teal` `pink` `gray`, or any hex value such as `C0392B`.

> [!IMPORTANT]
> **First sign-in:** quit the regular Claude before you sign in to a new profile. Sign-in comes back
> through a `claude://` link, and your system hands it to whichever Claude is open. You only do this
> once per profile.

## FAQ

**Can I use Claude Code in every profile at once?**
Yes. Each profile has its own account and session list. All profiles share your `~/.claude` folder:
settings, skills, memory and the history of Claude Code sessions.

**Do profiles combine usage limits?**
No. Each profile is simply signed in to its own account, with that account's plan and limits.

**Does it work with Cowork?**
On Windows, Cowork runs in one profile at a time, because Windows allows one Cowork VM per user.

**Why does the Dock show the regular icon on macOS?**
The colored icon belongs to the profile's launcher. The running app is Claude itself, so macOS shows
Claude's icon.

**How do I update?**
Run the install command again. To refresh a profile's icon, run `multi-claude add` with the same name.

More: [how it works](docs/how-it-works.md) · [troubleshooting](docs/troubleshooting.md)

## Uninstall

```sh
multi-claude uninstall
```

Your profiles' sign-in data stays in `%LOCALAPPDATA%\Claude-*` (Windows),
`~/Library/Application Support/Claude-*` (macOS) or `~/.config/Claude-*` (Linux). Delete those
folders to sign out for good.

---

<sub>multi-claude is an independent project, not affiliated with or endorsed by Anthropic. Claude is
a trademark of Anthropic. [MIT License](LICENSE).</sub>
