# CartoonSeriesToolkit

Отдельный переносимый toolkit для нормализации библиотеки мультсериалов.

## Возможности
- Массовый режим по библиотеке.
- Ручной режим для одного сериала (HTML + TMDB).
- Нормализация папок сезонов в `Сезон N`.
- Переименование серий в `Название сериала - SNNENN - Название серии`.
- Подробные логи CSV/TXT.
- GUI с RU/EN локализацией.

## Быстрый запуск

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CartoonSeriesToolkit.ps1 -Mode Batch -DryRun
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-CartoonSeriesToolkitGui.ps1
```

## Версии
- Текущая версия хранится в `version.json`.
- Инкремент SemVer: `0.0.9 -> 0.1.0`, `0.9.9 -> 1.0.0`.
- Новые записи в `CHANGELOG.md` всегда добавляются сверху.
