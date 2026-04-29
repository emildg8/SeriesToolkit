#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$VersionFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($VersionFile)) {
    $VersionFile = Join-Path $PSScriptRoot 'version.json'
}
if (-not (Test-Path -LiteralPath $VersionFile)) { throw "version file not found: $VersionFile" }
$obj = Get-Content -LiteralPath $VersionFile -Raw -Encoding UTF8 | ConvertFrom-Json
$parts = ([string]$obj.version).Split('.')
if ($parts.Count -ne 3) { throw "invalid version: $($obj.version)" }
$maj = [int]$parts[0]; $min = [int]$parts[1]; $pat = [int]$parts[2]

$pat++
if ($pat -gt 9) { $pat = 0; $min++ }
if ($min -gt 9) { $min = 0; $maj++ }

$obj.version = "$maj.$min.$pat"
$obj.releasedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$json = $obj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($VersionFile, $json, [System.Text.UTF8Encoding]::new($true))
Write-Host $obj.version

