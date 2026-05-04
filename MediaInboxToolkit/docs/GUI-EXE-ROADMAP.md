# GUI и EXE (минимализм «в духе Apple»)

Фазы:

1. **MVP** — `Start-MediaInboxToolkitGui.ps1` + `Start-MediaInboxToolkitGui.Engine.ps1`: inbox, политика, UseTmdb / DryRun / Apply, вывод stdout/stderr в текстовое поле.
2. **WinForms / WPF** — светлая тема, много воздуха, системный шрифт Segoe UI, без лишних панелей.
3. **Сборка** — `Build-MediaInboxToolkitExe.ps1` (аналог SeriesToolkit): упаковка `MediaInboxToolkit.ps1` + Engine + ContentKinds + пример JSON.
4. **Иконка** — общая с SeriesToolkit или отдельная линия MIT.

Сейчас: только CLI; этот файл — контракт на дизайн.
