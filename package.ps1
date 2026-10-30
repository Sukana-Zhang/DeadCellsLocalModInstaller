$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version.' }
$allowed = @('InstallLocalMods.cmd','InstallLocalMods.ps1','README.md','README.en.md','README.txt','LICENSE','VERSION','THIRD-PARTY-NOTICES.md','dependencies.sha256','ResTool/PAKTool.exe','ResTool/Common.dll','ResTool/Newtonsoft.Json.dll','licenses/alivecells-MIT.txt','licenses/Newtonsoft.Json-MIT.txt')
$stage = Join-Path $PSScriptRoot ('build\package-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stage 'DeadCellsLocalModInstaller'
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $packageRoot,$dist | Out-Null
try {
    foreach ($file in $allowed) {
        $source = Join-Path $PSScriptRoot $file
        $target = Join-Path $packageRoot $file
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    $zip = Join-Path $dist "DeadCellsLocalModInstaller-$version-win.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $actual = @($archive.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName.Replace('\','/') })
        $expected = @($allowed | ForEach-Object { "DeadCellsLocalModInstaller/$_" })
        if (@(Compare-Object $actual $expected).Count -gt 0) { throw 'Unexpected package contents.' }
    } finally { $archive.Dispose() }
    [IO.File]::WriteAllText(($zip + '.sha256'),((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip) + [Environment]::NewLine),[Text.Encoding]::ASCII)
    Write-Host "Verified allowlisted package: $zip"
}
finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $prefix = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'build')).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
