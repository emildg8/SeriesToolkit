#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Batch', 'Manual')]
    [string]$Mode = 'Batch',
    [string]$RootPath = '\\Emilian_TNAS\emildg8\Video\Мультсериалы',
    [string]$SeriesPath = '',
    [string]$ReferenceRootPath = '\\Emilian_TNAS\emildg8\Video\Сериалы',
    [string]$HtmlPath = '',
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

$legacyScript = Join-Path $PSScriptRoot 'SeriesToolkit.Engine.ps1'
if ($null -eq $legacyScript -or -not (Test-Path -LiteralPath $legacyScript)) {
    throw "Engine script not found next to launcher."
}

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $PSScriptRoot 'LOGS'
}

if (-not $SkipAutoVersion) {
    $bump = Join-Path $PSScriptRoot 'Bump-Version.ps1'
    if (Test-Path -LiteralPath $bump) {
        try {
            & $bump -ProjectRoot $PSScriptRoot -ChangeNote "Автоинкремент версии при запуске SeriesToolkit ($Mode)."
        } catch { }
    }
}

$runArgs = @{}
foreach ($k in $PSBoundParameters.Keys) { $runArgs[$k] = $PSBoundParameters[$k] }
$runArgs['LogDirectory'] = $LogDirectory
$null = $runArgs.Remove('SkipAutoVersion')
$null = $runArgs.Remove('SkipAutoSync')
& $legacyScript @runArgs

$syncScript = Join-Path $PSScriptRoot 'Sync-GitHub.ps1'
if ((-not $SkipAutoSync) -and (Test-Path -LiteralPath $syncScript)) {
    try { & $syncScript -ProjectRoot $PSScriptRoot } catch { }
}
