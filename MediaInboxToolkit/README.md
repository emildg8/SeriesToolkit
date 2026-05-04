# MediaInboxToolkit

Отдельный инструмент для **входной сортировки** видео (inbox → `Сериалы` / `Фильмы` / `_SortReview`), с русскими именами через TMDB, Blu-ray remux и отчётами CSV/TXT.

**SeriesToolkit** (стабильная линия **0.1.27**) остаётся продуктом нормализации уже разложенных библиотек сериалов. Этот пакет — расширяемый конвейер «до библиотеки»; дальнейшая полировка имён эпизодов — отдельным запуском SeriesToolkit по целевым папкам.

## Требования

- Репозиторий `Script_Rename_ALLVideo`: рядом с каталогом `MediaInboxToolkit` в **корне** лежит `Fetch-VideoMetadata.ps1`.
- Для TMDB: переменная окружения `TMDB_API_KEY` (или см. `Fetch-VideoMetadata.ps1`).

## Быстрый запуск

```powershell
cd <корень репозитория>\MediaInboxToolkit
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.ps1 -UseTmdb -DryRun
```

Минимальный GUI (WinForms):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-MediaInboxToolkitGui.ps1
```

Политика по умолчанию: `.\sort-inbox.example.json` (нейтральные пути). Пример разнесённой библиотеки с папками «Сериалы / Фильмы / Аниме / …»: `.\sort-inbox.library-layout-emilian.example.json` — скопируйте и замените `nasShareRoot` на свой UNC; лишние ключи в `destinations` можно удалить. При `-Apply` и `folders.createDestinationRootsOnApply: true` целевые корни из политики **создаются**, если их ещё нет.

После проверки CSV в `LOGS\`: добавьте `-Apply`.

## Оркестратор (inbox → SeriesToolkit)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit.Orchestrate.ps1 `
  -InboxPath '\\NAS\share\Video\Sort' -UseTmdb -DryRun
```

С `-Apply` и `-RunSeriesToolkitAfter` вторым шагом вызывается `SeriesToolkit\SeriesToolkit.Engine.ps1`. Корни можно задать вручную (`-SeriesToolkitRoots`) и/или взять из последнего `sort-inbox-*.csv` шага 1: `-SeriesToolkitRootsFromLastCsv` (или явный `-SeriesToolkitCsvPath`).

## Публикация в отдельный репозиторий GitHub

Из **корня монорепо** при настроенном remote `media-inbox` → `https://github.com/emildg8/MediaInboxToolkit.git`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MediaInboxToolkit\Publish-MediaInboxStandalone.ps1 -ForceWithLease
```

`-ForceWithLease` нужен, если на GitHub в `main` уже есть коммиты вне текущего subtree (типично после ручных правок).

## Связка с SeriesToolkit

**MediaInboxToolkit** раскладывает файлы по структуре; **SeriesToolkit** (стабильная линия **0.1.27**) полирует имена эпизодов уже в целевых папках. Общий модуль метаданных — `Fetch-VideoMetadata.ps1`.

## Политика (расширения)

- **`destinations`** — любые именованные корни (не только `series` / `cartoons` / `movies` / `review`): например `animeSeries`, `animeMovies`; пути относительно `nasShareRoot`.
- **`destinationsByKind`** — карта вида контента (`MediaInboxToolkit.ContentKinds.ps1`) → имя ключа из `destinations`.
- **`destinationsByKindMinConfidence`** — минимальная уверенность эвристики (0–100), иначе используется прежняя логика (`preferCartoonsSubfolder` / сериал vs фильм).
- **`safety`** — `requireSourceUnderInbox`, `skipSourceIfUnderLibrary` + `libraryRootRelatives`, чтобы не трогать файлы уже в библиотеке.
- **`tmdbKindRefinement`** — уточнение «аниме vs мульт» по TMDB (жанр Animation + регион).
- **`folders.createDestinationRootsOnApply`** — перед переносом создать все каталоги из `destinations`, если отсутствуют.
- **`classification`** — `folderSeasonContext` (папка `Season N` + файл `NN.`), `tvSpecialFilenameBoost` (Robot Chicken Star Wars Episode I→TV), `movies.allowMissingYearIfTmdbMatched`.

## Документация

- [docs/SORT-INBOX-PLAN.md](docs/SORT-INBOX-PLAN.md) — структура NAS, фазы, параметры политики.
- [docs/CLASSIFICATION-ROADMAP.md](docs/CLASSIFICATION-ROADMAP.md) — типы контента 2.x и план сигналов.
- [docs/OFFLINE-METADATA.md](docs/OFFLINE-METADATA.md) — постер и описание рядом с медиа.
- [docs/INSPIRATION-SERIESTOOLKIT.md](docs/INSPIRATION-SERIESTOOLKIT.md) — что перенимаем из SeriesToolkit.
- [docs/GUI-EXE-ROADMAP.md](docs/GUI-EXE-ROADMAP.md) — GUI и сборка EXE.

## Версии и журнал

- `version.json`, `CHANGELOG.md`, `Bump-Version.ps1` — как в SeriesToolkit.
- Ветка Git: **`media-inbox-toolkit`** (см. корневой README репозитория).

## Логи

По умолчанию `.\LOGS\` (каталог в `.gitignore`).
