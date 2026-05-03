# План: входная сортировка видео (NAS `emildg8`)

Документ фиксирует **целевую раскладку** под вашу схему шаров и пошаговый план автоматизации. Реализация первой фазы — скрипт `MediaInboxToolkit.ps1` и пример политики `sort-inbox.example.json`.

## Как у вас устроено по путям

| Роль | UNC-путь |
|------|-----------|
| Общий корень шары | `\\Emilian_TNAS\emildg8` |
| Зона видео | `\\Emilian_TNAS\emildg8\Video` |

Скрипты нормализации сериалов уже опираются на подпапки внутри `Video` (например `Сериалы`, `Мультсериалы`) — см. `Normalize-CartoonSeriesLibrary.md`.

## Примерная целевая структура (шаблон)

Ниже — **рекомендуемая** схема в духе существующих шаблонов (`Сезон N`, раздельные ветки для сериалов и мультов). Имена подпапок можно подстроить в JSON-политике без правки кода.

```text
\\Emilian_TNAS\emildg8\
  Video\
    Sort\                    ← вход: «сырой» материал перед разбором
    _SortReview\             ← спорные файлы (нет SxxEyy, нет уверенного TMDB и т.п.)
    Сериалы\
      <Название сериала>\
        Сезон 1\
          <Сериал> - S01E01 - <Название серии>.mkv
    Мультсериалы\
      ... (та же логика сезонов/имён, как в Normalize-CartoonSeriesLibrary)
    Фильмы\
      <Русское название>.mkv
      <Русское название BD-remux>\   ← целиком папка релиза с BDMV, без подпапки «(год)»
        BDMV\ ...
```

Опционально позже (не обязательно на первом шаге):

```text
  Music\          ← отдельный конвейер
  Photos\         ← отдельный конвейер
  Quarantine\     ← всё подозрительное/не-видео
```

## План действий

### Фаза 1 (сделано в репозитории)

1. Пример политики `sort-inbox.example.json` — корень шары, относительные пути под `Video`, шаблоны папок.
2. Скрипт `MediaInboxToolkit.ps1`:
   - рекурсивное сканирование inbox;
   - эвристика **сериал** (наличие `SxxEyy` / `NNxMM` в имени) vs **фильм**;
   - **кириллические имена**: при `-UseTmdb` и ключе API — поиск сериала/фильма на TMDB в `ru-RU`, уточнение через `tv/{id}` и **alternative_titles** с регионом `RU`; названия эпизодов — из **сезона** TMDB (один запрос на сезон, кэш), без «мусора» из имени файла после кода серии;
   - **Blu-ray remux**: папки с `BDMV/STREAM/*.m2ts` переносятся целиком в `Фильмы\<русское название>\` по TMDB (без подпапки года);
   - вспомогательные функции в `Fetch-VideoMetadata.ps1`: `Get-TmdbTvResolvedRuDisplayName`, `Get-TmdbMovieResolvedRuTitle`, `Get-TmdbTvSeasonEpisodeTitleMap` и др.;
   - отчёт CSV + TXT, по умолчанию **DryRun**; `-Apply` — перенос с созданием папок;
   - неоднозначные случаи — в `_SortReview` (или путь из политики).

### Фаза 2

- Учёт `series-aliases` / локальных overrides для «плохих» имён.
- Связка с основным движком SeriesToolkit для финальной нормализации эпизодов после раскладки по сериалам.

### Фаза 3

- Музыка/фото: отдельные политики и расширения MIME, без смешения с видео-пайплайном.

## Запуск

```powershell
cd D:\Dev\Script_Rename_ALLVideo\SeriesToolkit
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.ps1 `
  -PolicyPath .\sort-inbox.example.json `
  -DryRun

# после проверки CSV:
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.ps1 `
  -PolicyPath .\sort-inbox.example.json `
  -Apply `
  -UseTmdb
```

Переопределить inbox без редактирования JSON: параметр `-InboxPath` (абсолютный UNC или локальный путь).
