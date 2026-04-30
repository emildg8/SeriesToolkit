#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$VersionFile = '',
    [string]$ChangelogPath = '',
    [string]$ProjectRoot = '',
    [string]$ChangeNote = 'Auto version bump'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VersionFile)) {
    $VersionFile = Join-Path $PSScriptRoot 'version.json'
}
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($ChangelogPath)) {
    $ChangelogPath = Join-Path $ProjectRoot 'CHANGELOG.md'
}
if (-not (Test-Path -LiteralPath $VersionFile)) { throw "version file not found: $VersionFile" }
$obj = Get-Content -LiteralPath $VersionFile -Raw -Encoding UTF8 | ConvertFrom-Json
$oldVersion = [string]$obj.version
$parts = ([string]$obj.version).Split('.')
if ($parts.Count -ne 3) { throw "invalid version: $($obj.version)" }
$maj = [int]$parts[0]; $min = [int]$parts[1]; $pat = [int]$parts[2]

$pat++
if ($pat -gt 9) { $pat = 0; $min++ }
if ($min -gt 9) { $min = 0; $maj++ }

$obj.version = "$maj.$min.$pat"
$obj.releasedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$json = $obj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($VersionFile, $json, [System.Text.UTF8Encoding]::new($true))

$newVersion = [string]$obj.version
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss K'

# Снимок текущего состояния проекта в OLD/version
$oldRoot = Join-Path $ProjectRoot 'OLD'
if (-not (Test-Path -LiteralPath $oldRoot)) {
    New-Item -ItemType Directory -Path $oldRoot -Force | Out-Null
}
$snapshotDir = Join-Path $oldRoot ("SeriesToolkit_v{0}_{1}" -f $oldVersion, (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
foreach ($name in @('SeriesToolkit.ps1', 'SeriesToolkit.Engine.ps1', 'Start-SeriesToolkitGui.ps1', 'Start-SeriesToolkitGui.Engine.ps1', 'UiStrings.ps1', 'README.md', 'CHANGELOG.md', 'version.json', 'Build-SeriesToolkitExe.ps1', 'Sync-GitHub.ps1', 'SeriesToolkit.settings.example.json', 'SeriesToolkit.settings.README.md')) {
    $p = Join-Path $ProjectRoot $name
    if (Test-Path -LiteralPath $p) {
        Copy-Item -LiteralPath $p -Destination (Join-Path $snapshotDir $name) -Force
    }
}

if (Test-Path -LiteralPath $ChangelogPath) {
    $existing = Get-Content -LiteralPath $ChangelogPath -Raw -Encoding UTF8
    $entry = "## $newVersion - $stamp`n- $ChangeNote`n- Автоматически создан snapshot предыдущей версии: `OLD/$(Split-Path -Leaf $snapshotDir)`.`n"
    $updated = if ($existing -match '^#\s*CHANGELOG\s*') {
        $existing -replace '^(#\s*CHANGELOG\s*\r?\n)', ('$1' + "`r`n" + $entry + "`r`n")
    } else {
        "# CHANGELOG`r`n`r`n$entry`r`n$existing"
    }
    [System.IO.File]::WriteAllText($ChangelogPath, $updated, [System.Text.UTF8Encoding]::new($true))
}

Write-Host $newVersion

