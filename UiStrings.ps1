Set-StrictMode -Version Latest

function Get-ToolkitStrings {
    param([ValidateSet('ru', 'en')][string]$Lang = 'ru')

    $ru = @{
        AppTitle               = 'SeriesToolkit'
        BatchMode              = 'Массовый режим'
        ManualMode             = 'Один сериал (HTML/TMDB)'
        RootPath               = 'Папка библиотеки'
        SeriesPath             = 'Папка сериала'
        HtmlPath               = 'HTML файл (необязательно)'
        UseTmdb                = 'Использовать TMDB'
        DryRun                 = 'Только предпросмотр (DryRun)'
        VerifyOnly             = 'Только проверка (VerifyOnly)'
        ExecutionProfile       = 'Профиль запуска'
        ProfileFast            = 'Быстрый'
        ProfileBalanced        = 'Баланс'
        ProfileFull            = 'Полный'
        ProfileHintFast        = 'Быстрый: TMDB или Wiki'
        ProfileHintBalanced    = 'Баланс: TMDB + Wiki + КП'
        ProfileHintFull        = 'Полный: TMDB + Wiki + КП + WebSearch'
        Minimize               = 'Свернуть'
        Start                  = 'Запустить'
        Browse                 = 'Выбрать...'
        Done                   = 'Готово'
        DoneOpenLog            = 'Готово. Открыть лог?'
        Error                  = 'Ошибка'
        Preview                = 'Предпросмотр'
    }

    $en = @{
        AppTitle               = 'SeriesToolkit'
        BatchMode              = 'Batch Mode'
        ManualMode             = 'Single Series (HTML/TMDB)'
        RootPath               = 'Library Folder'
        SeriesPath             = 'Series Folder'
        HtmlPath               = 'HTML file (optional)'
        UseTmdb                = 'Use TMDB'
        DryRun                 = 'Preview only (DryRun)'
        VerifyOnly             = 'Verify only (VerifyOnly)'
        ExecutionProfile       = 'Execution Profile'
        ProfileFast            = 'Fast'
        ProfileBalanced        = 'Balanced'
        ProfileFull            = 'Full'
        ProfileHintFast        = 'Fast: TMDB or Wiki'
        ProfileHintBalanced    = 'Balanced: TMDB + Wiki + KP'
        ProfileHintFull        = 'Full: TMDB + Wiki + KP + WebSearch'
        Minimize               = 'Minimize'
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

