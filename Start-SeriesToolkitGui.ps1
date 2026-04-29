#requires -Version 5.1
[CmdletBinding()]
param()

$legacyGui = Join-Path $PSScriptRoot 'Start-CartoonSeriesToolkitGui.ps1'
if (-not (Test-Path -LiteralPath $legacyGui)) {
    throw "Legacy GUI launcher not found: $legacyGui"
}

& $legacyGui
