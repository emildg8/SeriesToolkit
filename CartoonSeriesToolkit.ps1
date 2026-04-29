#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Batch', 'Manual')]
    [string]$Mode = 'Batch',
    [string]$RootPath = '\\Emilian_TNAS\emildg8\Video\Мультсериалы',
    [string]$SeriesPath = '',
    [string]$ReferenceRootPath = '\\Emilian_TNAS\emildg8\Video\Сериалы',
    [string]$HtmlPath = '',
    [string]$LogDirectory = '',
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$UseTmdb,
    [string]$TmdbApiKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Apply -and $DryRun) { throw 'Нельзя одновременно указывать -Apply и -DryRun.' }
if (-not $Apply) { $DryRun = $true }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Join-Path $PSScriptRoot 'logs' }
if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

$script:Records = [System.Collections.Generic.List[object]]::new()
$script:TmdbEpisodeCache = @{}
$script:TmdbApiKeyEffective = if ($TmdbApiKey) { $TmdbApiKey } else { [Environment]::GetEnvironmentVariable('TMDB_API_KEY', 'User') }
$script:TmdbEnabled = [bool]$UseTmdb -and -not [string]::IsNullOrWhiteSpace($script:TmdbApiKeyEffective)

function Add-Record {
    param(
        [string]$Series, [string]$Action, [string]$Status = 'OK',
        [string]$SourcePath = '', [string]$TargetPath = '', [string]$Details = ''
    )
    [void]$script:Records.Add([PSCustomObject]@{
            time        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            series      = $Series
            action      = $Action
            status      = $Status
            source_path = $SourcePath
            target_path = $TargetPath
            details     = $Details
        })
}

function ConvertTo-SafeName([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $name = $Value -replace '[\p{Cc}\p{Cf}]', ''
    $name = $name -replace ':', ' - '
    $name = $name -replace '[\\/*?"<>|]', ' '
    $name = $name -replace '\s+', ' '
    $name = $name.Trim().TrimEnd('.', ' ')
    if ($name.Length -gt 180) { $name = $name.Substring(0, 180).TrimEnd('.', ' ') }
    return $name
}

function Get-SeasonFolderName([int]$SeasonNumber) { return "Сезон $SeasonNumber" }

function Resolve-SeasonFromFolderName([string]$FolderName) {
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return $null }
    $n = ($FolderName -replace [char]0x00A0, ' ').Trim()
    if ($n -match '^(?i)сезон\s+(\d+)$') { return [int]$Matches[1] }
    if ($n -match '^(?i)(\d+)(?:[-–]\s*й)?\s+сезон$') { return [int]$Matches[1] }
    if ($n -match '^(?i)season[_\s-]*(\d+)$') { return [int]$Matches[1] }
    if ($n -match '(?i)(?:^|[\s._-])s(\d{1,2})(?:[\s._-]|$)') { return [int]$Matches[1] }
    return $null
}

