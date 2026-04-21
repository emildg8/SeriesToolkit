#requires -Version 5.1
param(
    [string]$RootPath = '',
    [string]$TitlesCsv = '',
    [string]$SeriesTitle = '',
    [switch]$DryRun,
    [switch]$SkipFolderRename,
    [string]$SeasonFolderMatchRegex = '(?i)\.S(\d+)\.',
    [switch]$NoLaunchCursor,
    [switch]$Manual,
    [string]$SourceUrl = '',
    # Игнорировать episode-titles.csv в папке сериала и заново получить список (HTML/Кинопоиск/диалоги).
    [switch]$RefreshEpisodeList,
    # Если нет русского названия в таблице — подставлять англ. хвост из имени файла (по умолчанию выкл., используется «Серия N»).
    [switch]$AllowEnglishFilenameFallback
)

# Версия набора: см. logs/CHANGELOG.md
$script:ToolkitVersion = '0.1.3'
$script:ToolkitScriptBaseName = 'Script_Rename_ALLVideo'

$ErrorActionPreference = 'Stop'

$ToolkitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FetchScript = Join-Path $ToolkitRoot 'Fetch-VideoMetadata.ps1'
if (Test-Path -LiteralPath $FetchScript) {
    . $FetchScript
}

function Sanitize-WinFileName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }
    $name = $name -replace '[\p{Cc}\p{Cf}]', ''
    $name = $name -replace ':', '-'
    $invalid = '[\\/*?"<>|]'
    $name = $name -replace $invalid, ' '
    $name = $name -replace '\s+', ' '
    $name = $name.Trim()
    # Windows: не допускаются завершающие пробелы и точки в имени
    do {
        $prev = $name
        $name = $name.TrimEnd(' ', '.', [char]0xA0)
    } while ($name -ne $prev -and -not [string]::IsNullOrWhiteSpace($name))
    if ($name.Length -gt 180) { $name = $name.Substring(0, 180).TrimEnd(' ', '.') }
    return $name
}

function Clear-HiddenAttribute([string]$LiteralPath) {
    $i = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction SilentlyContinue
    if (-not $i) { return }
    $h = [System.IO.FileAttributes]::Hidden
    if ($i.Attributes -band $h) { $i.Attributes = $i.Attributes -bxor $h }
}

