$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$script:checks = 0
function Assert($condition,$label) { if (-not $condition) { throw "FAIL: $label" }; $script:checks++ }
function Expect-Failure([scriptblock]$operation,$label) { $failed=$false; try { & $operation | Out-Null } catch { $failed=$true }; Assert $failed $label }
. (Join-Path $root 'InstallLocalMods.ps1')
$testRoot = Join-Path $root ('build\diagnostics-' + [Guid]::NewGuid().ToString('N') + '-中文 spaces')
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$script:LogRoot = Join-Path $testRoot 'logs'
$script:LogEnabled = $true
$workRoot = Join-Path $testRoot 'temp'
try {
    Set-InstallerStage test-stage
    $profilePath = [Environment]::GetFolderPath('UserProfile')
    $fakeStamp = 'a' * 64
    Write-InstallerLog INFO ("$profilePath\test S-1-5-21-123-456-789-1001 with stamp $fakeStamp 中文日志")
    $log = Join-Path $script:LogRoot 'activity.log'
    $text = [IO.File]::ReadAllText($log)
    Assert ($text.Contains('test-stage')) 'Stage recorded'
    Assert (-not $text.Contains($profilePath)) 'Profile redacted'
    Assert (-not $text.Contains('S-1-5-21-123-456-789-1001')) 'User SID redacted'
    Assert (-not $text.Contains($fakeStamp)) 'Stamp redacted'
    Assert ($text.Contains('中文日志')) 'UTF-8 log text'
    try { throw (New-Object IO.IOException('fixture failure')) } catch { Write-InstallerException $_ }
    $text = [IO.File]::ReadAllText($log)
    Assert ($text.Contains('System.IO.IOException') -and $text.Contains('hresult=0x')) 'Exception type and HRESULT'
    $export = Join-Path $testRoot 'diagnostic.txt'
    $null = Export-InstallerLogs $export
    $report = [IO.File]::ReadAllText($export)
    Assert ($report.Contains('version=' + (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()) -and $report.Contains('powershell=')) 'Export includes version and environment'
    Assert ($report.Contains('fixture failure')) 'Export includes recent errors'
    Assert ([IO.File]::ReadAllBytes($export)[0] -eq 239) 'Export has UTF-8 BOM'
    Expect-Failure { Export-InstallerLogs $export } 'Export cannot overwrite existing file'
    Expect-Failure { Export-InstallerLogs $log } 'Export cannot overwrite active log'
    [IO.File]::WriteAllText($log,('x' * (1MB + 5)))
    Write-InstallerLog INFO 'after rotation'
    Assert (Test-Path -LiteralPath (Join-Path $script:LogRoot 'activity.previous.log')) 'Log rotates at 1 MiB'
    Assert ((Get-Item -LiteralPath $log).Length -lt 1MB) 'Current log bounded after rotation'
    Assert ((Read-LogTail (Join-Path $script:LogRoot 'activity.previous.log')).Length -le 512KB) 'Tail read bounded'
    $goodLogRoot = $script:LogRoot
    $script:LogRoot = Join-Path $testRoot 'blocked-log-root'
    [IO.File]::WriteAllText($script:LogRoot,'a file blocks directory creation')
    Write-InstallerLog INFO 'cannot write'
    Assert ([bool]$script:LogFailure) 'Logging failure does not stop operation'
    $script:LogRoot = $goodLogRoot
    $game = Join-Path $testRoot 'game'
    New-Item -ItemType Directory -Path $game | Out-Null
    $handle = Open-GameLock $game
    try { Expect-Failure { $other=Open-GameLock $game; $other.Dispose() } 'Same game cannot be locked by another copy' } finally { $handle.Dispose() }
    $handle=Open-GameLock $game; $handle.Dispose()
    Assert $true 'Game lock released for next run'
    $hidden = Join-Path $game 'res1.pak'
    [IO.File]::WriteAllText($hidden,'hidden package')
    [IO.File]::SetAttributes($hidden,[IO.FileAttributes]::Hidden)
    Assert (@(Get-LocalModFiles $game).Count -eq 1) 'Hidden numbered mod is discovered'
    $backupRoot=Join-Path $testRoot 'backups'
    Remove-LocalMods $game
    Assert (-not (Test-Path -LiteralPath $hidden)) 'Hidden numbered mod removed with backup'
    $run=Join-Path $workRoot 'locked-run'
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    $busy=[IO.File]::Open((Join-Path $run 'busy'),[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Remove-RunWorkspace $run; Assert (Test-Path -LiteralPath $run) 'Cleanup failure is nonfatal' } finally { $busy.Dispose() }
    Remove-RunWorkspace $run
    Assert (-not (Test-Path -LiteralPath $run)) 'Cleanup succeeds when handle released'
    $originalTool=$pakTool
    $pakTool=(Get-Command powershell.exe).Source
    Invoke-PakTool @('-NoProfile','-NonInteractive','-Command','[Console]::Error.WriteLine("warning only"); exit 0')
    Assert $true 'Native stderr with exit zero is not a failure'
    Expect-Failure { Invoke-PakTool @('-NoProfile','-NonInteractive','-Command','exit 7') } 'Native nonzero exit fails'
    Assert ([IO.File]::ReadAllText($log).Contains('exit=7')) 'Native exit code recorded'
    $argumentScript=Join-Path $testRoot 'arguments.ps1'
    [IO.File]::WriteAllText($argumentScript,'param([string]$value,[string]$destination) [IO.File]::WriteAllText($destination,$value)')
    $argumentOut=Join-Path $testRoot 'argument-result.txt'
    $value='spaces and "quotes" with trailing\'
    Invoke-PakTool @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$argumentScript,'-value',$value,'-destination',$argumentOut)
    Assert ([IO.File]::ReadAllText($argumentOut) -eq $value) 'Native quoting preserves quotes and trailing backslash'
    $pakTool=$originalTool
    $SteamDirectory=$testRoot
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'steamapps') | Out-Null
    Assert (@(Get-SteamRootCandidates).Count -eq 1) 'Explicit Steam directory does not scan unrelated libraries'
    $otherLib=Join-Path $testRoot 'legacy-library'
    New-Item -ItemType Directory -Force -Path (Join-Path $otherLib 'steamapps') | Out-Null
    [IO.File]::WriteAllText((Join-Path $testRoot 'steamapps\libraryfolders.vdf'),('"1" "' + $otherLib.Replace('\','\\') + '"'))
    Assert (@(Get-SteamLibraries).Count -eq 2) 'Legacy Steam library format supported'
    $entry=Join-Path $testRoot 'minimal-copy'
    New-Item -ItemType Directory -Path $entry | Out-Null
    foreach ($name in @('InstallLocalMods.ps1','Diagnostics.ps1','VERSION')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $entry }
    [IO.File]::WriteAllText((Join-Path $game 'res.pak'),'base fixture')
    [IO.File]::WriteAllText((Join-Path $game 'res1.pak'),'old fixture')
    $handle=Open-GameLock $game
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $entry 'InstallLocalMods.ps1') -Action Remove -GameDirectory $game -LogDirectory (Join-Path $testRoot 'childlogs') | Out-Null
        Assert ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText((Join-Path $game 'res1.pak')) -eq 'old fixture') 'Another tool copy cannot modify a locked game'
    } finally { $handle.Dispose() }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $entry 'InstallLocalMods.ps1') -Action Remove -GameDirectory $game -LogDirectory (Join-Path $testRoot 'childlogs') | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $game 'res1.pak'))) 'Real entry point removes without PAKTool or Steam discovery'
    $exportOut=Join-Path $testRoot 'child-export.txt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $entry 'InstallLocalMods.ps1') -Action ExportLogs -DiagnosticPath $exportOut -LogDirectory (Join-Path $testRoot 'childlogs') | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exportOut)) 'Real entry point exports without game or PAKTool'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $entry 'InstallLocalMods.ps1') -Action Remove -GameDirectory (Join-Path $testRoot 'missing-game') -LogDirectory (Join-Path $testRoot 'childlogs') | Out-Null
    Assert ($LASTEXITCODE -eq 1) 'Real entry point preserves failure exit code'
    Assert ([IO.File]::ReadAllText((Join-Path $testRoot 'childlogs\activity.log')).Contains('hresult=0x')) 'Entry point logs failure details'
    Write-Host "PASS: $script:checks diagnostic and regression checks; fixtures only."
}
finally {
    $script:LogEnabled=$false
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $prefix=[IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('\')+'\'
    if (-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
