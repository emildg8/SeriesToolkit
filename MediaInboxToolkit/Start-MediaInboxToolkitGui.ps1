#requires -Version 5.1
[CmdletBinding()]
param()

function Get-MediaInboxToolkitInstallRoot {
    $envRoot = [Environment]::GetEnvironmentVariable('MEDIAINBOXTOOLKIT_ROOT', 'User')
    if (-not [string]::IsNullOrWhiteSpace($envRoot)) { return $envRoot.Trim().TrimEnd('\', '/') }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $PSScriptRoot }
    $p = $MyInvocation.MyCommand.Path
    if (-not [string]::IsNullOrWhiteSpace($p)) {
        $d = Split-Path -Parent $p
        if (-not [string]::IsNullOrWhiteSpace($d)) { return $d }
    }
    try {
        $argv = [Environment]::GetCommandLineArgs()
        if ($argv -and $argv.Length -gt 0 -and [string]$argv[0] -match '\.exe$' -and (Test-Path -LiteralPath $argv[0])) {
            return (Split-Path -Parent $argv[0])
        }
    } catch { }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe)) { return (Split-Path -Parent $exe) }
    } catch { }
    throw 'Не удалось определить папку MediaInboxToolkit. Задайте MEDIAINBOXTOOLKIT_ROOT или запускайте из каталога со скриптами.'
}

$toolkitRoot = Get-MediaInboxToolkitInstallRoot
$engineGui = Join-Path $toolkitRoot 'Start-MediaInboxToolkitGui.Engine.ps1'
if (-not (Test-Path -LiteralPath $engineGui)) {
    throw "GUI script not found: $engineGui"
}
& (Resolve-Path -LiteralPath $engineGui).Path -ToolkitRoot $toolkitRoot
