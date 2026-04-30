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

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $fetchModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'Fetch-VideoMetadata.ps1'
    if (-not (Test-Path -LiteralPath $fetchModule)) {
        $fetchModule = Join-Path $PSScriptRoot 'Fetch-VideoMetadata.ps1'
    }
    if (Test-Path -LiteralPath $fetchModule) {
        . $fetchModule
    }
} catch { }

try {
    if (Get-Command Initialize-WebClient -ErrorAction SilentlyContinue) {
        Initialize-WebClient
    }
} catch { }

function Get-TmdbApiKeyFromEnvironment {
    foreach ($name in @('TMDB_API_KEY', 'RENAME_VIDEO_TMDB_API_KEY', 'THEMOVIEDB_API_KEY')) {
        foreach ($scope in @('User', 'Machine', 'Process')) {
            $v = [Environment]::GetEnvironmentVariable($name, $scope)
            if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
        }
    }
    return $null
}

if ($Apply -and $DryRun) { throw 'Нельзя одновременно указывать -Apply и -DryRun.' }
if (-not $Apply) { $DryRun = $true }
if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Join-Path $PSScriptRoot 'LOGS' }
if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

$script:UserSettings = @{
    episode_filename_format = '{Series} - {Code} - {Title}'
    season_folder_format = 'Сезон {Season}'
    aggressive_second_pass_kinopoisk_min_score = 85
    placeholder_repair_allow_latin_titles = $false
    create_missing_season_folders = $true
    write_episode_index_csv = $true
}

function Import-SeriesToolkitUserSettings {
    $p = Join-Path $PSScriptRoot 'SeriesToolkit.settings.json'
    if (-not (Test-Path -LiteralPath $p)) { return }
    try {
        $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $key = $j.PSObject.Properties.Name
        if ($key -contains 'tmdb_api_key' -and $j.tmdb_api_key) {
            $tv = [string]$j.tmdb_api_key.Trim()
            if (-not [string]::IsNullOrWhiteSpace($tv)) {
                [Environment]::SetEnvironmentVariable('TMDB_API_KEY', $tv, 'Process')
            }
        }
        if ($key -contains 'kinopoisk_cookie' -and $j.kinopoisk_cookie) {
            $ck = [string]$j.kinopoisk_cookie.Trim()
            if (-not [string]::IsNullOrWhiteSpace($ck)) {
                [Environment]::SetEnvironmentVariable('KINOPOISK_COOKIE', $ck, 'Process')
            }
        }
        if ($key -contains 'episode_filename_format' -and $j.episode_filename_format) {
            $script:UserSettings.episode_filename_format = [string]$j.episode_filename_format
        }
        if ($key -contains 'season_folder_format' -and $j.season_folder_format) {
            $script:UserSettings.season_folder_format = [string]$j.season_folder_format
        }
        if ($key -contains 'aggressive_second_pass_kinopoisk_min_score' -and $null -ne $j.aggressive_second_pass_kinopoisk_min_score) {
            $script:UserSettings.aggressive_second_pass_kinopoisk_min_score = [int]$j.aggressive_second_pass_kinopoisk_min_score
        }
        if ($key -contains 'placeholder_repair_allow_latin_titles' -and $null -ne $j.placeholder_repair_allow_latin_titles) {
            $script:UserSettings.placeholder_repair_allow_latin_titles = [bool]$j.placeholder_repair_allow_latin_titles
        }
        if ($key -contains 'create_missing_season_folders' -and $null -ne $j.create_missing_season_folders) {
            $script:UserSettings.create_missing_season_folders = [bool]$j.create_missing_season_folders
        }
        if ($key -contains 'write_episode_index_csv' -and $null -ne $j.write_episode_index_csv) {
            $script:UserSettings.write_episode_index_csv = [bool]$j.write_episode_index_csv
        }
    } catch { }
}

Import-SeriesToolkitUserSettings

$script:ToolkitVersion = '0.0.0'
try {
    $vf = Join-Path $PSScriptRoot 'version.json'
    if (Test-Path -LiteralPath $vf) {
        $vo = Get-Content -LiteralPath $vf -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($vo.version) { $script:ToolkitVersion = [string]$vo.version }
    }
} catch { }

$script:Records = [System.Collections.Generic.List[object]]::new()
$script:TmdbEpisodeCache = @{}
$script:SeriesTitlesCache = @{}
$script:ProgressLogPath = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_PROGRESS_LOG', 'Process')
$script:TmdbApiKeyEffective = if ($TmdbApiKey) { $TmdbApiKey } else { Get-TmdbApiKeyFromEnvironment }
$script:TmdbEnabled = -not [string]::IsNullOrWhiteSpace($script:TmdbApiKeyEffective)
if ($UseTmdb) { $script:TmdbEnabled = $true }

