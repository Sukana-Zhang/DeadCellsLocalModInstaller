param(
    [ValidateSet("", "Install", "Remove", "ExportLogs")]
    [string]$Action = "",

    [string]$Order = "",

    [string]$GameDirectory = "",

    [string]$SteamDirectory = "",

    [string]$DiagnosticPath = "",

    [string]$LogDirectory = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$appId = "588650"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pakTool = Join-Path $scriptRoot "ResTool\PAKTool.exe"
$workRoot = Join-Path $env:TEMP "DeadCellsLocalModInstaller"
$backupRoot = Join-Path $scriptRoot "Backups"
. (Join-Path $scriptRoot 'Diagnostics.ps1')
if ($LogDirectory) { $script:LogRoot = [IO.Path]::GetFullPath($LogDirectory) }

function ConvertTo-NativeArgument([string]$argument) {
    $escaped = [regex]::Replace($argument,'(\\*)"','$1$1\"')
    $escaped = [regex]::Replace($escaped,'(\\+)$','$1$1')
    return '"' + $escaped + '"'
}

function Invoke-PakTool([string[]]$arguments) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $pakTool
    $info.Arguments = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        foreach ($output in @($stdout.Result,$stderr.Result)) {
            if ($output) { Write-Host $output.TrimEnd(); Write-InstallerLog TOOL $output }
        }
        Write-InstallerLog INFO "PAKTool exit=$($process.ExitCode)"
        if ($process.ExitCode -ne 0) { throw "PAKTool 失败，退出码 $($process.ExitCode)。请导出诊断日志。" }
    } finally { $process.Dispose() }
}

function Open-GameLock([string]$gameDir) {
    return [IO.File]::Open((Join-Path $gameDir '.deadcells-localmods.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
}

function Get-LocalModFiles([string]$gameDir) {
    $files = @(Get-ChildItem -LiteralPath $gameDir -File -Force | Where-Object { $_.Name -match '^res[1-9][0-9]*\.pak$' } | Sort-Object Name)
    foreach ($file in $files) { if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "不处理链接形式的 Mod 文件: $($file.Name)" } }
    return $files
}

function Remove-RunWorkspace([string]$runRoot) {
    try {
        $resolvedRun = [IO.Path]::GetFullPath($runRoot)
        $resolvedParent = [IO.Path]::GetFullPath($workRoot).TrimEnd('\') + '\'
        if (-not $resolvedRun.StartsWith($resolvedParent,[StringComparison]::OrdinalIgnoreCase)) { throw '临时目录超出预期范围。' }
        if (Test-Path -LiteralPath $resolvedRun) { Remove-Item -LiteralPath $resolvedRun -Recurse -Force }
    } catch { Write-InstallerLog WARN ('temporary cleanup failed: ' + $_.Exception.Message); Write-Warning '临时文件清理失败；不影响已完成的安装。详情见日志。' }
}

function Write-Title($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Cyan
}

function Require-Path($path, $label) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$label 不存在: $path"
    }
}

function Get-DeadCellsPakStamp($gameDir) {
    $resPak = Join-Path $gameDir "res.pak"
    Require-Path $resPak "游戏本体 res.pak"

    $buffer = New-Object byte[] 512
    $stream = [System.IO.File]::OpenRead($resPak)
    try {
        $count = $stream.Read($buffer, 0, $buffer.Length)
    }
    finally {
        $stream.Close()
    }

    if ($count -lt 76 -or [Text.Encoding]::ASCII.GetString($buffer,0,3) -ne 'PAK' -or $buffer[3] -ne 1) { throw '当前只支持带 stamp 的 v1 游戏 PAK。' }
    $headerText = [System.Text.Encoding]::ASCII.GetString($buffer, 12, 64)
    $match = [regex]::Match($headerText, '^[0-9a-fA-F]{64}$')
    if (-not $match.Success) {
        throw "无法从游戏本体 res.pak 头部提取 64 字符 stamp，当前游戏版本可能改变了 PAK 格式。"
    }

    return $match.Value.ToLowerInvariant()
}