function Get-InferredSeasonFromFilePath([string]$FileDirectoryPath, [string]$SeriesRootPath) {
    if ([string]::IsNullOrWhiteSpace($FileDirectoryPath)) { return $null }
    $current = [System.IO.Path]::GetFullPath($FileDirectoryPath)
    $seriesRoot = [System.IO.Path]::GetFullPath($SeriesRootPath)
    while ($current -and $current.StartsWith($seriesRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = Split-Path -Path $current -Leaf
        $sn = Resolve-SeasonFromFolderName $leaf
        if ($sn) { return $sn }
        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Resolve-EpisodeTagFromName([string]$Name, $InferredSeason) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    $patterns = @(
        @{ Re = '(?i)S(?<s>\d{1,2})[ ._-]*E(?<e>\d{1,3})'; Score = 100; Kind = 'SxxEyy' },
        @{ Re = '(?i)(?<!\d)(?<s>\d{1,2})x(?<e>\d{2,3})(?!\d)'; Score = 90; Kind = 'NxNN' },
        @{ Re = '(?i)season[\s._-]*(?<s>\d{1,2})[\s._-]*episode[\s._-]*(?<e>\d{1,3})'; Score = 95; Kind = 'SeasonEpisode' },
        @{ Re = '(?i)\[(?<e>\d{1,3})\]'; Score = 70; Kind = '[NN]' },
        @{ Re = '(?i)\((?<e>\d{1,3})\)'; Score = 65; Kind = '(NN)' },
        @{ Re = '(?i)(?:^|[^0-9])ep(?:isode)?[\s._-]*(?<e>\d{1,3})(?:[^0-9]|$)'; Score = 75; Kind = 'EPnn' },
        @{ Re = '(?i)(?:^|[^0-9])серия[\s._-]*(?<e>\d{1,3})(?:[^0-9]|$)'; Score = 75; Kind = 'Seriya' }
    )

    $best = $null
    foreach ($p in $patterns) {
        if ($Name -match $p.Re) {
            $s = $null
            if ($Matches.ContainsKey('s') -and $Matches['s']) { $s = [int]$Matches['s'] }
            $e = [int]$Matches['e']
            if ($p.Kind -eq 'NxNN' -and $e -in @(480, 540, 720, 1080, 1440, 2160, 4320)) { continue }
            if ($null -eq $s) {
                $s = if ($null -ne $InferredSeason -and [int]$InferredSeason -gt 0) { [int]$InferredSeason } else { 1 }
            }
            $candidate = @{ Season = $s; Episode = $e; Score = [int]$p.Score; Pattern = $p.Kind }
            if ($null -eq $best -or $candidate.Score -gt $best.Score) { $best = $candidate }
        }
    }
    # Паттерн компактного кода: 301, 1207, 3101 (сезон+эпизод без S/E)
    if ($null -eq $best -and $null -ne $InferredSeason -and [int]$InferredSeason -gt 0) {
        $sTxt = [string][int]$InferredSeason
        $rxCompact = [regex]'(?<!\d)(?<v>\d{3,4})(?!\d)'
        foreach ($m in $rxCompact.Matches($Name)) {
            $v = [string]$m.Groups['v'].Value
            if ($v.StartsWith($sTxt, [StringComparison]::Ordinal)) {
                $epTxt = $v.Substring($sTxt.Length)
                if ($epTxt.Length -ge 1 -and $epTxt.Length -le 2) {
                    $ep = [int]$epTxt
                    if ($ep -ge 1 -and $ep -le 99) {
                        $best = @{ Season = [int]$InferredSeason; Episode = $ep; Score = 85; Pattern = 'CompactSeasonEpisode' }
                        break
                    }
                }
            }
        }
    }
    return $best
}

function Extract-EpisodeTitleFromHtml([string]$HtmlPath) {
    if ([string]::IsNullOrWhiteSpace($HtmlPath) -or -not (Test-Path -LiteralPath $HtmlPath)) { return @{} }
    $text = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
    $map = @{}
    # Простой общий парсер для строк типа "1 сезон 2 серия — Название"
    $rx = [regex]'(?im)(?<s>\d{1,2})\s*сезон[^\r\n]{0,40}?(?<e>\d{1,3})\s*сер[ияй][^\r\n\-–—:]{0,20}[\-–—:]\s*(?<t>[^\r\n<]{2,200})'
    foreach ($m in $rx.Matches($text)) {
        $s = [int]$m.Groups['s'].Value
        $e = [int]$m.Groups['e'].Value
        $t = ConvertTo-SafeName $m.Groups['t'].Value
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $map["$s|$e"] = $t
    }
    return $map
}

function Invoke-TmdbEpisodeNameLookup([string]$SeriesName, [int]$Season, [int]$Episode) {
    if (-not $script:TmdbEnabled) { return $null }
    $key = "$SeriesName|$Season|$Episode"
    if ($script:TmdbEpisodeCache.ContainsKey($key)) { return $script:TmdbEpisodeCache[$key] }
    try {
        $searchUri = 'https://api.themoviedb.org/3/search/tv?api_key=' + [Uri]::EscapeDataString($script:TmdbApiKeyEffective) + '&language=ru-RU&query=' + [Uri]::EscapeDataString($SeriesName)
        $search = Invoke-RestMethod -Uri $searchUri -Method Get -TimeoutSec 20
        if (-not $search.results -or $search.results.Count -eq 0) { $script:TmdbEpisodeCache[$key] = $null; return $null }
        $tvId = [int]$search.results[0].id
        $epUri = 'https://api.themoviedb.org/3/tv/' + $tvId + '/season/' + $Season + '/episode/' + $Episode + '?api_key=' + [Uri]::EscapeDataString($script:TmdbApiKeyEffective) + '&language=ru-RU'
        $ep = Invoke-RestMethod -Uri $epUri -Method Get -TimeoutSec 20
        $name = if ($ep.name) { ConvertTo-SafeName ([string]$ep.name) } else { '' }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $null }
        $script:TmdbEpisodeCache[$key] = $name
        return $name
    } catch {
        $script:TmdbEpisodeCache[$key] = $null
        return $null
    }
}

function Build-RenamePlanForSeries([System.IO.DirectoryInfo]$SeriesDir, [hashtable]$HtmlTitles) {
    $plan = [System.Collections.Generic.List[object]]::new()
    $seriesName = ConvertTo-SafeName $SeriesDir.Name
    $files = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$' })
    foreach ($f in $files) {
        $infSeason = Get-InferredSeasonFromFilePath -FileDirectoryPath $f.DirectoryName -SeriesRootPath $SeriesDir.FullName
        $tag = Resolve-EpisodeTagFromName -Name $f.Name -InferredSeason $infSeason
        if (-not $tag) {
            Add-Record -Series $SeriesDir.Name -Action 'skip-file' -Status 'WARN' -SourcePath $f.FullName -Details 'Не найден шаблон сезона/серии.'
            continue
        }
        if ($tag.Score -lt 65) {
            Add-Record -Series $SeriesDir.Name -Action 'skip-file' -Status 'WARN' -SourcePath $f.FullName -Details ("Низкая уверенность распознавания: {0}" -f $tag.Pattern)
            continue
        }
        $seasonPath = Join-Path $SeriesDir.FullName (Get-SeasonFolderName $tag.Season)
        $code = ('S{0:00}E{1:00}' -f $tag.Season, $tag.Episode)
        $title = $null
        $hKey = "$($tag.Season)|$($tag.Episode)"
        if ($HtmlTitles.ContainsKey($hKey)) { $title = $HtmlTitles[$hKey] }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = Invoke-TmdbEpisodeNameLookup -SeriesName $seriesName -Season $tag.Season -Episode $tag.Episode }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = "Серия $($tag.Episode)" }
        $newBase = ConvertTo-SafeName("$seriesName - $code - $title")
        if ([string]::IsNullOrWhiteSpace($newBase)) {
            Add-Record -Series $SeriesDir.Name -Action 'skip-file' -Status 'ERROR' -SourcePath $f.FullName -Details 'Пустое целевое имя после sanitize.'
            continue
        }
        $target = Join-Path $seasonPath ($newBase + $f.Extension)
        [void]$plan.Add([PSCustomObject]@{
                series      = $SeriesDir.Name
                source      = $f.FullName
                seasonPath  = $seasonPath
                target      = $target
                pattern     = $tag.Pattern
                confidence  = $tag.Score
            })
    }
    return $plan
}

