Dead Cells Local Mod Installer

用途
把 Steam 创意工坊下载的 Dead Cells mod 重新打包成本地资源包：

  res1.pak
  res2.pak
  res3.pak

然后放入 Dead Cells 游戏本体目录。工具会自动查找 Steam 库、游戏目录和 Workshop mod 目录。

工具会从游戏本体 res.pak 文件头部自动提取 64 位打包密钥，游戏更新后通常不需要手动改密钥。

使用方法
1. 确保已经通过 Steam 创意工坊订阅并下载了 mod。
2. 双击 InstallLocalMods.cmd。
3. 选择 1 安装，或选择 2 卸载本地 mod。
4. 安装时，按提示输入 mod 顺序，例如：

   1
   1,3,2

5. 安装完成后，从 Steam 正常启动 Dead Cells。
6. 不要在游戏内 Workshop/Mod 菜单启用同一个 mod。

多个 mod 的规则
输入顺序会决定输出文件名：

  第 1 个 -> res1.pak
  第 2 个 -> res2.pak
  第 3 个 -> res3.pak

后面的包通常会更晚加载。如果多个 mod 修改了同一个资源，后面的 mod 可能覆盖前面的 mod。

备份和卸载
安装前，工具会把游戏目录里已有的本地 mod 文件移动到工具目录下的备份目录：

  Backups\LocalModBackup-YYYYMMDD-HHMMSS

只会处理 res1.pak、res2.pak、res3.pak 这类本地 mod 文件，不会移动原版 res.pak。

卸载时选择 2，工具会备份并移除本地 mod 文件。备份不会放进游戏目录或创意工坊目录。

文件说明
InstallLocalMods.cmd  双击入口
InstallLocalMods.ps1  主脚本
ResTool\PAKTool.exe   PAK 解包/打包工具
ResTool\Common.dll    PAKTool 依赖
ResTool\Newtonsoft.Json.dll  PAKTool 依赖
