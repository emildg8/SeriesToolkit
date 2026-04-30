#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$OutputFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-DeferredExeSwap {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentExe,
        [Parameter(Mandatory = $true)][string]$NewExe,
        [Parameter(Mandatory = $true)][string]$BakExe
    )
    $helper = Join-Path ([System.IO.Path]::GetTempPath()) ('SeriesToolkit-deferred-swap-{0}.ps1' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $scriptText = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$current = '$($CurrentExe -replace "'", "''")'
`$new = '$($NewExe -replace "'", "''")'
`$bak = '$($BakExe -replace "'", "''")'
for (`$i = 0; `$i -lt 600; `$i++) {
    if (-not (Test-Path -LiteralPath `$new)) { break }
    `$ready = `$false
    if (Test-Path -LiteralPath `$current) {
        try {
            Move-Item -LiteralPath `$current -Destination `$bak -Force
            `$ready = `$true
        } catch { Start-Sleep -Milliseconds 1000; continue }
    } else {
        `$ready = `$true
    }
    if (`$ready) {
        try {
            Move-Item -LiteralPath `$new -Destination `$current -Force
            break
        } catch {
            if (Test-Path -LiteralPath `$bak -and -not (Test-Path -LiteralPath `$current)) {
                try { Move-Item -LiteralPath `$bak -Destination `$current -Force } catch { }
            }
        }
    }
    Start-Sleep -Milliseconds 1000
}
try { Remove-Item -LiteralPath '$($helper -replace "'", "''")' -Force } catch { }
"@
    Set-Content -LiteralPath $helper -Value $scriptText -Encoding UTF8
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $helper) | Out-Null
    Write-Host "Deferred swap scheduled: $helper"
}

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
    Start-DeferredExeSwap -CurrentExe $OutputFile -NewExe $fallback -BakExe $bakOutput
}

Write-Host "EXE built: $finalOutput"