function Resolve-TargetConflicts([System.Collections.Generic.List[object]]$Plan) {
    $occupied = @{}
    foreach ($op in $Plan) {
        $target = $op.target
        if (-not $occupied.ContainsKey($target)) {
            $occupied[$target] = 0
            continue
        }
        $occupied[$target]++
        $suffix = $occupied[$target]
        $dir = Split-Path -Path $target -Parent
        $ext = [IO.Path]::GetExtension($target)
        $base = [IO.Path]::GetFileNameWithoutExtension($target)
        $op.target = Join-Path $dir ((ConvertTo-SafeName("$base [$suffix]")) + $ext)
    }
}

function Ensure-SeasonFolders([System.Collections.Generic.List[object]]$Plan, [string]$SeriesName) {
    $uniq = @{}
    foreach ($p in $Plan) { $uniq[$p.seasonPath] = $true }
    foreach ($path in $uniq.Keys) {
        if (Test-Path -LiteralPath $path) { continue }
        if ($DryRun) {
            Add-Record -Series $SeriesName -Action 'create-season-folder' -Status 'DRYRUN' -TargetPath $path
        } else {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Add-Record -Series $SeriesName -Action 'create-season-folder' -Status 'OK' -TargetPath $path
        }
    }
}

function Normalize-SeasonFolderNames([System.IO.DirectoryInfo]$SeriesDir) {
    foreach ($d in @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Directory -ErrorAction SilentlyContinue)) {
        $sn = Resolve-SeasonFromFolderName $d.Name
        if (-not $sn) { continue }
        $expected = Get-SeasonFolderName $sn
        if ($d.Name -ceq $expected) { continue }
        $target = Join-Path $SeriesDir.FullName $expected
        if (Test-Path -LiteralPath $target) {
            Add-Record -Series $SeriesDir.Name -Action 'rename-season-folder' -Status 'WARN' -SourcePath $d.FullName -TargetPath $target -Details 'Цель уже существует.'
            continue
        }
        if ($DryRun) {
            Add-Record -Series $SeriesDir.Name -Action 'rename-season-folder' -Status 'DRYRUN' -SourcePath $d.FullName -TargetPath $target
        } else {
            Rename-Item -LiteralPath $d.FullName -NewName $expected
            Add-Record -Series $SeriesDir.Name -Action 'rename-season-folder' -Status 'OK' -SourcePath $d.FullName -TargetPath $target
        }
    }
}

