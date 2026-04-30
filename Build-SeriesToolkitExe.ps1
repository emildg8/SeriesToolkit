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
$outputDir = Split-Path -Parent $OutputFile
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Компилируем Engine напрямую: ps2exe не должен вызывать второй .ps1 через & (ломается внутри EXE).
$guiScript = Join-Path $ProjectRoot 'Start-SeriesToolkitGui.Engine.ps1'
if (-not (Test-Path -LiteralPath $guiScript)) { throw "GUI Engine script not found: $guiScript" }

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    } catch {
        throw "Не удалось установить модуль ps2exe: $($_.Exception.Message)"
    }
}

$tmpOut = Join-Path $outputDir ('SeriesToolkit.GUI.build-{0}.exe' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$iconPath = Join-Path $ProjectRoot 'assets\SeriesToolkit.icon.ico'
if (Test-Path -LiteralPath $iconPath) {
    Invoke-ps2exe -InputFile $guiScript -OutputFile $tmpOut -noConsole -iconFile $iconPath -title 'SeriesToolkit GUI' -description 'SeriesToolkit GUI launcher'
} else {
    Invoke-ps2exe -InputFile $guiScript -OutputFile $tmpOut -noConsole -title 'SeriesToolkit GUI' -description 'SeriesToolkit GUI launcher'
}

$finalOutput = $OutputFile
$bakOutput = $OutputFile + '.bak'
try {
    if (Test-Path -LiteralPath $bakOutput) {
        Remove-Item -LiteralPath $bakOutput -Force
    }
} catch { }

try {
    if (Test-Path -LiteralPath $OutputFile) {
        Move-Item -LiteralPath $OutputFile -Destination $bakOutput -Force
        Write-Host "Rotated old EXE to: $bakOutput"
    }
    Move-Item -LiteralPath $tmpOut -Destination $OutputFile -Force
    $finalOutput = $OutputFile
} catch {
    $fallback = Join-Path $outputDir 'SeriesToolkit.GUI.new.exe'
    if (Test-Path -LiteralPath $fallback) {
        try { Remove-Item -LiteralPath $fallback -Force } catch { }
    }
    Move-Item -LiteralPath $tmpOut -Destination $fallback -Force
    $finalOutput = $fallback
    Write-Warning "Main EXE is locked; wrote fallback EXE: $fallback"
}

Write-Host "EXE built: $finalOutput"
