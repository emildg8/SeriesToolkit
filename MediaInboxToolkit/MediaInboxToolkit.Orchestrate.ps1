#requires -Version 5.1
<#
.SYNOPSIS
  Оркестратор: шаг 1 — MediaInboxToolkit (раскладка inbox), шаг 2 — опционально SeriesToolkit по выбранным корням сериалов.
.DESCRIPTION
  Не ломает существующие файлы: по умолчанию DryRun на шаге 1, если не передан -Apply.
  SeriesToolkit вызывается только с -RunSeriesToolkitAfter и явным списком -SeriesToolkitRoots (пока без авто-разбора CSV).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InboxPath,
    [string]$PolicyPath = '',
    [string]$LogDirectory = '',
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$UseTmdb,
    [string]$TmdbApiKey = '',
    [switch]$RunSeriesToolkitAfter,
    [string[]]$SeriesToolkitRoots = @(),
    [string]$SeriesToolkitEnginePath = '',
    [ValidateSet('Batch', 'Manual')]
    [string]$SeriesToolkitMode = 'Batch',
    [switch]$SkipAutoVersion,
    [switch]$SkipAutoSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $PSScriptRoot 'sort-inbox.example.json'
}
if ([string]::IsNullOrWhiteSpace($SeriesToolkitEnginePath)) {
    $SeriesToolkitEnginePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'SeriesToolkit\SeriesToolkit.Engine.ps1'
}

$launcher = Join-Path $PSScriptRoot 'MediaInboxToolkit.ps1'
if (-not (Test-Path -LiteralPath $launcher)) { throw "MediaInboxToolkit.ps1 not found: $launcher" }

Write-Host '=== [1/2] MediaInboxToolkit (inbox) ===' -ForegroundColor Cyan
& $launcher -PolicyPath $PolicyPath -InboxPath $InboxPath -LogDirectory $LogDirectory -UseTmdb:$UseTmdb `
    -TmdbApiKey $TmdbApiKey -Apply:$Apply -DryRun:$DryRun -SkipAutoVersion:$SkipAutoVersion -SkipAutoSync:$true

if (-not $RunSeriesToolkitAfter) {
    Write-Host 'SeriesToolkit пропущен (-RunSeriesToolkitAfter не указан).' -ForegroundColor DarkGray
    return
}
if (-not $Apply) {
    Write-Host 'SeriesToolkit не запускается без -Apply на шаге 1 (безопасность).' -ForegroundColor Yellow
    return
}
if (-not $SeriesToolkitRoots -or $SeriesToolkitRoots.Count -eq 0) {
    throw 'Укажите -SeriesToolkitRoots с путями к папкам сериалов для нормализации (пока без авто-вывода из CSV).'
}
if (-not (Test-Path -LiteralPath $SeriesToolkitEnginePath)) {
    throw "SeriesToolkit.Engine.ps1 не найден: $SeriesToolkitEnginePath"
}

foreach ($root in $SeriesToolkitRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Warning "Пропуск (нет пути): $root"
        continue
    }
    Write-Host "=== [2/2] SeriesToolkit: $root ===" -ForegroundColor Cyan
    $stArgs = @{
        Mode            = $SeriesToolkitMode
        RootPath        = $root
        LogDirectory    = if ([string]::IsNullOrWhiteSpace($LogDirectory)) { Join-Path $PSScriptRoot 'LOGS' } else { $LogDirectory }
        UseTmdb         = $UseTmdb
        DryRun          = (-not $Apply)
    }
    if (-not [string]::IsNullOrWhiteSpace($TmdbApiKey)) { $stArgs['TmdbApiKey'] = $TmdbApiKey }
    if ($Apply) { $stArgs['Apply'] = $true }
    & $SeriesToolkitEnginePath @stArgs
}