function Parse-VdfQuotedPairs($path) {
    $pairs = @{}
    foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
        if ($line -match '^\s*"([^"]+)"\s*"([^"]*)"\s*$') {
            $pairs[$matches[1]] = $matches[2]
        }
    }
    return $pairs
}

function Get-SteamRootCandidates {
    if ($SteamDirectory) {
        Require-Path (Join-Path $SteamDirectory 'steamapps') '指定的 Steam 库 steamapps 目录'
        return [IO.Path]::GetFullPath($SteamDirectory)
    }
    $paths = New-Object System.Collections.Generic.List[string]
    $regPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam"
    )

    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $item = Get-ItemProperty -Path $regPath
            foreach ($name in @("SteamPath", "InstallPath")) {
                if ($item.$name) {
                    $paths.Add(($item.$name -replace '/', '\'))
                }
            }
        }
    }

    foreach ($fallback in @(
        $SteamDirectory,
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam",
        "C:\Steam",
        "D:\Steam",
        "D:\Games\Steam"
    )) {
        if ($fallback) {
            $paths.Add($fallback)
        }
    }

    return $paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
}

function Get-SteamLibraries {
    $libraries = New-Object System.Collections.Generic.List[string]

    foreach ($steamRoot in Get-SteamRootCandidates) {
        $libraries.Add($steamRoot)
        $libraryVdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryVdf) {
            foreach ($line in Get-Content -LiteralPath $libraryVdf -Encoding UTF8) {
                if ($line -match '^\s*"(?:path|[0-9]+)"\s*"([^"]+)"\s*$') {
                    $candidate = $matches[1] -replace '\\\\', '\'
                    if ([IO.Path]::IsPathRooted($candidate)) { $libraries.Add($candidate) }
                }
            }
        }
    }

    $seen = @{}
    $result = @()
    foreach ($library in $libraries) {
        if (-not $library) {
            continue
        }
        $fullPath = [System.IO.Path]::GetFullPath($library)
        $key = $fullPath.ToLowerInvariant()
        if (-not $seen.ContainsKey($key) -and (Test-Path -LiteralPath (Join-Path $fullPath "steamapps"))) {
            $seen[$key] = $true
            $result += $fullPath
        }
    }
    return $result
}

function Find-DeadCellsInstall($libraries) {
    $installs = @()
    $seen = @{}
    foreach ($library in $libraries) {
        $manifest = Join-Path $library "steamapps\appmanifest_$appId.acf"
        if (-not (Test-Path -LiteralPath $manifest)) {
            continue
        }

        $pairs = Parse-VdfQuotedPairs $manifest
        $installDirName = if ($pairs.ContainsKey("installdir")) { $pairs["installdir"] } else { "Dead Cells" }
        $gameDir = Join-Path (Join-Path $library "steamapps\common") $installDirName
        $gameDir = [System.IO.Path]::GetFullPath($gameDir)
        $key = $gameDir.ToLowerInvariant()
        if (-not $seen.ContainsKey($key) -and (Test-Path -LiteralPath (Join-Path $gameDir "res.pak"))) {
            $seen[$key] = $true
            $installs += [pscustomobject]@{
                Library = $library
                GameDir = $gameDir
                Manifest = $manifest
            }
        }
    }
    return $installs
}

function Get-ModName($modDir) {
    $settings = Join-Path $modDir "settings.json"
    if (Test-Path -LiteralPath $settings) {
        try {
            $json = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.name) {
                return [string]$json.name
            }
        }
        catch {
            return "(settings.json 无法读取)"
        }
    }
    return "(settings.json 中没有名称)"
}

