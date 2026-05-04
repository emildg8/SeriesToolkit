#requires -Version 5.1
# Классификация видео для MediaInboxToolkit (расширяемый модуль).
# Идентификаторы 2.x — соответствуют ТЗ пользователя; эвристики дорабатываются поэтапно.

Set-StrictMode -Version Latest

# Категории контента (строковые константы для политики и логов).
$script:MediaInboxKind = @{
    Unknown                   = 'unknown'
    Movie                     = 'movie'
    SeriesEpisode             = 'series_episode'
    SeriesRelatedMovie        = 'series_related_movie'
    CartoonMovie              = 'cartoon_movie'
    CartoonSeriesEpisode      = 'cartoon_series_episode'
    CartoonSeriesRelatedMovie = 'cartoon_series_related_movie'
    AnimeMovie                = 'anime_movie'
    AnimeSeriesEpisode        = 'anime_series_episode'
    AnimeSeriesRelated        = 'anime_series_related'
    AnimeOva                  = 'anime_ova'
    BlurayRemux               = 'bluray_remux'
}

function Get-MediaInboxKindConstants {
    return $script:MediaInboxKind.Clone()
}

<#
.SYNOPSIS
  Грубая классификация одного видеофайла (v0: серия / фильм / неизвестно; далее — TMDB genre, пути, ключевые слова).
#>
function Get-MediaInboxVideoKindGuess {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,
        [string]$RelativePathFromInbox = ''
    )
    $name = $File.Name
    $rel = if ([string]::IsNullOrWhiteSpace($RelativePathFromInbox)) { $File.FullName } else { $RelativePathFromInbox }
    $lower = $rel.ToLowerInvariant()
    # BD внутри релиза — отдельная ветка движка; здесь только «обычный» файл.
    if ($lower -match '\banime\b|аниме') {
        if ($name -match '(?i)\bS\d{1,2}\s*E\d{1,3}\b|\d{1,2}x\d{1,3}') {
            return @{ Kind = $script:MediaInboxKind.AnimeSeriesEpisode; Confidence = 45; Reason = 'path_or_name_anime+episode_pattern' }
        }
        if ($name -match '(?i)\bova\b|\bспешл\b') {
            return @{ Kind = $script:MediaInboxKind.AnimeOva; Confidence = 40; Reason = 'name_ova' }
        }
        return @{ Kind = $script:MediaInboxKind.AnimeMovie; Confidence = 35; Reason = 'anime_hint_no_episode_code' }
    }
    if ($lower -match 'мульт|cartoon|disney|pixar') {
        if ($name -match '(?i)\bS\d{1,2}\s*E\d{1,3}\b|\d{1,2}x\d{1,3}') {
            return @{ Kind = $script:MediaInboxKind.CartoonSeriesEpisode; Confidence = 45; Reason = 'cartoon_context+episode' }
        }
        return @{ Kind = $script:MediaInboxKind.CartoonMovie; Confidence = 35; Reason = 'cartoon_context' }
    }
    if ($name -match '(?i)\bS\d{1,2}\s*E\d{1,3}\b|\b\d{1,2}x\d{1,3}\b') {
        return @{ Kind = $script:MediaInboxKind.SeriesEpisode; Confidence = 60; Reason = 'episode_code_in_filename' }
    }
    if ($name -match '(?i)\b(pilot|featurette|special)\b') {
        return @{ Kind = $script:MediaInboxKind.SeriesRelatedMovie; Confidence = 30; Reason = 'keyword_special' }
    }
    return @{ Kind = $script:MediaInboxKind.Movie; Confidence = 40; Reason = 'default_single_file' }
}
