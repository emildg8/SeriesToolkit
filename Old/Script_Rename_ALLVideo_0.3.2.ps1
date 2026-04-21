#requires -Version 5.1
param(
    [string]$RootPath = '',
    [string]$TitlesCsv = '',
    [string]$SeriesTitle = '',
    [switch]$DryRun,
    [switch]$SkipFolderRename,
    # Имена подпапок с номером сезона: «.S01.», «( S01 )», либо через пробел как в релизах «… S01 …» (например Supernatural S01 BDRemux …), либо «1 сезон», «2 сезон» — переименуются в «Сезон 1», «Сезон 2». Папки «Сезон N» шаблону не соответствуют — переименование каталогов для них не выполняется (шаг фактически пропущен). Свой regex: группа (?<sn>…) или первая () с номером сезона.
    [string]$SeasonFolderMatchRegex = '(?i)(?:(?:\.|\(\s*)S(?<sn>\d+)(?:\.|\s*\))|(?:^|\s)S(?<sn>\d+)(?=\s|$))',
    [switch]$NoLaunchCursor,
    [switch]$Manual,
    [string]$SourceUrl = '',
    # Игнорировать episode-titles.csv в папке сериала и заново получить список (HTML/Кинопоиск/диалоги).
    [switch]$RefreshEpisodeList,
    # Если нет русского названия в таблице — подставлять англ. хвост из имени файла (по умолчанию выкл., используется «Серия N»).
    [switch]$AllowEnglishFilenameFallback,
    # Разрешить названия-заглушки (Эпизод N / Серия N). Полезно, если это корректные названия из источника.
    [switch]$AllowPlaceholderTitles,
    # Не показывать итоговый диалог (Да/Нет/Назад/Отмена) — для автоматизации.
    [switch]$SkipOutcomeDialog
)

# Версия набора: см. logs/CHANGELOG.md
$script:ToolkitVersion = '0.3.2'
$script:ToolkitScriptBaseName = 'Script_Rename_ALLVideo'

$ErrorActionPreference = 'Stop'

$ToolkitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FetchScript = Join-Path $ToolkitRoot 'Fetch-VideoMetadata.ps1'
if (Test-Path -LiteralPath $FetchScript) {
    . $FetchScript
}
$UiStringsPath = Join-Path $ToolkitRoot 'UiStrings.ps1'
if (-not (Test-Path -LiteralPath $UiStringsPath)) { throw "UiStrings.ps1 not found next to toolkit: $UiStringsPath" }
. $UiStringsPath
$script:UiLanguage = Get-UiLanguagePreference

function Measure-UiTextHeight([string]$Text, [System.Drawing.Font]$Font, [int]$MaxWidth) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 24 }
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font, [System.Drawing.Size]::new([Math]::Max(80, $MaxWidth), 8000), [System.Windows.Forms.TextFormatFlags]::WordBreak)
    return [Math]::Max($sz.Height + 6, 24)
}

function ConvertTo-DotNetFileSystemPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $p = $Path.Trim()
    # Префикс провайдера PS: [System.IO.File] и UNC не принимают такой формат пути.
    $prefix = 'Microsoft.PowerShell.Core\FileSystem::'
    if ($p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $p.Substring($prefix.Length)
    }
    return $p
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