function Find-WorkshopMods($libraries) {
    $mods = @()
    foreach ($library in $libraries) {
        $contentDir = Join-Path $library "steamapps\workshop\content\$appId"
        if (-not (Test-Path -LiteralPath $contentDir)) {
            continue
        }

        foreach ($dir in Get-ChildItem -LiteralPath $contentDir -Directory) {
            $pak = @(
                (Join-Path $dir.FullName "res.pak"),
                (Join-Path $dir.FullName "res1.pak")
            ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

            if ($pak) {
                $pakItem = Get-Item -LiteralPath $pak
                $mods += [pscustomobject]@{
                    Id = $dir.Name
                    Name = Get-ModName $dir.FullName
                    Pak = $pak
                    Directory = $dir.FullName
                    Library = $library
                    Size = $pakItem.Length
                    LastWriteTime = $pakItem.LastWriteTime
                }
            }
        }
    }
    return $mods | Sort-Object @{Expression='LastWriteTime';Descending=$true},Id,Directory
}

function Select-GameInstall($installs) {
    if ($installs.Count -eq 1) {
        return $installs[0]
    }

    Write-Title "检测到多个死亡细胞安装目录"
    for ($i = 0; $i -lt $installs.Count; $i++) {
        Write-Host "[$($i + 1)] $($installs[$i].GameDir)"
    }

    while ($true) {
        $choice = Read-Host "请选择游戏目录编号"
        $index = 0
        if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $installs.Count) {
            return $installs[$index - 1]
        }
        Write-Host "输入无效。" -ForegroundColor Yellow
    }
}

function Show-Mods($mods) {
    Write-Title "检测到的创意工坊 Mod"
    for ($i = 0; $i -lt $mods.Count; $i++) {
        $m = $mods[$i]
        Write-Host "[$($i + 1)] $($m.Name)"
        Write-Host "    Workshop ID: $($m.Id)"
        Write-Host "    PAK 文件: $($m.Pak)"
        Write-Host "    大小: $($m.Size) bytes"
    }
}

function Select-ModOrder($mods, $presetOrder) {
    Show-Mods $mods
    Write-Host ""
    Write-Host "请输入安装顺序，例如: 1 或 1,3,2"
    Write-Host "选中的 Mod 会按顺序生成 res1.pak、res2.pak、res3.pak。"
    Write-Host "序号越靠后通常越晚加载；如果资源冲突，后面的 Mod 可能覆盖前面的 Mod。"

    while ($true) {
        $usedPreset = [bool]$presetOrder
        if ($presetOrder) {
            $inputText = $presetOrder
            $presetOrder = ""
            Write-Host "安装顺序: $inputText"
        }
        else {
            $inputText = Read-Host "安装顺序"
        }
        $parts = $inputText -split "[,，\s]+" | Where-Object { $_ }
        $indexes = @()
        $ok = $true

        foreach ($part in $parts) {
            $value = 0
            if (-not [int]::TryParse($part, [ref]$value) -or $value -lt 1 -or $value -gt $mods.Count) {
                $ok = $false
                break
            }
            if ($indexes -contains $value) {
                $ok = $false
                break
            }
            $indexes += $value
        }

        if ($ok -and $indexes.Count -gt 0) {
            return $indexes | ForEach-Object { $mods[$_ - 1] }
        }
        if ($usedPreset) { throw '预设顺序无效：请使用列表中的编号，且不要重复。' }
        Write-Host "顺序无效。请使用列表里的编号，且不要重复。" -ForegroundColor Yellow
    }
}

function Backup-ExistingLocalMods($gameDir) {
    $existing = @(Get-LocalModFiles $gameDir)

    if ($existing.Count -eq 0) {
        return
    }

    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupDir = Join-Path $backupRoot ("LocalModBackup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Write-Title "备份旧的本地 Mod"
    Set-InstallerStage backup
    foreach ($file in $existing) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $backupDir $file.Name)
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $backupDir $file.Name)).Hash) {
            throw "备份校验失败: $($file.Name)"
        }
        Write-Host "已备份 $($file.Name) -> $backupDir"
        Write-InstallerLog INFO "backup verified file=$($file.Name) destination=$backupDir"
    }
    return $backupDir
}

