# Файл настроек `SeriesToolkit.settings.json`

1. Скопируйте **`SeriesToolkit.settings.example.json`** → **`SeriesToolkit.settings.json`** в той же папке, что `SeriesToolkit.ps1`.
2. Заполните поля (пустые строки можно удалить или оставить `""`).
3. **`SeriesToolkit.settings.json`** не коммитьте в git с секретами (см. `.gitignore`).

## Поля

| Поле | Описание |
|------|----------|
| `tmdb_api_key` | Ключ API themoviedb.org. Подставляется в переменную процесса `TMDB_API_KEY` на время запуска (аналог `setx`, но только для этого окна PowerShell). |
| `kinopoisk_cookie` | Одна строка **как в браузере**: заголовок **`Cookie`** из вкладки Network (см. ниже). Подходит значение с **www.kinopoisk.ru** или с **`api.plus.kinopoisk.ru`** (например POST `graphql?operationName=...`) — это те же cookies сеанса. Уменьшает капчу/антибот при парсинге HTML Кинопоиска. |
| `episode_filename_format` | Шаблон **без расширения** файла эпизода. Плейсхолдеры: `{Series}` (имя папки сериала, очищенное), `{Code}` (например `S01E05`), `{Title}` (название эпизода), `{Season}`, `{Episode}` (числа). |
| `season_folder_format` | Имя папки сезона. Плейсхолдер: `{Season}` (номер сезона). По умолчанию `Сезон {Season}`. **Важно:** распознавание уже существующих папок заточено под `Сезон N` / `Season N` и др. (см. движок). Сильно экзотический шаблон может потребовать доработки правил. |
| `aggressive_second_pass_kinopoisk_min_score` | Порог совпадения Кинопоиска во **втором** проходе (число, по умолчанию `85`). |
| `execution_profile` | Профиль выполнения: `Fast`, `Balanced`, `Full`. `Fast` — максимум скорости (без второго прохода), `Balanced` — компромисс, `Full` — максимум качества (полный второй проход). |
| `metadata_second_pass_min_coverage_percent` | Порог покрытия (0-100) для решения о втором проходе в `Balanced`: если доля файлов с валидными заголовками >= порога, второй проход пропускается. |
| `metadata_cache_ttl_hours` | TTL кэша метаданных в часах (по умолчанию 168 = 7 дней). |
| `metadata_cache_force_refresh` | Если `true`, игнорировать кэш и всегда обновлять из сети. |
| `metadata_request_timeout_sec` | Базовый таймаут сетевых запросов метаданных (сек). |
| `metadata_enable_stage_timing` | Если `true`, писать тайминги этапов (`wiki/tmdb/kp/ddg/merge/plan/apply`) в лог. |
| `metadata_slow_series_top_n` | Сколько самых медленных сериалов показать в итоговой сводке. |
| `placeholder_repair_allow_latin_titles` | Если `true`, для заглушек «Серия N» допускаются **латинские** названия из TMDB, когда кириллицы нет. |
| `create_missing_season_folders` | Если `true`, для сезонов, есть в метаданных, но нет папки на диске — создаётся заготовка (маркер + подсказка). |
| `write_episode_index_csv` | Если `true`, в корень сериала пишется **`SeriesToolkit-episode-index.csv`** (список эпизодов из слитых источников). |

## Как взять cookie Кинопоиска (Chrome)

1. Откройте [kinopoisk.ru](https://www.kinopoisk.ru) и при необходимости войдите в аккаунт.
2. **F12** → вкладка **Сеть (Network)**.
3. Обновите страницу (**F5**) или выполните действие на сайте, чтобы пошли запросы.
4. Выберите любой подходящий запрос:
   - документ или XHR к **`www.kinopoisk.ru`**, **или**
   - **POST** к **`https://api.plus.kinopoisk.ru/graphql?...`** (как `registerSimpleActionWithPixel` и другие) — у них в **Request Headers** тот же заголовок **`cookie:`**, его и используйте.
5. **Заголовки (Headers)** → **Заголовки запроса (Request Headers)** → строка **`cookie:`**.
6. Скопируйте **только значение** (всю длинную строку после `cookie: `), одной линией.
7. Вставьте в **`SeriesToolkit.settings.json`** в поле **`kinopoisk_cookie`** (удобнее через редактор JSON; строка в двойных кавычках).

Альтернатива: **Приложение (Application)** → **Cookies** → `https://www.kinopoisk.ru` — вручную сложнее, чем один **Cookie** из Network.

### Безопасность

Строка **Cookie** даёт доступ к вашему сеансу Яндекса/Кинопоиска. **Не публикуйте** её в чатах, issue и скриншотах. Если кто-то мог её увидеть — смените пароль Яндекса или завершите сеансы в настройках аккаунта. Со временем cookie протухает — при ошибках/капче обновите значение из браузера.

## Матрица источников по профилям

- `Fast`: TMDB-only (если есть API), иначе Wiki-only.
- `Balanced`: TMDB + Wiki + КП (если есть API), иначе Wiki + КП.
- `Full`: TMDB + Wiki + КП + DDG + Yandex + Google (если есть API), иначе Wiki + КП + DDG + Yandex + Google.
