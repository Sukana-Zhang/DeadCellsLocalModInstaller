param(
    [ValidateSet("", "Install", "Remove")]
    [string]$Action = "",

    [string]$Order = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$appId = "588650"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pakTool = Join-Path $scriptRoot "ResTool\PAKTool.exe"
$workRoot = Join-Path $env:TEMP "DeadCellsLocalModInstaller"
$backupRoot = Join-Path $scriptRoot "Backups"

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

    $headerText = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $count)
    $match = [regex]::Match($headerText, '[0-9a-fA-F]{64}')
    if (-not $match.Success) {
        throw "无法从游戏本体 res.pak 头部提取 64 位密钥，当前游戏版本可能改变了 PAK 格式。"
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
                if ($line -match '^\s*"path"\s*"([^"]+)"\s*$') {
                    $libraries.Add(($matches[1] -replace '\\\\', '\'))
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
            ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

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
    return $mods | Sort-Object LastWriteTime -Descending
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
        Write-Host "顺序无效。请使用列表里的编号，且不要重复。" -ForegroundColor Yellow
    }
}

function Backup-ExistingLocalMods($gameDir) {
    $existing = Get-ChildItem -LiteralPath $gameDir -File |
        Where-Object { $_.Name -match '^res[1-9][0-9]*\.pak$' } |
        Sort-Object Name

    if ($existing.Count -eq 0) {
        return
    }

    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupDir = Join-Path $backupRoot ("LocalModBackup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Write-Title "备份旧的本地 Mod"
    foreach ($file in $existing) {
        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $backupDir $file.Name) -Force
        Write-Host "已移动 $($file.Name) -> $backupDir"
    }
}

function Install-SelectedMods($selectedMods, $gameDir, $stamp) {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

    for ($i = 0; $i -lt $selectedMods.Count; $i++) {
        $mod = $selectedMods[$i]
        $slot = $i + 1
        $slotDir = Join-Path $workRoot "mod-$slot"
        $unpackedDir = Join-Path $slotDir "unpacked"
        $packedPak = Join-Path $slotDir "res$slot.pak"
        $targetPak = Join-Path $gameDir "res$slot.pak"

        New-Item -ItemType Directory -Force -Path $unpackedDir | Out-Null

        Write-Title "正在安装 #${slot}: $($mod.Name)"
        Write-Host "源文件: $($mod.Pak)"

        & $pakTool Expand $unpackedDir $mod.Pak
        if ($LASTEXITCODE -ne 0) {
            throw "PAKTool 解包失败: $($mod.Pak)"
        }

        $fileStats = Get-ChildItem -LiteralPath $unpackedDir -Recurse -File | Measure-Object -Property Length -Sum
        if ($fileStats.Count -le 0) {
            throw "解包后没有文件: $($mod.Pak)"
        }

        & $pakTool Collapsev1 $unpackedDir $packedPak -s $stamp
        if ($LASTEXITCODE -ne 0) {
            throw "PAKTool 重新打包失败: $($mod.Pak)"
        }

        Require-Path $packedPak "重新打包后的文件"
        Copy-Item -LiteralPath $packedPak -Destination $targetPak -Force
        $result = Get-Item -LiteralPath $targetPak
        Write-Host "已安装: $($result.FullName)"
        Write-Host "大小: $($result.Length) bytes"
    }
}

function Remove-LocalMods($gameDir) {
    $existing = Get-ChildItem -LiteralPath $gameDir -File |
        Where-Object { $_.Name -match '^res[1-9][0-9]*\.pak$' } |
        Sort-Object Name

    if ($existing.Count -eq 0) {
        Write-Host "没有找到本地 Mod 文件。"
        return
    }

    Backup-ExistingLocalMods $gameDir
    Write-Host "已从游戏目录移除本地 Mod，备份保留在工具目录。"
}

try {
    Require-Path $pakTool "PAKTool"

    Write-Host "死亡细胞本地 Mod 安装工具" -ForegroundColor Green
    Write-Host "用途：把创意工坊 Mod 重新打包成本地 res1.pak/res2.pak 文件。"

    $libraries = @(Get-SteamLibraries)
    if ($libraries.Count -eq 0) {
        throw "没有找到 Steam 库。请先启动一次 Steam，然后重新运行本工具。"
    }

    $installs = @(Find-DeadCellsInstall $libraries)
    if ($installs.Count -eq 0) {
        throw "没有在已检测到的 Steam 库中找到死亡细胞安装目录。"
    }

    $game = Select-GameInstall $installs
    $gameDir = $game.GameDir
    Write-Title "死亡细胞安装目录"
    Write-Host $gameDir

    $stamp = Get-DeadCellsPakStamp $gameDir
    Write-Host "已从本体 res.pak 自动提取密钥: $stamp"

    Write-Host ""
    Write-Host "[1] 安装创意工坊 Mod 为本地 Mod"
    Write-Host "[2] 卸载本地 Mod（备份并移除 res1.pak/res2.pak/...）"
    if ($Action -eq "Install") {
        $mode = "1"
        Write-Host "选择功能: 1"
    }
    elseif ($Action -eq "Remove") {
        $mode = "2"
        Write-Host "选择功能: 2"
    }
    else {
        $mode = Read-Host "选择功能"
    }

    if ($mode -eq "2") {
        Remove-LocalMods $gameDir
        Write-Host ""
        Write-Host "完成。" -ForegroundColor Green
        exit 0
    }
    elseif ($mode -ne "1" -and $mode -ne "") {
        throw "未知功能: $mode"
    }

    $mods = @(Find-WorkshopMods $libraries)
    if ($mods.Count -eq 0) {
        throw "没有在 steamapps\workshop\content\$appId 下找到创意工坊 Mod PAK 文件。"
    }

    $selectedMods = @(Select-ModOrder $mods $Order)

    Backup-ExistingLocalMods $gameDir
    Install-SelectedMods $selectedMods $gameDir $stamp

    Write-Host ""
    Write-Host "完成。" -ForegroundColor Green
    Write-Host "已安装 $($selectedMods.Count) 个本地 Mod。请从 Steam 正常启动死亡细胞。"
    Write-Host "不要在游戏内 Workshop / Mod 菜单里启用同一个 Mod。"
}
catch {
    Write-Host ""
    Write-Host "失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