function Set-LocalModFiles($gameDir, $packedFiles) {
    $existing = @(Get-LocalModFiles $gameDir)
    $backupDir = Backup-ExistingLocalMods $gameDir
    $attempted = @()
    Set-InstallerStage publish
    try {
        foreach ($file in $existing) { Remove-Item -LiteralPath $file.FullName -Force }
        foreach ($packed in $packedFiles) {
            $name = [IO.Path]::GetFileName($packed)
            if ($name -notmatch '^res[1-9][0-9]*\.pak$') { throw "无效的本地 Mod 文件名: $name" }
            $target = Join-Path $gameDir $name
            if (Test-Path -LiteralPath $target) { throw "目标已存在或不是普通文件: $target" }
            $attempted += $target
            Copy-Item -LiteralPath $packed -Destination $target
            if ((Get-FileHash -LiteralPath $packed).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "安装校验失败: $name" }
            Write-InstallerLog INFO "installed file=$name"
        }
    }
    catch {
        $failure = $_
        Write-InstallerException $failure
        Set-InstallerStage rollback
        try {
            foreach ($target in $attempted) {
                if (Test-Path -LiteralPath $target -PathType Leaf) { Remove-Item -LiteralPath $target -Force }
            }
            foreach ($file in $existing) { Copy-Item -LiteralPath (Join-Path $backupDir $file.Name) -Destination $file.FullName -Force }
            Write-InstallerLog INFO 'previous files restored'
        }
        catch { throw "安装/卸载失败，自动恢复也失败。请从备份目录手动恢复: $backupDir。$($_.Exception.Message)" }
        throw $failure
    }
}

function Install-SelectedMods($selectedMods, $gameDir, $stamp) {
    $runRoot = Join-Path $workRoot ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $packedFiles = @()
    try {

    for ($i = 0; $i -lt $selectedMods.Count; $i++) {
        $mod = $selectedMods[$i]
        $slot = $i + 1
        $slotDir = Join-Path $runRoot "mod-$slot"
        $unpackedDir = Join-Path $slotDir "unpacked"
        $packedPak = Join-Path $slotDir "res$slot.pak"

        New-Item -ItemType Directory -Force -Path $unpackedDir | Out-Null

        Write-Title "正在安装 #${slot}: $($mod.Name)"
        Write-Host "源文件: $($mod.Pak)"

        Set-InstallerStage expand
        Write-InstallerLog INFO "slot=$slot source=$($mod.Pak)"
        Invoke-PakTool @('Expand',$unpackedDir,$mod.Pak)

        $fileStats = Get-ChildItem -LiteralPath $unpackedDir -Recurse -File | Measure-Object -Property Length -Sum
        if ($fileStats.Count -le 0) {
            throw "解包后没有文件: $($mod.Pak)"
        }

        Set-InstallerStage repack
        Invoke-PakTool @('Collapsev1',$unpackedDir,$packedPak,'-s',$stamp)

        Require-Path $packedPak "重新打包后的文件"
        if ((Get-Item -LiteralPath $packedPak).Length -le 0) { throw "重新打包后的文件为空。" }
        $packedFiles += $packedPak
    }
    Set-LocalModFiles $gameDir $packedFiles
    }
    finally {
        Remove-RunWorkspace $runRoot
    }
}

function Remove-LocalMods($gameDir) {
    $existing = @(Get-LocalModFiles $gameDir)

    if ($existing.Count -eq 0) {
        Write-Host "没有找到本地 Mod 文件。"
        return
    }

    Set-LocalModFiles $gameDir @()
    Write-Host "已从游戏目录移除本地 Mod，备份保留在工具目录。"
}

if ($MyInvocation.InvocationName -eq '.') { return }

