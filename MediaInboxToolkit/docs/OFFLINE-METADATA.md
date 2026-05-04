# Офлайн «о чём это» рядом с файлом

Идея: без сети видеть постер и краткое описание.

## Варианты (совместимы с плеерами)

1. **Постер** — `folder.jpg` или `poster.jpg` в папке сериала/фильма (много ТВ и Kodi/Plex понимают).
2. **NFO** — `movie.nfo` / `tvshow.nfo` / `имя эпизода.nfo` (Kodi; можно генерировать из TMDB XML export или минимальный XML вручную из API).
3. **Лёгкий sidecar JSON** (наш формат, не ломает плееры) — `MediaInboxToolkit.meta.json` рядом с папкой шоу:
   ```json
   {
     "tmdb_tv_id": 12345,
     "title_ru": "…",
     "overview_ru": "…",
     "poster_url_cached": ".\\cache\\poster.jpg"
   }
   ```
4. **Кэш картинок** — подкаталог `.mit-cache` в `LOGS` или рядом с библиотекой: скачанный `poster` по `still_path`/`poster_path` TMDB (только при `-UseTmdb` и политике `offlineArtifacts.enabled` — в планах).

Реализация поэтапно: не дублировать гигабайты; по умолчанию только JSON + один `folder.jpg` на папку.
