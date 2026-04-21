#requires -Version 5.1
# Вызов вручную после добавления очередной копии в папку old.
# Правило: в Old хранится не более $MaxInOld файлов Script_Rename_ALLVideo_*.ps1; более старые переносятся в archive.
param(
    [string]$ToolkitRoot = '',
    [int]$MaxInOld = 1000
)
$ErrorActionPreference = 'Stop'
if (-not $ToolkitRoot) {
    $ToolkitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$oldDir = Join-Path $ToolkitRoot 'Old'
$archiveDir = Join-Path $ToolkitRoot 'archive'
if (-not (Test-Path -LiteralPath $oldDir)) {
    Write-Host "No folder: $oldDir"
    exit 0
}
if (-not (Test-Path -LiteralPath $archiveDir)) {
    New-Item -ItemType Directory -Path $archiveDir | Out-Null
}
$files = @(Get-ChildItem -LiteralPath $oldDir -File -Filter 'Script_Rename_ALLVideo_*.ps1' | Sort-Object LastWriteTime)
if ($files.Count -le $MaxInOld) {
    Write-Host "OK: $($files.Count) backup(s) in old (limit $MaxInOld)."
    exit 0
}
$toMove = $files.Count - $MaxInOld
$files | Select-Object -First $toMove | ForEach-Object {
    $dest = Join-Path $archiveDir $_.Name
    $n = 1
    while (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $archiveDir ($_.BaseName + '_' + $n + $_.Extension)
        $n++
    }
    Move-Item -LiteralPath $_.FullName -Destination $dest -Force
    Write-Host "Moved to archive: $($_.Name) -> $(Split-Path -Leaf $dest)"
}
Write-Host "Done. Moved $toMove file(s) to archive."
