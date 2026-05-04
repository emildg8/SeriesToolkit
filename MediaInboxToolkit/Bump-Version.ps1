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
$launcherPath = Join-Path $ProjectRoot 'MediaInboxToolkit.ps1'
if (-not (Test-Path -LiteralPath $launcherPath)) { throw "launcher not found: $launcherPath" }
$statePath = Join-Path $ProjectRoot '.launcher-content.sha256'
$bytes = [System.IO.File]::ReadAllBytes($launcherPath)
$sha = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
$prevSha = $null
if (Test-Path -LiteralPath $statePath) {
    try { $prevSha = (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8).Trim().ToLowerInvariant() } catch { }
}
if ($prevSha -eq $sha) {
    $vfQuick = if (Test-Path -LiteralPath $VersionFile) { $VersionFile } else { Join-Path $ProjectRoot 'version.json' }
    try {
        $vo = Get-Content -LiteralPath $vfQuick -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ([string]$vo.version)
    } catch {
        Write-Host 'unchanged'
    }
    return
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

$oldRoot = Join-Path $ProjectRoot 'OLD'
if (-not (Test-Path -LiteralPath $oldRoot)) {
    New-Item -ItemType Directory -Path $oldRoot -Force | Out-Null
}
$snapshotDir = Join-Path $oldRoot ("MediaInboxToolkit_v{0}_{1}" -f $oldVersion, (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
foreach ($name in @(
        'MediaInboxToolkit.ps1', 'MediaInboxToolkit.Engine.ps1', 'MediaInboxToolkit.ContentKinds.ps1',
        'MediaInboxToolkit.Orchestrate.ps1', 'Publish-MediaInboxStandalone.ps1',
        'README.md', 'CHANGELOG.md', 'version.json',
        'Sync-GitHub.ps1', 'sort-inbox.example.json', 'docs/SORT-INBOX-PLAN.md',
        'docs/CLASSIFICATION-ROADMAP.md', 'docs/OFFLINE-METADATA.md', 'docs/INSPIRATION-SERIESTOOLKIT.md', 'docs/GUI-EXE-ROADMAP.md'
    )) {
    $p = Join-Path $ProjectRoot $name
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $dest = Join-Path $snapshotDir $name
    $destParent = Split-Path -Parent $dest
    if (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Copy-Item -LiteralPath $p -Destination $dest -Force
}

if (Test-Path -LiteralPath $ChangelogPath) {
    $existing = Get-Content -LiteralPath $ChangelogPath -Raw -Encoding UTF8
    $entry = "## $newVersion - $stamp`n- $ChangeNote`n- Snapshot: OLD/$(Split-Path -Leaf $snapshotDir) (launcher MediaInboxToolkit.ps1).`n"
    $updated = if ($existing -match '^#\s*CHANGELOG\s*') {
        $existing -replace '^(#\s*CHANGELOG\s*\r?\n)', ('$1' + "`r`n" + $entry + "`r`n")
    } else {
        "# CHANGELOG`r`n`r`n$entry`r`n$existing"
    }
    [System.IO.File]::WriteAllText($ChangelogPath, $updated, [System.Text.UTF8Encoding]::new($true))
}

[System.IO.File]::WriteAllText($statePath, $sha, [System.Text.UTF8Encoding]::new($false))

Write-Host $newVersion
