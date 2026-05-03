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

Политика по умолчанию: `.\sort-inbox.example.json`. Свой inbox: `-InboxPath '\\NAS\share\Video\Sort'`.

После проверки CSV в `LOGS\`: добавьте `-Apply`.

## Связка с SeriesToolkit (дорожная карта)

Идея: **MediaInboxToolkit** раскладывает файлы по структуре; **SeriesToolkit.Engine.ps1** можно вызывать вторым шагом с `-RootPath` на папку нового сериала (тот же `Fetch-VideoMetadata.ps1` уже подключён в обоих). Явная оркестрация (один master-скрипт) — в планах; сейчас два независимых запуска.

## Документация

- [docs/SORT-INBOX-PLAN.md](docs/SORT-INBOX-PLAN.md) — структура NAS, фазы, параметры политики.

## Версии и журнал

- `version.json`, `CHANGELOG.md`, `Bump-Version.ps1` — как в SeriesToolkit.
- Ветка Git: **`media-inbox-toolkit`** (см. корневой README репозитория).

## Логи

По умолчанию `.\LOGS\` (каталог в `.gitignore`).
