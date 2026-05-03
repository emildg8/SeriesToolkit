#requires -Version 5.1
<#
.SYNOPSIS
  Точка входа MediaInboxToolkit — входная сортировка видео (NAS / локально).
#>
[CmdletBinding()]
param(
    [string]$PolicyPath = '',
    [string]$InboxPath = '',
    [string]$LogDirectory = '',
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$UseTmdb,
    [string]$TmdbApiKey = '',
    [switch]$SkipAutoVersion,
    [switch]$SkipAutoSync
)

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot 'sort-inbox.example.json'
}

if (-not $SkipAutoVersion) {
    $bump = Join-Path $PSScriptRoot 'Bump-Version.ps1'
    if (Test-Path -LiteralPath $bump) {
        try {
            & $bump -ProjectRoot $PSScriptRoot -ChangeNote "Автоинкремент при изменении MediaInboxToolkit.ps1."
        } catch { }
    }
}

$engine = Join-Path $PSScriptRoot 'MediaInboxToolkit.Engine.ps1'
if (-not (Test-Path -LiteralPath $engine)) {
    throw "Engine not found: $engine"
}

$runArgs = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($k -in @('SkipAutoVersion', 'SkipAutoSync')) { continue }
    $runArgs[$k] = $PSBoundParameters[$k]
}
$runArgs['PolicyPath'] = $PolicyPath
if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $runArgs['LogDirectory'] = Join-Path $PSScriptRoot 'LOGS'
} else {
    $runArgs['LogDirectory'] = $LogDirectory
}

& $engine @runArgs

$syncScript = Join-Path $PSScriptRoot 'Sync-GitHub.ps1'
if ((-not $SkipAutoSync) -and (Test-Path -LiteralPath $syncScript)) {
    try { & $syncScript -ProjectRoot $PSScriptRoot } catch { }
}
