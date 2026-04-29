#requires -Version 5.1
[CmdletBinding()]
param()

$legacyGui = $null
$candidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*SeriesToolkitGui*.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Start-SeriesToolkitGui.ps1' })
if ($candidates.Count -gt 0) {
    $legacyGui = $candidates[0].FullName
}
if (-not (Test-Path -LiteralPath $legacyGui)) {
    throw "GUI script not found next to launcher."
}

& $legacyGui
