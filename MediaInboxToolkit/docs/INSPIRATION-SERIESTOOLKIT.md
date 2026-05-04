# Что перенимаем из SeriesToolkit

| Идея | Как использовать в MediaInboxToolkit |
|------|--------------------------------------|
| DryRun → Apply | Уже: CSV-план, без изменений до `-Apply` |
| Порог confidence / review | Дальше: низкая уверенность → `_SortReview` + отдельный `review-queue.csv` |
| Кэш метаданных / retry | Общий `Fetch-VideoMetadata.ps1`; позже локальный кэш TMDB-ответов в `LOGS` |
| `series-aliases` | Перенос в политику `aliases` для плохих имён релизов |
| Профили Fast/Balanced/Full | Упростить до «только TMDB» / «TMDB+эвристика пути» для скорости |
| GUI + сборка EXE | Тот же подход: `Start-*Gui.Engine.ps1` + ps2exe / WinForms; минималистичный UI — отдельная фаза |
| Логи CSV/TXT | Уже; расширить колонками `ContentKind*` |
