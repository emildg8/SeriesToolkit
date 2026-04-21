#requires -Version 5.1
# Автовыпуск новой версии: копия текущего скрипта в old, новый номер в корне, cmd, CHANGELOG, ротация archive.
param(
    [string]$ToolkitRoot = '',
    [Parameter(Mandatory = $true)]
    [string]$NextVersion,
    [string]$ChangelogNote = ''
)
$ErrorActionPreference = 'Stop'
if (-not $ToolkitRoot) {
    $ToolkitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ($NextVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "NextVersion must be like 0.2.9 (got: $NextVersion)"
}
$main = Get-ChildItem -LiteralPath $ToolkitRoot -File -Filter 'Script_Rename_ALLVideo_*.ps1' |
    Sort-Object { [version]($_.BaseName -replace '^Script_Rename_ALLVideo_', '') } -Descending |
    Select-Object -First 1
if (-not $main) {
    throw "No Script_Rename_ALLVideo_*.ps1 in $ToolkitRoot"
}
$curVer = ($main.BaseName -replace '^Script_Rename_ALLVideo_', '')
if ([version]$NextVersion -le [version]$curVer) {
    throw "NextVersion ($NextVersion) must be greater than current ($curVer)"
}

$oldDir = Join-Path $ToolkitRoot 'Old'
$archiveDir = Join-Path $ToolkitRoot 'archive'
$logsDir = Join-Path $ToolkitRoot 'logs'
foreach ($d in @($oldDir, $archiveDir, $logsDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d | Out-Null
    }
}

$backupDest = Join-Path $oldDir ($main.Name)
Copy-Item -LiteralPath $main.FullName -Destination $backupDest -Force
function Set-ToolkitVersionLine([string]$content, [string]$version) {
    $nl = if ($content -match "`r`n") { "`r`n" } elseif ($content -match "`n") { "`n" } else { "`r`n" }
    $lines = $content -split '\r?\n', -1
    $done = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].IndexOf('$script:ToolkitVersion', [System.StringComparison]::Ordinal) -ge 0 -and
            $lines[$i].IndexOf('=', [System.StringComparison]::Ordinal) -gt 0) {
            $lines[$i] = '$script:ToolkitVersion = ''' + $version + ''''
            $done = $true
            break
        }
    }
    if (-not $done) { throw "Could not find `$script:ToolkitVersion line." }
    return ($lines -join $nl)
}

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$backupText = [System.IO.File]::ReadAllText($backupDest, $utf8NoBom)
$backupText = Set-ToolkitVersionLine $backupText $curVer
[System.IO.File]::WriteAllText($backupDest, $backupText, $utf8Bom)
Write-Host "Backup -> $backupDest (ToolkitVersion=$curVer)"

$text = [System.IO.File]::ReadAllText($main.FullName, $utf8NoBom)
$text2 = Set-ToolkitVersionLine $text $NextVersion
$newName = "Script_Rename_ALLVideo_$NextVersion.ps1"
$newPath = Join-Path $ToolkitRoot $newName
[System.IO.File]::WriteAllText($newPath, $text2, $utf8Bom)
Write-Host "Created $newPath"

Remove-Item -LiteralPath $main.FullName -Force
Write-Host "Removed $($main.Name) from toolkit root."

$cmdPath = $null
$cmdCand = Get-ChildItem -LiteralPath $ToolkitRoot -File -Filter '*.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmdCand) { $cmdPath = $cmdCand.FullName }
if ($cmdPath -and (Test-Path -LiteralPath $cmdPath)) {
    $cmd = [System.IO.File]::ReadAllText($cmdPath, [System.Text.UTF8Encoding]::new($false))
    $cmd2 = $cmd -replace 'Script_Rename_ALLVideo_[\d.]+\.ps1', $newName
    [System.IO.File]::WriteAllText($cmdPath, $cmd2, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Updated Переименовать-сериал.cmd -> $newName"
}

$clPath = Join-Path $logsDir 'CHANGELOG.md'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$entry = "`n## $NextVersion - $stamp`n"
if ($ChangelogNote) {
    $entry += "`n$ChangelogNote`n"
} else {
    $entry += "`n- Выпуск версии $NextVersion (см. коммит / описание задачи).`n"
}
Add-Content -LiteralPath $clPath -Value $entry -Encoding UTF8
Write-Host "Appended CHANGELOG.md"

$rotate = Join-Path $ToolkitRoot 'Rotate-ToolkitBackups.ps1'
if (Test-Path -LiteralPath $rotate) {
    & $rotate -ToolkitRoot $ToolkitRoot
}

Write-Host "Done. Current release: $newName"