function Read-EpisodeTitlesCsvRawText([string]$LiteralPath) {
    $LiteralPath = ConvertTo-DotNetFileSystemPath $LiteralPath
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    if ($bytes.Length -eq 0) { return '' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $utf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($utf8.IndexOf([char]0xFFFD) -ge 0) {
        return [System.Text.Encoding]::GetEncoding(1251).GetString($bytes)
    }
    $cyrU = ([regex]::Matches($utf8, '\p{IsCyrillic}')).Count
    $cp1251 = [System.Text.Encoding]::GetEncoding(1251).GetString($bytes)
    $cyrC = ([regex]::Matches($cp1251, '\p{IsCyrillic}')).Count
    if ($cyrC -gt $cyrU + 3 -and $cp1251 -match '\p{IsCyrillic}') { return $cp1251 }
    return $utf8
}

function Import-EpisodeTitlesCsvRows([string]$LiteralPath) {
    $t = Read-EpisodeTitlesCsvRawText $LiteralPath
    if ($t.Length -gt 0 -and [int][char]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ep-titles-' + [Guid]::NewGuid().ToString() + '.csv')
    try {
        [System.IO.File]::WriteAllText($tmp, $t, [System.Text.UTF8Encoding]::new($false))
        return Import-Csv -LiteralPath $tmp -Encoding UTF8
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Export-CsvUtf8BomEpisodeList([object[]]$Objects, [string]$LiteralPath) {
    $LiteralPath = ConvertTo-DotNetFileSystemPath $LiteralPath
    if (-not $Objects -or @($Objects).Count -eq 0) {
        Set-Content -LiteralPath $LiteralPath -Value '' -Encoding utf8
        return
    }
    $lines = @($Objects | ConvertTo-Csv -NoTypeInformation)
    Set-Content -LiteralPath $LiteralPath -Value $lines -Encoding utf8
}

function Get-EpisodeNumbersFromVideoFilename([string]$fileName) {
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $null }
    # «.S1.E01.» / «S01.E01» — точка между номером сезона и E (частый релизный шаблон)
    if ($fileName -match '(?i)S(\d+)\.E(\d+)(?:-(\d+))?') {
        $fe = [int]$Matches[2]
        return @{
            Fs    = [int]$Matches[1]
            Fe    = $fe
            FeEnd = if ($Matches[3]) { [int]$Matches[3] } else { $fe }
        }
    }
    # «S01E01», «S01E01-E02»
    if ($fileName -match '(?i)S(\d+)E(\d+)(?:-(\d+))?') {
        $fe = [int]$Matches[2]
        return @{
            Fs    = [int]$Matches[1]
            Fe    = $fe
            FeEnd = if ($Matches[3]) { [int]$Matches[3] } else { $fe }
        }
    }
    return $null
}

function Get-FallbackEpisodeTitleFromFilename([string]$fileName) {
    if ([string]::IsNullOrWhiteSpace($fileName)) { return $null }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $chunk = $null
    if ($base -match '(?i)\.S\d+E\d+(?:-\d+)?\.(.+)$') {
        $chunk = $Matches[1]
    }
    elseif ($base -match '(?i)\.S\d+\.E\d+(?:-\d+)?\.(.+)$') {
        $chunk = $Matches[1]
    }
    if (-not $chunk) { return $null }
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
    $t = $title
    # Хвост шаблонов Википедии: |RTitle = …
    $t = $t -replace '(?is)\|\s*RTitle\s*=.*$', ''
    # «Русское название |AltTitle = English» (Википедия) или «English |AltTitle = Русское» (TVDB и др.)
    # Раньше брали только хвост после AltTitle → для «Землевладелец |AltTitle = Landman» оставался Landman и отбрасывался как «только латиница».
    if ($t -match '(?is)(.+?)\|\s*AltTitle\s*=\s*([^|]+)') {
        $segBefore = $Matches[1].Trim()
        $segAlt = $Matches[2].Trim()
        if ($segBefore -match '\p{IsCyrillic}' -and $segAlt -notmatch '\p{IsCyrillic}') {
            $t = $segBefore
        }
        elseif ($segAlt -match '\p{IsCyrillic}' -and $segBefore -notmatch '\p{IsCyrillic}') {
            $t = $segAlt
        }
        elseif ($segBefore -match '\p{IsCyrillic}') {
            $t = $segBefore
        }
        else {
            $t = if (-not [string]::IsNullOrWhiteSpace($segBefore)) { $segBefore } else { $segAlt }
        }
    }
    # «Друзья»: в одной строке «English » « Русское» (ячейка Википедии в CSV без пересборки списка)
    if ($t -match '»\s*«\s*(.+)') {
        $tail = ($Matches[1].Trim() -replace '(?is)\|\s*RTitle\s*=.*$', '')
        if ($tail -match '\p{IsCyrillic}') {
            $t = $tail
        }
    }
    $t = Remove-EnglishSubtitleFromTitle $t
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

# «1 сезон», «1-й сезон», «12 сезон» в корне сериала → «Сезон 1», …
# Учёт неразрывного пробела между числом и «сезон» (часто в именах с Проводника/сети)
function Get-NumericWordSeasonFolderRegex {
    return '^(?i)(\d+)(?:[-–]\s*й\s+|\s+)сезон\s*$'
}

function Resolve-SeasonNumberFromFolderName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $n = $name -replace [char]0x00A0, ' ' -replace [char]0x202F, ' '
    $n = $n.Trim()
    $sr = Get-SeasonFolderRegex
    if ($n -match $sr) { return [int]$Matches[1] }
    $nw = Get-NumericWordSeasonFolderRegex
    if ($n -match $nw) { return [int]$Matches[1] }
    return $null
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

function Normalize-ForDownloadsHtmlMatch([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $t = $s.ToLowerInvariant()
    $t = $t -replace 'ё', 'е'
    $t = $t -replace '[_\-\u2013\u2014\u2012]', ' '
    $t = $t -replace '[^\p{L}\p{Nd}\s]', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-ScoreSeriesNameVsHtmlFileName([string]$seriesNorm, [string]$nameNoExtNorm) {
    if ([string]::IsNullOrWhiteSpace($seriesNorm) -or [string]::IsNullOrWhiteSpace($nameNoExtNorm)) { return 0 }
    $score = 0
    if ($seriesNorm.Length -ge 5 -and $nameNoExtNorm.Contains($seriesNorm)) {
        return 200
    }
    if ($seriesNorm.Length -ge 8) {
        $maxLen = [Math]::Min($seriesNorm.Length, 48)
        for ($len = $maxLen; $len -ge 8; $len--) {
            for ($i = 0; $i + $len -le $seriesNorm.Length; $i++) {
                $sub = $seriesNorm.Substring($i, $len)
                if ($nameNoExtNorm.Contains($sub)) {
                    $score = [Math]::Max($score, 35 + $len)
                }
            }
            if ($score -ge 120) { break }
        }
    }
    foreach ($w in ($seriesNorm -split '\s+')) {
        if ($w.Length -ge 3 -and $nameNoExtNorm.Contains($w)) {
            $score += 26
        }
    }
    return $score
}

function Find-BestEpisodeListHtmlInDownloads {
    param(
        [string]$SeriesRootPath,
        [int]$MaxAgeDays = 7
    )
    $dl = Get-DownloadsFolderForDialogs
    if (-not (Test-Path -LiteralPath $dl)) { return $null }
    $leaf = Get-DefaultSearchQuery $SeriesRootPath
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }
    $seriesNorm = Normalize-ForDownloadsHtmlMatch $leaf
    if ($seriesNorm.Length -lt 3) { return $null }
    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $candidates = @()
    try {
        $candidates = @(Get-ChildItem -LiteralPath $dl -File -ErrorAction Stop | Where-Object {
                $_.LastWriteTime -ge $cutoff -and ($_.Extension -eq '.html' -or $_.Extension -eq '.htm')
            })
    } catch {
        return $null
    }
    if ($candidates.Count -eq 0) { return $null }
    $bestPath = $null
    $bestScore = 0
    $bestTime = [DateTime]::MinValue
    $minScore = 38
    foreach ($f in $candidates) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $fnNorm = Normalize-ForDownloadsHtmlMatch $baseName
        $score = Get-ScoreSeriesNameVsHtmlFileName $seriesNorm $fnNorm
        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestPath = $f.FullName
            $bestTime = $f.LastWriteTime
        }
        elseif ($score -eq $bestScore -and $score -ge $minScore -and $null -ne $bestPath) {
            if ($f.LastWriteTime -gt $bestTime) {
                $bestPath = $f.FullName
                $bestTime = $f.LastWriteTime
            }
        }
    }
    if ($bestScore -lt $minScore) { return $null }
    return $bestPath
}

# Явный Font(string, float, FontStyle): при New-Object третья перегрузка путается с Font(string, float, GraphicsUnit).
function New-UiFont([string]$family, [float]$emSize, $style) {
    [System.Drawing.Font]::new($family, $emSize, [System.Drawing.FontStyle]$style)
}

function Set-AppleDialogStyle([System.Windows.Forms.Form]$form) {
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 250)
    $form.Font = New-UiFont 'Segoe UI' 9.75 ([System.Drawing.FontStyle]::Regular)
    $form.Padding = New-Object System.Windows.Forms.Padding(10)
}

function Set-AppleReadOnlyTextStyle([System.Windows.Forms.TextBox]$tb) {
    $tb.BackColor = [System.Drawing.Color]::White
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tb.Font = New-UiFont 'Segoe UI' 9.25 ([System.Drawing.FontStyle]::Regular)
}

function Set-AppleButtonStyle(
    [System.Windows.Forms.Button]$button,
    [switch]$Primary
) {
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 1
    $button.Font = New-UiFont 'Segoe UI' 9 ([System.Drawing.FontStyle]::Bold)
    if ($Primary) {
        $button.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
        $button.ForeColor = [System.Drawing.Color]::White
        $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
    } else {
        $button.BackColor = [System.Drawing.Color]::FromArgb(242, 242, 247)
        $button.ForeColor = [System.Drawing.Color]::FromArgb(28, 28, 30)
        $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(210, 210, 215)
    }
}

function Get-DialogButtonLayout {
    [PSCustomObject]@{
        BtnColW = 132
        BtnH    = 30
        Gap     = 8
        Margin  = 12
    }
}

function Show-WikipediaSearchForm {
    param(
        [string]$DefaultText = '',
        [switch]$ShowBack
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $t = Get-UiStrings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $t.WikiSearchTitle
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Set-AppleDialogStyle $form
    $dl = Get-DialogButtonLayout
    $m = $dl.Margin
    $tbMsg = New-Object System.Windows.Forms.TextBox
    $tbMsg.Multiline = $true
    $tbMsg.ReadOnly = $true
    $tbMsg.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $tbMsg.Text = $t.WikiSearchInstructions
    $tbMsg.Left = $m
    $tbMsg.Top = $m
    $tbMsg.TabIndex = 10
    Set-AppleReadOnlyTextStyle $tbMsg
    $tbMsg.Add_Enter({ $tbMsg.SelectionLength = 0; $tbMsg.SelectionStart = 0 })
    $form.Controls.Add($tbMsg)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $DefaultText
    $txt.Left = $m
    $txt.TabIndex = 0
    $txt.Font = New-UiFont 'Segoe UI' 10 ([System.Drawing.FontStyle]::Regular)
    $txt.Add_GotFocus({
            if ($txt.Text.Length -gt 0) {
                $txt.SelectionStart = $txt.Text.Length
                $txt.SelectionLength = 0
            }
        })
    $form.Controls.Add($txt)
    $bBack = $null
    if ($ShowBack) {
        $bBack = New-Object System.Windows.Forms.Button
        $bBack.Text = $t.BtnBack
        $bBack.Width = $dl.BtnColW
        $bBack.Height = $dl.BtnH
        $bBack.TabIndex = 1
        $bBack.Add_Click({ $form.Tag = 'Back'; $form.Close() })
        Set-AppleButtonStyle $bBack
        $form.Controls.Add($bBack)
    }
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = $t.BtnOk
    $btnOk.Width = $dl.BtnColW
    $btnOk.Height = $dl.BtnH
    $btnOk.TabIndex = 2
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-AppleButtonStyle $btnOk -Primary
    $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = $t.BtnCancel
    $btnCancel.Width = $dl.BtnColW
    $btnCancel.Height = $dl.BtnH
    $btnCancel.TabIndex = 3
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-AppleButtonStyle $btnCancel
    $form.Controls.Add($btnCancel)
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel
    $relayoutWiki = {
        $cw = [Math]::Max(400, [int]$form.ClientSize.Width)
        $inner = $cw - 2 * $m
        $tbMsg.Width = $inner
        $tbMsg.Height = [Math]::Max(60, (Measure-UiTextHeight $t.WikiSearchInstructions $tbMsg.Font $inner))
        $txt.Top = $tbMsg.Bottom + 10
        $txt.Width = [Math]::Max(120, $inner - $dl.BtnColW - $dl.Gap)
        $btnTop = $txt.Bottom + 14
        $btnOk.Left = $txt.Right - $dl.BtnColW
        $btnOk.Top = $btnTop
        $btnCancel.Left = $txt.Right + $dl.Gap
        $btnCancel.Top = $btnTop
        if ($bBack) {
            $bBack.Left = $m
            $bBack.Top = $btnTop
        }
        $needH = $btnTop + $dl.BtnH + $m + 8
        $form.ClientSize = New-Object System.Drawing.Size($cw, $needH)
    }
    $form.Add_Load($relayoutWiki)
    $form.Add_Shown({
            & $relayoutWiki
            $form.ActiveControl = $txt
            $tbMsg.SelectionLength = 0
            $tbMsg.SelectionStart = 0
            if ($txt.Text.Length -gt 0) {
                $txt.SelectionStart = $txt.Text.Length
                $txt.SelectionLength = 0
            }
        })
    $form.ClientSize = New-Object System.Drawing.Size(560, 360)
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
    $t0 = Get-UiStrings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $t0.EpisodeListTitle
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Set-AppleDialogStyle $form
    $dl = Get-DialogButtonLayout
    $m = $dl.Margin
    $gapUrlBrowse = $dl.Gap

    $tbMsg = New-Object System.Windows.Forms.TextBox
    $tbMsg.Multiline = $true
    $tbMsg.ReadOnly = $true
    $tbMsg.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $tbMsg.TabIndex = 10
    Set-AppleReadOnlyTextStyle $tbMsg
    $tbMsg.Add_Enter({ param($s, $e) $tbMsg.SelectionLength = 0; $tbMsg.SelectionStart = 0 })

    $lblUrl = New-Object System.Windows.Forms.Label
    $lblUrl.AutoSize = $true

    $txtUrl = New-Object System.Windows.Forms.TextBox
    $txtUrl.TabIndex = 0
    $txtUrl.Font = New-UiFont 'Segoe UI' 10 ([System.Drawing.FontStyle]::Regular)
    $txtUrl.Text = $InitialText
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

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Width = $dl.BtnColW
    $btnBrowse.Height = $dl.BtnH
    $btnBrowse.TabIndex = 1
    Set-AppleButtonStyle $btnBrowse
    $btnBrowse.Add_Click({
            $ti = Get-UiStrings
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = 'HTML (*.html;*.htm)|*.html;*.htm|All files|*.*'
            $ofd.Title = $ti.OpenHtmlTitle
            $ofd.InitialDirectory = Get-DownloadsFolderForDialogs
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtUrl.Text = $ofd.FileName
                $txtUrl.SelectionStart = $txtUrl.Text.Length
                $txtUrl.SelectionLength = 0
            }
        })

    $lblLang = New-Object System.Windows.Forms.Label
    $lblLang.AutoSize = $true

    $cbLang = New-Object System.Windows.Forms.ComboBox
    $cbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbLang.TabIndex = 5
    $pairs = @(Get-UiLanguageComboItems)
    foreach ($p in $pairs) { [void]$cbLang.Items.Add($p.Display) }
    for ($i = 0; $i -lt $pairs.Count; $i++) {
        if ($pairs[$i].Code -eq $script:UiLanguage) {
            $cbLang.SelectedIndex = $i
            break
        }
    }

    $bBackSrc = $null
    if ($ShowBack) {
        $bBackSrc = New-Object System.Windows.Forms.Button
        $bBackSrc.Width = $dl.BtnColW
        $bBackSrc.Height = $dl.BtnH
        $bBackSrc.TabIndex = 2
        $bBackSrc.Add_Click({ $form.Tag = 'Back'; $form.Close() })
        Set-AppleButtonStyle $bBackSrc
    }

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Width = $dl.BtnColW
    $btnOk.Height = $dl.BtnH
    $btnOk.TabIndex = 3
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-AppleButtonStyle $btnOk -Primary

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Width = $dl.BtnColW
    $btnCancel.Height = $dl.BtnH
    $btnCancel.TabIndex = 4
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-AppleButtonStyle $btnCancel

    $form.Controls.AddRange(@($tbMsg, $lblUrl, $txtUrl, $btnBrowse, $lblLang, $cbLang, $btnOk, $btnCancel))
    if ($bBackSrc) { $form.Controls.Add($bBackSrc) }
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $relayoutEp = {
        $t = Get-UiStrings
        $form.Text = $t.EpisodeListTitle
        $tbMsg.Text = $t.EpisodeInstructions
        $lblUrl.Text = $t.UrlLabel
        $btnBrowse.Text = $t.BtnBrowse
        $btnOk.Text = $t.BtnOk
        $btnCancel.Text = $t.BtnCancel
        $lblLang.Text = $t.LangLabel
        if ($bBackSrc) { $bBackSrc.Text = $t.BtnBack }
        $cw = [Math]::Max(520, [int]$form.ClientSize.Width)
        $inner = $cw - 2 * $m
        $tbMsg.Left = $m
        $tbMsg.Top = $m
        $tbMsg.Width = $inner
        $tbMsg.Height = [Math]::Max(72, (Measure-UiTextHeight $tbMsg.Text $tbMsg.Font $inner))
        $lblUrl.Left = $m
        $lblUrl.Top = $tbMsg.Bottom + 10
        $txtUrl.Left = $m
        $txtUrl.Top = $lblUrl.Bottom + 4
        $txtUrl.Width = [Math]::Max(120, $inner - $dl.BtnColW - $gapUrlBrowse)
        $btnBrowse.Left = $txtUrl.Right + $gapUrlBrowse
        $btnBrowse.Top = $txtUrl.Top
        $langTop = [Math]::Max($txtUrl.Bottom, $btnBrowse.Bottom) + 14
        $lblLang.Left = $m
        $lblLang.Top = $langTop + 3
        $cbLang.Left = $m + 96
        $cbLang.Top = $langTop
        $cbLang.Width = $inner - 96 - 8
        $btnRowTop = $langTop + [Math]::Max($lblLang.Height, $cbLang.Height) + 18
        $btnOk.Left = $txtUrl.Right - $dl.BtnColW
        $btnOk.Top = $btnRowTop
        $btnCancel.Left = $btnBrowse.Left
        $btnCancel.Top = $btnRowTop
        if ($bBackSrc) {
            $bBackSrc.Left = $m
            $bBackSrc.Top = $btnRowTop
        }
        $needH = $btnRowTop + $dl.BtnH + $m + 8
        $form.ClientSize = New-Object System.Drawing.Size($cw, $needH)
    }

    $cbLang.Add_SelectedIndexChanged({
            if ($cbLang.SelectedIndex -lt 0) { return }
            $code = $pairs[$cbLang.SelectedIndex].Code
            if ($code -eq $script:UiLanguage) { return }
            Save-UiLanguagePreference $code
            & $relayoutEp
        })

    $form.Add_Load($relayoutEp)
    $form.Add_Shown({
            & $relayoutEp
            $form.ActiveControl = $txtUrl
            $tbMsg.SelectionLength = 0
            $tbMsg.SelectionStart = 0
            if ($txtUrl.Text.Length -gt 0) {
                $txtUrl.SelectionStart = $txtUrl.Text.Length
                $txtUrl.SelectionLength = 0
            }
        })
    $form.ClientSize = New-Object System.Drawing.Size(580, 480)

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
    $t = Get-UiStrings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $title
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Set-AppleDialogStyle $form
    $dl = Get-DialogButtonLayout
    $m = $dl.Margin
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $tb.Text = $text
    $tb.Left = $m
    $tb.Top = $m
    $tb.TabIndex = 50
    Set-AppleReadOnlyTextStyle $tb
    $tb.Add_Enter({ param($s, $e) $tb.SelectionLength = 0; $tb.SelectionStart = 0 })
    $form.Controls.Add($tb)

    $bBackDlg = $null
    if ($ShowBack) {
        $bBackDlg = New-Object System.Windows.Forms.Button
        $bBackDlg.Text = $t.BtnBack
        $bBackDlg.Width = $dl.BtnColW
        $bBackDlg.Height = $dl.BtnH
        $bBackDlg.TabIndex = 0
        $bBackDlg.Add_Click({ $form.Tag = 'Back'; $form.Close() })
        Set-AppleButtonStyle $bBackDlg
        $form.Controls.Add($bBackDlg)
    }

    $mkBtn = {
        param([string]$caption, [System.Windows.Forms.DialogResult]$dr, [int]$left, [int]$top)
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $caption
        $b.Width = $dl.BtnColW
        $b.Height = $dl.BtnH
        $b.Top = $top
        $b.Left = $left
        $b.DialogResult = $dr
        if ($dr -eq [System.Windows.Forms.DialogResult]::Yes -or $dr -eq [System.Windows.Forms.DialogResult]::OK) {
            Set-AppleButtonStyle $b -Primary
        } else {
            Set-AppleButtonStyle $b
        }
        $form.Controls.Add($b)
        return $b
    }

    $bYes = $null
    $bNo = $null
    $bCan = $null
    $bCur = $null
    $bOkOnly = $null

    $relayoutBd = {
        $ti = Get-UiStrings
        if ($bBackDlg) { $bBackDlg.Text = $ti.BtnBack }
        $cw = [Math]::Max(480, [int]$form.ClientSize.Width)
        if ($ShowBack -and $buttons -eq 'YesNoCursor') { $cw = [Math]::Max(720, $cw) }
        elseif ($ShowBack) { $cw = [Math]::Max(640, $cw) }
        $extraBtn = 0
        if ($buttons -eq 'YesNoCursor') { $extraBtn = $dl.BtnColW + $dl.Gap }
        $tblW = $cw - 2 * $m - $extraBtn
        $tb.Width = [Math]::Max(120, $tblW)
        $hText = [Math]::Max(40, (Measure-UiTextHeight $text $tb.Font $tb.Width))
        if ($hText -gt 520) {
            $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
            $tb.Height = 520
        } else {
            $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::None
            $tb.Height = $hText
        }
        $btnTop = $tb.Bottom + 16
        $rightX = $cw - $m
        if ($null -ne $bOkOnly) {
            $bOkOnly.Left = $rightX - $dl.BtnColW
            $bOkOnly.Top = $btnTop
            $bOkOnly.Text = $ti.BtnOk
        }
        if ($buttons -eq 'YesNo' -and $null -ne $bYes -and $null -ne $bNo) {
            $bNo.Left = $rightX - $dl.BtnColW
            $bNo.Top = $btnTop
            $bYes.Left = $bNo.Left - $dl.Gap - $dl.BtnColW
            $bYes.Top = $btnTop
            $bYes.Text = $ti.BtnYes
            $bNo.Text = $ti.BtnNo
        }
        if ($buttons -eq 'YesNoCancel' -and $null -ne $bYes -and $null -ne $bNo -and $null -ne $bCan) {
            $bCan.Left = $rightX - $dl.BtnColW
            $bCan.Top = $btnTop
            $bNo.Left = $bCan.Left - $dl.Gap - $dl.BtnColW
            $bNo.Top = $btnTop
            $bYes.Left = $bNo.Left - $dl.Gap - $dl.BtnColW
            $bYes.Top = $btnTop
            $bYes.Text = $ti.BtnYes
            $bNo.Text = $ti.BtnNo
            $bCan.Text = $ti.BtnCancel
        }
        if ($buttons -eq 'YesNoCursor' -and $null -ne $bCur -and $null -ne $bYes -and $null -ne $bNo) {
            $bCur.Left = $tb.Right + $dl.Gap
            $bCur.Top = $btnTop
            $bCur.Text = $ti.BtnCursor
            $bNo.Left = $bCur.Left - $dl.Gap - $dl.BtnColW
            $bNo.Top = $btnTop
            $bYes.Left = $bNo.Left - $dl.Gap - $dl.BtnColW
            $bYes.Top = $btnTop
            $bYes.Text = $ti.BtnYes
            $bNo.Text = $ti.BtnNo
        }
        if ($bBackDlg) {
            $bBackDlg.Left = $m
            $bBackDlg.Top = $btnTop
        }
        $needH = $btnTop + $dl.BtnH + $m + 8
        $form.ClientSize = New-Object System.Drawing.Size($cw, $needH)
    }

    if ($buttons -eq 'OK') {
        $bOkOnly = & $mkBtn $t.BtnOk ([System.Windows.Forms.DialogResult]::OK) 0 0
        $bOkOnly.TabIndex = 1
        $form.AcceptButton = $bOkOnly
    } elseif ($buttons -eq 'YesNo') {
        $bNo = & $mkBtn $t.BtnNo ([System.Windows.Forms.DialogResult]::No) 0 0
        $bYes = & $mkBtn $t.BtnYes ([System.Windows.Forms.DialogResult]::Yes) 0 0
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $form.AcceptButton = $bYes
        $form.CancelButton = $bNo
    } elseif ($buttons -eq 'YesNoCancel') {
        $bCan = & $mkBtn $t.BtnCancel ([System.Windows.Forms.DialogResult]::Cancel) 0 0
        $bNo = & $mkBtn $t.BtnNo ([System.Windows.Forms.DialogResult]::No) 0 0
        $bYes = & $mkBtn $t.BtnYes ([System.Windows.Forms.DialogResult]::Yes) 0 0
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $bCan.TabIndex = 3
        $form.AcceptButton = $bYes
        $form.CancelButton = $bCan
    } elseif ($buttons -eq 'YesNoCursor') {
        $bCur = New-Object System.Windows.Forms.Button
        $bCur.Width = $dl.BtnColW
        $bCur.Height = $dl.BtnH
        $bCur.TabIndex = 3
        Set-AppleButtonStyle $bCur
        $ttCur = New-Object System.Windows.Forms.ToolTip
        [void]$ttCur.SetToolTip($bCur, $t.BtnCursor)
        $bCur.Add_Click({ $form.Tag = 'Cursor'; $form.Close() })
        $form.Controls.Add($bCur)
        $bNo = & $mkBtn $t.BtnNo ([System.Windows.Forms.DialogResult]::No) 0 0
        $bYes = & $mkBtn $t.BtnYes ([System.Windows.Forms.DialogResult]::Yes) 0 0
        $bYes.TabIndex = 1
        $bNo.TabIndex = 2
        $form.AcceptButton = $bYes
        $form.CancelButton = $bNo
    } else {
        $bOkOnly = & $mkBtn $t.BtnOk ([System.Windows.Forms.DialogResult]::OK) 0 0
        $bOkOnly.TabIndex = 1
        $form.AcceptButton = $bOkOnly
    }

    $firstBtn = $bYes
    if (-not $firstBtn) { $firstBtn = $bOkOnly }

    $form.Add_Load($relayoutBd)
    $form.Add_Shown({
            & $relayoutBd
            if ($firstBtn) { $form.ActiveControl = $firstBtn }
            $tb.SelectionLength = 0
            $tb.SelectionStart = 0
        })
    $form.ClientSize = New-Object System.Drawing.Size(580, 400)

    $result = $form.ShowDialog()
    if ($form.Tag -eq 'Cursor') { return 'Cursor' }
    if ($form.Tag -eq 'Back') { return 'Back' }
    return $result.ToString()
}

function Export-RenameDebugBundle([string]$SeriesBase) {
    $SeriesBase = ConvertTo-DotNetFileSystemPath $SeriesBase
    if (-not (Test-Path -LiteralPath $SeriesBase)) { return $null }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $zipName = "rename-series-debug-$stamp.zip"
    $zipPath = Join-Path $SeriesBase $zipName
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('rename-debug-' + [Guid]::NewGuid().ToString('n'))
    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $meta = [System.Collections.Generic.List[string]]::new()
        [void]$meta.Add('Date (local): ' + (Get-Date -Format 'o'))
        [void]$meta.Add('PSVersion: ' + $PSVersionTable.PSVersion.ToString())
        [void]$meta.Add('ToolkitVersion: ' + $script:ToolkitVersion)
        [void]$meta.Add('SeriesBase: ' + $SeriesBase)
        [void]$meta.Add('DryRun: ' + $DryRun)
        [void]$meta.Add('SkipFolderRename: ' + $SkipFolderRename)
        [void]$meta.Add('Manual: ' + $Manual)
        [void]$meta.Add('RefreshEpisodeList: ' + $RefreshEpisodeList)
        Set-Content -LiteralPath (Join-Path $tempDir 'debug-info.txt') -Value ($meta -join "`n") -Encoding UTF8
        foreach ($name in @('rename-series-log.txt', 'episode-titles.csv', 'titles.csv', 'CURSOR-ASK-EPISODES.txt')) {
            $p = Join-Path $SeriesBase $name
            if (Test-Path -LiteralPath $p) {
                Copy-Item -LiteralPath $p -Destination (Join-Path $tempDir $name) -Force
            }
        }
        $toZip = @(Get-ChildItem -LiteralPath $tempDir -File -ErrorAction SilentlyContinue)
        if ($toZip.Count -eq 0) { return $null }
        Compress-Archive -Path ($toZip | ForEach-Object { $_.FullName }) -DestinationPath $zipPath -Force
    } catch {
        return $null
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $zipPath) { return $zipPath }
    return $null
}

function Remove-RenameSeriesArtifacts([string]$SeriesBase) {
    $SeriesBase = ConvertTo-DotNetFileSystemPath $SeriesBase
    foreach ($name in @('episode-titles.csv', 'titles.csv', 'rename-series-log.txt')) {
        $p = Join-Path $SeriesBase $name
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
    }
    $cmdPath = Join-Path $SeriesBase 'Переименовать-сериал.cmd'
    if (Test-Path -LiteralPath $cmdPath) {
        Remove-Item -LiteralPath $cmdPath -Force -ErrorAction SilentlyContinue
    }
}

function Show-RenameOutcomeDialog([string]$SeriesBase) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $t = Get-UiStrings
    $form = New-Object System.Windows.Forms.Form
    $form.Text = ($t.OutcomeTitleFmt -f $script:ToolkitVersion)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    Set-AppleDialogStyle $form
    $dl = Get-DialogButtonLayout
    $m = $dl.Margin

    $lblQ = New-Object System.Windows.Forms.Label
    $lblQ.AutoSize = $false
    $lblQ.Left = $m
    $lblQ.Top = $m
    $lblQ.Font = New-UiFont 'Segoe UI Semibold' 10 ([System.Drawing.FontStyle]::Regular)
    $lblQ.Text = $t.OutcomeDoneQuestion

    $lblCb = New-Object System.Windows.Forms.Label
    $lblCb.AutoSize = $false
    $lblCb.Left = $m
    $lblCb.Font = New-UiFont 'Segoe UI' 9 ([System.Drawing.FontStyle]::Regular)
    $lblCb.Text = $t.OutcomeCleanupCheckbox

    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = ''
    $cb.AutoSize = $false
    $cb.Size = New-Object System.Drawing.Size(24, 24)
    $cb.Checked = $true

    $btnBack = New-Object System.Windows.Forms.Button
    $btnBack.Text = $t.BtnBack
    $btnBack.Width = $dl.BtnColW
    $btnBack.Height = $dl.BtnH
    $btnBack.TabIndex = 0
    $btnBack.Add_Click({
            $form.Tag = @{ Action = 'Back' }
            $form.Close()
        })
    Set-AppleButtonStyle $btnBack

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = $t.BtnCancel
    $btnCancel.Width = $dl.BtnColW
    $btnCancel.Height = $dl.BtnH
    $btnCancel.TabIndex = 4
    $btnCancel.Add_Click({
            $form.Tag = @{ Action = 'Cancel' }
            $form.Close()
        })
    Set-AppleButtonStyle $btnCancel

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = $t.BtnNo
    $btnNo.Width = $dl.BtnColW
    $btnNo.Height = $dl.BtnH
    $btnNo.TabIndex = 3
    $btnNo.Add_Click({
            $form.Tag = @{ Action = 'No' }
            $form.Close()
        })
    Set-AppleButtonStyle $btnNo

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = $t.BtnYes
    $btnYes.Width = $dl.BtnColW
    $btnYes.Height = $dl.BtnH
    $btnYes.TabIndex = 1
    $btnYes.Add_Click({
            $form.Tag = @{ Action = 'Yes'; DeleteArtifacts = $cb.Checked }
            $form.Close()
        })
    Set-AppleButtonStyle $btnYes -Primary

    $form.Controls.AddRange(@($lblQ, $lblCb, $cb, $btnBack, $btnCancel, $btnNo, $btnYes))
    $form.CancelButton = $btnCancel
    $form.TopMost = $true

    $relayout = {
        $minClientW = $m + (4 * $dl.BtnColW) + (3 * $dl.Gap) + $m
        $cw = [Math]::Max($minClientW, [int]$form.ClientSize.Width)
        $lblQ.Width = $cw - 2 * $m
        $lblQ.Height = [Math]::Max(28, (Measure-UiTextHeight $t.OutcomeDoneQuestion $lblQ.Font $lblQ.Width))
        $lblCb.Top = $lblQ.Bottom + 10
        $lblCb.Width = $cw - 2 * $m - 24 - $dl.Gap - 8
        $lblCb.Height = [Math]::Max(28, (Measure-UiTextHeight $t.OutcomeCleanupCheckbox $lblCb.Font $lblCb.Width))
        $cb.Left = $lblCb.Right + $dl.Gap
        $cb.Top = $lblCb.Top + [int]([Math]::Max(0, ($lblCb.Height - $cb.Height) / 2))
        $bt = [Math]::Max($lblCb.Bottom, $cb.Bottom) + 16
        $rightX = $cw - $m
        $btnCancel.Left = $rightX - $dl.BtnColW
        $btnCancel.Top = $bt
        $btnNo.Left = $btnCancel.Left - $dl.Gap - $dl.BtnColW
        $btnNo.Top = $bt
        $btnYes.Left = $btnNo.Left - $dl.Gap - $dl.BtnColW
        $btnYes.Top = $bt
        $btnBack.Left = $m
        $btnBack.Top = $bt
        $needH = $bt + $dl.BtnH + $m + 8
        $form.ClientSize = New-Object System.Drawing.Size($cw, $needH)
    }
    $form.Add_Load($relayout)
    $form.Add_Shown({
            & $relayout
            $form.Activate()
            $form.BringToFront()
            $form.ActiveControl = $btnYes
        })
    $form.ClientSize = New-Object System.Drawing.Size(580, 260)
    [void]$form.ShowDialog()
    if ($form.Tag) { return $form.Tag }
    return @{ Action = 'Cancel' }
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
Попросите Cursor создать episode-titles.csv для этой папки.

Формат CSV:
season, episode, title (UTF-8)

Можно передать:
- ссылку на Кинопоиск/Википедию
- или сохранённый HTML

[EN]
Ask Cursor to create episode-titles.csv for this folder.

CSV format:
season, episode, title (UTF-8)

You can provide:
- Kinopoisk/Wikipedia URL
- or saved HTML file
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
    Export-CsvUtf8BomEpisodeList $rows $LiteralPath
}

