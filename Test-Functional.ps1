$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$script:checks = 0
function Assert($condition, $label) {
    if (-not $condition) { throw "FAIL: $label" }
    $script:checks++
}
function Expect-Failure([scriptblock]$operation, $label) {
    $failed = $false
    try { & $operation | Out-Null } catch { $failed = $true }
    Assert $failed $label
}
. (Join-Path $root 'InstallLocalMods.ps1')
$testRoot = Join-Path $root ('build\tests-' + [Guid]::NewGuid().ToString('N') + '-中文 spaces')
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$workRoot = Join-Path $testRoot 'temporary'
$backupRoot = Join-Path $testRoot 'backups'
try {
    $game = Join-Path $testRoot 'game'
    $fixture = Join-Path $testRoot 'input'
    New-Item -ItemType Directory -Force -Path $game,$fixture,(Join-Path $fixture 'nested') | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'nested\fixture.txt'),'synthetic fixture only')
    $stamp = '0123456789abcdef' * 4
    & $pakTool collapsev1 $fixture (Join-Path $game 'res.pak') -s $stamp | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Create synthetic game PAK'
    Assert ((Get-DeadCellsPakStamp $game) -eq $stamp) 'Read exact v1 stamp'
    $originalHash = (Get-FileHash -LiteralPath (Join-Path $game 'res.pak')).Hash
    $invalid = Join-Path $testRoot 'invalid'
    New-Item -ItemType Directory -Path $invalid | Out-Null
    [IO.File]::WriteAllText((Join-Path $invalid 'res.pak'),('x' * 100))
    Expect-Failure { Get-DeadCellsPakStamp $invalid } 'Reject malformed PAK'
    $workshop = Join-Path $testRoot 'steamapps\workshop\content\588650\123'
    New-Item -ItemType Directory -Force -Path $workshop | Out-Null
    & $pakTool collapse $fixture (Join-Path $workshop 'res.pak') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Create synthetic Workshop PAK'
    [IO.File]::WriteAllText((Join-Path $workshop 'settings.json'),'{"name":"Fixture Mod"}')
    $mods = @(Find-WorkshopMods @($testRoot))
    Assert ($mods.Count -eq 1 -and $mods[0].Name -eq 'Fixture Mod') 'Workshop discovery'
    Assert (@(Select-ModOrder $mods '1').Count -eq 1) 'Select valid order'
    Expect-Failure { Select-ModOrder $mods '1,1' } 'Reject duplicate preset without hanging'
    Expect-Failure { Select-ModOrder $mods '2' } 'Reject out-of-range preset'
    [IO.File]::WriteAllText((Join-Path $game 'res1.pak'),'old mod')
    Install-SelectedMods $mods $game $stamp
    Assert (Test-Path -LiteralPath (Join-Path $game 'res1.pak')) 'Install staged PAK'
    $expanded = Join-Path $testRoot 'expanded'
    New-Item -ItemType Directory -Path $expanded | Out-Null
    & $pakTool expand $expanded (Join-Path $game 'res1.pak') | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText((Join-Path $expanded 'nested\fixture.txt')) -eq 'synthetic fixture only') 'Repacked data roundtrip'
    $backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory)
    Assert ($backups.Count -eq 1) 'Existing mod backed up'
    Assert ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'res1.pak')) -eq 'old mod') 'Backup preserves old data'
    Assert (@(Get-ChildItem -LiteralPath $workRoot -Directory).Count -eq 0) 'Temporary run removed'
    Install-SelectedMods @($mods[0],$mods[0]) $game $stamp
    Assert (Test-Path -LiteralPath (Join-Path $game 'res2.pak')) 'Install multiple numbered packages'
    Install-SelectedMods $mods $game $stamp
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'res2.pak'))) 'Replacing setup removes stale higher slots'
    $before = (Get-FileHash -LiteralPath (Join-Path $game 'res1.pak')).Hash
    $broken = [pscustomobject]@{ Name='Broken'; Pak=(Join-Path $testRoot 'missing.pak') }
    Expect-Failure { Install-SelectedMods @($mods[0],$broken) $game $stamp } 'Failed second repack aborts install'
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'res1.pak')).Hash -eq $before) 'Failed repack keeps old installation'
    $staged = Join-Path $testRoot 'staged'
    New-Item -ItemType Directory -Path $staged,(Join-Path $game 'res2.pak') | Out-Null
    [IO.File]::WriteAllText((Join-Path $staged 'res1.pak'),'new one')
    [IO.File]::WriteAllText((Join-Path $staged 'res2.pak'),'new two')
    Expect-Failure { Set-LocalModFiles $game @((Join-Path $staged 'res1.pak'),(Join-Path $staged 'res2.pak')) } 'Blocked destination aborts publication'
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'res1.pak')).Hash -eq $before) 'Publication rollback restores old mod'
    Assert (Test-Path -LiteralPath (Join-Path $game 'res2.pak') -PathType Container) 'Rollback preserves foreign directory'
    Remove-LocalMods $game
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'res1.pak'))) 'Remove local mod'
    Remove-LocalMods $game
    Assert ((Get-FileHash -LiteralPath (Join-Path $game 'res.pak')).Hash -eq $originalHash) 'Original game PAK untouched'
    $manifestDir = Join-Path $testRoot 'steamapps'
    $targetGame = Join-Path $manifestDir 'common\Test Game'
    New-Item -ItemType Directory -Force -Path $targetGame | Out-Null
    Copy-Item -LiteralPath (Join-Path $game 'res.pak') -Destination (Join-Path $targetGame 'res.pak')
    [IO.File]::WriteAllText((Join-Path $manifestDir 'appmanifest_588650.acf'),('"installdir" "Test Game"' + [Environment]::NewLine))
    Assert (@(Find-DeadCellsInstall @($testRoot)).Count -eq 1) 'Discover install from synthetic Steam manifest'
    [IO.File]::WriteAllText((Join-Path $workshop 'settings.json'),'{bad json')
    Assert ((Get-ModName $workshop) -match 'settings.json') 'Malformed mod metadata handled'
    Write-Host "PASS: $script:checks checks. Only synthetic files under build/ were used; no Steam/game directory was scanned or modified."
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $prefix = [IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
