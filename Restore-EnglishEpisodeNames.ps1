#requires -Version 5.1
# Восстанавливает имена файлов вида "Series - S01E01 - English title.ext" из episode-titles.csv
# (берёт последний блок «...» с латиницей в колонке title).
param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,
    [string]$TitlesCsv = '',
    [string]$SeriesTitleEnglish = 'Castle',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Sanitize-WinFileName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }
    $name = $name -replace '[\p{Cc}\p{Cf}]', ''
    $invalid = '[\\/:*?"<>|]'
    $name = $name -replace $invalid, ' '
    $name = $name -replace '\s+', ' '
    $name = $name.Trim()
    do {
        $prev = $name
        $name = $name.TrimEnd(' ', '.', [char]0xA0)
    } while ($name -ne $prev -and -not [string]::IsNullOrWhiteSpace($name))
    if ($name.Length -gt 180) { $name = $name.Substring(0, 180).TrimEnd(' ', '.') }
    return $name
}

function Clear-HiddenAttribute([string]$LiteralPath) {
    $i = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue
    if (-not $i) { return }
    $h = [System.IO.FileAttributes]::Hidden
    if ($i.Attributes -band $h) { $i.Attributes = $i.Attributes -bxor $h }
}

function Get-EnglishTitleFromCsvCell([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $t = ($raw -replace '[\p{Cc}\p{Cf}]', '').Trim()
    # Типично: ...русский» «English Title" (закрывающая «» в CSV может отсутствовать)
    $lastGuillemet = $t.LastIndexOf([char]0x00AB)
    if ($lastGuillemet -ge 0) {
        $rest = $t.Substring($lastGuillemet + 1).Trim()
        $rest = $rest -replace '\s*»\s*.*$', ''
        $rest = $rest -replace '"\s*$', ''
        $rest = $rest -replace '(?i)\s*RTitle\s*=\s*.*$', ''
        $rest = $rest.Trim()
        if ($rest -match '^[A-Za-z0-9]') { return $rest }
    }
    $best = $null
    foreach ($m in [regex]::Matches($t, '«\s*([A-Za-z][^»]*)\s*»')) {
        $best = $m.Groups[1].Value.Trim()
    }
    if ($best) { return $best }
    return $null
}

function Get-SeasonFolderRegexForRestore {
    $word = [regex]::Escape([string]::new([char[]]@(0x421, 0x435, 0x437, 0x43E, 0x43D)))
    return '^' + $word + '\s+(\d+)$'
}

$RootPath = $RootPath.Trim().Trim([char]0x22)
if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPath not found: $RootPath" }
$Base = (Resolve-Path -LiteralPath $RootPath).Path

if (-not $TitlesCsv) {
    foreach ($name in @('episode-titles.csv', 'titles.csv')) {
        $p = Join-Path $Base $name
        if (Test-Path -LiteralPath $p) { $TitlesCsv = $p; break }
    }
}
if (-not $TitlesCsv -or -not (Test-Path -LiteralPath $TitlesCsv)) {
    throw "episode-titles.csv not found under: $Base"
}

$SeriesTitleEnglish = Sanitize-WinFileName $SeriesTitleEnglish
if (-not $SeriesTitleEnglish) { throw "SeriesTitleEnglish empty after sanitize." }

$map = @{}
$rows = Import-Csv -LiteralPath $TitlesCsv -Encoding UTF8
foreach ($r in $rows) {
    $seasonVal = $r.season; if (-not $seasonVal) { $seasonVal = $r.Season }
    $episodeVal = $r.episode; if (-not $episodeVal) { $episodeVal = $r.Episode }
    $titleVal = $r.title; if (-not $titleVal) { $titleVal = $r.Title }
    if (-not $seasonVal -or -not $episodeVal) { continue }
    $sn = [int]$seasonVal
    $en = [int]$episodeVal
    $enTitle = Get-EnglishTitleFromCsvCell $titleVal
    if (-not $enTitle) { $enTitle = "Episode $en" }
    if (-not $map.ContainsKey($sn)) { $map[$sn] = @{} }
    $map[$sn][$en] = $enTitle
}

$seasonFolderRe = Get-SeasonFolderRegexForRestore

Get-ChildItem -LiteralPath $Base -Directory | ForEach-Object {
    if ($_.Name -notmatch $seasonFolderRe) { return }
    $seasonNum = [int]$Matches[1]
    $st = $map[$seasonNum]
    if (-not $st) {
        Write-Warning "No CSV rows for season $seasonNum in $($_.Name)"
        return
    }
    Get-ChildItem -LiteralPath $_.FullName -File -Force | ForEach-Object {
        $fn = $_.Name
        if ($fn -notmatch '(?i)S(\d+)E(\d+)') {
            Write-Warning "Skip (no SxxEyy): $fn"
            return
        }
        $fs = [int]$Matches[1]
        $fe = [int]$Matches[2]
        if ($fs -ne $seasonNum) {
            Write-Warning "Season mismatch: $fn"
            return
        }
        $titleEn = $st[$fe]
        if (-not $titleEn) {
            Write-Warning "No English title in CSV for S${fs}E$fe : $fn"
            return
        }
        $tag = 'S{0:00}E{1:00}' -f $fs, $fe
        $baseNew = Sanitize-WinFileName ($SeriesTitleEnglish + ' - ' + $tag + ' - ' + $titleEn)
        if ([string]::IsNullOrWhiteSpace($baseNew)) {
            Write-Warning "Skip empty target: $fn"
            return
        }
        $newName = "$baseNew$($_.Extension)"
        if ($fn -eq $newName) { return }
        $dest = Join-Path $_.DirectoryName $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skip (exists): $newName"
            return
        }
        if ($DryRun) {
            Write-Host "[DryRun] $fn -> $newName"
            return
        }
        Rename-Item -LiteralPath $_.FullName -NewName $newName
        Clear-HiddenAttribute (Join-Path $_.DirectoryName $newName)
        Write-Host "OK: $fn -> $newName"
    }
}

Write-Host 'Done.'
