# Dead Cells Local Mod Installer

[简体中文](README.md) · [Download](https://github.com/Sukana-Zhang/DeadCellsLocalModInstaller/releases/latest)

Repackage locally downloaded Steam Workshop mods for **Dead Cells** into numbered resource archives (`res1.pak`, `res2.pak`, …), in the order you choose. The original `res.pak` and save files are not modified. This is a packaging utility, not a mod containing game content.

## Quick start

For the Steam edition on Windows 10/11 with Windows PowerShell 5.1. The included PAKTool uses .NET Framework; check that .NET Framework 4.8 is available if it will not launch. Repackaging currently targets stamped v1 game archives (v35 and later); future format changes may require updates.

1. Subscribe to the mods in Steam Workshop and wait for the downloads to finish. Close the game.
2. Download the ZIP from [Releases](https://github.com/Sukana-Zhang/DeadCellsLocalModInstaller/releases/latest). Extract everything to a writable, permanent folder.
3. Double-click `InstallLocalMods.cmd`. Choose `1` to install. Select an installation if several are detected.
4. Enter mod numbers in the desired order, for example `1,3,2`. The list is sorted by local modification time; check names before every installation.
5. Launch the game normally through Steam. Do not enable the same mods a second time in the in-game Workshop menu.

Console prompts are currently Chinese: `1` installs, `2` removes, and `安装顺序` asks for comma-separated mod numbers. The first chosen mod becomes `res1.pak`, the second `res2.pak`, and so on. Later archives may override earlier resources. Conflicting mods are not automatically merged.

## Backups and removal

All selected packages are prepared before existing files are changed. Existing numbered archives are copied and checksum-verified in `Backups/LocalModBackup-<time>-<unique-id>/`, beside the installer. Handled file-publication errors trigger restoration of the previous files. Power loss, forced termination or disk failure can still require manual recovery.

Choose `2` to back up and remove all numbered archives. **All `resN.pak` files, N ≥ 1, are managed**, including packages installed by other tools. The base `res.pak` is left untouched.

To restore an older setup: close the game, keep a separate copy of its current numbered archives, then copy `resN.pak` from the selected backup folder back into the game folder. Keep the installer's backups and maintain separate save backups.

## Command line

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\InstallLocalMods.ps1 -Action Install -Order "1,3,2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\InstallLocalMods.ps1 -Action Remove
```

Override discovery for custom locations (replace these example paths):

```powershell
.\InstallLocalMods.ps1 -Action Install -Order "1" -SteamDirectory "E:\Steam" -GameDirectory "E:\Steam\steamapps\common\Dead Cells"
```

`-SteamDirectory` identifies a Steam library containing `steamapps`; mods should be under `steamapps/workshop/content/588650/`. `-GameDirectory` identifies the folder containing the game's original `res.pak`. Invalid preset order values fail without entering an input loop.

## Troubleshooting

- No mods found: finish the Steam downloads; each supported mod needs a `res.pak` or `res1.pak`.
- Tool fails to start: extract all files, check .NET Framework 4.8 and folder permissions, and run the command above to read the error.
- Game detected as running: close `deadcells.exe` / `deadcells_gl.exe` first.
- Interrupted install or game error: keep `Backups/`, remove or restore numbered archives, then test mod compatibility individually.
- Access denied: check write permission for the tool and game folders. The CMD launcher only sets execution policy for its PowerShell process; it does not change the system-wide policy.

## Source and verification

`InstallLocalMods.ps1` contains the automation source. Third-party origins, hashes and licenses are documented in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). No game resources, Workshop content, saves, personal logs, backups or credentials are published.

```powershell
.\Test-InstallLocalMods.ps1
.\Test-Functional.ps1
.\package.ps1
```

Tests use synthetic archives and fake Steam directories under `build/` only. They exercise real packing roundtrips, order validation, backup, install, removal and handled failure recovery without discovering or modifying real game installations. CI tests Windows PowerShell 5.1 and PowerShell 7 on Windows Server 2022/2025. Not every Windows 10/11 PC, game version or mod combination has been tested.

## License

Project scripts and documentation use the [MIT License](LICENSE). PAKTool, Common.dll and Newtonsoft.Json retain their upstream MIT notices; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Dead Cells and game content belong to their respective owners. This project is not affiliated with the game's developers or Valve.
