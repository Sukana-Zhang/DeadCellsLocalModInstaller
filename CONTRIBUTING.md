# Contributing

Use Windows PowerShell 5.1 or PowerShell 7 on Windows. Run `Test-InstallLocalMods.ps1`, `Test-Functional.ps1` and `package.ps1` before submitting changes. Tests use synthetic PAK archives in isolated directories under `build/`; they must not modify or discover real Steam libraries.

Never commit game assets, Workshop mods, saves, backups, logs, API keys, credentials or machine-specific paths. Use the package allowlist when creating releases. Keep the Chinese and English guides consistent and retain upstream license notices.

For a release, update `VERSION` and `CHANGELOG.md`, wait for Windows CI to pass, and push a matching `vX.Y.Z` tag. The release workflow publishes a ZIP and its SHA-256 checksum after both Windows jobs succeed.
