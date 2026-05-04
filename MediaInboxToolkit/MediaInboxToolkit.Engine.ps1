#requires -Version 5.1
<#
.SYNOPSIS
  Движок MediaInboxToolkit: inbox (сериалы SxxEyy, фильмы, Blu-ray remux), русские имена через TMDB, план CSV/TXT.
.DESCRIPTION
  Вызывается из MediaInboxToolkit.ps1. Политика JSON (sort-inbox.example.json). Родительский модуль метаданных — Fetch-VideoMetadata.ps1 в корне репозитория.
  Дальнейшая нормализация библиотеки сериалов — отдельным запуском SeriesToolkit (см. README «Связка с SeriesToolkit»).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PolicyPath,
    [string]$InboxPath = '',
    [string]$LogDirectory = '',
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$UseTmdb,
    [string]$TmdbApiKey = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch { }

if ($Apply -and $DryRun) { throw 'Cannot use -Apply and -DryRun together.' }
if (-not $Apply) { $DryRun = $true }

$fetchModule = $null
$envFetch = [Environment]::GetEnvironmentVariable('FETCH_VIDEO_METADATA_PATH', 'Process')
if (-not [string]::IsNullOrWhiteSpace($envFetch) -and (Test-Path -LiteralPath $envFetch)) {
    $fetchModule = $envFetch
}
if (-not $fetchModule) {
    $here = Join-Path $PSScriptRoot 'Fetch-VideoMetadata.ps1'
    if (Test-Path -LiteralPath $here) { $fetchModule = $here }
}
if (-not $fetchModule) {
    $parent = Join-Path (Split-Path -Parent $PSScriptRoot) 'Fetch-VideoMetadata.ps1'
    if (Test-Path -LiteralPath $parent) { $fetchModule = $parent }
}
if (-not $fetchModule -or -not (Test-Path -LiteralPath $fetchModule)) {
    throw "Fetch-VideoMetadata.ps1 not found. Положите рядом со скриптами (standalone), в родителе папки MediaInboxToolkit (монорепо) или задайте FETCH_VIDEO_METADATA_PATH."
}
. $fetchModule
if (Get-Command Initialize-WebClient -ErrorAction SilentlyContinue) {
    try { Initialize-WebClient } catch { }
}

$contentKindsPath = Join-Path $PSScriptRoot 'MediaInboxToolkit.ContentKinds.ps1'
if (Test-Path -LiteralPath $contentKindsPath) {
    . $contentKindsPath
}
$tmdbKindRefinePath = Join-Path $PSScriptRoot 'MediaInboxToolkit.TmdbKindRefine.ps1'
if (Test-Path -LiteralPath $tmdbKindRefinePath) {
    . $tmdbKindRefinePath
}

function ConvertTo-SafeFolderName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return '_' }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch -or [char]::IsControl($ch)) { [void]$sb.Append(' ') }
        else { [void]$sb.Append($ch) }
    }
    $t = $sb.ToString().Trim()
    $t = $t -replace '\s{2,}', ' '
    if ([string]::IsNullOrWhiteSpace($t)) { return '_' }
    return $t
}

