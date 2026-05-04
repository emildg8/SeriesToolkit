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

function Test-MediaInboxPathContainsCyrillicToken {
    param(
        [string]$HaystackLower,
        [int[]]$CodepointsUtf16
    )
    if ([string]::IsNullOrWhiteSpace($HaystackLower) -or -not $CodepointsUtf16) { return $false }
    $tok = -join ($CodepointsUtf16 | ForEach-Object { [char]$_ })
    return $HaystackLower.Contains($tok)
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

    # "аниме" UTF-16: U+0430 U+043D U+0438 U+043C U+0435
    $hasAnimeHint = ($lower -match '(?i)\banime\b') -or (Test-MediaInboxPathContainsCyrillicToken $lower @(0x0430, 0x043D, 0x0438, 0x043C, 0x0435))
    if ($hasAnimeHint) {
        if ($name -match '(?i)\bS\d{1,2}\s*E\d{1,3}\b|\d{1,2}x\d{1,3}') {
            return @{ Kind = $script:MediaInboxKind.AnimeSeriesEpisode; Confidence = 45; Reason = 'path_or_name_anime+episode_pattern' }
        }
        if ($name -match '(?i)\bova\b') { return @{ Kind = $script:MediaInboxKind.AnimeOva; Confidence = 40; Reason = 'name_ova' } }
        # "спешл"
        if (Test-MediaInboxPathContainsCyrillicToken $name.ToLowerInvariant() @(0x0441, 0x043F, 0x0435, 0x0448, 0x043B)) {
            return @{ Kind = $script:MediaInboxKind.AnimeOva; Confidence = 40; Reason = 'name_special_ru' }
        }
        return @{ Kind = $script:MediaInboxKind.AnimeMovie; Confidence = 35; Reason = 'anime_hint_no_episode_code' }
    }

    # "мульт" как подсказка мультов
    $hasCartoonHint = ($lower -match '(?i)cartoon|disney|pixar') -or (Test-MediaInboxPathContainsCyrillicToken $lower @(0x043C, 0x0443, 0x043B, 0x044C, 0x0442))
    if ($hasCartoonHint) {
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
