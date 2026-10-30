# Dead Cells Local Mod Installer

[English](README.en.md) · [下载分享版](https://github.com/Sukana-Zhang/DeadCellsLocalModInstaller/releases/latest)

把已经下载到本地的 Steam 创意工坊《死亡细胞》Mod，按指定顺序重打包为 `res1.pak`、`res2.pak` 等资源包，放到游戏目录中加载。原版 `res.pak` 不会被修改。

## 使用

适用于 Windows 10/11、Windows PowerShell 5.1 和 Steam 版 Dead Cells。随附 PAKTool 使用 .NET Framework；如无法启动，请检查 Windows 的 .NET Framework 4.8。当前打包方式面向带 stamp 的 v1 游戏 PAK（v35 及以后），未来游戏版本可能改变格式。

1. 先在 Steam 创意工坊订阅 Mod，等待下载完成，然后关闭游戏。
2. 从 [Releases](https://github.com/Sukana-Zhang/DeadCellsLocalModInstaller/releases/latest) 下载 ZIP，完整解压到可写的固定目录。
3. 双击 `InstallLocalMods.cmd`。选择 `1` 安装；检测到多个游戏目录时再选目录。`2` 卸载，`3` 导出诊断日志。
4. 按列表编号输入 Mod 顺序，例如 `1,3,2`。列表按本地文件修改时间排序，每次使用时请确认名称。
5. 完成后从 Steam 正常启动游戏，不要在游戏内再启用同一份 Workshop Mod。

第一个选中的 Mod 成为 `res1.pak`，第二个为 `res2.pak`，依此类推。后面的资源包可能覆盖前面的资源；本工具不会自动合并 Mod 冲突。它是资源重打包工具，不是自带内容的游戏 Mod。

## 备份、卸载与恢复

安装时先完成所有解包和重打包，再校验备份并替换游戏目录中的编号资源包。备份保存在本工具目录的 `Backups/LocalModBackup-时间-随机标识/` 中。正常捕获到的文件写入错误会触发旧文件恢复；断电、强制结束进程或磁盘故障仍可能需要手动恢复。

选择 `2` 卸载：备份并移除游戏目录里所有 `res1.pak`、`res2.pak` 等编号包。**工具将所有 `resN.pak`（N ≥ 1）视为待管理文件**，包括由其他工具安装的同名包。不会修改原版 `res.pak` 或存档。

如要恢复某次旧安装，关闭游戏，先将当前编号包另存，再把对应备份文件夹里的 `resN.pak` 复制回游戏目录。请保留工具的备份文件夹，并自行备份游戏存档。

## 命令行

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\InstallLocalMods.ps1 -Action Install -Order "1,3,2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\InstallLocalMods.ps1 -Action Remove
```

Steam 或游戏安装在自定义位置、自动查找失败时，可以指定目录（示例路径请替换）：

```powershell
.\InstallLocalMods.ps1 -Action Install -Order "1" -SteamDirectory "E:\Steam" -GameDirectory "E:\Steam\steamapps\common\Dead Cells"
```

`-SteamDirectory` 指向包含 `steamapps` 的 Steam 库目录；Mod 需要位于其 `steamapps/workshop/content/588650/` 下。`-GameDirectory` 指向包含游戏原版 `res.pak` 的目录。命令行无效的预设顺序会报错退出。

## 排错

程序自动将 UTF-8 日志保存到 `%LOCALAPPDATA%\DeadCellsLocalModInstaller\Logs`，记录版本、运行编号、执行阶段、PAKTool 输出与退出码、备份、恢复及异常信息。`activity.log` 达到 1 MiB 后轮换，保留一份 `activity.previous.log`。

出错后重新运行工具，选择 **3：导出诊断日志**。TXT 默认保存在工具目录，包含系统/PowerShell 版本和两份日志的近期内容（每份最多 512 KiB），不包含游戏资源、Mod、存档或备份，也不会自动上传。用户目录、用户 SID 和 PAKTool 输出中的 stamp 会默认替换；分享前仍请检查自定义目录等信息。导出不需要游戏或 PAKTool 可用。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\InstallLocalMods.ps1 -Action ExportLogs
```

可通过 `-DiagnosticPath "E:\Temp\report.txt"` 指定一个尚不存在的导出文件，通过 `-LogDirectory "E:\Temp\LocalModLogs"` 自定义日志目录。后续导出时请使用同一个日志目录。日志写入失败会提示，不会中断安装。

- 找不到 Mod：检查 Steam 下载是否完成，订阅内容内是否含 `res.pak` 或 `res1.pak`。
- 工具闪退：完整解压所有文件，通过上面的命令行运行以查看错误；检查 .NET Framework 4.8 和目录写入权限。
- 游戏运行中：关闭 `deadcells.exe` / `deadcells_gl.exe` 后再操作。
- 安装中断或游戏异常：保留 `Backups/`，卸载或手动恢复之前的编号包，再逐个检查 Mod 兼容性。
- 游戏目录不可写：优先检查目录权限。无需为日常使用永久更改系统 PowerShell 执行策略，CMD 入口只为当前进程指定策略。

## 源码与验证

`InstallLocalMods.ps1` 是完整自动化源码；`ResTool/` 是第三方打包工具，来源、哈希和许可见 [第三方说明](THIRD-PARTY-NOTICES.md)。仓库不包含游戏、Workshop Mod、个人存档、备份、运行日志或凭据。

```powershell
.\Test-InstallLocalMods.ps1
.\Test-Functional.ps1
.\Test-Diagnostics.ps1
.\package.ps1
```

测试只使用 `build/` 下的合成 PAK 和模拟 Steam 目录，包含 24 项功能检查及 32 项日志/回归检查，覆盖真实打包往返、顺序校验、备份、安装、卸载、失败恢复、日志脱敏与轮换，以及真正的脚本入口，不会扫描或修改你的游戏目录。GitHub Actions 在 Windows Server 2022/2025 上分别运行 Windows PowerShell 5.1 和 PowerShell 7。尚未验证所有 Windows 10/11 硬件、游戏版本或 Mod 组合。

游戏目录会保留一个空的 `.deadcells-localmods.lock` 文件。它用于阻止不同副本同时修改同一目录；程序退出会释放占用，无需删除锁文件。临时目录清理失败只产生警告，并在日志中留下位置。

## 许可

本项目脚本和文档使用 [MIT License](LICENSE)。PAKTool、Common.dll 和 Newtonsoft.Json 保留各自上游 MIT 许可及版权声明，详见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。Dead Cells 名称及游戏内容归其权利人所有。本项目与游戏开发商及 Valve 没有关联。