function Normalize-SortSeriesSearchQuery([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $t = $s -replace '\.', ' '
    $t = $t -replace '_', ' '
    $t = ($t -replace '\s+', ' ').Trim()
    return $t
}

function Remove-SortReleaseTechnicalTokens([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $t = $s
    $t = $t -replace '(?i)\s*[\(\[]?(2160p|1080p|720p|480p|DVD\d*)\]?[\)\]]?', ' '
    $t = $t -replace '(?i)\b(WEB-?DL|WEBRip|BluRay|BDRip|BDRemux|REMUX|HDR10?|DV|DoVi|Hybrid|UHD|IMAX|x264|x265|H\.?265|HEVC|AVC)\b', ' '
    $t = $t -replace '(?i)\b(AMZN|NF|NETFLIX|DSNP|DISNEY|TVShows|RGzsRutracker|Rutracker|TeamHD|Remux|CR|Funi|HIDIVE|LostFilm|NewStudio|AlexFilm|Jaskier)\b', ' '
    $t = $t -replace '(?i)\b\d{3,4}p\b', ' '
    $t = $t -replace '(?i)\bS\d{1,2}E\d{1,3}\b', ' '
    $t = $t -replace '\.', ' '
    $t = ($t -replace '\s+', ' ').Trim()
    return $t
}

function Get-SortYearTokenFromText([string]$text) {
    $m = [regex]::Match($text, '\b((?:19|20)\d{2})\b')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Select-SortTmdbTvBestHit {
    param(
        [object[]]$Hits,
        [string]$SeriesGuessNorm
    )
    $hitList = @($Hits)
    if ($hitList.Count -eq 0) { return $null }
    $q = ($SeriesGuessNorm.ToLowerInvariant() -replace '[^a-z0-9\u0400-\u04ff]+', ' ').Trim()
    $qTokens = @($q -split '\s+' | Where-Object { $_.Length -ge 5 } | Select-Object -Unique)
    $pool = [System.Collections.Generic.List[object]]::new()
    foreach ($h in $hitList) { [void]$pool.Add($h) }
    if ($qTokens.Count -gt 0) {
        $narrowed = [System.Collections.Generic.List[object]]::new()
        foreach ($h in $hitList) {
            $n = ([string]$h.name).ToLowerInvariant() -replace '[^a-z0-9\u0400-\u04ff]+', ' '
            $hitTok = $false
            foreach ($w in $qTokens) {
                if ($n.Contains($w)) { $hitTok = $true; break }
            }
            if ($hitTok) { [void]$narrowed.Add($h) }
        }
        if ($narrowed.Count -gt 0) { $pool = $narrowed }
    }
    $best = $pool[0]
    $bestScore = [double]::NegativeInfinity
    foreach ($h in $pool) {
        $name = [string]$h.name
        $pop = 0.0
        try {
            if ($null -ne $h.popularity) { $pop = [double]$h.popularity }
        } catch { $pop = 0.0 }
        $n = ($name.ToLowerInvariant() -replace '[^a-z0-9\u0400-\u04ff]+', ' ').Trim()
        $score = $pop
        if ($q.Length -ge 2) {
            if ($n.Contains($q)) { $score += 80 }
            elseif ($n.StartsWith($q.Substring(0, [Math]::Min([Math]::Max(1, $q.Length), 6)))) { $score += 40 }
        }
        if (Get-Command Test-TmdbTitleHasCyrillic -ErrorAction SilentlyContinue) {
            if (Test-TmdbTitleHasCyrillic $name) { $score += 25 }
        }
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $h
        }
    }
    return $best
}

function Find-BlurayReleaseRootsUnderInbox {
    param([string]$InboxRoot)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $InboxRoot)) { return @() }
    $inboxPrefix = $InboxRoot.TrimEnd('\') + '\'
    foreach ($streamDir in Get-ChildItem -LiteralPath $InboxRoot -Directory -Recurse -Filter 'STREAM' -ErrorAction SilentlyContinue) {
        try {
            $parentName = $streamDir.Parent.Name
            if ($parentName -ne 'BDMV') { continue }
            $bdmvPath = $streamDir.Parent.FullName
            $m2ts = @(Get-ChildItem -LiteralPath $streamDir.FullName -Filter '*.m2ts' -File -ErrorAction SilentlyContinue)
            if ($m2ts.Count -eq 0) { continue }
            $releaseRoot = [System.IO.Directory]::GetParent($bdmvPath).FullName
            if (-not $releaseRoot.StartsWith($inboxPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
            [void]$set.Add($releaseRoot)
        } catch { }
    }
    return @($set)
}

function Test-PathUnderAnyRoot {
    param(
        [string]$FullPath,
        [string[]]$Roots
    )
    foreach ($r in $Roots) {
        if ([string]::IsNullOrWhiteSpace($r)) { continue }
        $prefix = $r.TrimEnd('\') + '\'
        if ($FullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-VideoClassification {
    param([string]$FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $m = [regex]::Match($base, '(?i)\bS(\d{1,2})\s*E(\d{1,3})\b')
    if (-not $m.Success) {
        $m = [regex]::Match($base, '(?<![\d])(\d{1,2})[xX](\d{1,3})(?![\d])')
    }
    if ($m.Success) {
        $sn = [int]$m.Groups[1].Value
        $en = [int]$m.Groups[2].Value
        $idx = $m.Index
        $trimEndChars = [char[]]@(' ', '.', '-', '_', [char]0x2014)
        $trimStartChars = [char[]]@(' ', '-', '_', [char]0x2014)
        $seriesPart = $base.Substring(0, $idx).TrimEnd($trimEndChars)
        $after = $base.Substring($idx + $m.Length).TrimStart($trimStartChars)
        if ([string]::IsNullOrWhiteSpace($after)) { $after = $null }
        else {
            $after = $after.TrimStart()
        }
        if ([string]::IsNullOrWhiteSpace($seriesPart)) { $seriesPart = 'UnknownSeries' }
        return [pscustomobject]@{
            Kind         = 'series'
            Season       = $sn
            Episode      = $en
            SeriesGuess  = $seriesPart
            EpisodeTitle = $after
            Confidence   = 70
            QueryMovie   = $null
        }
    }
    return [pscustomobject]@{
        Kind         = 'movie'
        Season       = 0
        Episode      = 0
        SeriesGuess  = $null
        EpisodeTitle = $null
        Confidence   = 40
        QueryMovie   = $base
    }
}

function Expand-PolicyPath {
    param(
        [string]$NasRoot,
        [string]$Relative
    )
    $rel = ($Relative -replace '/', '\').TrimStart('\')
    return (Join-Path -Path $NasRoot -ChildPath $rel)
}

$PolicyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PolicyPath)
if (-not (Test-Path -LiteralPath $PolicyPath)) { throw "Policy file not found: $PolicyPath" }
$policy = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json

$nasRoot = [string]$policy.nasShareRoot
if ([string]::IsNullOrWhiteSpace($nasRoot)) { throw 'Policy requires nasShareRoot.' }

$inboxRel = [string]$policy.inboxRelative
if ([string]::IsNullOrWhiteSpace($InboxPath)) {
    $InboxPath = Expand-PolicyPath -NasRoot $nasRoot -Relative $inboxRel
} else {
    $InboxPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InboxPath)
}

if (-not (Test-Path -LiteralPath $InboxPath)) {
    throw "Inbox path not found (create folder or pass -InboxPath): $InboxPath"
}

$inboxNormForRel = $InboxPath.TrimEnd('\')

$destByKey = @{}
foreach ($dp in $policy.destinations.PSObject.Properties) {
    $destByKey[$dp.Name] = Expand-PolicyPath -NasRoot $nasRoot -Relative ([string]$dp.Value)
}
foreach ($req in @('series', 'movies', 'review')) {
    if (-not $destByKey.ContainsKey($req)) { throw "Policy requires destinations.$req" }
}
if (-not $destByKey.ContainsKey('cartoons')) {
    $destByKey['cartoons'] = $destByKey['series']
}

$destSeries = $destByKey['series']
$destCartoons = $destByKey['cartoons']
$destMovies = $destByKey['movies']
$destReview = $destByKey['review']

$destinationsByKindMap = @{}
$destinationsByKindMinConf = 0
if ($policy.PSObject.Properties.Name -contains 'destinationsByKind' -and $null -ne $policy.destinationsByKind) {
    foreach ($kp in $policy.destinationsByKind.PSObject.Properties) {
        $destinationsByKindMap[$kp.Name] = [string]$kp.Value
    }
    if ($policy.PSObject.Properties.Name -contains 'destinationsByKindMinConfidence') {
        try { $destinationsByKindMinConf = [int]$policy.destinationsByKindMinConfidence } catch { $destinationsByKindMinConf = 0 }
    }
    foreach ($targetKey in $destinationsByKindMap.Values) {
        if (-not $destByKey.ContainsKey($targetKey)) {
            throw "destinationsByKind: unknown destinations key '$targetKey' - add it to policy.destinations."
        }
    }
}

$safetyRequireInbox = $false
$safetySkipLibrary = $false
$libraryRootsExpanded = [System.Collections.Generic.List[string]]::new()
if ($policy.PSObject.Properties.Name -contains 'safety' -and $null -ne $policy.safety) {
    $sf = $policy.safety
    if ($sf.PSObject.Properties.Name -contains 'requireSourceUnderInbox') {
        $safetyRequireInbox = [bool]$sf.requireSourceUnderInbox
    }
    if ($sf.PSObject.Properties.Name -contains 'skipSourceIfUnderLibrary') {
        $safetySkipLibrary = [bool]$sf.skipSourceIfUnderLibrary
    }
    if ($sf.libraryRootRelatives) {
        foreach ($rel in @($sf.libraryRootRelatives)) {
            $normRel = ([string]$rel -replace '/', '\').TrimStart('\')
            [void]$libraryRootsExpanded.Add((Expand-PolicyPath -NasRoot $nasRoot -Relative $normRel))
        }
    }
}

function Resolve-MediaInboxDestinationKey {
    param(
        [string]$ContentKind,
        [int]$ContentConf,
        [hashtable]$ByKindMap,
        [int]$MinConfidence,
        [string]$FallbackKey
    )
    if ($null -eq $ByKindMap -or $ByKindMap.Count -eq 0) { return $FallbackKey }
    if ([string]::IsNullOrWhiteSpace($ContentKind)) { return $FallbackKey }
    if ($ContentConf -lt $MinConfidence) { return $FallbackKey }
    if ($ByKindMap.ContainsKey($ContentKind)) { return [string]$ByKindMap[$ContentKind] }
    return $FallbackKey
}

$preferCartoons = $false
if ($null -ne $policy.preferCartoonsSubfolder) { $preferCartoons = [bool]$policy.preferCartoonsSubfolder }
$seasonFmt = [string]$policy.seasonFolderFormat
if ([string]::IsNullOrWhiteSpace($seasonFmt)) { $seasonFmt = 'Сезон {0}' }

$tmdbLang = 'ru-RU'
$preferCyrillic = $true
if ($policy.PSObject.Properties.Name -contains 'displayNames') {
    $dn = $policy.displayNames
    if ($dn -and ($dn.PSObject.Properties.Name -contains 'tmdbLanguage') -and -not [string]::IsNullOrWhiteSpace([string]$dn.tmdbLanguage)) {
        $tmdbLang = [string]$dn.tmdbLanguage
    }
    if ($dn -and ($dn.PSObject.Properties.Name -contains 'preferCyrillic')) {
        $preferCyrillic = [bool]$dn.preferCyrillic
    }
}

$blurayEnabled = $true
if (($policy.PSObject.Properties.Name -contains 'blurayRemux') -and $policy.blurayRemux) {
    $br = $policy.blurayRemux
    if ($br.PSObject.Properties.Name -contains 'enabled') {
        $blurayEnabled = [bool]$br.enabled
    }
}

$tmdbKindRefineEnabled = $UseTmdb
if (($policy.PSObject.Properties.Name -contains 'tmdbKindRefinement') -and $null -ne $policy.tmdbKindRefinement) {
    $tkr = $policy.tmdbKindRefinement
    if ($tkr.PSObject.Properties.Name -contains 'enabled') {
        $tmdbKindRefineEnabled = [bool]$tkr.enabled -and $UseTmdb
    }
}

$createDestRootsOnApply = $true
if (($policy.PSObject.Properties.Name -contains 'folders') -and $null -ne $policy.folders) {
    $fd = $policy.folders
    if ($fd.PSObject.Properties.Name -contains 'createDestinationRootsOnApply') {
        $createDestRootsOnApply = [bool]$fd.createDestinationRootsOnApply
    }
}

$epFallbackFmt = 'Серия {0}'
if (($policy.PSObject.Properties.Name -contains 'episodeTitleFallback') -and -not [string]::IsNullOrWhiteSpace([string]$policy.episodeTitleFallback)) {
    $epFallbackFmt = [string]$policy.episodeTitleFallback
}

$extList = @()
foreach ($e in @($policy.videoExtensions)) { $extList += [string]$e.ToLowerInvariant() }
if ($extList.Count -eq 0) { $extList = @('mkv', 'mp4', 'avi') }

if ([string]::IsNullOrWhiteSpace($LogDirectory)) { $LogDirectory = Join-Path $PSScriptRoot 'LOGS' }
if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $LogDirectory ("sort-inbox-{0}.csv" -f $stamp)
$txtPath = Join-Path $LogDirectory ("sort-inbox-{0}.txt" -f $stamp)

$key = $TmdbApiKey
if ($UseTmdb -and [string]::IsNullOrWhiteSpace($key)) {
    if (Get-Command Get-TmdbApiKeyFromEnvironment -ErrorAction SilentlyContinue) {
        $key = Get-TmdbApiKeyFromEnvironment
    }
}

$blurayRoots = @()
if ($blurayEnabled) {
    $blurayRoots = @(Find-BlurayReleaseRootsUnderInbox -InboxRoot $InboxPath)
}

$allFiles = @(Get-ChildItem -LiteralPath $InboxPath -File -Recurse -ErrorAction Stop | Where-Object {
        $extList -contains $_.Extension.TrimStart('.').ToLowerInvariant()
    })

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($f in $allFiles) {
    if (Test-PathUnderAnyRoot -FullPath $f.FullName -Roots $blurayRoots) { continue }
    [void]$files.Add($f)
}

$seriesTemplate = [string]$policy.filenameTemplates.series
if ([string]::IsNullOrWhiteSpace($seriesTemplate)) {
    $seriesTemplate = '{Series} - S{Season:D2}E{Episode:D2} - {Title}.{Ext}'
}
$movieTemplate = [string]$policy.filenameTemplates.movie
if ([string]::IsNullOrWhiteSpace($movieTemplate)) {
    # Плоская выкладка в «Фильмы»: без подпапки года (удобнее для ТВ).
    $movieTemplate = '{Title}.{Ext}'
}

$seriesResolveCache = @{}
$seasonMapCache = @{}

function Get-CachedSeriesTmdbRow {
    param(
        [string]$SeriesGuess,
        [string]$ApiKey,
        [string]$Lang
    )
    $normQ = Normalize-SortSeriesSearchQuery $SeriesGuess
    if ([string]::IsNullOrWhiteSpace($normQ)) { $normQ = $SeriesGuess }
    if ($seriesResolveCache.ContainsKey($normQ)) { return $seriesResolveCache[$normQ] }
    $row = @{
        TvId         = $null
        SeriesFolder = (ConvertTo-SafeFolderName $SeriesGuess)
        Notes        = ''
    }
    if ($UseTmdb -and -not [string]::IsNullOrWhiteSpace($ApiKey) -and (Get-Command Search-TmdbTvSeries -ErrorAction SilentlyContinue)) {
        $hits = @(Search-TmdbTvSeries -Query $normQ -ApiKey $ApiKey -Language $Lang)
        $pick = Select-SortTmdbTvBestHit -Hits $hits -SeriesGuessNorm $normQ
        if ($pick) {
            $tid = [int]$pick.id
            $row.TvId = $tid
            $disp = $null
            if (Get-Command Get-TmdbTvResolvedRuDisplayName -ErrorAction SilentlyContinue) {
                $disp = Get-TmdbTvResolvedRuDisplayName -TvId $tid -ApiKey $ApiKey
            }
            if (-not [string]::IsNullOrWhiteSpace($disp)) {
                $row.SeriesFolder = ConvertTo-SafeFolderName $disp
            }
            else {
                $row.SeriesFolder = ConvertTo-SafeFolderName ([string]$pick.name)
            }
            $row.Notes = "tmdb_tv:$tid"
        }
    }
    $seriesResolveCache[$normQ] = $row
    return $row
}

function Get-CachedSeasonEpisodeTitle {
    param(
        [int]$TvId,
        [int]$SeasonNumber,
        [int]$EpisodeNumber,
        [string]$ApiKey,
        [string]$Lang
    )
    if ($TvId -le 0 -or [string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
    $sk = "${TvId}|${SeasonNumber}|${Lang}"
    if (-not $seasonMapCache.ContainsKey($sk)) {
        $map = @{}
        if (Get-Command Get-TmdbTvSeasonEpisodeTitleMap -ErrorAction SilentlyContinue) {
            $map = Get-TmdbTvSeasonEpisodeTitleMap -TvId $TvId -SeasonNumber $SeasonNumber -ApiKey $ApiKey -Language $Lang
        }
        $seasonMapCache[$sk] = $map
    }
    $m = $seasonMapCache[$sk]
    $ek = [string]$EpisodeNumber
    if ($m -and $m.ContainsKey($ek)) { return [string]$m[$ek] }
    return $null
}

function Resolve-SortEpisodeDisplayTitle {
    param(
        $Cls,
        [hashtable]$SeriesRow,
        [string]$ApiKey,
        [string]$Lang,
        [string]$FallbackFmt
    )
    $en = [int]$Cls.Episode
    $fromTmdb = $null
    if ($SeriesRow.TvId -and -not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $fromTmdb = Get-CachedSeasonEpisodeTitle -TvId ([int]$SeriesRow.TvId) -SeasonNumber ([int]$Cls.Season) -EpisodeNumber $en -ApiKey $ApiKey -Lang $Lang
    }
    if (-not [string]::IsNullOrWhiteSpace($fromTmdb)) {
        $clean = Remove-SortReleaseTechnicalTokens $fromTmdb
        if ([string]::IsNullOrWhiteSpace($clean)) { $clean = $fromTmdb.Trim() }
        return (ConvertTo-SafeFolderName $clean)
    }
    $raw = [string]$Cls.EpisodeTitle
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $clean2 = Remove-SortReleaseTechnicalTokens $raw
        if (-not [string]::IsNullOrWhiteSpace($clean2) -and $clean2.Length -ge 2) {
            return (ConvertTo-SafeFolderName $clean2)
        }
    }
    return (ConvertTo-SafeFolderName ($FallbackFmt -f $en))
}

$mitTvDetailById = @{}
$mitMovieDetailById = @{}

function Get-MitCachedTmdbTvDetails {
    param(
        [int]$TvId,
        [string]$ApiKey,
        [string]$Lang
    )
    if ($TvId -le 0 -or [string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
    $k = "${TvId}|${Lang}"
    if ($mitTvDetailById.ContainsKey($k)) { return $mitTvDetailById[$k] }
    $d = $null
    if (Get-Command Get-TmdbTvDetailsLocalized -ErrorAction SilentlyContinue) {
        $d = Get-TmdbTvDetailsLocalized -TvId $TvId -ApiKey $ApiKey -Language $Lang
    }
    $mitTvDetailById[$k] = $d
    return $d
}

function Get-MitCachedTmdbMovieDetails {
    param(
        [int]$MovieId,
        [string]$ApiKey,
        [string]$Lang
    )
    if ($MovieId -le 0 -or [string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
    $k = "${MovieId}|${Lang}"
    if ($mitMovieDetailById.ContainsKey($k)) { return $mitMovieDetailById[$k] }
    $d = $null
    if (Get-Command Get-TmdbMovieDetailsLocalized -ErrorAction SilentlyContinue) {
        $d = Get-TmdbMovieDetailsLocalized -MovieId $MovieId -ApiKey $ApiKey -Language $Lang
    }
    $mitMovieDetailById[$k] = $d
    return $d
}

$rows = [System.Collections.Generic.List[object]]::new()

foreach ($f in $files) {
    $cls = Get-VideoClassification -FileName $f.Name
    $relFromInbox = ''
    $prefixInbox = $inboxNormForRel + '\'
    if ($f.FullName.StartsWith($prefixInbox, [StringComparison]::OrdinalIgnoreCase)) {
        $relFromInbox = $f.FullName.Substring($prefixInbox.Length)
    }
    $ckKind = ''
    $ckConf = ''
    $ckWhy = ''
    $ckConfInt = 0
    if (Get-Command Get-MediaInboxVideoKindGuess -ErrorAction SilentlyContinue) {
        $kg = Get-MediaInboxVideoKindGuess -File $f -RelativePathFromInbox $relFromInbox
        if ($kg) {
            $ckKind = [string]$kg.Kind
            $ckConf = [string]$kg.Confidence
            $ckWhy = [string]$kg.Reason
            $null = [int]::TryParse($ckConf, [ref]$ckConfInt)
        }
    }

    if ($safetyRequireInbox -and -not $f.FullName.StartsWith($prefixInbox, [StringComparison]::OrdinalIgnoreCase)) {
        $rows.Add([pscustomobject]@{
                SourceFullPath          = $f.FullName
                DestFullPath            = $f.FullName
                Kind                    = $cls.Kind
                ContentKindGuess        = $ckKind
                ContentKindConfidence   = $ckConf
                ContentKindReason       = $ckWhy
                DestRootKey             = ''
                Confidence              = 5
                Notes                   = 'skip_not_under_inbox'
                DryRun                  = [bool]$DryRun
            }) | Out-Null
        continue
    }
    if ($safetySkipLibrary -and ($libraryRootsExpanded.Count -gt 0) -and (Test-PathUnderAnyRoot -FullPath $f.FullName -Roots @($libraryRootsExpanded.ToArray()))) {
        $rows.Add([pscustomobject]@{
                SourceFullPath          = $f.FullName
                DestFullPath            = $f.FullName
                Kind                    = $cls.Kind
                ContentKindGuess        = $ckKind
                ContentKindConfidence   = $ckConf
                ContentKindReason       = $ckWhy
                DestRootKey             = ''
                Confidence              = 5
                Notes                   = 'skip_source_in_library'
                DryRun                  = [bool]$DryRun
            }) | Out-Null
        continue
    }

    $fallbackSeriesKey = if ($preferCartoons) { 'cartoons' } else { 'series' }
    $seriesDestKey = $fallbackSeriesKey
    $movieDestKey = 'movies'
    $destFull = $null
    $newFileName = $f.Name
    $notes = [string]::Empty
    $activeDestRootKey = ''

    if ($cls.Kind -eq 'series') {
        $seriesRow = Get-CachedSeriesTmdbRow -SeriesGuess $cls.SeriesGuess -ApiKey $key -Lang $tmdbLang
        if ($tmdbKindRefineEnabled -and $seriesRow.TvId -and (Get-Command Resolve-MediaInboxContentKindFromTmdbTv -ErrorAction SilentlyContinue)) {
            $tvDet = Get-MitCachedTmdbTvDetails -TvId ([int]$seriesRow.TvId) -ApiKey $key -Lang $tmdbLang
            $adjTv = Resolve-MediaInboxContentKindFromTmdbTv -TvDetails $tvDet -HeuristicKind $ckKind -HeuristicConfidence $ckConfInt
            if ($adjTv) {
                $ckKind = [string]$adjTv.Kind
                $ckConfInt = [int]$adjTv.Confidence
                $ckConf = [string]$adjTv.Confidence
                $whyAdd = [string]$adjTv.Reason
                $ckWhy = if ([string]::IsNullOrWhiteSpace($ckWhy)) { $whyAdd } else { "$ckWhy|$whyAdd" }
            }
        }
        $seriesDestKey = Resolve-MediaInboxDestinationKey -ContentKind $ckKind -ContentConf $ckConfInt -ByKindMap $destinationsByKindMap -MinConfidence $destinationsByKindMinConf -FallbackKey $fallbackSeriesKey
        if (-not $destByKey.ContainsKey($seriesDestKey)) { $seriesDestKey = $fallbackSeriesKey }
        $destRootSeries = $destByKey[$seriesDestKey]
        $activeDestRootKey = $seriesDestKey
        if (-not [string]::IsNullOrWhiteSpace($seriesRow.Notes)) { $notes = $seriesRow.Notes }
        $seriesFolder = [string]$seriesRow.SeriesFolder
        $seasonFolder = $seasonFmt -f $cls.Season
        $titleForFile = Resolve-SortEpisodeDisplayTitle -Cls $cls -SeriesRow $seriesRow -ApiKey $key -Lang $tmdbLang -FallbackFmt $epFallbackFmt
        if ($preferCyrillic -and (Get-Command Test-TmdbTitleHasCyrillic -ErrorAction SilentlyContinue)) {
            if (-not (Test-TmdbTitleHasCyrillic $seriesFolder)) {
                $cls.Confidence = [math]::Min([int]$cls.Confidence, 55)
                if ($notes) { $notes += ';' }
                $notes += 'series_folder_not_cyrillic'
            }
            if (-not (Test-TmdbTitleHasCyrillic $titleForFile)) {
                $cls.Confidence = [math]::Min([int]$cls.Confidence, 55)
                if ($notes) { $notes += ';' }
                $notes += 'episode_title_not_cyrillic'
            }
        }
        $newFileName = $seriesTemplate `
            -replace '\{Series\}', $seriesFolder `
            -replace '\{Season:D2\}', ($cls.Season.ToString('D2')) `
            -replace '\{Episode:D2\}', ($cls.Episode.ToString('D2')) `
            -replace '\{Title\}', $titleForFile `
            -replace '\{Ext\}', $f.Extension.TrimStart('.')
        $destFull = Join-Path $destRootSeries (Join-Path $seriesFolder (Join-Path $seasonFolder $newFileName))
    }
    else {
        $year = ''
        $movieTitle = ConvertTo-SafeFolderName $cls.QueryMovie
        $mid = $null
        $my = [regex]::Match([string]$cls.QueryMovie, '\((\d{4})\)\s*$')
        if ($my.Success) { $year = $my.Groups[1].Value }
        if ([string]::IsNullOrWhiteSpace($year)) {
            $yFromName = Get-SortYearTokenFromText ([string]$cls.QueryMovie)
            if (-not [string]::IsNullOrWhiteSpace($yFromName)) { $year = $yFromName }
        }
        if ($UseTmdb -and -not [string]::IsNullOrWhiteSpace($key) -and (Get-Command Search-TmdbMovie -ErrorAction SilentlyContinue)) {
            $q = [regex]::Replace([string]$cls.QueryMovie, '\s*\(\d{4}\)\s*$', '').Trim()
            $q = Remove-SortReleaseTechnicalTokens $q
            if ([string]::IsNullOrWhiteSpace($q)) { $q = [string]$cls.QueryMovie }
            $mh = @(Search-TmdbMovie -Query $q -ApiKey $key -Language $tmdbLang)
            if ($mh.Count -gt 0) {
                $mid = [int]$mh[0].id
                $resolved = $null
                if (Get-Command Get-TmdbMovieResolvedRuTitle -ErrorAction SilentlyContinue) {
                    $resolved = Get-TmdbMovieResolvedRuTitle -MovieId $mid -ApiKey $key
                }
                if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                    $movieTitle = ConvertTo-SafeFolderName $resolved
                }
                else {
                    $movieTitle = ConvertTo-SafeFolderName ([string]$mh[0].title)
                }
                $rd = [string]$mh[0].release_date
                if ($rd -and $rd.Length -ge 4) { $year = $rd.Substring(0, 4) }
                $notes = "tmdb_movie:$mid"
                $cls.Confidence = 75
            }
        }
        if ($tmdbKindRefineEnabled -and $mid -and (Get-Command Resolve-MediaInboxContentKindFromTmdbMovie -ErrorAction SilentlyContinue)) {
            $mDet = Get-MitCachedTmdbMovieDetails -MovieId $mid -ApiKey $key -Lang $tmdbLang
            $adjM = Resolve-MediaInboxContentKindFromTmdbMovie -MovieDetails $mDet -HeuristicKind $ckKind -HeuristicConfidence $ckConfInt
            if ($adjM) {
                $ckKind = [string]$adjM.Kind
                $ckConfInt = [int]$adjM.Confidence
                $ckConf = [string]$adjM.Confidence
                $whyAddM = [string]$adjM.Reason
                $ckWhy = if ([string]::IsNullOrWhiteSpace($ckWhy)) { $whyAddM } else { "$ckWhy|$whyAddM" }
            }
        }
        $movieDestKey = Resolve-MediaInboxDestinationKey -ContentKind $ckKind -ContentConf $ckConfInt -ByKindMap $destinationsByKindMap -MinConfidence $destinationsByKindMinConf -FallbackKey 'movies'
        if (-not $destByKey.ContainsKey($movieDestKey)) { $movieDestKey = 'movies' }
        $destMoviesResolved = $destByKey[$movieDestKey]
        if ([string]::IsNullOrWhiteSpace($year)) { $year = '0000' }
        $tmdbMovieOk = $notes -match '^tmdb_movie:\d+'
        if ($year -eq '0000' -and -not $tmdbMovieOk) {
            $destFull = Join-Path $destReview $f.Name
            $newFileName = $f.Name
            $cls.Confidence = 25
            $activeDestRootKey = 'review'
            $notes = if ([string]::IsNullOrWhiteSpace($notes)) { 'movie_needs_year_or_tmdb' } else { "$notes;movie_needs_year_or_tmdb" }
        }
        else {
            $yearToken = if ($year -eq '0000') { '' } else { $year }
            $newFileName = $movieTemplate `
                -replace '\{Title\}', $movieTitle `
                -replace '\{Year\}', $yearToken `
                -replace '\{Ext\}', $f.Extension.TrimStart('.')
            $newFileName = ($newFileName -replace '\s+', ' ').Trim()
            $destFull = Join-Path $destMoviesResolved $newFileName
            $activeDestRootKey = $movieDestKey
        }
        if (-not $UseTmdb -or [string]::IsNullOrWhiteSpace($key)) {
            if ($cls.Confidence -lt 35) { $cls.Confidence = 35 }
            if ($notes -notmatch 'movie_needs_year') { $notes = if ($notes) { "$notes;tmdb_skipped" } else { 'tmdb_skipped' } }
        }
    }

    if ($null -eq $destFull) {
        $destFull = Join-Path $destReview $f.Name
        $notes = 'unresolved'
        $activeDestRootKey = 'review'
    }

    if ((Test-Path -LiteralPath $destFull) -and ($destFull -ne $f.FullName)) {
        $destFull = Join-Path $destReview ("dup_{0}_{1}" -f $stamp, $f.Name)
        $notes = 'collision_to_review'
        $activeDestRootKey = 'review'
        $cls.Confidence = [math]::Min($cls.Confidence, 20)
    }

    if ([string]::IsNullOrWhiteSpace($activeDestRootKey)) {
        if ($cls.Kind -eq 'series') { $activeDestRootKey = $seriesDestKey }
        else { $activeDestRootKey = $movieDestKey }
    }

    $rows.Add([pscustomobject]@{
            SourceFullPath          = $f.FullName
            DestFullPath            = $destFull
            Kind                    = $cls.Kind
            ContentKindGuess        = $ckKind
            ContentKindConfidence   = $ckConf
            ContentKindReason       = $ckWhy
            DestRootKey             = $activeDestRootKey
            Confidence              = $cls.Confidence
            Notes                   = $notes
            DryRun                    = [bool]$DryRun
        }) | Out-Null
}

foreach ($bdRoot in $blurayRoots) {
    $blurayDestKey = Resolve-MediaInboxDestinationKey -ContentKind 'bluray_remux' -ContentConf 100 -ByKindMap $destinationsByKindMap -MinConfidence $destinationsByKindMinConf -FallbackKey 'movies'
    if (-not $destByKey.ContainsKey($blurayDestKey)) { $blurayDestKey = 'movies' }
    $destBlurayMoviesRoot = $destByKey[$blurayDestKey]
    $bdDestRootKey = $blurayDestKey
    $folderBase = [System.IO.Path]::GetFileName($bdRoot)
    $year = Get-SortYearTokenFromText $folderBase
    $query = Remove-SortReleaseTechnicalTokens ($folderBase -replace '\b((?:19|20)\d{2})\b', ' ')
    $query = ($query -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($query)) { $query = $folderBase }
    $movieTitleRu = ConvertTo-SafeFolderName $query
    $notes = 'bluray_remux'
    $mid = $null
    if ($UseTmdb -and -not [string]::IsNullOrWhiteSpace($key) -and (Get-Command Search-TmdbMovie -ErrorAction SilentlyContinue)) {
        $mh = @(Search-TmdbMovie -Query $query -ApiKey $key -Language $tmdbLang)
        if ($mh.Count -gt 0) {
            $mid = [int]$mh[0].id
            $resolved = $null
            if (Get-Command Get-TmdbMovieResolvedRuTitle -ErrorAction SilentlyContinue) {
                $resolved = Get-TmdbMovieResolvedRuTitle -MovieId $mid -ApiKey $key
            }
            if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                $movieTitleRu = ConvertTo-SafeFolderName $resolved
            }
            else {
                $movieTitleRu = ConvertTo-SafeFolderName ([string]$mh[0].title)
            }
            $rd = [string]$mh[0].release_date
            if ([string]::IsNullOrWhiteSpace($year) -and $rd -and $rd.Length -ge 4) { $year = $rd.Substring(0, 4) }
            $notes = "bluray_remux;tmdb_movie:$mid"
        }
    }
    if ([string]::IsNullOrWhiteSpace($year)) { $year = '0000' }
    # Одна папка под релиз в «Фильмы», без «(год)» в имени каталога.
    $destFull = Join-Path $destBlurayMoviesRoot $movieTitleRu
    if ((Test-Path -LiteralPath $destFull) -and $destFull -ne $bdRoot) {
        $destFull = Join-Path $destReview ("bd_dup_{0}_{1}" -f $stamp, $folderBase)
        $notes += ';collision_folder_to_review'
        $bdDestRootKey = 'review'
    }
    $rows.Add([pscustomobject]@{
            SourceFullPath          = $bdRoot
            DestFullPath            = $destFull
            Kind                    = 'bluray_remux'
            ContentKindGuess        = 'bluray_remux'
            ContentKindConfidence   = ''
            ContentKindReason       = 'bdmv_stream'
            DestRootKey             = $bdDestRootKey
            Confidence              = if ($mid) { 72 } else { 35 }
            Notes                     = $notes
            DryRun                    = [bool]$DryRun
        }) | Out-Null
}

$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$applied = 0
$skipped = 0
if ($Apply) {
    if ($createDestRootsOnApply) {
        $seenRoots = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($rootPath in $destByKey.Values) {
            if ([string]::IsNullOrWhiteSpace($rootPath)) { continue }
            if (-not $seenRoots.Add($rootPath)) { continue }
            if (-not (Test-Path -LiteralPath $rootPath)) {
                New-Item -ItemType Directory -Path $rootPath -Force | Out-Null
            }
        }
    }
    foreach ($r in $rows) {
        if ($r.Notes -match '^skip_') { $skipped++; continue }
        if ($r.SourceFullPath -eq $r.DestFullPath) { $skipped++; continue }
        if ($r.Kind -eq 'bluray_remux') {
            $destParent = Split-Path -Parent $r.DestFullPath
            $leaf = Split-Path -Leaf $r.DestFullPath
            if (-not (Test-Path -LiteralPath $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Move-Item -LiteralPath $r.SourceFullPath -Destination $r.DestFullPath -Force
            $applied++
            continue
        }
        $destDir = Split-Path -Parent $r.DestFullPath
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Move-Item -LiteralPath $r.SourceFullPath -Destination $r.DestFullPath -Force
        $applied++
    }
}

$summary = @(
    "MediaInboxToolkit $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
    "Policy: $PolicyPath"
    "Inbox: $InboxPath"
    "Apply: $Apply  DryRun: $DryRun  UseTmdb: $UseTmdb  BlurayRoots: $($blurayRoots.Count)"
    "TmdbKindRefine: $tmdbKindRefineEnabled  CreateDestRootsOnApply: $createDestRootsOnApply"
    "Planned rows: $($rows.Count)  Moved: $applied  SkippedSamePath: $skipped"
    "CSV: $csvPath"
) -join "`r`n"
[System.IO.File]::WriteAllText($txtPath, $summary, [System.Text.UTF8Encoding]::new($true))

Write-Host $summary