# --- Root ---
if (-not $RootPath) { $RootPath = $PSScriptRoot }
# CMD: "-RootPath "%~dp0"" — если путь оканчивается на \, кавычка экранируется и в аргумент попадает лишняя "
$RootPath = $RootPath.Trim().Trim([char]0x22).Trim()
if (-not (Test-Path -LiteralPath $RootPath)) { throw "RootPath not found: $RootPath" }
$Base = Normalize-SeriesRootPath ((Get-Item -LiteralPath $RootPath -ErrorAction Stop).FullName)
$Base = ConvertTo-DotNetFileSystemPath $Base
$resolvedAllowPlaceholderTitles = [bool]$AllowPlaceholderTitles

# --- Manual: только CSV пользователя в папке с .cmd (корень сериала) ---
if ($Manual) {
    $t = Get-UiStrings
    foreach ($name in @('episode-titles.csv', 'titles.csv')) {
        $p = Join-Path $Base $name
        if (Test-Path -LiteralPath $p) { $TitlesCsv = $p; break }
    }
    if (-not $TitlesCsv -or -not (Test-Path -LiteralPath $TitlesCsv)) {
        $templatePath = Join-Path $Base 'episode-titles.csv'
        if ($DryRun) {
            $dryRunText = ($t.ManualDryRun -f $Base)
            Show-MessageBox $dryRunText $t.RenameSeriesTitle
            exit 1
        }
        New-EpisodeTitlesTemplateFile -LiteralPath $templatePath
        $msg = ($t.ManualTemplateMsg -f $templatePath)
        Show-MessageBox $msg $t.RenameManualTitle
        $notepad = Join-Path $env:WINDIR 'notepad.exe'
        if (Test-Path -LiteralPath $notepad) {
            Start-Process -FilePath $notepad -ArgumentList "`"$templatePath`""
        } else {
            Invoke-Item -LiteralPath $templatePath
        }
        exit 1
    }
} else {
    $t = Get-UiStrings
    $placeholderCsvNeedsRefresh = $false
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

    # Если в локальном CSV в основном заглушки вида «Эпизод N/Серия N», пробуем тихо обновить список
    # по SourceUrl (если передан) или по названию папки сериала, без ручного диалога.
    if ($TitlesCsv -and (Test-Path -LiteralPath $TitlesCsv) -and -not $RefreshEpisodeList) {
        $existingRows = @()
        try {
            $existingRows = @(Import-EpisodeTitlesCsvRows $TitlesCsv)
        } catch { }
        if ($existingRows.Count -gt 0 -and (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($existingRows))) {
            $placeholderCsvNeedsRefresh = $true
            $autoItems = $null
            if ($SourceUrl) {
                $autoItems = Try-ResolveEpisodeList -SourceUrl $SourceUrl -SearchQuery $null
            }
            if (-not $autoItems) {
                $autoItems = Try-ResolveEpisodeList -SourceUrl $null -SearchQuery (Get-DefaultSearchQuery $Base)
            }
            if ($autoItems -and @($autoItems).Count -gt 0 -and -not (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($autoItems))) {
                $outCsv = Join-Path $Base 'episode-titles.csv'
                Export-CsvUtf8BomEpisodeList @($autoItems) $outCsv
                $TitlesCsv = $outCsv
                $placeholderCsvNeedsRefresh = $false
                Write-Host "[Info] Existing CSV had placeholder episode names; refreshed from source."
            }
        }
    }

    if ($placeholderCsvNeedsRefresh) {
        Show-MessageBox $t.PlaceholderCsvWarn $t.RenameSeriesTitle
        exit 1
    }

    if (-not $TitlesCsv -or -not (Test-Path -LiteralPath $TitlesCsv)) {
        $fetchRememberUrl = ''
        $fetchShowBackSource = $false
        $skipSourceUrlParam = $false
        if ([string]::IsNullOrWhiteSpace($SourceUrl)) {
            $autoHtml = Find-BestEpisodeListHtmlInDownloads -SeriesRootPath $Base
            if ($autoHtml) {
                $fetchRememberUrl = $autoHtml
                Write-Host "[Info] Подставлен HTML из папки «Загрузки» (совпадение с именем папки сериала): $autoHtml" -ForegroundColor Cyan
            }
        }
        :fetchLoop while ($true) {
            $t = Get-UiStrings
            $items = $null
            $q = ''
            $allowPlaceholderFromSource = $false
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
                    $capChoice = Show-MessageBox $t.KinopoiskCaptcha $t.KinopoiskTitle 'YesNoCancel' -ShowBack:$backOk
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
                        $pickHtml = Show-BilingualDialog -text $t.KinopoiskHtmlPrompt -title $t.KinopoiskHtmlTitle -buttons 'YesNo' -ShowBack:$backOk
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
                            $ofd.Title = (Get-UiStrings).OpenHtmlTitle
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
                    $twc = Get-UiStrings
                    Show-MessageBox $twc.WikiCancelFmt ($twc.ToolNameFmt -f $script:ToolkitVersion)
                    exit 1
                }
                $q = $ws.Text
                $items = Try-ResolveEpisodeList -SourceUrl $null -SearchQuery $q.Trim()
            }

            if ($items) {
                if ($urlTrim -or $effectiveSource) {
                    $allowPlaceholderFromSource = $true
                }
                break fetchLoop
            }

            $tryTv = Show-MessageBox $t.TvmazePrompt $t.ErrorTitle 'YesNo' -ShowBack:$backOk
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
                $extraHint = $t.FailedTextExtraCaptcha
            }
            $failedText = $t.FailedText + $extraHint
            $again = Show-BilingualDialog -text $failedText -title $t.FailedTitle -buttons 'YesNoCursor' -ShowBack:$backOk
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

        $allowPlaceholderNow = $resolvedAllowPlaceholderTitles -or $allowPlaceholderFromSource
        if ((-not $allowPlaceholderNow) -and (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($items))) {
            Show-MessageBox $t.PhPlaceholder $t.RenameSeriesTitle
            exit 1
        }
        if ($allowPlaceholderFromSource -and (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($items))) {
            $resolvedAllowPlaceholderTitles = $true
        }

        $items = Expand-EpisodeListWithRussianWikipedia @($items) (Get-DefaultSearchQuery $Base)
        if ((-not $resolvedAllowPlaceholderTitles) -and (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($items))) {
            Show-MessageBox $t.PhPlaceholder2 $t.RenameSeriesTitle
            exit 1
        }
        $outCsv = Join-Path $Base 'episode-titles.csv'
        Export-CsvUtf8BomEpisodeList @($items) $outCsv
        $TitlesCsv = $outCsv
        $savedMsg = ($t.SavedBodyFmt -f $outCsv)
        Show-MessageBox $savedMsg $t.SavedTitle
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
$primaryRows = @($rows)
$expandedRows = Expand-EpisodeListWithRussianWikipedia $rows (Get-DefaultSearchQuery $Base)
if ($expandedRows) {
    $candidateRows = @($expandedRows)
    $useCandidate = $true
    $primarySeasons = @{}
    $candidateSeasons = @{}
    foreach ($pr in $primaryRows) {
        $ps = $pr.season
        if (-not $ps) { $ps = $pr.Season }
        if (-not $ps) { continue }
        $primarySeasons[[int]$ps] = $true
    }
    foreach ($cr in $candidateRows) {
        $cs = $cr.season
        if (-not $cs) { $cs = $cr.Season }
        if (-not $cs) { continue }
        $candidateSeasons[[int]$cs] = $true
    }
    foreach ($k in $primarySeasons.Keys) {
        if (-not $candidateSeasons.ContainsKey([int]$k)) {
            # Регрессия из реального кейса: wiki-обогащение может подменить сезон (напр. S03 -> S04) и "уронить" нужный.
            $useCandidate = $false
            Write-Warning "Wikipedia expansion dropped season $k; using local CSV episode list."
            break
        }
    }
    if ($useCandidate) {
        # Локальный CSV имеет приоритет по уже известным эпизодам (особенно если в нём уже есть кириллица).
        # Wiki-обогащение используется только для дополнения/исправления пустых или латинских значений.
        $candByKey = @{}
        foreach ($cr in $candidateRows) {
            $cs = $cr.season; if (-not $cs) { $cs = $cr.Season }
            $ce = $cr.episode; if (-not $ce) { $ce = $cr.Episode }
            if (-not $cs -or -not $ce) { continue }
            $key = ('{0}:{1}' -f ([int]$cs), ([int]$ce))
            $candByKey[$key] = $cr
        }
        foreach ($pr in $primaryRows) {
            $ps = $pr.season; if (-not $ps) { $ps = $pr.Season }
            $pe = $pr.episode; if (-not $pe) { $pe = $pr.Episode }
            if (-not $ps -or -not $pe) { continue }
            $pt = $pr.title; if (-not $pt) { $pt = $pr.Title }
            $key = ('{0}:{1}' -f ([int]$ps), ([int]$pe))
            if (-not $candByKey.ContainsKey($key)) {
                $candByKey[$key] = $pr
                continue
            }
            $ctObj = $candByKey[$key]
            $ct = $ctObj.title; if (-not $ct) { $ct = $ctObj.Title }
            $primaryHasCyr = (-not [string]::IsNullOrWhiteSpace([string]$pt)) -and ([string]$pt -match '\p{IsCyrillic}')
            $candidateHasCyr = (-not [string]::IsNullOrWhiteSpace([string]$ct)) -and ([string]$ct -match '\p{IsCyrillic}')
            $primaryIsPlaceholder = $false
            if (Get-Command Test-EpisodeTitleLooksLikePlaceholder -ErrorAction SilentlyContinue) {
                $primaryIsPlaceholder = Test-EpisodeTitleLooksLikePlaceholder ([string]$pt)
            }
            if ((-not $primaryIsPlaceholder -and $primaryHasCyr) -or -not $candidateHasCyr) {
                $candByKey[$key] = $pr
            }
        }
        $rows = @(
            $candByKey.Values |
                Sort-Object `
                @{ Expression = { $v = $_.season; if (-not $v) { $v = $_.Season }; [int]$v } }, `
                @{ Expression = { $v = $_.episode; if (-not $v) { $v = $_.Episode }; [int]$v } }
        )
    }
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
    $normTitle = Normalize-EpisodeTitleForFileName $titleVal $en
    if ((-not $resolvedAllowPlaceholderTitles) -and (Test-EpisodeTitleLooksLikePlaceholder $normTitle)) { $normTitle = '' }
    $map[$sn][$en] = $normTitle
}

$mappedTitleCount = 0
foreach ($snKey in $map.Keys) {
    foreach ($enKey in $map[$snKey].Keys) {
        $tv = [string]$map[$snKey][$enKey]
        if (-not [string]::IsNullOrWhiteSpace($tv)) { $mappedTitleCount++ }
    }
}
if ($mappedTitleCount -eq 0) {
    $tNt = Get-UiStrings
    Show-MessageBox $tNt.NoTitleCsv $tNt.RenameSeriesTitle
    exit 1
}

# Два шага: (1) подпапки: SeasonFolderMatchRegex («.S01.», …) или «N сезон» → «Сезон N»; если все папки уже «Сезон N», для шага .S01/релиз — в лог пишется SKIP. (2) внутри «Сезон N» — файлы с тегом S01E01 или «.S1.E01.» (см. Get-EpisodeNumbersFromVideoFilename) → «Сериал - S01E01 - название».
$seasonFolderRe = Get-SeasonFolderRegex
$numericWordSeasonRe = Get-NumericWordSeasonFolderRegex

if (-not $SkipFolderRename) {
    $dotSFolders = @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $SeasonFolderMatchRegex })
    if ($dotSFolders.Count -eq 0) {
        $alreadySeasonDirs = @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $seasonFolderRe })
        if ($alreadySeasonDirs.Count -gt 0) {
            Write-RenameLog $Base 'SKIP folder rename: folders already «Сезон N» (no season-folder pattern names left to convert)'
        }
    }
    foreach ($dir in $dotSFolders) {
        if ($dir.Name -notmatch $SeasonFolderMatchRegex) { continue }
        $snStr = $Matches['sn']
        if (-not $snStr) { $snStr = $Matches[1] }
        $sn = [int]$snStr
        $newName = Get-PrefixSeasonFolder $sn
        if ($dir.Name -eq $newName) { continue }
        $dest = Join-Path $Base $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skip folder (exists): $newName"
            continue
        }
        if ($DryRun) {
            Write-Host "[DryRun] Folder: $($dir.Name) -> $newName"
        } else {
            Rename-Item -LiteralPath $dir.FullName -NewName $newName
            Write-RenameLog $Base "Folder: $($dir.Name) -> $newName"
            Write-Host "Folder: $($dir.Name) -> $newName"
        }
    }
    $numericWordFolders = @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $numericWordSeasonRe })
    foreach ($dir in $numericWordFolders) {
        $sn = Resolve-SeasonNumberFromFolderName $dir.Name
        if (-not $sn) { continue }
        $newName = Get-PrefixSeasonFolder $sn
        if ($dir.Name -eq $newName) { continue }
        $dest = Join-Path $Base $newName
        if (Test-Path -LiteralPath $dest) {
            Write-Warning "Skip folder (exists): $newName"
            continue
        }
        if ($DryRun) {
            Write-Host "[DryRun] Folder: $($dir.Name) -> $newName"
        } else {
            Rename-Item -LiteralPath $dir.FullName -NewName $newName
            Write-RenameLog $Base "Folder: $($dir.Name) -> $newName"
            Write-Host "Folder: $($dir.Name) -> $newName"
        }
    }
}

Get-ChildItem -LiteralPath $Base -Directory | ForEach-Object {
    $seasonNum = Resolve-SeasonNumberFromFolderName $_.Name
    if (-not $seasonNum) { return }
    $st = $map[$seasonNum]
    if (-not $st) {
        Write-Warning "No titles for season $seasonNum in $($_.Name)"
        return
    }
    Get-ChildItem -LiteralPath $_.FullName -File -Force | ForEach-Object {
        $fn = $_.Name
        $ep = Get-EpisodeNumbersFromVideoFilename $fn
        if (-not $ep) {
            Write-Warning "No SxxEyy: $fn"
            return
        }
        $fs = $ep.Fs
        $fe = $ep.Fe
        $feEnd = $ep.FeEnd
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

function Write-RenameDiagnosticsIfNothingDone {
    $numericWordRe = Get-NumericWordSeasonFolderRegex
    $allDirs = @(Get-ChildItem -LiteralPath $Base -Directory -ErrorAction SilentlyContinue)
    # «Сезон N» и «N сезон» / «N-й сезон» — оба считаются папками сезона (файлы обрабатываются в обоих)
    $seasonDirs = @($allDirs | Where-Object { $null -ne (Resolve-SeasonNumberFromFolderName $_.Name) })
    $pendingDotS = @($allDirs | Where-Object { $_.Name -match $SeasonFolderMatchRegex })
    $pendingNumericWord = @($allDirs | Where-Object { $_.Name -match $numericWordRe })
    if ($seasonDirs.Count -eq 0) {
        $msgRu = @'
[RU] Переименование не выполнялось: нет подпапок «Сезон 1», «Сезон 2», …
Скрипт: (1) папки с «.S01.», «( S01 )», «… S01 …» (релиз), либо «1 сезон», «2 сезон» → «Сезон 1»; если папки уже «Сезон N», шаг для .S01/релиза только пропускается; (2) внутри «Сезон N» — файлы с S01E01 или .S1.E01. в имени.
Положите видео в «Сезон N»; в имени файла — тег S01E01 или .S1.E01. (S02E03 и т.д.).
'@
        $msgEn = @'
[EN] Nothing renamed: no «Сезон 1», «Сезон 2», … subfolders.
Script: (1) folders with «.S01.», «( S01 )», release «… S01 …», or «1 сезон» / «2 сезон» → «Сезон N»; if already «Сезон N», the release step is skipped; (2) inside «Сезон N» — files with S01E01 or «.S1.E01.» in the filename.
Put videos in season folders; filenames must include S01E01 or dotted S.E tags (S02E03, .S1.E02., …).
'@
        if ($pendingDotS.Count -gt 0) {
            $msgRu += "`n[RU] Обнаружены папки по шаблону сезона (.S01., ( S01 ), «… S01 …» и т.д.), но имя «Сезон N» ещё не создано — проверьте конфликт имён или запуск с -SkipFolderRename."
            $msgEn += "`n[EN] Folders matching season pattern (.S01., ( S01 ), release S01, …) exist, but not «Сезон N» yet — check name conflicts or -SkipFolderRename."
        }
        if ($pendingNumericWord.Count -gt 0) {
            $msgRu += "`n[RU] Есть папки вида «N сезон», но «Сезон N» ещё не получено — проверьте конфликт имён (уже есть «Сезон N»?) или запуск с -SkipFolderRename."
            $msgEn += "`n[EN] Folders named like «N сезон» exist, but not renamed to «Сезон N» — check name conflicts or -SkipFolderRename."
        }
        Write-Host $msgRu -ForegroundColor Yellow
        Write-Host $msgEn -ForegroundColor Yellow
        Write-RenameLog $Base 'DIAG: no season subfolders (Сезон N)'
        return
    }
    $anyTag = $false
    foreach ($d in $seasonDirs) {
        foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '(?i)S\d+\.E\d+|S\d+E\d+') {
                $anyTag = $true
                break
            }
        }
        if ($anyTag) { break }
    }
    if (-not $anyTag) {
        $msgRu = '[RU] В подпапках «Сезон N» нет файлов с тегом S01E01 или .S1.E01. в имени — нечего переименовывать.'
        $msgEn = '[EN] No files with SxxEyy / dotted S.E tags in the name inside season folders — nothing to rename.'
        Write-Host $msgRu -ForegroundColor Yellow
        Write-Host $msgEn -ForegroundColor Yellow
        Write-RenameLog $Base 'DIAG: no SxxEyy filenames in season folders'
    }
}

