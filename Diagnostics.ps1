$script:LogEnabled = $false
$script:LogFailure = ''
$script:RunId = [Guid]::NewGuid().ToString('N')
$script:Stage = 'startup'
$script:LogRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DeadCellsLocalModInstaller\Logs'

function Protect-LogText([string]$text) {
    $profilePath = [Environment]::GetFolderPath('UserProfile')
    if ($profilePath) { $text = [regex]::Replace($text,[regex]::Escape($profilePath),'%USERPROFILE%',[Text.RegularExpressions.RegexOptions]::IgnoreCase) }
    $text = [regex]::Replace($text,'S-1-5-21-\d+-\d+-\d+-\d+','<user-sid>')
    return [regex]::Replace($text,'(?i)(with stamp\s+)[a-f0-9]{64}','$1<redacted>')
}

function Write-InstallerLog([string]$level, [string]$message) {
    if (-not $script:LogEnabled) { return }
    try {
        New-Item -ItemType Directory -Force -Path $script:LogRoot | Out-Null
        $path = Join-Path $script:LogRoot 'activity.log'
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -ge 1MB) {
            $previous = Join-Path $script:LogRoot 'activity.previous.log'
            if (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Force }
            Move-Item -LiteralPath $path -Destination $previous
        }
        $safe = Protect-LogText $message
        if ($safe.Length -gt 8192) { $safe = $safe.Substring(0,8192) + ' [truncated]' }
        $line = [ordered]@{time=[DateTimeOffset]::Now.ToString('o');run=$script:RunId;level=$level;stage=$script:Stage;message=$safe} | ConvertTo-Json -Compress
        [IO.File]::AppendAllText($path,($line + [Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
    }
    catch {
        if (-not $script:LogFailure) { Write-Warning '无法写入日志；操作会继续。可用导出日志查看环境信息。' }
        $script:LogFailure = Protect-LogText $_.Exception.Message
    }
}

function Set-InstallerStage([string]$stage) {
    $script:Stage = $stage
    Write-InstallerLog INFO 'begin'
}

function Write-InstallerException($record) {
    $exception = $record.Exception
    Write-InstallerLog ERROR ('type=' + $exception.GetType().FullName + ' hresult=' + ('0x{0:X8}' -f $exception.HResult) + ' message=' + $exception.Message + ' stack=' + $record.ScriptStackTrace)
}

function Get-DiagnosticHeader {
    $version = (Get-Content -LiteralPath (Join-Path $scriptRoot 'VERSION') -Raw).Trim()
    return "Dead Cells Local Mod Installer diagnostics`r`nversion=$version`r`nos=$([Environment]::OSVersion.VersionString)`r`npowershell=$($PSVersionTable.PSVersion)`r`nprocess64=$([Environment]::Is64BitProcess) os64=$([Environment]::Is64BitOperatingSystem)`r`nlog-write-error=$script:LogFailure"
}

function Read-LogTail([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '(not present)' }
    $stream = New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length = [int][Math]::Min($stream.Length,512KB)
        $buffer = New-Object byte[] $length
        $stream.Position = $stream.Length - $length
        $read = 0
        while ($read -lt $length) { $count = $stream.Read($buffer,$read,$length-$read); if ($count -eq 0) { break }; $read += $count }
        return [Text.Encoding]::UTF8.GetString($buffer,0,$read)
    } finally { $stream.Dispose() }
}

function Export-InstallerLogs([string]$destination) {
    if (-not $destination) { $destination = Join-Path $scriptRoot ('DeadCells-diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.txt') }
    if ([IO.Path]::GetExtension($destination) -ne '.txt') { throw '诊断导出文件必须使用 .txt 扩展名。' }
    $content = (Get-DiagnosticHeader) + "`r`nexported=$([DateTimeOffset]::Now.ToString('o'))`r`n"
    foreach ($name in @('activity.previous.log','activity.log')) {
        $content += "`r`n--- $name ---`r`n"
        try { $content += Read-LogTail (Join-Path $script:LogRoot $name) } catch { $content += 'read-error=' + $_.Exception.GetType().Name }
    }
    $content = Protect-LogText $content
    $stream = [IO.File]::Open([IO.Path]::GetFullPath($destination),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes = (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($content); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    Write-Host "诊断日志已导出: $destination"
    return $destination
}
