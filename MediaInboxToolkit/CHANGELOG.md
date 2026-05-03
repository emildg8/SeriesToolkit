# CHANGELOG

## 0.1.0 - 2026-05-04 12:00:00 +03:00
- Выделен отдельный продукт **MediaInboxToolkit** в каталоге репозитория `MediaInboxToolkit/` (ветка `media-inbox-toolkit`): движок `MediaInboxToolkit.Engine.ps1`, launcher `MediaInboxToolkit.ps1`, политика `sort-inbox.example.json`, план `docs/SORT-INBOX-PLAN.md`.
- **SeriesToolkit 0.1.27** зафиксирован как стабильная линия нормализации сериалов; расширенный inbox-конвейер развивается здесь и по возможности вызывает общий `Fetch-VideoMetadata.ps1` и в перспективе сценарии SeriesToolkit как модуль пост-обработки (см. README).
- Перенесена функциональность бывших версий 0.2.x (черновик в SeriesToolkit): кириллица TMDB, кэш сезонов, Blu-ray remux, плоские `Фильмы`, год из имени файла, StrictMode JSON.

### История переноса из черновика SeriesToolkit 0.2.x
- Плоская выкладка фильмов в `Фильмы\Имя.mkv`; BD — `Фильмы\Русское имя\` без папки года.
- TMDB: `Search-TmdbMovie`, `Get-TmdbTvResolvedRuDisplayName`, `Get-TmdbMovieResolvedRuTitle`, `Get-TmdbTvSeasonEpisodeTitleMap`, alternative titles для фильмов (`titles`).
