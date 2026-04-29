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
    [switch]$SkipAutoVersion
)

$legacyScript = $null
$candidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*SeriesToolkit*.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'SeriesToolkit.ps1' -and $_.Name -ne 'Start-SeriesToolkitGui.ps1' -and $_.Name -ne 'Start-SeriesToolkitGui.Engine.ps1' })
if ($candidates.Count -gt 0) {
    $legacyScript = $candidates[0].FullName
}
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
& $legacyScript @runArgs

$syncScript = Join-Path $PSScriptRoot 'Sync-GitHub.ps1'
if (Test-Path -LiteralPath $syncScript) {
    try { & $syncScript -ProjectRoot $PSScriptRoot } catch { }
}
