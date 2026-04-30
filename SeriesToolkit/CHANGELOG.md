# CHANGELOG

## 0.1.10 - 2026-04-30 12:42:00 +03:00
- Приватность: дефолтные пути в launcher/engine/GUI заменены на нейтральные (`\\MEDIA-SERVER\Video\Cartoons`, `\\MEDIA-SERVER\Video\Series`).
- Публикация: `Sync-GitHub.ps1` переведён на строгий allowlist файлов релиза, чтобы в ZIP не попадали legacy-скрипты и временные артефакты (`*.bak`, `*.new.exe`, `_make-icon.ps1`, старые GUI-скрипты).
- Релизный pipeline: повторно синхронизирован GitHub с проверкой состава ZIP-архива перед публикацией.

## 0.1.9 - 2026-04-30 12:28:00 +03:00
- GitHub releases: удалены ZIP-ассеты старых релизов, чтобы в публичных архивах не оставалось ранее опубликованных лишних скриншотов.
- Документация: подтверждён единый актуальный GUI-скрин `docs/images/01-gui-main.png` без второго изображения.

## 0.1.8 - 2026-04-30 12:20:00 +03:00
- GUI-метрики: добавлены явные поля `Старт`, `Прошло`, `ETA` и общая шкала прогресса по библиотеке.
- GUI-управление: добавлена кнопка `Пропуск` текущего сериала (без остановки всего прогона), поддержка сигнала в `SeriesToolkit.Engine.ps1`.
- Stop-логика: при ручной остановке выводится статус «прервано пользователем» с итогом `выполнено/осталось`, вместо общей ошибки.
- Окно GUI: включены стандартные кнопки окна (`свернуть/развернуть`) и явная установка иконки формы из `assets/SeriesToolkit.icon.ico`.
- Документация: обновлён актуальный скриншот GUI (`docs/images/01-gui-main.png`) с нейтральным путём.

## 0.1.7 - 2026-04-30 11:30:00 +03:00
- GUI-стабильность: убраны падения/зависания при чтении прогресса; переход на tail-чтение `gui-progress-*.log` вместо нестабильных pipe-callback в EXE.
- GUI-прогресс: добавлены `LibraryProgress` и `SeriesProgress` (проценты и этапы), а также статус «последняя активность Nс назад».
- GUI-управление: рабочие кнопки `Пауза/Продолжить` и `Стоп`; закрытие окна блокируется во время выполнения.
- Диагностика GUI: добавлен `gui-session-*.log` с причинами закрытия/исключениями.
- EXE-сборка: добавлена иконка приложения (`assets/SeriesToolkit.icon.ico`) и авто-ротация `SeriesToolkit.GUI.exe -> .bak`.
- Публикация: `Sync-GitHub.ps1` теперь автоматически создаёт/обновляет GitHub Release `vX.Y.Z` и прикрепляет ZIP-архив версии.
- Документация: в `README.md` и `docs/SCREENSHOTS-RU.md` обновлён реальный скриншот GUI (`docs/images/01-gui-main.png`).
## 0.1.2 - 2026-04-30 04:55:11 +03:00
- **`SeriesToolkit.settings.README.md`** и **README**: явно указано, что заголовок **`Cookie`** можно копировать с запросов к **`api.plus.kinopoisk.ru/graphql`** (тот же сеанс, что и у `www.kinopoisk.ru`).
- Раздел **безопасности**: cookie = доступ к аккаунту; не публиковать; при утечке — смена пароля / завершение сеансов; периодическое обновление строки.
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.1.1_20260430-045511.

## 0.1.1 - 2026-04-30 04:53:24 +03:00
- **`Set-ExecutionPolicy -Scope Process Bypass`** в `Start-SeriesToolkitGui.Engine.ps1`, `SeriesToolkit.Engine.ps1`, `SeriesToolkit.ps1` — устраняет ошибку загрузки `UiStrings.ps1` при политике `Restricted`.
- **`SeriesToolkit.settings.example.json`** + **`SeriesToolkit.settings.README.md`**: опциональный **`SeriesToolkit.settings.json`** — `tmdb_api_key`, `kinopoisk_cookie`, `episode_filename_format`, `season_folder_format`; секреты в `.gitignore`.
- Движок: **`Format-EpisodeFileBase`**, чтение настроек до инициализации TMDB.
- **`Sync-GitHub.ps1`**: gist включает файлы настроек-примера.
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.1.0_20260430-045324.

## 0.1.0 - 2026-04-30 04:43:23 +03:00
- **Кинопоиск (обход типовых блокировок к PowerShell):** по умолчанию запросы через `curl.exe` (если есть), заголовки как у браузера, Referer, пауза; опционально cookie из `KINOPOISK_COOKIE` / `SERIESTOOLKIT_KINOPOISK_COOKIE`; `SERIESTOOLKIT_KP_USE_CURL=0` — только `Invoke-WebRequest`; `SERIESTOOLKIT_KP_DELAY_MS` — задержка между запросами; редирект `kp_query` через `curl -I` с разбором `Location`.
- **Веб-поиск эпизодов:** если прямые запросы к API Википедии не дали список — запросы к `html.duckduckgo.com` (`site:ru.wikipedia.org …`) и разбор страниц списков эпизодов.
- **GUI / EXE:** `Build-SeriesToolkitExe.ps1` собирает **`Start-SeriesToolkitGui.Engine.ps1`** (один процесс, без `&` второго скрипта); резолв каталога: `SERIESTOOLKIT_ROOT`, `PSCommandLine` для `.exe`, проверки путей перед запуском `powershell -File`; открытие `LOGS` без `null` в `LiteralPath`.
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.9_20260430-044323.

