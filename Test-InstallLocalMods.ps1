$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$required = @(
    'InstallLocalMods.cmd',
    'InstallLocalMods.ps1',
    'Diagnostics.ps1',
    'ResTool\PAKTool.exe',
    'ResTool\Common.dll',
    'ResTool\Newtonsoft.Json.dll'
)

foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "缺少必需文件: $relative"
    }
}

foreach ($line in Get-Content -LiteralPath (Join-Path $root 'dependencies.sha256')) {
    if ($line -notmatch '^([a-f0-9]{64})  (ResTool/[A-Za-z.]+)$') { throw 'Invalid dependency manifest.' }
    if ((Get-FileHash -LiteralPath (Join-Path $root $matches[2]) -Algorithm SHA256).Hash -ne $matches[1]) { throw "Dependency checksum mismatch: $($matches[2])" }
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'InstallLocalMods.ps1'),
    [ref]$tokens,
    [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) {
    throw "InstallLocalMods.ps1 语法检查失败: $($errors[0].Message)"
}
foreach ($name in @('Diagnostics.ps1','Test-Diagnostics.ps1')) {
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw "Syntax error in $name" }
}

$help = & (Join-Path $root 'ResTool\PAKTool.exe') --help 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $help -notmatch 'collapsev1') {
    throw 'PAKTool smoke test 失败。'
}

Write-Host 'PASS: 文件、PowerShell 语法和 PAKTool smoke test 均通过。'
Write-Host '注意：此测试不会扫描或修改 Steam/Dead Cells 安装目录。'