$runLock = $null
$gameLock = $null
$script:LogEnabled = $true
try {
    Write-InstallerLog INFO (Get-DiagnosticHeader)
    Write-Host "死亡细胞本地 Mod 安装工具" -ForegroundColor Green
    Write-Host "用途：把创意工坊 Mod 重新打包成本地 res1.pak/res2.pak 文件。"
    Write-Host ""
    Write-Host "[1] 安装创意工坊 Mod 为本地 Mod"
    Write-Host "[2] 卸载本地 Mod（备份并移除 res1.pak/res2.pak/...）"
    Write-Host "[3] 导出诊断日志"
    Set-InstallerStage select-action
    if ($Action -eq "Install") {
        $mode = "1"
        Write-Host "选择功能: 1"
    }
    elseif ($Action -eq "Remove") {
        $mode = "2"
        Write-Host "选择功能: 2"
    }
    elseif ($Action -eq 'ExportLogs') { $mode = '3' }
    else {
        $mode = Read-Host "选择功能"
    }

    if ($mode -eq '3') { $null = Export-InstallerLogs $DiagnosticPath; exit 0 }
    if ($mode -notin @('','1','2')) { throw "未知功能: $mode" }

    Set-InstallerStage lock-installer
    $runLock = [IO.File]::Open((Join-Path $scriptRoot '.installer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if (@(Get-Process -Name deadcells,deadcells_gl -ErrorAction SilentlyContinue).Count -gt 0) { throw '请先关闭死亡细胞，再安装或卸载 Mod。' }
    Set-InstallerStage discover
    $libraries = @()
    if ($GameDirectory) {
        $gameDir = [IO.Path]::GetFullPath($GameDirectory)
        Require-Path (Join-Path $gameDir 'res.pak') '游戏本体 res.pak'
    }
    else {
        $libraries = @(Get-SteamLibraries)
        $installs = @(Find-DeadCellsInstall $libraries)
        if ($installs.Count -eq 0) { throw '没有在已检测到的 Steam 库中找到死亡细胞安装目录。' }
        $gameDir = (Select-GameInstall $installs).GameDir
    }
    Write-Host "游戏目录: $gameDir"
    Write-InstallerLog INFO "game=$gameDir"
    Set-InstallerStage lock-game
    $gameLock = Open-GameLock $gameDir
    if ($mode -eq '2') {
        Set-InstallerStage remove
        Remove-LocalMods $gameDir
        Set-InstallerStage complete
        Write-InstallerLog INFO 'remove success'
        Write-Host ""
        Write-Host "完成。" -ForegroundColor Green
        exit 0
    }
    Set-InstallerStage verify-dependencies
    Require-Path $pakTool 'PAKTool'
    foreach ($line in Get-Content -LiteralPath (Join-Path $scriptRoot 'dependencies.sha256')) {
        if ($line -notmatch '^([a-f0-9]{64})  (ResTool/[A-Za-z.]+)$') { throw '依赖清单格式错误。' }
        if ((Get-FileHash -LiteralPath (Join-Path $scriptRoot $matches[2]) -Algorithm SHA256).Hash -ne $matches[1]) { throw "依赖校验失败: $($matches[2])" }
    }
    Set-InstallerStage discover-mods
    if ($libraries.Count -eq 0) { $libraries = @(Get-SteamLibraries) }
    $mods = @(Find-WorkshopMods $libraries)
    if ($mods.Count -eq 0) {
        throw "没有在 steamapps\workshop\content\$appId 下找到创意工坊 Mod PAK 文件。"
    }

    $selectedMods = @(Select-ModOrder $mods $Order)
    Write-InstallerLog INFO "selected=$($selectedMods.Count) order=$Order"
    Set-InstallerStage read-stamp
    $stamp = Get-DeadCellsPakStamp $gameDir
    Write-Host '已读取当前游戏 PAK stamp。'
    Install-SelectedMods $selectedMods $gameDir $stamp
    Set-InstallerStage complete
    Write-InstallerLog INFO "install success count=$($selectedMods.Count)"
    Write-Host ""
    Write-Host "完成。" -ForegroundColor Green
    Write-Host "已安装 $($selectedMods.Count) 个本地 Mod。请从 Steam 正常启动死亡细胞。"
    Write-Host "不要在游戏内 Workshop / Mod 菜单里启用同一个 Mod。"
}
catch {
    Write-InstallerException $_
    Write-Host ""
    Write-Host "失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '可重新运行并选择 3 导出诊断日志。'
    exit 1
}
finally {
    if ($null -ne $gameLock) { $gameLock.Dispose() }
    if ($null -ne $runLock) { $runLock.Dispose() }
}