function Write-ToolkitProgress([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    Write-Host $Line
    if (-not [string]::IsNullOrWhiteSpace($script:ProgressLogPath)) {
        try {
            Add-Content -LiteralPath $script:ProgressLogPath -Value $Line -Encoding UTF8
        } catch { }
    }
}

function Write-SeriesProgress([string]$SeriesName, [string]$Stage, [int]$Index, [int]$Total) {
    if ($Total -le 0) { $Total = 1 }
    if ($Index -lt 0) { $Index = 0 }
    if ($Index -gt $Total) { $Index = $Total }
    $pct = [int][Math]::Floor(($Index * 100.0) / $Total)
    Write-ToolkitProgress ("[SeriesToolkit][SeriesProgress {0}% {1}/{2}] {3} :: {4}" -f $pct, $Index, $Total, $SeriesName, $Stage)
}

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

function Normalize-ForTmdbSearch([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.ToLowerInvariant()
    $t = $t -replace '[\(\)\[\]\{\}]', ' '
    $t = $t -replace '[\._\-]+', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-TmdbScore([string]$Expected, [string]$CandidateRu, [string]$CandidateOrig) {
    $e = Normalize-ForTmdbSearch $Expected
    $r = Normalize-ForTmdbSearch $CandidateRu
    $o = Normalize-ForTmdbSearch $CandidateOrig
    $score = 0
    if (-not [string]::IsNullOrWhiteSpace($e)) {
        if ($r -eq $e -or $o -eq $e) { $score += 1000 }
        if ($r.Contains($e) -or $e.Contains($r)) { $score += 300 }
        if ($o.Contains($e) -or $e.Contains($o)) { $score += 250 }
        foreach ($w in ($e -split '\s+')) {
            if ($w.Length -lt 3) { continue }
            if ($r.Contains($w) -or $o.Contains($w)) { $score += 12 }
        }
    }
    return $score
}

function Get-SeasonFolderName([int]$SeasonNumber) {
    $fmt = $script:UserSettings.season_folder_format
    if ([string]::IsNullOrWhiteSpace($fmt)) { $fmt = 'Сезон {Season}' }
    return ($fmt -replace '\{Season\}', ([string][int]$SeasonNumber))
}

function Format-EpisodeFileBase([string]$SeriesFolderName, [string]$Code, [string]$Title, [int]$Season, [int]$Episode) {
    $fmt = $script:UserSettings.episode_filename_format
    if ([string]::IsNullOrWhiteSpace($fmt)) { $fmt = '{Series} - {Code} - {Title}' }
    $ser = ConvertTo-SafeName $SeriesFolderName
    $tit = ConvertTo-SafeName $Title
    $s = $fmt
    $s = $s.Replace('{Series}', $ser).Replace('{Code}', $Code).Replace('{Title}', $tit)
    $s = $s.Replace('{Season}', ([string][int]$Season)).Replace('{Episode}', ([string][int]$Episode))
    return (ConvertTo-SafeName $s)
}

function Resolve-SeasonFromFolderName([string]$FolderName) {
    if ([string]::IsNullOrWhiteSpace($FolderName)) { return $null }
    $n = ($FolderName -replace [char]0x00A0, ' ').Trim()
    if ($n -match '^(?i)сезон\s+(\d+)$') { return [int]$Matches[1] }
    if ($n -match '^(?i)(\d+)(?:[-–]\s*й)?\s+сезон$') { return [int]$Matches[1] }
    if ($n -match '^(?i)season[_\s-]*(\d+)$') { return [int]$Matches[1] }
    if ($n -match '(?i)(?:^|[\s._-])s(\d{1,2})(?:[\s._-]|$)') { return [int]$Matches[1] }
    return $null
}

function Test-SeriesToolkitVideoExtension([string]$Ext) {
    if ([string]::IsNullOrWhiteSpace($Ext)) { return $false }
    return [bool]($Ext -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$')
}

function Test-LooksLikeSeriesMediaSubtree([System.IO.DirectoryInfo]$Dir) {
    $one = @(Get-ChildItem -LiteralPath $Dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { Test-SeriesToolkitVideoExtension $_.Extension } | Select-Object -First 1)
    if ($one.Count -gt 0) { return $true }
    foreach ($sub in @(Get-ChildItem -LiteralPath $Dir.FullName -Directory -ErrorAction SilentlyContinue)) {
        if ($null -ne (Resolve-SeasonFromFolderName $sub.Name)) { return $true }
    }
    return $false
}

function Test-AllImmediateSubdirsAreSeasonFolders([System.IO.DirectoryInfo]$Dir) {
    $subs = @(Get-ChildItem -LiteralPath $Dir.FullName -Directory -ErrorAction SilentlyContinue)
    if ($subs.Count -eq 0) { return $false }
    foreach ($s in $subs) {
        if ($null -eq (Resolve-SeasonFromFolderName $s.Name)) { return $false }
    }
    return $true
}

function Test-IsSagaContainerFolder([System.IO.DirectoryInfo]$Dir) {
    $immediateV = @(Get-ChildItem -LiteralPath $Dir.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { Test-SeriesToolkitVideoExtension $_.Extension })
    if ($immediateV.Count -gt 0) { return $false }
    $subs = @(Get-ChildItem -LiteralPath $Dir.FullName -Directory -ErrorAction SilentlyContinue)
    if ($subs.Count -eq 0) { return $false }
    if (Test-AllImmediateSubdirsAreSeasonFolders $Dir) { return $false }
    $nonSeason = @($subs | Where-Object { $null -eq (Resolve-SeasonFromFolderName $_.Name) })
    if ($nonSeason.Count -eq 1 -and $subs.Count -eq 1) {
        return (Test-LooksLikeSeriesMediaSubtree $subs[0])
    }
    if ($subs.Count -lt 2) { return $false }
    if ($nonSeason.Count -lt 2) { return $false }
    foreach ($s in $subs) {
        if (-not (Test-LooksLikeSeriesMediaSubtree $s)) { return $false }
    }
    return $true
}

function Get-SeriesRootsUnderLibrary([string]$LibraryRootPath) {
    $out = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    function Walk-SeriesLibraryNode([System.IO.DirectoryInfo]$Node) {
        if (Test-IsSagaContainerFolder $Node) {
            foreach ($c in @(Get-ChildItem -LiteralPath $Node.FullName -Directory -ErrorAction SilentlyContinue)) {
                Walk-SeriesLibraryNode $c
            }
            return
        }
        if (Test-LooksLikeSeriesMediaSubtree $Node) {
            [void]$out.Add($Node)
        }
    }
    foreach ($top in @(Get-ChildItem -LiteralPath $LibraryRootPath -Directory -ErrorAction SilentlyContinue)) {
        Walk-SeriesLibraryNode $top
    }
    return $out
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
        @{ Re = '(?i)(?<s>\d{1,2})\s*ACV\s*(?<e>\d{2})'; Score = 96; Kind = 'ACVCode' },
        @{ Re = '(?i)(?<s>\d{1,2})[._\s-]*sezon[._\s-]*(?<e>\d{1,3})[._\s-]*(?:seriya|serii)'; Score = 95; Kind = 'TranslitSezonSeriya' },
        @{ Re = '(?i)(?<s>\d{1,2})[._\s-]*сезон[._\s-]*(?<e>\d{1,3})[._\s-]*(?:серия|серии)'; Score = 95; Kind = 'RuSezonSeriya' },
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
    if ($null -eq $best -and $null -ne $InferredSeason -and [int]$InferredSeason -gt 0) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        if ($base -match '(?i)(?:^|[\s._-])(?<e>\d{1,3})$') {
            $ep = [int]$Matches['e']
            if ($ep -ge 1 -and $ep -le 200) {
                $best = @{ Season = [int]$InferredSeason; Episode = $ep; Score = 74; Pattern = 'TrailingEpisodeNumber' }
            }
        }
    }
    if ($null -eq $best) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        if ($base -match '(?i)(?:^|[\s._-]|x-)(?<e>\d{1,3})(?:$|[\s._-])') {
            $ep = [int]$Matches['e']
            if ($ep -ge 1 -and $ep -le 200 -and $ep -notin @(480, 540, 720, 1080, 1440, 2160, 4320)) {
                $season = if ($null -ne $InferredSeason -and [int]$InferredSeason -gt 0) { [int]$InferredSeason } else { 1 }
                $best = @{ Season = $season; Episode = $ep; Score = 70; Pattern = 'GenericEpisodeNumber' }
            }
        }
    }
    return $best
}

function Get-InferredEpisodeFromPath([string]$FileDirectoryPath, [string]$SeriesRootPath) {
    if ([string]::IsNullOrWhiteSpace($FileDirectoryPath)) { return $null }
    $current = [System.IO.Path]::GetFullPath($FileDirectoryPath)
    $seriesRoot = [System.IO.Path]::GetFullPath($SeriesRootPath)
    while ($current -and $current.StartsWith($seriesRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = Split-Path -Path $current -Leaf
        if ($leaf -match '^(?<e>\d{1,3})(?:[\s._-]|$)') {
            $ep = [int]$Matches['e']
            if ($ep -ge 1 -and $ep -le 999) { return $ep }
        }
        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Test-LooksLikeExtraVideo([string]$FullPath, [string]$FileNameNoExt) {
    $pathL = $FullPath.ToLowerInvariant()
    $nameL = $FileNameNoExt.ToLowerInvariant()
    $extraWords = @(
        'opening', 'ending', 'trailer', 'тизер', 'teaser', 'preview', 'promo', 'pv', 'cm',
        'logo', 'intro', 'outro', 'op', 'ed', 'credit', 'credits', 'menu', 'bonus',
        'special', 'featurette', 'behind', 'making', 'movie', 'film', 'theme',
        'benders.big.score', 'billion.backs', 'wild.green.yonder', 'benders.game'
    )
    foreach ($w in $extraWords) {
        if ($pathL.Contains($w) -or $nameL -match ("(?<!\w){0}(?!\w)" -f [regex]::Escape($w))) { return $true }
    }
    return $false
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

function Get-TmdbEpisodeMapForSeries([string]$SeriesName) {
    $key = Normalize-ForTmdbSearch $SeriesName
    if ($script:SeriesTitlesCache.ContainsKey($key)) { return $script:SeriesTitlesCache[$key] }
    $map = @{}
    if (-not $script:TmdbEnabled) { $script:SeriesTitlesCache[$key] = $map; return $map }
    try {
        $searchUri = 'https://api.themoviedb.org/3/search/tv?api_key=' + [Uri]::EscapeDataString($script:TmdbApiKeyEffective) + '&language=ru-RU&query=' + [Uri]::EscapeDataString($SeriesName)
        $search = Invoke-RestMethod -Uri $searchUri -Method Get -TimeoutSec 25
        if (-not $search.results -or $search.results.Count -eq 0) { $script:SeriesTitlesCache[$key] = $map; return $map }
        $pick = $null
        $best = -1
        foreach ($r in @($search.results | Select-Object -First 8)) {
            $sc = Get-TmdbScore -Expected $SeriesName -CandidateRu ([string]$r.name) -CandidateOrig ([string]$r.original_name)
            if ($null -ne $r.popularity) { $sc += [int][Math]::Round([double]$r.popularity) }
            if ($sc -gt $best) { $best = $sc; $pick = $r }
        }
        if (-not $pick) { $script:SeriesTitlesCache[$key] = $map; return $map }
        $tvId = [int]$pick.id
        $detailsUri = 'https://api.themoviedb.org/3/tv/' + $tvId + '?api_key=' + [Uri]::EscapeDataString($script:TmdbApiKeyEffective) + '&language=ru-RU'
        $details = Invoke-RestMethod -Uri $detailsUri -Method Get -TimeoutSec 25
        $seasonNumbers = @()
        if ($details.seasons) {
            foreach ($s in @($details.seasons)) {
                if ($null -eq $s.season_number) { continue }
                $sn = [int]$s.season_number
                if ($sn -gt 0) { $seasonNumbers += $sn }
            }
        }
        foreach ($sn in ($seasonNumbers | Sort-Object -Unique)) {
            try {
                $sUri = 'https://api.themoviedb.org/3/tv/' + $tvId + '/season/' + $sn + '?api_key=' + [Uri]::EscapeDataString($script:TmdbApiKeyEffective) + '&language=ru-RU'
                $sData = Invoke-RestMethod -Uri $sUri -Method Get -TimeoutSec 25
                foreach ($ep in @($sData.episodes)) {
                    if ($null -eq $ep.episode_number) { continue }
                    $en = [int]$ep.episode_number
                    if ($en -le 0) { continue }
                    $title = ConvertTo-SafeName ([string]$ep.name)
                    if ([string]::IsNullOrWhiteSpace($title)) { continue }
                    $map["$sn|$en"] = $title
                }
            } catch { }
        }
    } catch { }
    $script:SeriesTitlesCache[$key] = $map
    return $map
}

function Merge-EpisodeTitleMaps([hashtable]$Primary, [hashtable]$Fallback) {
    $merged = @{}
    foreach ($k in $Fallback.Keys) { $merged[$k] = $Fallback[$k] }
    foreach ($k in $Primary.Keys) { $merged[$k] = $Primary[$k] }
    return $merged
}

function Get-WikiEpisodeMapForSeries([string]$SeriesName) {
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($SeriesName)) { return $map }
    if (-not (Get-Command Get-EpisodesFromWikipediaSearchQueries -ErrorAction SilentlyContinue)) { return $map }
    try {
        $items = Get-EpisodesFromWikipediaSearchQueries $SeriesName
        if ($items -and (Get-Command Expand-EpisodeListWithRussianWikipedia -ErrorAction SilentlyContinue)) {
            $items = Expand-EpisodeListWithRussianWikipedia @($items) $SeriesName
        }
        foreach ($it in @($items)) {
            if ($null -eq $it) { continue }
            $sn = if ($null -ne $it.season) { [int]$it.season } else { 0 }
            $en = if ($null -ne $it.episode) { [int]$it.episode } else { 0 }
            if ($sn -le 0 -or $en -le 0) { continue }
            $tt = if ($null -ne $it.title) { [string]$it.title } else { '' }
            $tt = ConvertTo-SafeName $tt
            if ([string]::IsNullOrWhiteSpace($tt)) { continue }
            $map["$sn|$en"] = $tt
        }
    } catch { }
    return $map
}

function Convert-EpisodeObjectsToHashtable([object[]]$List) {
    $h = @{}
    foreach ($it in @($List)) {
        if ($null -eq $it) { continue }
        $sn = if ($null -ne $it.season) { [int]$it.season } elseif ($null -ne $it.Season) { [int]$it.Season } else { 0 }
        $en = if ($null -ne $it.episode) { [int]$it.episode } elseif ($null -ne $it.Episode) { [int]$it.Episode } else { 0 }
        if ($sn -le 0 -or $en -le 0) { continue }
        $tt = if ($null -ne $it.title) { [string]$it.title } elseif ($null -ne $it.Title) { [string]$it.Title } else { '' }
        $tt = ConvertTo-SafeName $tt
        if ([string]::IsNullOrWhiteSpace($tt)) { continue }
        $h["$sn|$en"] = $tt
    }
    return $h
}

function Limit-HashtableToCyrillicEpisodeTitles([hashtable]$Map) {
    if (-not $Map -or $Map.Count -eq 0) { return @{} }
    $o = @{}
    foreach ($k in $Map.Keys) {
        $t = [string]$Map[$k]
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -notmatch '\p{IsCyrillic}') { continue }
        if (Get-Command Test-EpisodeTitleLooksLikePlaceholder -ErrorAction SilentlyContinue) {
            if (Test-EpisodeTitleLooksLikePlaceholder $t) { continue }
        }
        $o[$k] = $t
    }
    return $o
}

function Expand-EpisodeTitleMapWithLatinFallback([hashtable]$Raw) {
    if (-not $Raw -or $Raw.Count -eq 0) { return @{} }
    $out = Limit-HashtableToCyrillicEpisodeTitles $Raw
    if (-not $script:UserSettings.placeholder_repair_allow_latin_titles) { return $out }
    foreach ($k in $Raw.Keys) {
        if ($out.ContainsKey($k)) { continue }
        $t = [string]$Raw[$k]
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match '\p{IsCyrillic}') { continue }
        if (Get-Command Test-EpisodeTitleLooksLikePlaceholder -ErrorAction SilentlyContinue) {
            if (Test-EpisodeTitleLooksLikePlaceholder $t) { continue }
        }
        elseif ($t -match '^(?i)(?:серия|episode)\s*\d+\s*$') { continue }
        $out[$k] = $t
    }
    return $out
}

function Get-CombinedEpisodeMergedObjects {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SeriesName,
        [int]$KinopoiskMinScore = 120,
        [switch]$AggressiveDdg
    )
    if ([string]::IsNullOrWhiteSpace($SeriesName)) { return @() }

    Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: wikipedia search start" -f $SeriesName)
    $wikiList = $null
    try {
        if (Get-Command Get-EpisodesFromWikipediaSearchQueries -ErrorAction SilentlyContinue) {
            $wikiList = Get-EpisodesFromWikipediaSearchQueries $SeriesName
        }
    } catch { }
    $wikiArr = @($wikiList)

    if ($AggressiveDdg -and (Get-Command Get-EpisodesFromWikipediaAggressiveDdgMerge -ErrorAction SilentlyContinue)) {
        Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: aggressive DDG merge start" -f $SeriesName)
        try {
            $ag = Get-EpisodesFromWikipediaAggressiveDdgMerge $SeriesName
            if ($ag -and @($ag).Count -gt 0) {
                if ($wikiArr.Count -gt 0) {
                    $wikiArr = @(Convert-EpisodeListToUniqueBySeasonEpisode (@($wikiArr) + @($ag)))
                } else {
                    $wikiArr = @($ag)
                }
            }
        } catch { }
    }

    Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: TMDB search start" -f $SeriesName)
    $tmdbArr = $null
    $pick = $null
    if ($script:TmdbEnabled -and (Get-Command Search-TmdbTvSeries -ErrorAction SilentlyContinue) -and (Get-Command Get-EpisodesFromTmdbTvSeries -ErrorAction SilentlyContinue)) {
        try {
            $results = Search-TmdbTvSeries $SeriesName $script:TmdbApiKeyEffective
            if ($results -and @($results).Count -gt 0) {
                $best = -1
                foreach ($r in @($results | Select-Object -First 8)) {
                    $sc = Get-TmdbScore -Expected $SeriesName -CandidateRu ([string]$r.name) -CandidateOrig ([string]$r.original_name)
                    if ($null -ne $r.popularity) { $sc += [int][Math]::Round([double]$r.popularity) }
                    if ($sc -gt $best) { $best = $sc; $pick = $r }
                }
                if ($pick) {
                    $tvId = [int]$pick.id
                    if ($tvId -gt 0) {
                        $tmdbArr = Get-EpisodesFromTmdbTvSeries $tvId $script:TmdbApiKeyEffective
                    }
                }
            }
        } catch { }
    }

    $merged = $null
    if ($tmdbArr -and @($tmdbArr).Count -gt 0 -and $wikiArr.Count -gt 0 -and (Get-Command Merge-EpisodeTitlesPreferRu -ErrorAction SilentlyContinue)) {
        $merged = Merge-EpisodeTitlesPreferRu @($tmdbArr) @($wikiArr)
    }
    elseif ($tmdbArr -and @($tmdbArr).Count -gt 0 -and (Get-Command Expand-EpisodeListWithRussianWikipedia -ErrorAction SilentlyContinue)) {
        $merged = @(Expand-EpisodeListWithRussianWikipedia @($tmdbArr) $SeriesName)
    }
    elseif ($wikiArr.Count -gt 0 -and (Get-Command Expand-EpisodeListWithRussianWikipedia -ErrorAction SilentlyContinue)) {
        $merged = @(Expand-EpisodeListWithRussianWikipedia @($wikiArr) $SeriesName)
    }
    elseif ($wikiArr.Count -gt 0) {
        $merged = $wikiArr
    }
    elseif ($tmdbArr) {
        $merged = $tmdbArr
    }

    Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: Kinopoisk verification start" -f $SeriesName)
    $kpArr = $null
    if (Get-Command Get-EpisodesFromKinopoiskVerifiedForSeries -ErrorAction SilentlyContinue) {
        try {
            $ru = if ($pick) { [string]$pick.name } else { $null }
            $orig = if ($pick) { [string]$pick.original_name } else { $null }
            $kpArr = Get-EpisodesFromKinopoiskVerifiedForSeries -FolderTitle $SeriesName -TmdbRuName $ru -TmdbOriginalName $orig -MinMatchScore $KinopoiskMinScore
        } catch { }
    }
    if ($merged -and @($merged).Count -gt 0 -and $kpArr -and @($kpArr).Count -gt 0 -and (Get-Command Merge-EpisodeTitlesPreferRu -ErrorAction SilentlyContinue)) {
        $merged = Merge-EpisodeTitlesPreferRu @($merged) @($kpArr)
    }
    elseif ((-not $merged -or @($merged).Count -eq 0) -and $kpArr -and @($kpArr).Count -gt 0) {
        $merged = $kpArr
    }

    if ($merged -and @($merged).Count -gt 0) {
        Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: merged episodes={1}" -f $SeriesName, @($merged).Count)
        return @($merged)
    }
    Write-ToolkitProgress ("[SeriesToolkit][Meta] {0} :: merged episodes=0" -f $SeriesName)
    return @()
}

function Get-CombinedEpisodeTitleMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SeriesName,
        [int]$KinopoiskMinScore = 120,
        [switch]$AggressiveDdg
    )
    $merged = @(Get-CombinedEpisodeMergedObjects -SeriesName $SeriesName -KinopoiskMinScore $KinopoiskMinScore -AggressiveDdg:$AggressiveDdg)
    if ($merged.Count -gt 0) {
        $h = Convert-EpisodeObjectsToHashtable @($merged)
        return (Expand-EpisodeTitleMapWithLatinFallback $h)
    }
    return @{}
}