function Import-EpisodeTitlesCsvRows([string]$LiteralPath) {
    $t = [System.IO.File]::ReadAllText($LiteralPath)
    if ($t.Length -gt 0 -and [int][char]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ep-titles-' + [Guid]::NewGuid().ToString() + '.csv')
    try {
        [System.IO.File]::WriteAllText($tmp, $t, [System.Text.UTF8Encoding]::new($false))
        return Import-Csv -LiteralPath $tmp -Encoding UTF8
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Export-CsvUtf8NoBom([object[]]$Objects, [string]$LiteralPath) {
    if (-not $Objects -or @($Objects).Count -eq 0) {
        [System.IO.File]::WriteAllText($LiteralPath, '', [System.Text.UTF8Encoding]::new($false))
        return
    }
    $lines = $Objects | ConvertTo-Csv -NoTypeInformation
    [System.IO.File]::WriteAllLines($LiteralPath, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
}

function Get-FallbackEpisodeTitleFromFilename([string]$fileName) {
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $null }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    if ($base -notmatch '(?i)\.S\d+E\d+(?:-\d+)?\.(.+)$') { return $null }
    $chunk = $Matches[1]
    if ($chunk -match '(?i)^(.*?)\.\d{4}\.') {
        $chunk = $Matches[1]
    }
    $chunk = $chunk -replace '(?i)\.(BDRip|WEBRip|WEB-DL|1080p|720p|2160p|4K|Rus\.|Ukr\.|Eng\.|H\.264|x264|x265).*$', ''
    $chunk = $chunk -replace '\.', ' '
    $chunk = $chunk -replace '\s+', ' '
    $chunk = $chunk.Trim()
    if ($chunk.Length -gt 180) { $chunk = $chunk.Substring(0, 180).Trim() }
    if ([string]::IsNullOrWhiteSpace($chunk)) { return $null }
    return $chunk
}

function Strip-HtmlFromTitle([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $t = $text -replace '(?i)<br\s*/?>', ' '
    $t = $t -replace '<[^>]+>', ' '
    return $t
}

function Remove-EnglishSubtitleFromTitle([string]$title) {
    if ([string]::IsNullOrWhiteSpace($title)) { return '' }
    $t = Strip-HtmlFromTitle $title
    $t = $t -replace '\s+', ' '
    # Мусор из шаблонов вики
    $t = $t -replace '(?i)\bRTitle\s*=\s*.*$', ''
    $t = $t.Trim()
    # Удаляем блоки «...» с латиницей (типичный англ. подзаголовок после русского)
    $latinGuillemet = [regex]::new('\s*«\s*[A-Za-z0-9][^»]*»')
    for ($i = 0; $i -lt 25; $i++) {
        $n = $latinGuillemet.Replace($t, ' ', 1)
        if ($n -eq $t) { break }
        $t = $n
    }
    $t = $t -replace '(?s)»\s*«\s*[A-Za-z0-9][^»]*»\s*$', '»'
    $t = $t -replace '(?s)»\s*«\s*[A-Za-z0-9][^»]*\s*$', ''
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Normalize-EpisodeTitleForFileName([string]$title, [int]$episodeInSeason) {
    if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) {
        return ''
    }
    $t = Remove-EnglishSubtitleFromTitle $title
    $t = $t -replace '[\p{Cc}\p{Cf}]', ''
    $t = $t.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
        return ''
    }
    if ($t -notmatch '\p{IsCyrillic}' -and $t -match '[A-Za-z]') {
        return ''
    }
    $t = $t -replace ':', '-'
    return $t
}

function Get-PrefixSeasonFolder([int]$n) {
    $w = [string]::new([char[]]@(0x421, 0x435, 0x437, 0x43E, 0x43D, 0x20))
    return $w + $n
}

function Get-SeasonFolderRegex {
    $word = [regex]::Escape([string]::new([char[]]@(0x421, 0x435, 0x437, 0x43E, 0x43D)))
    return '^' + $word + '\s+(\d+)$'
}

function Show-InputBox([string]$message, [string]$title, [string]$default = '') {
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($message, $title, $default)
}

function Normalize-SeriesRootPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    $p = $path.Trim()
    # .cmd передаёт "%~dp0." → путь заканчивается на "\." и GetFileName даёт "."
    $p = $p -replace '(?i)[\\/]\.\s*$', ''
    return $p.TrimEnd('\', '/')
}

function Get-DownloadsFolderForDialogs {
    foreach ($name in @('Downloads', 'Загрузки')) {
        $c = Join-Path $env:USERPROFILE $name
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $env:USERPROFILE
}

function Show-WikipediaSearchForm {
    param(
        [string]$DefaultText = '',
        [switch]$ShowBack
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Search / Поиск'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width = 560
    $form.Height = 280
    $msg = @'
[RU]
Введите название сериала для поиска в Википедии (например: Клан Сопрано).
«Назад» — вернуться к вводу ссылки. «Отмена» — выйти.

[EN]
Enter series title for Wikipedia search (for example: The Sopranos).
«Back» returns to the URL step. «Cancel» exits.
'@
    $tbMsg = New-Object System.Windows.Forms.TextBox
    $tbMsg.Multiline = $true
    $tbMsg.ReadOnly = $true
    $tbMsg.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tbMsg.Text = $msg
    $tbMsg.Left = 12
    $tbMsg.Top = 12
    $tbMsg.Width = $form.ClientSize.Width - 24
    $tbMsg.Height = 100
    $tbMsg.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $tbMsg.TabIndex = 10
    $tbMsg.Add_Enter({ $tbMsg.SelectionLength = 0; $tbMsg.SelectionStart = 0 })
    $form.Controls.Add($tbMsg)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $DefaultText
    $txt.Left = 12
    $txt.Top = $tbMsg.Bottom + 10
    $txt.Width = $form.ClientSize.Width - 24
    $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txt.TabIndex = 0
    $txt.Add_GotFocus({
            if ($txt.Text.Length -gt 0) {
                $txt.SelectionStart = $txt.Text.Length
                $txt.SelectionLength = 0
            }
        })
    $form.Controls.Add($txt)
    $btnW = 100
    $btnH = 28
    $btnTop = $txt.Bottom + 14
    $right = $form.ClientSize.Width - 16
    $bBack = $null
    if ($ShowBack) {
        $bBack = New-Object System.Windows.Forms.Button
        $bBack.Text = 'Назад / Back'
        $bBack.Width = 100
        $bBack.Height = $btnH
        $bBack.Left = 12
        $bBack.Top = $btnTop
        $bBack.TabIndex = 1
        $bBack.Add_Click({ $form.Tag = 'Back'; $form.Close() })
        $form.Controls.Add($bBack)
    }
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK / ОК'
    $btnOk.Width = $btnW
    $btnOk.Height = $btnH
    $btnOk.Left = $right - 2 * $btnW - 20
    $btnOk.Top = $btnTop
    $btnOk.TabIndex = 2
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Отмена / Cancel'
    $btnCancel.Width = $btnW + 30
    $btnCancel.Height = $btnH
    $btnCancel.Left = $right - $btnW - 30
    $btnCancel.Top = $btnTop
    $btnCancel.TabIndex = 3
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel
    $form.Add_Shown({
            $form.ActiveControl = $txt
            $tbMsg.SelectionLength = 0
            $tbMsg.SelectionStart = 0
            if ($txt.Text.Length -gt 0) {
                $txt.SelectionStart = $txt.Text.Length
                $txt.SelectionLength = 0
            }
        })
    $dr = $form.ShowDialog()
    if ($form.Tag -eq 'Back') { return @{ Action = 'Back' } }
    if ($dr -ne [System.Windows.Forms.DialogResult]::OK) { return @{ Action = 'Cancel' } }
    return @{ Action = 'OK'; Text = $txt.Text.Trim() }
}

function Show-EpisodeSourceUrlForm {
    param(
        [switch]$ShowBack,
        [string]$InitialText = ''
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Episode list / Список эпизодов'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width = 640
    $form.Height = 440

    $instructions = @(
        '[RU]'
        'Укажите одно из:'
        '- Ссылку на страницу эпизодов Кинопоиска:'
        '  https://www.kinopoisk.ru/film/ID/episodes/'
        '- Прямую ссылку на русскую Википедию со списком эпизодов:'
        '  https://ru.wikipedia.org/wiki/...'
        ''
        'Если страницу с Кинопоиска вы уже сохраняли вручную (в браузере: «Сохранить как» → «Веб-страница, только HTML»), нажмите «Обзор…» ниже и выберите этот файл — чаще всего он в папке «Загрузки».'
        ''
        'Поле можно оставить пустым и нажать OK — тогда в следующем окне введите название сериала для поиска в Википедии.'
        ''
        '[EN]'
        'Provide one of:'
        '- Kinopoisk episodes page URL:'
        '  https://www.kinopoisk.ru/film/ID/episodes/'
        '- Direct ru.wikipedia.org URL to an episode-list article.'
        ''
        'If you already saved the Kinopoisk page in the browser (Save as → Web Page, HTML only), click «Browse…» below and select that file — it is usually in your Downloads folder.'
        ''
        'Or leave empty, click OK, then enter the series title for Wikipedia search in the next box.'
    ) -join [Environment]::NewLine

    $tbMsg = New-Object System.Windows.Forms.TextBox
    $tbMsg.Multiline = $true
    $tbMsg.ReadOnly = $true
    $tbMsg.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tbMsg.Text = $instructions
    $tbMsg.Left = 12
    $tbMsg.Top = 12
    $tbMsg.Width = $form.ClientSize.Width - 24
    $tbMsg.Height = 230
    $tbMsg.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $tbMsg.TabIndex = 10
    $tbMsg.Add_Enter({
            param($s, $e)
            $tbMsg.SelectionLength = 0
            $tbMsg.SelectionStart = 0
        })
    $form.Controls.Add($tbMsg)

    $lblUrl = New-Object System.Windows.Forms.Label
    $lblUrl.Text = 'Ссылка или файл / URL or file:'
    $lblUrl.Left = 12
    $lblUrl.Top = $tbMsg.Bottom + 10
    $lblUrl.AutoSize = $true
    $form.Controls.Add($lblUrl)

    $browseW = 128
    $txtUrl = New-Object System.Windows.Forms.TextBox
    $txtUrl.Left = 12
    $txtUrl.Top = $lblUrl.Bottom + 4
    $txtUrl.Width = [Math]::Max(120, $form.ClientSize.Width - 24 - $browseW - 8)
    $txtUrl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $txtUrl.TabIndex = 0
    $txtUrl.Add_GotFocus({
            if ($txtUrl.Text.Length -gt 0) {
                $txtUrl.SelectionStart = $txtUrl.Text.Length
                $txtUrl.SelectionLength = 0
            }
        })
    $txtUrl.Add_Enter({
            $txtUrl.SelectionStart = $txtUrl.Text.Length
            $txtUrl.SelectionLength = 0
        })
    $form.Controls.Add($txtUrl)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = 'Обзор… / Browse…'
    $btnBrowse.Width = $browseW
    $btnBrowse.Height = 24
    $btnBrowse.Left = 12 + $txtUrl.Width + 8
    $btnBrowse.Top = $txtUrl.Top - 2
    $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $btnBrowse.TabIndex = 1
    $btnBrowse.Add_Click({
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = 'HTML (*.html;*.htm)|*.html;*.htm|All files|*.*'
            $ofd.Title = 'Выберите сохранённый HTML Кинопоиска / Select saved Kinopoisk HTML'
            $ofd.InitialDirectory = Get-DownloadsFolderForDialogs
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtUrl.Text = $ofd.FileName
                $txtUrl.SelectionStart = $txtUrl.Text.Length
                $txtUrl.SelectionLength = 0
            }
        })
    $form.Controls.Add($btnBrowse)

    $txtUrl.Text = $InitialText

    $btnW = 100
    $btnH = 28
    $btnTop = $txtUrl.Bottom + 18
    $right = $form.ClientSize.Width - 16
    $bBackSrc = $null
    if ($ShowBack) {
        $bBackSrc = New-Object System.Windows.Forms.Button
        $bBackSrc.Text = 'Назад / Back'
        $bBackSrc.Width = 100
        $bBackSrc.Height = $btnH
        $bBackSrc.Left = 12
        $bBackSrc.Top = $btnTop
        $bBackSrc.TabIndex = 2
        $bBackSrc.Add_Click({ $form.Tag = 'Back'; $form.Close() })
        $form.Controls.Add($bBackSrc)
    }
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK / ОК'
    $btnOk.Width = $btnW
    $btnOk.Height = $btnH
    $btnOk.Left = $right - 2 * $btnW - 12
    $btnOk.Top = $btnTop
    $btnOk.TabIndex = 3
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Отмена / Cancel'
    $btnCancel.Width = $btnW + 36
    $btnCancel.Height = $btnH
    $btnCancel.Left = $right - $btnW - 36
    $btnCancel.Top = $btnTop
    $btnCancel.TabIndex = 4
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $form.Add_Shown({
            $form.ActiveControl = $txtUrl
            $tbMsg.SelectionLength = 0
            $tbMsg.SelectionStart = 0
            if ($txtUrl.Text.Length -gt 0) {
                $txtUrl.SelectionStart = $txtUrl.Text.Length
                $txtUrl.SelectionLength = 0
            }
        })

    $dr = $form.ShowDialog()
    if ($form.Tag -eq 'Back') { return 'BACK' }
    if ($dr -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $txtUrl.Text.Trim()
}

function Show-BilingualDialog {
    param(
        [string]$text,
        [string]$title,
        [string]$buttons = 'OK',
        [switch]$ShowBack
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $fw = 580
    if ($ShowBack -and $buttons -eq 'YesNoCursor') { $fw = 780 }
    elseif ($ShowBack) { $fw = 700 }
    $form.Width = $fw
    $form.Height = 360
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tb.Text = $text
    $tb.Left = 12
    $tb.Top = 12
    $tb.Width = $form.ClientSize.Width - 24
    $tb.Height = 240
    $tb.TabIndex = 50
    $tb.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $tb.Add_Enter({
            param($s, $e)
            $tb.SelectionLength = 0
            $tb.SelectionStart = 0
        })
    $form.Controls.Add($tb)
    $btnW = 118
    $btnH = 30
    $btnTop = $tb.Bottom + 16
    $right = $form.ClientSize.Width - 16
    $mkBtn = {
        param([string]$caption, [System.Windows.Forms.DialogResult]$dr, [int]$left)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $caption
        $b.Width = $btnW
        $b.Height = $btnH
        $b.Top = $btnTop
        $b.Left = $left
        $b.DialogResult = $dr
        $form.Controls.Add($b)
        return $b
    }
    if ($ShowBack) {
        $bBackDlg = New-Object System.Windows.Forms.Button
        $bBackDlg.Text = 'Назад / Back'
        $bBackDlg.Width = 100
        $bBackDlg.Height = $btnH
        $bBackDlg.Left = 12
        $bBackDlg.Top = $btnTop
        $bBackDlg.TabIndex = 0
        $bBackDlg.Add_Click({
                $form.Tag = 'Back'
                $form.Close()
            })
        $form.Controls.Add($bBackDlg)
    }
    $firstBtn = $null
    if ($buttons -eq 'OK') {
        $firstBtn = & $mkBtn 'OK / ОК' ([System.Windows.Forms.DialogResult]::OK) ($right - $btnW)
        $firstBtn.TabIndex = 1
        $form.AcceptButton = $firstBtn
    } elseif ($buttons -eq 'YesNo') {
        $bNo = & $mkBtn 'Нет / No' ([System.Windows.Forms.DialogResult]::No) ($right - $btnW)
        $bYes = & $mkBtn 'Да / Yes' ([System.Windows.Forms.DialogResult]::Yes) ($right - 2 * $btnW - 10)
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $firstBtn = $bYes
        $form.AcceptButton = $bYes
        $form.CancelButton = $bNo
    } elseif ($buttons -eq 'YesNoCancel') {
        $bCan = & $mkBtn 'Отмена / Cancel' ([System.Windows.Forms.DialogResult]::Cancel) ($right - $btnW)
        $bNo = & $mkBtn 'Нет / No' ([System.Windows.Forms.DialogResult]::No) ($right - 2 * $btnW - 10)
        $bYes = & $mkBtn 'Да / Yes' ([System.Windows.Forms.DialogResult]::Yes) ($right - 3 * $btnW - 20)
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $bCan.TabIndex = 3
        $firstBtn = $bYes
        $form.AcceptButton = $bYes
        $form.CancelButton = $bCan
    } elseif ($buttons -eq 'YesNoCursor') {
        $bCur = New-Object System.Windows.Forms.Button
        $bCur.Text = 'Попросить Cursor / Ask Cursor'
        $bCur.Width = 200
        $bCur.Height = $btnH
        $bCur.Top = $btnTop
        $bCur.Left = $right - $bCur.Width
        $bCur.TabIndex = 3
        $bCur.Add_Click({
                $form.Tag = 'Cursor'
                $form.Close()
            })
        $form.Controls.Add($bCur)
        $bNo = & $mkBtn 'Нет / No' ([System.Windows.Forms.DialogResult]::No) ($right - $bCur.Width - $btnW - 10)
        $bYes = & $mkBtn 'Да / Yes' ([System.Windows.Forms.DialogResult]::Yes) ($right - $bCur.Width - 2 * $btnW - 20)
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $firstBtn = $bYes
        $form.AcceptButton = $bYes
        $form.CancelButton = $bNo
    } else {
        $firstBtn = & $mkBtn 'OK / ОК' ([System.Windows.Forms.DialogResult]::OK) ($right - $btnW)
        $firstBtn.TabIndex = 1
        $form.AcceptButton = $firstBtn
    }
    $form.Add_Shown({
            $form.ActiveControl = $firstBtn
            $tb.SelectionLength = 0
            $tb.SelectionStart = 0
        })
    $result = $form.ShowDialog()
    if ($form.Tag -eq 'Cursor') { return 'Cursor' }
    if ($form.Tag -eq 'Back') { return 'Back' }
    return $result.ToString()
}

function Show-MessageBox {
    param(
        [string]$text,
        [string]$title,
        [string]$buttons = 'OK',
        [switch]$ShowBack
    )
    return Show-BilingualDialog -text $text -title $title -buttons $buttons -ShowBack:$ShowBack
}

function Get-DefaultSearchQuery([string]$rootPath) {
    $leaf = [System.IO.Path]::GetFileName($rootPath.TrimEnd('\', '/'))
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -eq '.') {
        $parent = Split-Path -Parent $rootPath.TrimEnd('\', '/')
        $leaf = [System.IO.Path]::GetFileName($parent)
    }
    if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -eq '.') { return '' }
    return $leaf
}

function Write-RenameLog([string]$basePath, [string]$message) {
    try {
        $logPath = Join-Path $basePath 'rename-series-log.txt'
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Invoke-CursorAssistantForEpisodes([string]$basePath) {
    $hintPath = Join-Path $basePath 'CURSOR-ASK-EPISODES.txt'
    $body = @'
[RU]
Попросите ассистента Cursor в этом рабочем пространстве собрать episode-titles.csv для этой папки сериала.

Нужен CSV с колонками: season, episode, title (UTF-8).
Можно дать ссылку на Кинопоиск / Википедию со списком эпизодов или приложить сохранённый HTML.

[EN]
Ask the Cursor assistant in this workspace to build episode-titles.csv for this series folder.

CSV columns: season, episode, title (UTF-8).
You can provide a Kinopoisk / Wikipedia episode-list link or attach a saved HTML file.
'@
    try {
        Set-Content -LiteralPath $hintPath -Value $body -Encoding UTF8
    } catch { }
    if ($NoLaunchCursor) {
        if (Test-Path -LiteralPath $hintPath) { Invoke-Item -LiteralPath $hintPath }
        return
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe'),
        (Join-Path ${env:ProgramFiles} 'Cursor\Cursor.exe')
    )
    foreach ($exe in $candidates) {
        if (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath $exe -ArgumentList @("`"$basePath`"")
            return
        }
    }
    try {
        Start-Process explorer.exe $basePath
    } catch { }
}

function New-EpisodeTitlesTemplateFile([string]$LiteralPath) {
    $rows = @(
        [pscustomobject]@{ season = 1; episode = 1; title = 'Название эпизода S01E01 (замените на своё)' }
        [pscustomobject]@{ season = 1; episode = 2; title = 'Название эпизода S01E02 (замените на своё)' }
        [pscustomobject]@{ season = 2; episode = 1; title = 'Пример: первый эпизод второго сезона' }
    )
    Export-CsvUtf8NoBom $rows $LiteralPath
}

# --- Root ---
if (-not $RootPath) { $RootPath = $PSScriptRoot }
# CMD: "-RootPath "%~dp0"" — если путь оканчивается на \, кавычка экранируется и в аргумент попадает лишняя "
$RootPath = $RootPath.Trim().Trim([char]0x22).Trim()
if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPath not found: $RootPath" }
$Base = Normalize-SeriesRootPath ((Resolve-Path -LiteralPath $RootPath).Path)

# --- Manual: только CSV пользователя в папке с .cmd (корень сериала) ---
if ($Manual) {
    foreach ($name in @('episode-titles.csv', 'titles.csv')) {
        $p = Join-Path $Base $name
        if (Test-Path -LiteralPath $p) { $TitlesCsv = $p; break }
    }
    if (-not $TitlesCsv -or -not (Test-Path -LiteralPath $TitlesCsv)) {
        $templatePath = Join-Path $Base 'episode-titles.csv'
        if ($DryRun) {
            $dryRunText = (
                "[RU] Ручной режим (-Manual): в этой папке нет файла episode-titles.csv или titles.csv.`n`n" +
                "Папка / Folder:`n$Base`n`n" +
                "(Сейчас включён -DryRun: шаблон CSV не создаётся.)`n`n" +
                "[EN] Manual mode (-Manual): episode-titles.csv or titles.csv was not found in this folder.`n`n" +
                "Folder:`n$Base`n`n" +
                "(-DryRun is on: the CSV template is not created.)"
            )
            Show-MessageBox $dryRunText 'Rename series / Переименование сериала'
            exit 1
        }
        New-EpisodeTitlesTemplateFile -LiteralPath $templatePath
        $msg = (
            "[RU] В папке с запускаемым файлом не найден CSV со списком эпизодов (episode-titles.csv или titles.csv).`n`n" +
            "Создан шаблон файла:`n$templatePath`n`n" +
            "Колонки:`n" +
            "  - season — номер сезона (целое число);`n" +
            "  - episode — номер эпизода внутри сезона (как в имени файла S01E02, здесь укажите 2);`n" +
            "  - title — название эпизода на русском или как вам нужно.`n`n" +
            "Сохраните файл в кодировке UTF-8, отредактируйте строки под ваши эпизоды и запустите скрипт снова с ключом -Manual.`n`n" +
            "[EN] No episode list CSV (episode-titles.csv or titles.csv) next to the launcher in this folder.`n`n" +
            "A template file was created:`n$templatePath`n`n" +
            "Columns:`n" +
            "  - season — season number (integer);`n" +
            "  - episode — episode number within the season (for S01E02, use 2 here);`n" +
            "  - title — episode title (any language you prefer).`n`n" +
            "Save the file as UTF-8, edit the rows for your episodes, then run again with -Manual."
        )
        Show-MessageBox $msg 'Rename series (manual) / Переименование сериала (ручной режим)'
        $notepad = Join-Path $env:WINDIR 'notepad.exe'
        if (Test-Path -LiteralPath $notepad) {
            Start-Process -FilePath $notepad -ArgumentList "`"$templatePath`""
        } else {
            Invoke-Item -LiteralPath $templatePath
        }
        exit 1
    }
} else {
    # optional explicit csv (без -RefreshEpisodeList подхватывается существующий episode-titles.csv)
    if (-not $TitlesCsv) {
        if (-not $RefreshEpisodeList) {
            foreach ($name in @('episode-titles.csv', 'titles.csv')) {
                $p = Join-Path $Base $name
                if (Test-Path -LiteralPath $p) { $TitlesCsv = $p; break }
            }
        }
    }
    $TitlesCsv = $TitlesCsv.Trim()

    if (-not $TitlesCsv -or -not (Test-Path -LiteralPath $TitlesCsv)) {
        $fetchRememberUrl = ''
        $fetchShowBackSource = $false
        $skipSourceUrlParam = $false
        :fetchLoop while ($true) {
            $items = $null
            $q = ''
            $effectiveSource = if ($skipSourceUrlParam) { $null } else { $SourceUrl }
            if ($effectiveSource) {
                $items = Try-ResolveEpisodeList -SourceUrl $effectiveSource -SearchQuery $null
            }
            $urlTrim = ''
            if ($effectiveSource) {
                $urlTrim = $effectiveSource.Trim()
            }
            if (-not $items -and -not $effectiveSource) {
                $u = Show-EpisodeSourceUrlForm -ShowBack:$fetchShowBackSource -InitialText $fetchRememberUrl
                $fetchShowBackSource = $false
                if ($u -eq 'BACK') { exit 1 }
                if ($u) {
                    $urlTrim = $u.Trim()
                    $fetchRememberUrl = $urlTrim
                }
                if ($urlTrim) {
                    $items = Try-ResolveEpisodeList -SourceUrl $urlTrim -SearchQuery $null
                }
            }

            $wikiUrlFromFirst = $false
            foreach ($cand in @($urlTrim, ([string]$effectiveSource))) {
                if ([string]::IsNullOrWhiteSpace($cand)) { continue }
                $c = $cand.Trim()
                if ($c -match '(?i)wikipedia\.org') { $wikiUrlFromFirst = $true; break }
                if ($null -ne (Get-WikipediaPageTitleFromUrl $c)) { $wikiUrlFromFirst = $true; break }
            }

            $backOk = (-not $effectiveSource) -or $skipSourceUrlParam
            $kpId = Get-KinopoiskFilmIdFromUrl $urlTrim
            if ($kpId -and -not $items) {
                $kpUrl = "https://www.kinopoisk.ru/film/$kpId/episodes/"
                while ($script:LastResolveHint -eq 'kinopoisk_captcha') {
                    $capMsg = @"
[RU]
Автоматическая загрузка страницы эпизодов получила ответ как от антибота/капчи (запрос из PowerShell отличается от браузера).

Да — открыть Кинопоиск в браузере, при необходимости пройти проверку, дождаться списка эпизодов, затем повторить загрузку скриптом.
Нет — пропустить Кинопоиск и перейти к поиску в Википедии (следующее окно).
Отмена — выйти.
«Назад» — снова ввести ссылку или файл в первом окне.

[EN]
The scripted request was blocked like a captcha/anti-bot (PowerShell is not your browser).

Yes — open Kinopoisk in the browser, complete any check if shown, wait for the episode list, then retry the download.
No — skip Kinopoisk and continue to Wikipedia search (next dialog).
Cancel — exit.
«Back» — return to the first dialog (URL or HTML file).
"@
                    $capChoice = Show-MessageBox $capMsg 'Kinopoisk / Кинопоиск' 'YesNoCancel' -ShowBack:$backOk
                    if ($capChoice -eq 'Back') {
                        $skipSourceUrlParam = $true
                        $fetchShowBackSource = $true
                        $fetchRememberUrl = $urlTrim
                        continue fetchLoop
                    }
                    if ($capChoice -eq 'Cancel') {
                        exit 1
                    }
                    if ($capChoice -eq 'No') {
                        $script:LastResolveHint = ''
                        break
                    }
                    Start-Process $kpUrl
                    $items = Get-EpisodesFromKinopoiskEpisodesPage $kpId
                    if ($items) { break }
                    if (-not $items -and $script:LastResolveHint -eq 'kinopoisk_captcha') {
                        $htmlMsg = @'
[RU]
Если в браузере список эпизодов уже открыт, но скрипт всё равно не может скачать его автоматически:
1) в браузере: «Файл» → «Сохранить как» → «Веб-страница, только HTML»;
2) здесь нажмите «Да / Yes» и выберите сохранённый .html/.htm — скрипт прочитает эпизоды из файла.

«Назад» — предыдущий шаг (окно Кинопоиска / капчи).

[EN]
If the episode list is visible in the browser but the script still cannot download it:
1) In the browser: File → Save as → Web Page, HTML only;
2) Click Yes here and pick the saved .html/.htm — the script will parse episodes from the file.

«Back» — previous step (Kinopoisk / captcha dialog).
'@
                        $pickHtml = Show-BilingualDialog -text $htmlMsg -title 'Kinopoisk HTML / Кинопоиск' -buttons 'YesNo' -ShowBack:$backOk
                        if ($pickHtml -eq 'Back') {
                            $skipSourceUrlParam = $true
                            $fetchShowBackSource = $true
                            $fetchRememberUrl = $urlTrim
                            continue fetchLoop
                        }
                        if ($pickHtml -eq 'Yes') {
                            Add-Type -AssemblyName System.Windows.Forms
                            $ofd = New-Object System.Windows.Forms.OpenFileDialog
                            $ofd.Filter = 'HTML (*.html;*.htm)|*.html;*.htm|All files|*.*'
                            $ofd.Title = 'Выберите сохранённый HTML / Select saved HTML'
                            $ofd.InitialDirectory = Get-DownloadsFolderForDialogs
                            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                                $items = Get-EpisodesFromKinopoiskSavedHtmlFile $ofd.FileName
                            }
                            $script:LastResolveHint = ''
                            break
                        }
                    }
                    if ($script:LastResolveHint -ne 'kinopoisk_captcha') { break }
                }
            }

            $q = ''
            if (-not $items -and -not $wikiUrlFromFirst) {
                $defaultQuery = Get-DefaultSearchQuery $Base
                $ws = Show-WikipediaSearchForm -DefaultText $defaultQuery -ShowBack:$backOk
                if ($ws.Action -eq 'Back') {
                    $skipSourceUrlParam = $true
                    $fetchShowBackSource = $true
                    $fetchRememberUrl = $urlTrim
                    continue fetchLoop
                }
                if ($ws.Action -eq 'Cancel') {
                    Show-MessageBox "[RU] Отменено.`n`n[EN] Cancelled." "Script_Rename_ALLVideo $script:ToolkitVersion"
                    exit 1
                }
                $q = $ws.Text
                $items = Try-ResolveEpisodeList -SourceUrl $null -SearchQuery $q.Trim()
            }

            if ($items) {
                break fetchLoop
            }

            $tvmazePrompt = @'
[RU]
Ошибка
Наименований не найдено (Кинопоиск и Википедия).

Повторить поиск на TVMaze?
«Назад» — вернуться к вводу ссылки / названия для Википедии.

[EN]
Error
No episode titles were found (Kinopoisk and Wikipedia).

Retry search on TVMaze?
«Back» — return to URL / Wikipedia search step.
'@
            $tryTv = Show-MessageBox $tvmazePrompt 'Ошибка / Error' 'YesNo' -ShowBack:$backOk
            if ($tryTv -eq 'Back') {
                $skipSourceUrlParam = $true
                $fetchShowBackSource = $true
                $fetchRememberUrl = $urlTrim
                continue fetchLoop
            }
            if ($tryTv -eq 'Yes') {
                $enTitle = $null
                $tvq = $q.Trim()
                if ([string]::IsNullOrWhiteSpace($tvq)) { $tvq = Get-DefaultSearchQuery $Base }
                $items = Get-EpisodesFromTvMaze $tvq
                if (-not $items) {
                    $enTitle = Get-EnglishTitleFromRuWikipedia $tvq
                    if ($enTitle) {
                        $items = Get-EpisodesFromTvMaze $enTitle
                    }
                }
                if ($items) {
                    $wikiRu = Get-EpisodesFromWikipediaSearchQueries $tvq
                    if (-not $wikiRu -and $enTitle) {
                        $wikiRu = Get-EpisodesFromWikipediaSearchQueries $enTitle
                    }
                    $items = Merge-EpisodeTitlesPreferRu $items $wikiRu
                }
            }

            if ($items) {
                break fetchLoop
            }

            $extraHint = ''
            if ($script:LastResolveHint -eq 'kinopoisk_captcha') {
                $extraHint = "`n[RU] Примечание: Кинопоиск всё ещё возвращает капчу для автоматической загрузки." +
                    "`nПопробуйте позже, другую сеть/VPN, или используйте CSV (-Manual).`n`n" +
                    "[EN] Note: Kinopoisk may still return a captcha for automated downloads.`nTry later, another network/VPN, or use a CSV (-Manual).`n"
            }
            $failedText = @'
[RU]
Не удалось получить список эпизодов.

Варианты:
- Положите в эту папку episode-titles.csv и запустите снова;
- Используйте -Manual со своим CSV;
- Попросите Cursor собрать CSV.

Открыть эту папку в Проводнике?
«Назад» — вернуться к шагу с TVMaze / поиском.

[EN]
Could not get the episode list.

Options:
- Add episode-titles.csv here and run again;
- Use -Manual with your CSV;
- Ask Cursor assistant to build CSV.

Open this folder in Explorer?
«Back» — return to the TVMaze / search step.
'@ + $extraHint
            $again = Show-BilingualDialog -text $failedText -title 'Failed / Ошибка' -buttons 'YesNoCursor' -ShowBack:$backOk
            if ($again -eq 'Back') {
                $skipSourceUrlParam = $true
                $fetchShowBackSource = $true
                $fetchRememberUrl = $urlTrim
                continue fetchLoop
            }
            if ($again -eq 'Yes') {
                Start-Process explorer.exe $Base
            }
            elseif ($again -eq 'Cursor') {
                Invoke-CursorAssistantForEpisodes $Base
            }
            exit 1
        }

        $items = Expand-EpisodeListWithRussianWikipedia @($items) (Get-DefaultSearchQuery $Base)
        $outCsv = Join-Path $Base 'episode-titles.csv'
        Export-CsvUtf8NoBom @($items) $outCsv
        $TitlesCsv = $outCsv
        Show-MessageBox "[RU] Сохранено: $outCsv`nЗапускаю переименование...`n`n[EN] Saved: $outCsv`nStarting rename..." "Script_Rename_ALLVideo $script:ToolkitVersion"
    }
}

if (-not $SeriesTitle) {
    $SeriesTitle = [System.IO.Path]::GetFileName($Base.TrimEnd('\', '/'))
}
$SeriesTitle = Sanitize-WinFileName $SeriesTitle
if ([string]::IsNullOrWhiteSpace($SeriesTitle) -or $SeriesTitle -eq '.' -or $SeriesTitle -eq '..') {
    $SeriesTitle = Sanitize-WinFileName (Get-DefaultSearchQuery $Base)
}
if (-not $SeriesTitle) { throw "SeriesTitle empty. Use -SeriesTitle." }

$rows = @(Import-EpisodeTitlesCsvRows $TitlesCsv)
$expandedRows = Expand-EpisodeListWithRussianWikipedia $rows (Get-DefaultSearchQuery $Base)
if ($expandedRows) {
    $rows = @($expandedRows)
}
$map = @{}
foreach ($r in $rows) {
    $seasonVal = $r.season; if (-not $seasonVal) { $seasonVal = $r.Season }
    $episodeVal = $r.episode; if (-not $episodeVal) { $episodeVal = $r.Episode }
    $titleVal = $r.title; if (-not $titleVal) { $titleVal = $r.Title }
    if (-not $seasonVal -or -not $episodeVal) { continue }
    $sn = [int]$seasonVal
    $en = [int]$episodeVal
    if (-not $map.ContainsKey($sn)) { $map[$sn] = @{} }
    $map[$sn][$en] = (Normalize-EpisodeTitleForFileName $titleVal $en)
}

$seasonFolderRe = Get-SeasonFolderRegex

if (-not $SkipFolderRename) {
    Get-ChildItem -LiteralPath $Base -Directory | ForEach-Object {
        if ($_.Name -notmatch $SeasonFolderMatchRegex) { return }
        $sn = [int]$Matches[1]
        $newName = Get-PrefixSeasonFolder $sn
        if ($_.Name -eq $newName) { return }
        $dest = Join-Path $Base $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skip folder (exists): $newName"
            return
        }
        if ($DryRun) {
            Write-Host "[DryRun] Folder: $($_.Name) -> $newName"
        } else {
            Rename-Item -LiteralPath $_.FullName -NewName $newName
            Write-RenameLog $Base "Folder: $($_.Name) -> $newName"
            Write-Host "Folder: $($_.Name) -> $newName"
        }
    }
}

Get-ChildItem -LiteralPath $Base -Directory | ForEach-Object {
    if ($_.Name -notmatch $seasonFolderRe) { return }
    $seasonNum = [int]$Matches[1]
    $st = $map[$seasonNum]
    if (-not $st) {
        Write-Warning "No titles for season $seasonNum in $($_.Name)"
        return
    }
    Get-ChildItem -LiteralPath $_.FullName -File -Force | ForEach-Object {
        $fn = $_.Name
        if ($fn -notmatch '(?i)S(\d+)E(\d+)(?:-(\d+))?') {
            Write-Warning "No SxxEyy: $fn"
            return
        }
        $fs = [int]$Matches[1]
        $fe = [int]$Matches[2]
        $feEnd = if ($Matches[3]) { [int]$Matches[3] } else { $fe }
        if ($fs -ne $seasonNum) {
            Write-Warning "Season mismatch: $fn"
            return
        }
        $tag = 'S{0:00}E{1:00}' -f $fs, $fe
        $title = $null
        if ($st.ContainsKey($fe)) {
            $title = $st[$fe]
        }
        elseif ($feEnd -ne $fe -and $st.ContainsKey($feEnd)) {
            $title = $st[$feEnd]
        }
        if (($null -eq $title -or [string]::IsNullOrWhiteSpace($title)) -and $AllowEnglishFilenameFallback) {
            $fb = Get-FallbackEpisodeTitleFromFilename $fn
            if ($fb) { $title = $fb }
        }
        if ($null -eq $title) {
            $title = 'Серия ' + $fe
        }
        if ([string]::IsNullOrWhiteSpace($title)) {
            $prefix = $SeriesTitle + ' - ' + $tag
        } else {
            $prefix = $SeriesTitle + ' - ' + $tag + ' - ' + $title
        }
        $baseNew = Sanitize-WinFileName $prefix
        if ([string]::IsNullOrWhiteSpace($baseNew)) {
            Write-Warning "Skip (empty target name after sanitize): $fn"
            Write-RenameLog $Base "SKIP empty name: $fn"
            return
        }
        $newName = "$baseNew$($_.Extension)"
        if ($fn -eq $newName) { return }
        $dest = Join-Path $_.DirectoryName $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skip (exists): $newName"
            return
        }
        if ($DryRun) {
            Write-Host "[DryRun] $fn -> $newName"
            return
        }
        try {
            Rename-Item -LiteralPath $_.FullName -NewName $newName -ErrorAction Stop
            Clear-HiddenAttribute (Join-Path $_.DirectoryName $newName)
            Write-RenameLog $Base "File: $fn -> $newName"
            Write-Host "File: $fn -> $newName"
        } catch {
            Write-Warning "Failed $fn :: $($_.Exception.Message)"
            Write-RenameLog $Base "FAIL: $fn :: $($_.Exception.Message)"
        }
    }
}

Write-Host 'Done.'
