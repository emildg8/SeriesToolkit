#requires -Version 5.1
[CmdletBinding()]
param()

function Get-SeriesToolkitInstallRoot {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $PSScriptRoot }
    $p = $MyInvocation.MyCommand.Path
    if (-not [string]::IsNullOrWhiteSpace($p)) {
        $d = Split-Path -Parent $p
        if (-not [string]::IsNullOrWhiteSpace($d)) { return $d }
    }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($exe)) { return (Split-Path -Parent $exe) }
    } catch { }
    throw 'Не удалось определить папку установки SeriesToolkit (PSScriptRoot пуст; для .exe нужен ps2exe рядом с остальными файлами).'
}

$toolkitRoot = Get-SeriesToolkitInstallRoot
$legacyGui = Join-Path $toolkitRoot 'Start-SeriesToolkitGui.Engine.ps1'
if (-not (Test-Path -LiteralPath $legacyGui)) {
    throw "GUI script not found next to launcher: $legacyGui"
}

& $legacyGui -ToolkitRoot $toolkitRoot