function Get-ExistingSeasonNumbersOnDisk([System.IO.DirectoryInfo]$SeriesDir) {
    $set = @{}
    foreach ($d in @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Directory -ErrorAction SilentlyContinue)) {
        $sn = Resolve-SeasonFromFolderName $d.Name
        if ($sn -and [int]$sn -gt 0) { $set[[int]$sn] = $true }
    }
    return $set
}

function Invoke-SeasonLibraryScaffold {
    param(
        [System.IO.DirectoryInfo]$SeriesDir,
        [object[]]$MergedEpisodes
    )
    if (-not $script:UserSettings.create_missing_season_folders -and -not $script:UserSettings.write_episode_index_csv) { return }
    $list = @($MergedEpisodes | Where-Object { $_ })
    if ($list.Count -eq 0) { return }

    $seasonsInData = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($it in $list) {
        $sn = if ($null -ne $it.season) { [int]$it.season } elseif ($null -ne $it.Season) { [int]$it.Season } else { 0 }
        $en = if ($null -ne $it.episode) { [int]$it.episode } elseif ($null -ne $it.Episode) { [int]$it.Episode } else { 0 }
        if ($sn -le 0 -or $en -le 0) { continue }
        $seasonsInData[$sn] = $true
        $tt = if ($null -ne $it.title) { [string]$it.title } elseif ($null -ne $it.Title) { [string]$it.Title } else { '' }
        $code = ('S{0:00}E{1:00}' -f $sn, $en)
        [void]$rows.Add([PSCustomObject]@{ season = $sn; episode = $en; code = $code; title = $tt })
    }
    if ($script:UserSettings.write_episode_index_csv -and $rows.Count -gt 0) {
        $idxPath = Join-Path $SeriesDir.FullName 'SeriesToolkit-episode-index.csv'
        $sorted = $rows | Sort-Object season, episode
        if ($DryRun) {
            Add-Record -Series $SeriesDir.Name -Action 'write-episode-index' -Status 'DRYRUN' -TargetPath $idxPath -Details ('Строк: {0}' -f $sorted.Count)
        } else {
            $sorted | Export-Csv -LiteralPath $idxPath -NoTypeInformation -Encoding UTF8
            Add-Record -Series $SeriesDir.Name -Action 'write-episode-index' -Status 'OK' -TargetPath $idxPath -Details ('Строк: {0}' -f $sorted.Count)
        }
    }
    if (-not $script:UserSettings.create_missing_season_folders) { return }
    $onDisk = Get-ExistingSeasonNumbersOnDisk $SeriesDir
    foreach ($sn in ($seasonsInData.Keys | Sort-Object)) {
        if ($onDisk.ContainsKey([int]$sn)) { continue }
        $folderName = Get-SeasonFolderName ([int]$sn)
        $seasonPath = Join-Path $SeriesDir.FullName $folderName
        $marker = Join-Path $seasonPath '.series-toolkit-scaffold'
        $note = Join-Path $seasonPath '00-ОЖИДАЕТСЯ-НА-ДИСКЕ.txt'
        if ($DryRun) {
            Add-Record -Series $SeriesDir.Name -Action 'create-missing-season-scaffold' -Status 'DRYRUN' -TargetPath $seasonPath -Details 'Сезон есть в метаданных, папки на диске не было.'
            continue
        }
        if (-not (Test-Path -LiteralPath $seasonPath)) {
            New-Item -ItemType Directory -Path $seasonPath -Force | Out-Null
        }
        $markerText = "SeriesToolkit: папка создана как заготовка под сезон {0}. Добавьте файлы эпизодов — тогда папка не будет пустой." -f $sn
        Set-Content -LiteralPath $marker -Value $markerText -Encoding UTF8
        $hint = @(
            "Сезон $sn — в базе (TMDB/Кинопоиск/Википедия) есть список серий, на диске сезона не было.",
            "Полный список: SeriesToolkit-episode-index.csv в корне сериала.",
            "Можно удалить этот файл после добавления видео."
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $note -Value $hint -Encoding UTF8
        Add-Record -Series $SeriesDir.Name -Action 'create-missing-season-scaffold' -Status 'OK' -TargetPath $seasonPath -Details 'Сезон из метаданных; маркер .series-toolkit-scaffold.'
    }
}

function Test-IsPlaceholderEpisodeFileName([string]$BaseName) {
    if ([string]::IsNullOrWhiteSpace($BaseName)) { return $false }
    return [bool]($BaseName -match '(?i)\s-\sS\d{1,2}E\d{1,3}\s-\sСерия\s+\d+\s*$')
}

function Invoke-PlaceholderTitleRepair([System.IO.DirectoryInfo]$SeriesDir, [hashtable]$EpisodeTitlesMap) {
    $seriesName = ConvertTo-SafeName $SeriesDir.Name
    $files = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$' })
    foreach ($f in $files) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if (-not (Test-IsPlaceholderEpisodeFileName $base)) { continue }
        if ($base -notmatch '(?i)\s-\sS(?<s>\d{1,2})E(?<e>\d{1,3})\s-\sСерия\s+(?<p>\d+)\s*$') { continue }
        $sn = [int]$Matches['s']
        $en = [int]$Matches['e']
        $key = "$sn|$en"
        $title = $null
        if ($EpisodeTitlesMap.ContainsKey($key)) { $title = $EpisodeTitlesMap[$key] }
        if ([string]::IsNullOrWhiteSpace($title)) { continue }
        if ($title -notmatch '\p{IsCyrillic}') {
            if (-not $script:UserSettings.placeholder_repair_allow_latin_titles) { continue }
        }
        if (Get-Command Test-EpisodeTitleLooksLikePlaceholder -ErrorAction SilentlyContinue) {
            if (Test-EpisodeTitleLooksLikePlaceholder $title) { continue }
        }
        elseif ($title -match '^(?i)(?:серия|episode)\s*\d+\s*$') { continue }
        $code = ('S{0:00}E{1:00}' -f $sn, $en)
        $newBase = Format-EpisodeFileBase -SeriesFolderName $SeriesDir.Name -Code $code -Title $title -Season $sn -Episode $en
        if ([string]::IsNullOrWhiteSpace($newBase)) { continue }
        $seasonPath = Join-Path $SeriesDir.FullName (Get-SeasonFolderName $sn)
        $target = Join-Path $seasonPath ($newBase + $f.Extension)
        if ($f.FullName -ieq $target) { continue }
        if ($DryRun) {
            Add-Record -Series $SeriesDir.Name -Action 'repair-placeholder-title' -Status 'DRYRUN' -SourcePath $f.FullName -TargetPath $target -Details 'Замена заглушки «Серия N» (ru.wikipedia, Кинопоиск, TMDB ru-RU только кириллица).'
            continue
        }
        try {
            if (-not (Test-Path -LiteralPath $seasonPath)) {
                New-Item -ItemType Directory -Path $seasonPath -Force | Out-Null
            }
            Move-Item -LiteralPath $f.FullName -Destination $target -Force
            Add-Record -Series $SeriesDir.Name -Action 'repair-placeholder-title' -Status 'OK' -SourcePath $f.FullName -TargetPath $target -Details 'Замена заглушки «Серия N» (ru.wikipedia, Кинопоиск, TMDB ru-RU только кириллица).'
        } catch {
            Add-Record -Series $SeriesDir.Name -Action 'repair-placeholder-title' -Status 'ERROR' -SourcePath $f.FullName -TargetPath $target -Details $_.Exception.Message
        }
    }
}

