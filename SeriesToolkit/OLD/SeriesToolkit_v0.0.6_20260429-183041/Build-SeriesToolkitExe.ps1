#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($OutputFile)) { $OutputFile = Join-Path $ProjectRoot 'SeriesToolkit.GUI.exe' }

$guiScript = Join-Path $ProjectRoot 'Start-SeriesToolkitGui.ps1'
if (-not (Test-Path -LiteralPath $guiScript)) { throw "GUI script not found: $guiScript" }

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    } catch {
        throw "Не удалось установить модуль ps2exe: $($_.Exception.Message)"
    }
}

Invoke-ps2exe -InputFile $guiScript -OutputFile $OutputFile -noConsole -title 'SeriesToolkit GUI' -description 'SeriesToolkit GUI launcher'
Write-Host "EXE built: $OutputFile"