## 0.0.9 - 2026-04-30 04:32:15 +03:00
- **`Fetch-VideoMetadata.ps1`**: `Get-EpisodesFromKinopoiskVerifiedForSeries` — редирект `index.php?kp_query=`, разбор заголовка карточки, порог совпадения с именем папки и (если есть) с названиями выбранного в TMDB сериала; затем парсинг `/film/{id}/episodes/`.
- **`SeriesToolkit.Engine.ps1`**: слияние списков TMDB + ru.wikipedia + Кинопоиск; убран TVMaze из цепочки; в имена файлов попадают **только** заголовки с кириллицей (без англ. fallback).
- **GUI**: `Start-SeriesToolkitGui.ps1` / `Start-SeriesToolkitGui.Engine.ps1` — параметр `-ToolkitRoot` и определение каталога через `MainModule.FileName`, чтобы **SeriesToolkit.GUI.exe** (ps2exe) находил `UiStrings.ps1` и `SeriesToolkit.ps1` рядом с собой.
- Добавлено правило Cursor: новая версия и запись в `CHANGELOG.md` сверху при каждом запросе по проекту (см. `.cursor/rules/series-toolkit-versioning.mdc`).
- **`Sync-GitHub.ps1`**: опциональный второй remote (`-SecondaryRemoteName` / `-SecondaryRemoteUrl`); копирование `Fetch-VideoMetadata.ps1` из родителя `SeriesToolkit` в publish-репозиторий для самодостаточного ZIP.
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.8_20260430-043215.

## 0.0.8 - 2026-04-30 04:30:00 +03:00
- Единая карта названий эпизодов: `Get-EpisodesFromTmdbTvSeries` + `Merge-EpisodeTitlesPreferRu` с Википедией, `Expand-EpisodeListWithRussianWikipedia`, при списке из «плейсхолдеров» — дополнительно TVMaze.
- После основного плана — фаза `repair-placeholder-title` (замена `- SxxEyy - Серия N` на осмысленное имя из карты, в т.ч. англ. TMDB, если нет кириллицы).
- В лог добавляется `WARN` с действием `unresolved-placeholder`, если файл всё ещё с заглушкой.
- При старте движка вызывается `Initialize-WebClient` из `Fetch-VideoMetadata.ps1`.

## 0.0.7 - 2026-04-29 18:30:41 +03:00
- Автоинкремент версии при запуске SeriesToolkit (Batch).
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.6_20260429-183041.

## 0.0.6 - 2026-04-29 18:26:33 +03:00
- Автоинкремент версии при запуске SeriesToolkit (Batch).
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.5_20260429-182633.

## 0.0.5 - 2026-04-29 18:23:35 +03:00
- Автоинкремент версии при запуске SeriesToolkit (Batch).
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.4_20260429-182335.

## 0.0.4 - 2026-04-29 17:29:58 +03:00
- Автоинкремент версии при запуске SeriesToolkit (Batch).
- Автоматически создан snapshot предыдущей версии: OLD/SeriesToolkit_v0.0.3_20260429-172958.

## 0.0.3 - 2026-04-29 16:55:40 +03:00
- Доработан движок распознавания эпизодов: добавлены паттерны `ACV`, `sezon/seriya`, универсальные числовые fallback-паттерны.
- Добавлена более безопасная классификация доп.видео (theme/opening/trailer/movie/credits), чтобы не создавать ложных переименований.
- Статусы для неошибочных конфликтов вида «целевая папка уже существует» переведены в `INFO`.
- Выполнен повторный массовый прогон по библиотеке `\\Emilian_TNAS\\emildg8\\Video\\Мультсериалы` с итогом `Warnings: 0`, `Errors: 0`.

## 0.0.2 - 2026-04-29 16:14:54 +03:00
- Добавлен скрипт `Bump-Version.ps1` для инкремента версий по правилам проекта.
- Исправлена инициализация пути `version.json` для совместимости с PowerShell 5.1.
- Выполнена проверка smoke-run нового движка `SeriesToolkit.Engine.ps1`.

## 0.0.1 - 2026-04-29 16:00:00 +03:00
- Создан отдельный пакет `SeriesToolkit` внутри проекта.
- Добавлен базовый движок нормализации мультсериалов с режимами `DryRun` и `Apply`.
- Добавлены правила автодетекта сезонов/эпизодов и безопасная стратегия разрешения коллизий имён.
- Добавлен ручной режим для одного сериала с подстановкой эпизодов из HTML и опциональным TMDB.
- Добавлен минималистичный GUI в стиле Apple-like с RU/EN локализацией.
- Добавлены документы по запуску, структуре версий и политике инкремента.