function Apply-Plan([System.Collections.Generic.List[object]]$Plan) {
    foreach ($op in $Plan) {
        if ($op.source -ieq $op.target) {
            Add-Record -Series $op.series -Action 'skip-file' -Status 'INFO' -SourcePath $op.source -Details 'Уже корректно.'
            continue
        }
        if ($DryRun) {
            Add-Record -Series $op.series -Action 'move-rename-file' -Status 'DRYRUN' -SourcePath $op.source -TargetPath $op.target -Details ("pattern={0}; confidence={1}" -f $op.pattern, $op.confidence)
            continue
        }
        try {
            Move-Item -LiteralPath $op.source -Destination $op.target -Force
            Add-Record -Series $op.series -Action 'move-rename-file' -Status 'OK' -SourcePath $op.source -TargetPath $op.target -Details ("pattern={0}; confidence={1}" -f $op.pattern, $op.confidence)
        } catch {
            Add-Record -Series $op.series -Action 'move-rename-file' -Status 'ERROR' -SourcePath $op.source -TargetPath $op.target -Details $_.Exception.Message
        }
    }
}

function Run-Series([System.IO.DirectoryInfo]$SeriesDir, [hashtable]$HtmlTitles) {
    Normalize-SeasonFolderNames -SeriesDir $SeriesDir
    $plan = Build-RenamePlanForSeries -SeriesDir $SeriesDir -HtmlTitles $HtmlTitles
    Resolve-TargetConflicts -Plan $plan
    Ensure-SeasonFolders -Plan $plan -SeriesName $SeriesDir.Name
    Apply-Plan -Plan $plan
}

if (Test-Path -LiteralPath $ReferenceRootPath) {
    Add-Record -Series '-' -Action 'reference-scan' -Status 'INFO' -SourcePath $ReferenceRootPath -Details 'Папка-референс доступна.'
} else {
    Add-Record -Series '-' -Action 'reference-scan' -Status 'WARN' -SourcePath $ReferenceRootPath -Details 'Папка-референс недоступна.'
}
if ($UseTmdb -and -not $script:TmdbEnabled) {
    Add-Record -Series '-' -Action 'tmdb' -Status 'WARN' -Details 'TMDB включен, но ключ отсутствует; работаем без TMDB.'
}

$htmlTitles = Extract-EpisodeTitleFromHtml -HtmlPath $HtmlPath
if ($Mode -eq 'Manual') {
    if ([string]::IsNullOrWhiteSpace($SeriesPath) -or -not (Test-Path -LiteralPath $SeriesPath)) { throw "SeriesPath не найден: $SeriesPath" }
    $sd = Get-Item -LiteralPath $SeriesPath -ErrorAction Stop
    Run-Series -SeriesDir $sd -HtmlTitles $htmlTitles
} else {
    if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPath не найден: $RootPath" }
    foreach ($sd in @(Get-ChildItem -LiteralPath $RootPath -Directory -ErrorAction SilentlyContinue)) {
        Run-Series -SeriesDir $sd -HtmlTitles $htmlTitles
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$modeTag = if ($DryRun) { 'dryrun' } else { 'apply' }
$csvPath = Join-Path $LogDirectory ("cartoons-toolkit-$($Mode.ToLowerInvariant())-$modeTag-$stamp.csv")
$txtPath = Join-Path $LogDirectory ("cartoons-toolkit-$($Mode.ToLowerInvariant())-$modeTag-$stamp.txt")
$script:Records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$warn = @($script:Records | Where-Object { $_.status -eq 'WARN' }).Count
$err = @($script:Records | Where-Object { $_.status -eq 'ERROR' }).Count
$summary = @(
    "Mode: $Mode",
    "RunMode: $(if ($DryRun) { 'DryRun' } else { 'Apply' })",
    "RootPath: $RootPath",
    "SeriesPath: $SeriesPath",
    "TotalLogRecords: $($script:Records.Count)",
    "Warnings: $warn",
    "Errors: $err",
    "CSV: $csvPath",
    "TXT: $txtPath"
) -join [Environment]::NewLine
Set-Content -LiteralPath $txtPath -Value $summary -Encoding UTF8
Write-Host $summary