Write-RenameDiagnosticsIfNothingDone
Write-Host 'Done.'

if (-not $SkipOutcomeDialog) {
    try {
        $outcome = Show-RenameOutcomeDialog -SeriesBase $Base
        if (-not $outcome) {
            $outcome = @{ Action = 'Cancel' }
        }
        $act = [string]$outcome.Action
        if ($act -eq 'Cancel') {
            exit 0
        }
        if ($act -eq 'Yes') {
            if ($outcome.DeleteArtifacts) {
                if ($DryRun) {
                    Write-Host '[DryRun] Чекбокс «удалить» включён — файлы в папке сериала не удалялись (режим пробного прогона).'
                } else {
                    Remove-RenameSeriesArtifacts $Base
                    Write-Host 'Удалены вспомогательные файлы в папке сериала (по запросу).'
                }
            }
        }
        elseif ($act -eq 'No') {
            $bundlePath = Export-RenameDebugBundle -SeriesBase $Base
            if ($bundlePath) {
                $tdb = Get-UiStrings
                Show-MessageBox ($tdb.DebugBundleOkFmt -f $bundlePath) $tdb.DebugBundleTitle
            } else {
                $tdb = Get-UiStrings
                Show-MessageBox $tdb.DebugBundleFail $tdb.DebugBundleTitle
            }
        }
    } catch {
        $errLine = "OUTCOME_DIALOG_ERROR: $($_.Exception.Message)"
        Write-Warning "Итоговый диалог: $($_.Exception.Message)"
        try {
            Write-RenameLog $Base $errLine
        } catch { }
        Write-Host $errLine -ForegroundColor Red
    }
}
