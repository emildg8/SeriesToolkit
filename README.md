# SeriesToolkit

`SeriesToolkit` — переносимый набор скриптов для нормализации библиотек **сериалов и мультсериалов**.

Инструмент работает как в массовом режиме (вся библиотека), так и в ручном режиме (один сериал), приводит структуру сезонов к единому виду, переименовывает эпизоды по шаблону и сохраняет подробные логи.

## Что делает toolkit

- Нормализует папки сезонов в формат `Сезон N`.
- Перемещает файлы в правильные папки сезонов.
- Переименовывает эпизоды в формат:
  - `Название сериала - S01E01 - Название эпизода`
- Поддерживает источники **русскоязычных** названий эпизодов (в имена файлов попадают только строки **с кириллицей**):
  - локальный HTML (ручной режим),
  - ru.wikipedia (списки эпизодов и расширение через `Fetch-VideoMetadata.ps1`),
  - **Кинопоиск** (поиск `kp_query`, сверка заголовка карточки с именем папки и с выбранным по TMDB сериалом, затем страница эпизодов),
  - TMDB API `ru-RU` (подмешивается в слияние; голые английские подписи в переименование не идут).
- Применяет безопасное планирование операций:
  - предотвращение коллизий имён,
  - аккуратная уникализация (`[1]`, `[2]`) при необходимости.
- Удаляет пустые папки после перемещений.
- Пишет логи:
  - детальный CSV по каждому действию,
  - итоговый TXT-отчёт.
- Автоматизирует релизный цикл:
  - автоинкремент версии при каждом запуске `SeriesToolkit.ps1`,
  - автоснимок предыдущей версии в `OLD`,
  - авто-синхронизация с GitHub через `Sync-GitHub.ps1` (если настроен `gh`).

## Режимы запуска

- **Batch** — обработка всех сериалов в корне библиотеки.
- **Manual** — обработка одного сериала (например, с локальным HTML-файлом названий).

## CLI запуск

### 1) Массовый dry-run (без изменений)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SeriesToolkit.ps1 -Mode Batch -RootPath "\\server\share\Сериалы" -DryRun
```

### 2) Массовый apply (боевой запуск)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SeriesToolkit.ps1 -Mode Batch -RootPath "\\server\share\Сериалы" -Apply
```

### 3) Ручной режим для одного сериала

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SeriesToolkit.ps1 -Mode Manual -SeriesPath "\\server\share\Сериалы\Название сериала" -HtmlPath "D:\episode-list.html" -Apply
```

## GUI запуск

Минималистичный GUI (RU/EN):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-SeriesToolkitGui.ps1
```

## TMDB

Для получения названий эпизодов с TMDB:

1. Получите API key в TMDB.
2. Запишите ключ в переменную окружения пользователя:

```powershell
setx TMDB_API_KEY "ВАШ_КЛЮЧ"
```

Если TMDB недоступен из сети, toolkit опирается на Википедию и Кинопоиск (при отсутствии капчи на стороне KP).

### Кинопоиск и антибот

Скрипт не обходит юридически значимую защиту (капчу нужно пройти в браузере). Для снижения ложных срабатываний:

1. По умолчанию для HTML Кинопоиска используется **`curl.exe`** (Windows 10+), если не задано `SERIESTOOLKIT_KP_USE_CURL=0`.
2. После входа на kinopoisk.ru в браузере можно скопировать заголовок **`Cookie`** и записать в переменную пользователя:
   - `setx KINOPOISK_COOKIE "session=...; ..."`  
   или `SERIESTOOLKIT_KINOPOISK_COOKIE`.
3. Опционально: `setx SERIESTOOLKIT_KP_DELAY_MS 800` — пауза перед запросом (мс).
4. Если EXE/скрипты лежат нестандартно: `setx SERIESTOOLKIT_ROOT "D:\путь\к\SeriesToolkit"`.

### Модуль метаданных

Движок подключает родительский **`Fetch-VideoMetadata.ps1`** (на уровень выше каталога `SeriesToolkit` или рядом с ним). Без этого файла сетевые источники (Википедия, Кинопоиск, TMDB) не загружаются.

## Логи

По умолчанию логи сохраняются в `.\LOGS`:

- `series-toolkit-vX.Y.Z-*.csv` — подробный лог действий (в имени есть версия, дата, время),
- `series-toolkit-*.txt` — краткий итог.

Старые логи из `logs` перенесены в `LOGS` для единого хранения.

## OLD (архив версий)

При каждом запуске `SeriesToolkit.ps1` создаётся snapshot предыдущей версии в `OLD`:

- формат: `OLD/SeriesToolkit_v<old_version>_<yyyyMMdd-HHmmss>`
- содержит ключевые скрипты, `README`, `CHANGELOG`, `version.json`
- позволяет откатиться к стабильной версии вручную.

## Обратная совместимость

Точки входа:

- `SeriesToolkit.ps1`
- `Start-SeriesToolkitGui.ps1`

## EXE GUI

Для сборки исполняемого файла GUI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build-SeriesToolkitExe.ps1
```

Результат: `SeriesToolkit.GUI.exe` в корне проекта.

Рядом с `.exe` должны лежать те же файлы, что и при запуске `.ps1` (`SeriesToolkit.ps1`, `Start-SeriesToolkitGui.Engine.ps1`, `UiStrings.ps1`, `SeriesToolkit.Engine.ps1`, `Fetch-VideoMetadata.ps1` выше по дереву или рядом). Сборка: **`Build-SeriesToolkitExe.ps1` компилирует `Start-SeriesToolkitGui.Engine.ps1`** в `SeriesToolkit.GUI.exe`. После обновления скриптов пересоберите EXE (закройте старый EXE, если Windows блокирует перезапись).

## Версионирование

- Версия хранится в `version.json`.
- Инкремент патча при каждом запуске `SeriesToolkit.ps1` (см. `Bump-Version.ps1`): `0.0.9 -> 0.1.0` при переполнении разрядов по правилам скрипта.
- Новые записи в `CHANGELOG.md` **всегда сверху** (см. `.cursor/rules/series-toolkit-versioning.mdc`).

## GitHub: публичный и второй remote

- Основная публикация: `emildg8/SeriesToolkit` (скрипт `Sync-GitHub.ps1` копирует проект в `.publish/SeriesToolkit` и пушит в `origin`).
- Для **второго** репозитория (например закрытого) передайте при вызове:

```powershell
.\Sync-GitHub.ps1 -SecondaryRemoteName private -SecondaryRemoteUrl "https://github.com/ORG/PRIVATE.git"
```

(нужен `gh`/git и права push на оба remote.)

## Скачивание старых версий

Чтобы всегда можно было откатиться к рабочей версии:

- в GitHub созданы теги и релизы (`v0.0.1`, `v0.0.3`, `v0.0.4`);
- у каждого релиза есть свой ZIP-архив исходников в состоянии этой версии;
- внутри архива находятся соответствующие версии `README.md` и `CHANGELOG.md`.

Релизы: [https://github.com/emildg8/SeriesToolkit/releases](https://github.com/emildg8/SeriesToolkit/releases)
