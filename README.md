# Dead Cells Local Mod Installer

将 Steam 创意工坊下载的《Dead Cells / 死亡细胞》Mod 重新打包为本地资源包，生成 `res1.pak`、`res2.pak`、`res3.pak` 等文件，并复制到游戏本体目录。

## 功能

- 自动查找 Steam 库、Dead Cells 安装目录和 Workshop Mod。
- 从游戏本体 `res.pak` 头部提取当前 64 位打包密钥。
- 按用户指定顺序重新打包多个 Mod。
- 安装前自动备份已有的本地 Mod；支持卸载并恢复到无本地 Mod 状态。
- 不修改原版 `res.pak`。

## 使用

1. 确保已通过 Steam 创意工坊订阅并下载需要的 Mod。
2. 解压本仓库，双击 `InstallLocalMods.cmd`。
3. 选择 `1` 安装本地 Mod，或选择 `2` 卸载本地 Mod。
4. 检测到多个 Mod 时，按提示输入安装顺序，例如 `1,3,2`。
5. 安装完成后从 Steam 正常启动 Dead Cells；不要在游戏内再次启用同一个 Mod。

也可以从 PowerShell 调用：

```powershell
.\InstallLocalMods.ps1 -Action Install -Order 1,3,2
.\InstallLocalMods.ps1 -Action Remove
```

更完整的说明见 [`帖子分享说明.txt`](./帖子分享说明.txt)；原始简版说明保留在 [`README.txt`](./README.txt)。

## 目录说明

| 路径 | 作用 |
| --- | --- |
| `InstallLocalMods.cmd` | 双击入口 |
| `InstallLocalMods.ps1` | 自动查找、备份、解包、重打包和复制流程 |
| `ResTool/PAKTool.exe` | PAK 解包/打包工具 |
| `ResTool/Common.dll` | PAKTool 依赖 |
| `ResTool/Newtonsoft.Json.dll` | PAKTool 依赖 |
| `Test-InstallLocalMods.ps1` | 不修改游戏目录的本地完整性和依赖 smoke test |

运行时产生的 `Backups/`、`res*.pak` 和日志不会纳入版本库。仓库不包含游戏本体、Workshop 内容或任何原版 `res.pak`。

提交或发布前可运行以下检查：

```powershell
.\Test-InstallLocalMods.ps1
```

仓库也不应提交 API key、访问令牌、密码、证书私钥或其他个人凭据；`.gitignore` 已覆盖常见凭据文件名和扩展名。

## 限制与风险

- 仅适用于 Steam 版 Dead Cells；游戏更新后 PAK 格式变化可能导致工具失效。
- Mod 之间存在资源冲突时，后加载的包可能覆盖先加载的包。
- 修改本地游戏资源可能导致异常、存档问题或违反游戏/Steam 规则，请自行备份并承担风险。

## 依赖与致谢

仓库随附的 `PAKTool.exe` 来自 Dead Cells ModTools 生态（运行时显示为 N3rdL0rd's PakTool v0.1a / based on ModTools v1.7.0），相关第三方组件的版权和许可归原作者所有。本仓库仅封装 PowerShell 自动化流程，不包含游戏资源。

## License

自动化脚本和文档以 MIT License 发布；随附第三方二进制文件不适用本仓库许可证，详见 [`THIRD-PARTY-NOTICES.md`](./THIRD-PARTY-NOTICES.md)。