function Test-SeriesDirHasPlaceholderVideoFiles([System.IO.DirectoryInfo]$SeriesDir) {
    $files = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$' })
    foreach ($f in $files) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if (Test-IsPlaceholderEpisodeFileName $base) { return $true }
    }
    return $false
}

function Add-WarningsForRemainingPlaceholders([System.IO.DirectoryInfo]$SeriesDir) {
    $files = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$' })
    foreach ($f in $files) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        if (Test-IsPlaceholderEpisodeFileName $base) {
            Add-Record -Series $SeriesDir.Name -Action 'unresolved-placeholder' -Status 'WARN' -SourcePath $f.FullName -Details 'Осталась заглушка «Серия N»: нет подтверждённого русскоязычного названия (ru.wikipedia, Кинопоиск с проверкой совпадения с TMDB/именем папки, TMDB ru-RU с кириллицей).'
        }
    }
}

function Build-RenamePlanForSeries([System.IO.DirectoryInfo]$SeriesDir, [hashtable]$EpisodeTitlesMap) {
    $plan = [System.Collections.Generic.List[object]]::new()
    $seriesName = ConvertTo-SafeName $SeriesDir.Name
    $files = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(mkv|mp4|avi|mov|wmv|m4v|ts|m2ts)$' })
    foreach ($f in $files) {
        $infSeason = Get-InferredSeasonFromFilePath -FileDirectoryPath $f.DirectoryName -SeriesRootPath $SeriesDir.FullName
        $tag = Resolve-EpisodeTagFromName -Name $f.Name -InferredSeason $infSeason
        if (-not $tag) {
            $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($nameNoExt -match '^(?<e>\d{1,3})(?:-?я)?[)\].\s_-]?') {
                $sFallback = if ($null -ne $infSeason -and [int]$infSeason -gt 0) { [int]$infSeason } else { 1 }
                $tag = @{ Season = $sFallback; Episode = [int]$Matches['e']; Score = 78; Pattern = 'LeadingEpisodeNumber' }
            }
        }
        if (-not $tag) {
            $epFromPath = Get-InferredEpisodeFromPath -FileDirectoryPath $f.DirectoryName -SeriesRootPath $SeriesDir.FullName
            if ($null -ne $epFromPath) {
                $sFallback = if ($null -ne $infSeason -and [int]$infSeason -gt 0) { [int]$infSeason } else { 1 }
                $tag = @{ Season = $sFallback; Episode = [int]$epFromPath; Score = 72; Pattern = 'FolderEpisodeNumber' }
            }
        }
        if (-not $tag) {
            $fileNoExt = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($fileNoExt -notmatch '\d' -or (Test-LooksLikeExtraVideo -FullPath $f.FullName -FileNameNoExt $fileNoExt)) {
                Add-Record -Series $SeriesDir.Name -Action 'skip-file' -Status 'INFO' -SourcePath $f.FullName -Details 'Похоже на доп.видео (opening/trailer/credits), пропущено без предупреждения.'
            } else {
                Add-Record -Series $SeriesDir.Name -Action 'skip-file' -Status 'WARN' -SourcePath $f.FullName -Details 'Не найден шаблон сезона/серии.'
            }
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
        if ($EpisodeTitlesMap.ContainsKey($hKey)) { $title = $EpisodeTitlesMap[$hKey] }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = Invoke-TmdbEpisodeNameLookup -SeriesName $seriesName -Season $tag.Season -Episode $tag.Episode }
        if ($title -and $title -notmatch '\p{IsCyrillic}') { $title = $null }
        if ([string]::IsNullOrWhiteSpace($title)) { $title = "Серия $($tag.Episode)" }
        $newBase = Format-EpisodeFileBase -SeriesFolderName $SeriesDir.Name -Code $code -Title $title -Season $tag.Season -Episode $tag.Episode
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
            Add-Record -Series $SeriesDir.Name -Action 'rename-season-folder' -Status 'INFO' -SourcePath $d.FullName -TargetPath $target -Details 'Цель уже существует.'
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
            $bn = [System.IO.Path]::GetFileNameWithoutExtension($op.source)
            if (Test-IsPlaceholderEpisodeFileName $bn) {
                Add-Record -Series $op.series -Action 'skip-file' -Status 'INFO' -SourcePath $op.source -Details 'Заглушка «Серия N»; далее repair-placeholder-title (Wiki/Кинопоиск/TMDB кириллица).'
            } else {
                Add-Record -Series $op.series -Action 'skip-file' -Status 'INFO' -SourcePath $op.source -Details 'Уже корректно.'
            }
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

function Remove-EmptyDirectories([System.IO.DirectoryInfo]$SeriesDir) {
    $dirs = @(Get-ChildItem -LiteralPath $SeriesDir.FullName -Directory -Recurse -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($d in $dirs) {
        $items = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { continue }
        if ($DryRun) {
            Add-Record -Series $SeriesDir.Name -Action 'remove-empty-folder' -Status 'DRYRUN' -SourcePath $d.FullName
        } else {
            try {
                Remove-Item -LiteralPath $d.FullName -Force
                Add-Record -Series $SeriesDir.Name -Action 'remove-empty-folder' -Status 'OK' -SourcePath $d.FullName
            } catch {
                Add-Record -Series $SeriesDir.Name -Action 'remove-empty-folder' -Status 'WARN' -SourcePath $d.FullName -Details $_.Exception.Message
            }
        }
    }
}

function Run-Series([System.IO.DirectoryInfo]$SeriesDir, [hashtable]$HtmlTitles) {
    Write-ToolkitProgress ("[SeriesToolkit] Обработка: {0}" -f $SeriesDir.FullName)
    $seriesTotalStages = 8
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Старт обработки' -Index 0 -Total $seriesTotalStages
    Normalize-SeasonFolderNames -SeriesDir $SeriesDir
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Нормализация папок сезонов' -Index 1 -Total $seriesTotalStages
    $seriesName = ConvertTo-SafeName $SeriesDir.Name
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Сбор метаданных (Wiki/TMDB/KP)' -Index 2 -Total $seriesTotalStages
    $mergedFirst = @(Get-CombinedEpisodeMergedObjects -SeriesName $seriesName -KinopoiskMinScore 120)
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Сбор метаданных завершён' -Index 3 -Total $seriesTotalStages
    Invoke-SeasonLibraryScaffold -SeriesDir $SeriesDir -MergedEpisodes $mergedFirst
    $mapFromNet = @{}
    if ($mergedFirst.Count -gt 0) {
        $mapFromNet = Expand-EpisodeTitleMapWithLatinFallback (Convert-EpisodeObjectsToHashtable @($mergedFirst))
    }
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Построение плана переименований' -Index 4 -Total $seriesTotalStages
    $allTitles = Merge-EpisodeTitleMaps -Primary $HtmlTitles -Fallback $mapFromNet
    $plan = Build-RenamePlanForSeries -SeriesDir $SeriesDir -EpisodeTitlesMap $allTitles
    Resolve-TargetConflicts -Plan $plan
    Ensure-SeasonFolders -Plan $plan -SeriesName $SeriesDir.Name
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Применение плана' -Index 5 -Total $seriesTotalStages
    Apply-Plan -Plan $plan
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Ремонт заглушек Серия N' -Index 6 -Total $seriesTotalStages
    Invoke-PlaceholderTitleRepair -SeriesDir $SeriesDir -EpisodeTitlesMap $allTitles
    Remove-EmptyDirectories -SeriesDir $SeriesDir

    if (-not (Test-SeriesDirHasPlaceholderVideoFiles $SeriesDir)) {
        Add-WarningsForRemainingPlaceholders -SeriesDir $SeriesDir
        Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Готово' -Index 8 -Total $seriesTotalStages
        return
    }

    $kp2 = [int]$script:UserSettings.aggressive_second_pass_kinopoisk_min_score
    if ($kp2 -lt 50) { $kp2 = 85 }
    Add-Record -Series $SeriesDir.Name -Action 'second-pass-aggressive' -Status 'INFO' -Details ('Повторный сбор названий: DDG+ru.wikipedia, Кинопоиск minScore={0}, вторая строка поиска — имя папки.' -f $kp2)
    $extraA = Get-CombinedEpisodeTitleMap -SeriesName $seriesName -KinopoiskMinScore $kp2 -AggressiveDdg
    $rawLeaf = $SeriesDir.Name.Trim()
    $extraB = @{}
    if ($rawLeaf -ne $seriesName) {
        $extraB = Get-CombinedEpisodeTitleMap -SeriesName $rawLeaf -KinopoiskMinScore $kp2 -AggressiveDdg
    }
    $extraMerged = Merge-EpisodeTitleMaps -Primary $extraA -Fallback $extraB
    $allTitles2 = Merge-EpisodeTitleMaps -Primary $allTitles -Fallback $extraMerged
    Invoke-PlaceholderTitleRepair -SeriesDir $SeriesDir -EpisodeTitlesMap $allTitles2
    Remove-EmptyDirectories -SeriesDir $SeriesDir
    Add-WarningsForRemainingPlaceholders -SeriesDir $SeriesDir
    Write-SeriesProgress -SeriesName $SeriesDir.Name -Stage 'Готово (после 2-го прохода)' -Index 8 -Total $seriesTotalStages
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
    $seriesRoots = @(Get-SeriesRootsUnderLibrary $RootPath)
    if ($seriesRoots.Count -eq 0) {
        Add-Record -Series '-' -Action 'library-scan' -Status 'WARN' -SourcePath $RootPath -Details 'Не найдено папок сериалов (нет видео/сезонов или пустой каталог).'
    }
    $idx = 0
    foreach ($sd in $seriesRoots) {
        $idx++
        $pct = [int][Math]::Floor(($idx * 100.0) / [Math]::Max($seriesRoots.Count, 1))
        Write-ToolkitProgress ("[SeriesToolkit][LibraryProgress {0}% {1}/{2}] {3}" -f $pct, $idx, $seriesRoots.Count, $sd.FullName)
        Run-Series -SeriesDir $sd -HtmlTitles $htmlTitles
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$modeTag = if ($DryRun) { 'dryrun' } else { 'apply' }
$csvPath = Join-Path $LogDirectory ("series-toolkit-v$($script:ToolkitVersion)-$($Mode.ToLowerInvariant())-$modeTag-$stamp.csv")
$txtPath = Join-Path $LogDirectory ("series-toolkit-v$($script:ToolkitVersion)-$($Mode.ToLowerInvariant())-$modeTag-$stamp.txt")
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
Write-ToolkitProgress $summary

