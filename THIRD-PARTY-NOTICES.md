# Third-party notices / 第三方说明

This project's MIT license covers its automation scripts and documentation. Third-party components retain the notices below.

## PAKTool and Common.dll

- Author / copyright: N3rdL0rd, Copyright (c) 2024.
- Source: https://github.com/N3rdL0rd/alivecells/tree/paktool-v0.1a
- Original release: https://github.com/N3rdL0rd/alivecells/releases/tag/paktool-v0.1a
- License: MIT; full upstream text is in `licenses/alivecells-MIT.txt`.
- `ResTool/PAKTool.exe` and `ResTool/Common.dll` are unchanged files extracted from `PAKTool-alivecells-0.1a.zip`. Their checksums are recorded in `dependencies.sha256`.
- The upstream tool identifies itself as N3rdL0rd's PakTool v0.1a, based on ModTools v1.7.0. No game assets are included.

## Newtonsoft.Json

- Author / copyright: James Newton-King, Copyright (c) 2007.
- Project: https://github.com/JamesNK/Newtonsoft.Json
- Included binary: Newtonsoft.Json 11.0.2 (.NET assembly version 11.0.0.0), provided for the legacy PAKTool dependency.
- License: MIT; full upstream text is in `licenses/Newtonsoft.Json-MIT.txt`.
- SHA-256 is in `dependencies.sha256`. The binary is used locally by the legacy tool, not to deserialize network-provided application settings.

The dependency notices do not license Dead Cells, its assets, or third-party Workshop mods. Obtain game and Workshop content separately from their authorized sources.
