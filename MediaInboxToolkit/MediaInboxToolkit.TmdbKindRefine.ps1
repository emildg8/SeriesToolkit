#requires -Version 5.1
# Уточнение вида контента по жанрам/странам TMDB (после эвристик ContentKinds).

Set-StrictMode -Version Latest

function Test-MediaInboxTmdbAnimeProneOrigin {
    param([string[]]$CountryCodes)
    if (-not $CountryCodes) { return $false }
    foreach ($c in $CountryCodes) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $u = $c.Trim().ToUpperInvariant()
        if ($u -in @('JP', 'KR', 'CN', 'TW')) { return $true }
    }
    return $false
}

function Resolve-MediaInboxContentKindFromTmdbTv {
    param(
        [object]$TvDetails,
        [string]$HeuristicKind,
        [int]$HeuristicConfidence
    )
    if (-not $TvDetails) { return $null }
    if (-not (Get-Command Get-TmdbGenreIdsFromMediaObject -ErrorAction SilentlyContinue)) { return $null }
    $gids = @(Get-TmdbGenreIdsFromMediaObject $TvDetails)
    if ($gids -notcontains 16) { return $null }
    $orig = @(Get-TmdbTvOriginCountryCodes $TvDetails)
    $animeOrigin = Test-MediaInboxTmdbAnimeProneOrigin $orig
    $baseConf = if ($HeuristicConfidence -gt 0) { $HeuristicConfidence } else { 50 }
    if ($animeOrigin) {
        return @{
            Kind       = $script:MediaInboxKind.AnimeSeriesEpisode
            Confidence = [Math]::Max(78, $baseConf)
            Reason     = 'tmdb_tv_animation+origin_jp_kr_cn_tw'
        }
    }
    return @{
        Kind       = $script:MediaInboxKind.CartoonSeriesEpisode
        Confidence = [Math]::Max(72, $baseConf)
        Reason     = 'tmdb_tv_animation_western_origin'
    }
}

function Resolve-MediaInboxContentKindFromTmdbMovie {
    param(
        [object]$MovieDetails,
        [string]$HeuristicKind,
        [int]$HeuristicConfidence
    )
    if (-not $MovieDetails) { return $null }
    if (-not (Get-Command Get-TmdbGenreIdsFromMediaObject -ErrorAction SilentlyContinue)) { return $null }
    $gids = @(Get-TmdbGenreIdsFromMediaObject $MovieDetails)
    if ($gids -notcontains 16) { return $null }
    $orig = @(Get-TmdbMovieOriginCountryCodes $MovieDetails)
    $animeOrigin = Test-MediaInboxTmdbAnimeProneOrigin $orig
    $baseConf = if ($HeuristicConfidence -gt 0) { $HeuristicConfidence } else { 45 }
    if ($animeOrigin) {
        return @{
            Kind       = $script:MediaInboxKind.AnimeMovie
            Confidence = [Math]::Max(78, $baseConf)
            Reason     = 'tmdb_movie_animation+origin_jp_kr_cn_tw'
        }
    }
    return @{
        Kind       = $script:MediaInboxKind.CartoonMovie
        Confidence = [Math]::Max(72, $baseConf)
        Reason     = 'tmdb_movie_animation_western_origin'
    }
}
