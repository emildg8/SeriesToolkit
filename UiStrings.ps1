Set-StrictMode -Version Latest

function Get-ToolkitStrings {
    param([ValidateSet('ru', 'en')][string]$Lang = 'ru')

    $ru = @{
        AppTitle               = 'Cartoon Series Toolkit'
        BatchMode              = 'Массовый режим'
        ManualMode             = 'Один сериал (HTML/TMDB)'
        RootPath               = 'Папка библиотеки'
        SeriesPath             = 'Папка сериала'
        HtmlPath               = 'HTML файл (необязательно)'
        UseTmdb                = 'Использовать TMDB'
        DryRun                 = 'Только предпросмотр (DryRun)'
        Start                  = 'Запустить'
        Browse                 = 'Выбрать...'
        Done                   = 'Готово'
        DoneOpenLog            = 'Готово. Открыть лог?'
        Error                  = 'Ошибка'
        Preview                = 'Предпросмотр'
    }

    $en = @{
        AppTitle               = 'Cartoon Series Toolkit'
        BatchMode              = 'Batch Mode'
        ManualMode             = 'Single Series (HTML/TMDB)'
        RootPath               = 'Library Folder'
        SeriesPath             = 'Series Folder'
        HtmlPath               = 'HTML file (optional)'
        UseTmdb                = 'Use TMDB'
        DryRun                 = 'Preview only (DryRun)'
        Start                  = 'Run'
        Browse                 = 'Browse...'
        Done                   = 'Done'
        DoneOpenLog            = 'Done. Open log?'
        Error                  = 'Error'
        Preview                = 'Preview'
    }

    if ($Lang -eq 'en') { return $en }
    return $ru
}

