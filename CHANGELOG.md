# Changelog

## 1.0.1 — 2026-10-30

- Add UTF-8 structured logs with run IDs, stages, native exit codes, errors, backup and rollback outcomes; rotate at 1 MiB with one previous log.
- Add menu item 3 and `-Action ExportLogs` for bounded diagnostic TXT exports. Redact user profiles, user SIDs and native stamp output. No automatic uploads.
- Fix removal unnecessarily depending on PAKTool and Steam discovery when an explicit game directory is provided.
- Lock the game directory across copies of the tool; include hidden numbered archives in backup/removal.
- Preserve the actual result when temporary cleanup fails and preserve the failure exit code in the CMD launcher.
- Capture native stdout/stderr independently and use the native exit code to determine success; fix quoting for paths with spaces, quotes and trailing backslashes.
- Respect explicit Steam-directory overrides, support legacy Steam library entries and stabilize equal-date mod ordering.
- Add diagnostics and real-entry-point regression coverage alongside the existing 24 functional checks.

## 1.0.0 — 2026-10-30

- Public release of the local Workshop-mod repackaging workflow.
- Steam discovery, ordered installation, checksum-verified backups and removal.
- Stage all packages before changing the installation; restore previous files on handled publication errors.
- Unique temporary/backup directories, concurrent-run lock, game-running check and explicit directory overrides.
- Chinese and English guides, original upstream PAKTool binaries, dependency hashes and bundled license notices.
- Synthetic archive roundtrip and failure-recovery tests on Windows PowerShell 5.1 and PowerShell 7.
