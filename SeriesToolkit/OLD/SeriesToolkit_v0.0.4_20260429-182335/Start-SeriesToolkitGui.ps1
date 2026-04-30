#requires -Version 5.1
[CmdletBinding()]
param()

$legacyGui = Join-Path $PSScriptRoot 'Start-SeriesToolkitGui.Engine.ps1'
if (-not (Test-Path -LiteralPath $legacyGui)) {
    throw "GUI script not found next to launcher."
}

& $legacyGui
