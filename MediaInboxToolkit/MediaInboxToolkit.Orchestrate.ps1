#requires -Version 5.1
<#
.SYNOPSIS
  Оркестратор: шаг 1 — MediaInboxToolkit (раскладка inbox), шаг 2 — опционально SeriesToolkit по выбранным корням сериалов.
.DESCRIPTION
  Не ломает существующие файлы: по умолчанию DryRun на шаге 1, если не передан -Apply.
  SeriesToolkit вызывается только с -RunSeriesToolkitAfter и непустым списком корней (вручную и/или из последнего CSV шага 1).
#>

function Get-MediaInboxSeriesToolkitRootsFromCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath
    )
    if (-not (Test-Path -LiteralPath $CsvPath)) {
        Write-Warning "CSV не найден: $CsvPath"
        return @()
    }
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in Import-Csv -LiteralPath $CsvPath) {
        if ([string]::IsNullOrWhiteSpace([string]$row.Kind)) { continue }
        if ([string]$row.Kind -ne 'series') { continue }
        $n = [string]$row.Notes
        if ($n -match '^skip_') { continue }
        if ($row.PSObject.Properties.Name -contains 'DestRootKey' -and [string]$row.DestRootKey -eq 'review') { continue }
        $dest = [string]$row.DestFullPath
        if ([string]::IsNullOrWhiteSpace($dest)) { continue }
        try {
            $seasonDir = [System.IO.Path]::GetDirectoryName($dest)
            if ([string]::IsNullOrWhiteSpace($seasonDir)) { continue }
            $seriesRoot = [System.IO.Path]::GetDirectoryName($seasonDir)
            if ([string]::IsNullOrWhiteSpace($seriesRoot)) { continue }
            [void]$set.Add($seriesRoot)
        } catch { }
    }
    return @($set)
}

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
    [switch]$SeriesToolkitRootsFromLastCsv,
    [string]$SeriesToolkitCsvPath = '',
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

$logDirResolved = if ([string]::IsNullOrWhiteSpace($LogDirectory)) { Join-Path $PSScriptRoot 'LOGS' } else { $LogDirectory }

Write-Host '=== [1/2] MediaInboxToolkit (inbox) ===' -ForegroundColor Cyan
& $launcher -PolicyPath $PolicyPath -InboxPath $InboxPath -LogDirectory $logDirResolved -UseTmdb:$UseTmdb `
    -TmdbApiKey $TmdbApiKey -Apply:$Apply -DryRun:$DryRun -SkipAutoVersion:$SkipAutoVersion -SkipAutoSync:$true

if (-not $RunSeriesToolkitAfter) {
    Write-Host 'SeriesToolkit пропущен (-RunSeriesToolkitAfter не указан).' -ForegroundColor DarkGray
    return
}
if (-not $Apply) {
    Write-Host 'SeriesToolkit не запускается без -Apply на шаге 1 (безопасность).' -ForegroundColor Yellow
    return
}

$resolvedCsv = ''
if (-not [string]::IsNullOrWhiteSpace($SeriesToolkitCsvPath)) {
    $resolvedCsv = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SeriesToolkitCsvPath)
}
elseif ($SeriesToolkitRootsFromLastCsv) {
    if (-not (Test-Path -LiteralPath $logDirResolved)) {
        throw "LOGS не найден: $logDirResolved"
    }
    $latest = Get-ChildItem -LiteralPath $logDirResolved -Filter 'sort-inbox-*.csv' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "В $logDirResolved нет sort-inbox-*.csv после шага 1."
    }
    $resolvedCsv = $latest.FullName
}

$mergedRoots = [System.Collections.Generic.List[string]]::new()
foreach ($r in @($SeriesToolkitRoots)) {
    if (-not [string]::IsNullOrWhiteSpace($r)) { [void]$mergedRoots.Add($r.Trim()) }
}
if (-not [string]::IsNullOrWhiteSpace($resolvedCsv)) {
    foreach ($auto in (Get-MediaInboxSeriesToolkitRootsFromCsv -CsvPath $resolvedCsv)) {
        [void]$mergedRoots.Add($auto)
    }
}

$unique = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$finalRoots = [System.Collections.Generic.List[string]]::new()
foreach ($x in $mergedRoots) {
    if ([string]::IsNullOrWhiteSpace($x)) { continue }
    if ($unique.Add($x)) { [void]$finalRoots.Add($x) }
}

if ($finalRoots.Count -eq 0) {
    throw 'Укажите -SeriesToolkitRoots и/или -SeriesToolkitRootsFromLastCsv (или явный -SeriesToolkitCsvPath).'
}
if (-not (Test-Path -LiteralPath $SeriesToolkitEnginePath)) {
    throw "SeriesToolkit.Engine.ps1 не найден: $SeriesToolkitEnginePath"
}
if (-not [string]::IsNullOrWhiteSpace($resolvedCsv)) {
    Write-Host "Корни SeriesToolkit из CSV: $resolvedCsv ($($finalRoots.Count) путей)." -ForegroundColor DarkGray
}

foreach ($root in $finalRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Warning "Пропуск (нет пути, возможен только DryRun шага 1): $root"
        continue
    }
    Write-Host "=== [2/2] SeriesToolkit: $root ===" -ForegroundColor Cyan
    $stArgs = @{
        Mode         = $SeriesToolkitMode
        RootPath     = $root
        LogDirectory = $logDirResolved
        UseTmdb      = $UseTmdb
        DryRun       = (-not $Apply)
    }
    if (-not [string]::IsNullOrWhiteSpace($TmdbApiKey)) { $stArgs['TmdbApiKey'] = $TmdbApiKey }
    if ($Apply) { $stArgs['Apply'] = $true }
    & $SeriesToolkitEnginePath @stArgs
}
