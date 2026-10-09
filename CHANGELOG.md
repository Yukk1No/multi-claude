# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

### Added

- `multi-claude add | list | open | remove | doctor | uninstall` on Windows, macOS (beta) and Linux
  (experimental).
- Profiles: the official Claude Desktop with its own `--user-data-dir`, so each keeps its own sign-in.
- Icons recolored from the installed Claude logo, in seven named colors or any hex value.
- Windows: each profile gets its own taskbar button through AppUserModelID tagging.
- Installers that download a versioned release and verify it against the SHA-256 written into them,
  with build provenance attestations.

[Unreleased]: https://github.com/thomasog/multi-claude/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/thomasog/multi-claude/releases/tag/v0.1.0
