#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ToolkitRoot = ''
)

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:GuiLogPath = $null

function Resolve-SeriesToolkitRoot {
    param([string]$Explicit)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        return $Explicit.Trim().TrimEnd('\', '/')
    }
    $envRoot = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_ROOT', 'User')
    if ([string]::IsNullOrWhiteSpace($envRoot)) { $envRoot = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_ROOT', 'Process') }
    if (-not [string]::IsNullOrWhiteSpace($envRoot)) {
        return $envRoot.Trim().TrimEnd('\', '/')
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $d = Split-Path -Parent $PSCommandPath
        if (-not [string]::IsNullOrWhiteSpace($d)) { return $d }
    }
    try {
        $argv = [Environment]::GetCommandLineArgs()
        if ($argv -and $argv.Length -gt 0) {
            $a0 = [string]$argv[0]
            if ($a0 -match '\.(exe|EXE)$' -and (Test-Path -LiteralPath $a0)) {
                return (Split-Path -Parent $a0)
            }
        }
    } catch { }
    try {
        $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe)) {
            return (Split-Path -Parent $exe)
        }
    } catch { }
    return $null
}

$ToolkitRoot = Resolve-SeriesToolkitRoot -Explicit $ToolkitRoot
if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
    throw 'ToolkitRoot пуст: задайте SERIESTOOLKIT_ROOT или положите SeriesToolkit.GUI.exe в папку со скриптами.'
}

$uiPath = Join-Path $ToolkitRoot 'UiStrings.ps1'
$enginePath = Join-Path $ToolkitRoot 'SeriesToolkit.ps1'
if (-not (Test-Path -LiteralPath $uiPath)) { throw "UiStrings.ps1 not found: $uiPath" }
if (-not (Test-Path -LiteralPath $enginePath)) { throw "SeriesToolkit.ps1 not found: $enginePath" }
try {
    . $uiPath
} catch {
    # В EXE под Restricted dot-source .ps1 может блокироваться.
    # Fallback: читаем содержимое как текст и выполняем в текущем scope.
    try {
        $uiCode = Get-Content -LiteralPath $uiPath -Raw -Encoding UTF8
        $uiSb = [scriptblock]::Create($uiCode)
        . $uiSb
    } catch {
        throw "Не удалось загрузить UiStrings.ps1: $($_.Exception.Message)"
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ProcControl {
    [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr processHandle);
    [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr processHandle);
}
"@

$lang = 'ru'
$s = Get-ToolkitStrings -Lang $lang
$script:RunInProgress = $false
$script:CurrentProcess = $null
$script:IsPaused = $false
$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:ProgressTailPath = $null
$script:ProgressTailOffset = 0L
$script:AllowClose = $false
$script:LastActivityAt = Get-Date
$script:StartedAt = $null
$script:TotalSeries = 0
$script:CurrentSeriesIndex = 0
$script:CurrentSeriesPercent = 0
$script:CompletedSeries = 0
$script:CurrentSeriesPath = ''
$script:UserStopped = $false
$script:SkipSignalFile = Join-Path $ToolkitRoot 'LOGS\gui-skip-request.txt'

try {
    $logsDir = Join-Path $ToolkitRoot 'LOGS'
    if (-not (Test-Path -LiteralPath $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $script:GuiLogPath = Join-Path $logsDir ('gui-session-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
} catch { }

function Write-GuiTrace([string]$msg) {
    if ([string]::IsNullOrWhiteSpace($script:GuiLogPath)) { return }
    try {
        $line = ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $msg)
        Add-Content -LiteralPath $script:GuiLogPath -Value $line -Encoding UTF8
    } catch { }
}
Write-GuiTrace 'GUI started.'

$form = New-Object Windows.Forms.Form
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.ShowIcon = $true
$form.BackColor = [Drawing.Color]::FromArgb(246, 246, 248)
$form.Font = [Drawing.Font]::new('Segoe UI', 9.5)
$form.ClientSize = [Drawing.Size]::new(920, 560)
$form.MinimumSize = [Drawing.Size]::new(980, 620)
try {
    $ico = Join-Path $ToolkitRoot 'assets\SeriesToolkit.icon.ico'
    if (Test-Path -LiteralPath $ico) { $form.Icon = New-Object System.Drawing.Icon($ico) }
} catch { }
try {
    $dbProp = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags] 'NonPublic,Instance')
    if ($dbProp) { $dbProp.SetValue($form, $true, $null) }
} catch { }

$lblLang = New-Object Windows.Forms.Label
$lblLang.Text = 'Language'
$lblLang.Left = 20
$lblLang.Top = 20
$lblLang.Width = 90

$cbLang = New-Object Windows.Forms.ComboBox
$cbLang.Left = 110
$cbLang.Top = 16
$cbLang.Width = 100
$cbLang.DropDownStyle = 'DropDownList'
[void]$cbLang.Items.AddRange(@('RU', 'EN'))
$cbLang.SelectedIndex = 0

$rbBatch = New-Object Windows.Forms.RadioButton
$rbBatch.Left = 20
$rbBatch.Top = 58
$rbBatch.Width = 300
$rbBatch.Checked = $true

$rbManual = New-Object Windows.Forms.RadioButton
$rbManual.Left = 340
$rbManual.Top = 58
$rbManual.Width = 340

$lblRoot = New-Object Windows.Forms.Label
$lblRoot.Left = 20; $lblRoot.Top = 92; $lblRoot.Width = 180
$tbRoot = New-Object Windows.Forms.TextBox
$tbRoot.Left = 20; $tbRoot.Top = 112; $tbRoot.Width = 780
$tbRoot.Text = '\\MEDIA-SERVER\Video\Cartoons'
$btnRoot = New-Object Windows.Forms.Button
$btnRoot.Left = 810; $btnRoot.Top = 110; $btnRoot.Width = 90
$btnRoot.FlatStyle = 'Flat'

$lblSeries = New-Object Windows.Forms.Label
$lblSeries.Left = 20; $lblSeries.Top = 146; $lblSeries.Width = 180
$tbSeries = New-Object Windows.Forms.TextBox
$tbSeries.Left = 20; $tbSeries.Top = 166; $tbSeries.Width = 780
$btnSeries = New-Object Windows.Forms.Button
$btnSeries.Left = 810; $btnSeries.Top = 164; $btnSeries.Width = 90
$btnSeries.FlatStyle = 'Flat'

$lblHtml = New-Object Windows.Forms.Label
$lblHtml.Left = 20; $lblHtml.Top = 200; $lblHtml.Width = 210
$tbHtml = New-Object Windows.Forms.TextBox
$tbHtml.Left = 20; $tbHtml.Top = 220; $tbHtml.Width = 780
$btnHtml = New-Object Windows.Forms.Button
$btnHtml.Left = 810; $btnHtml.Top = 218; $btnHtml.Width = 90
$btnHtml.FlatStyle = 'Flat'

$cbTmdb = New-Object Windows.Forms.CheckBox
$cbTmdb.Left = 20; $cbTmdb.Top = 256; $cbTmdb.Width = 220
$cbDry = New-Object Windows.Forms.CheckBox
$cbDry.Left = 260; $cbDry.Top = 256; $cbDry.Width = 280
$cbDry.Checked = $true
$cbVerify = New-Object Windows.Forms.CheckBox
$cbVerify.Left = 260; $cbVerify.Top = 280; $cbVerify.Width = 280

$lblProfile = New-Object Windows.Forms.Label
$lblProfile.Left = 560; $lblProfile.Top = 258; $lblProfile.Width = 120
$lblProfile.Text = 'Профиль запуска'

$cbProfile = New-Object Windows.Forms.ComboBox
$cbProfile.Left = 640; $cbProfile.Top = 254; $cbProfile.Width = 260
$cbProfile.DropDownStyle = 'DropDownList'
$script:ProfileItems = @(
    [PSCustomObject]@{ LabelRu = 'Быстрый'; LabelEn = 'Fast'; Value = 'Fast' },
    [PSCustomObject]@{ LabelRu = 'Баланс'; LabelEn = 'Balanced'; Value = 'Balanced' },
    [PSCustomObject]@{ LabelRu = 'Полный'; LabelEn = 'Full'; Value = 'Full' }
)

function Refresh-ProfileItems {
    $cbProfile.Items.Clear()
    foreach ($it in $script:ProfileItems) {
        $label = if ($script:lang -eq 'en') { [string]$it.LabelEn } else { [string]$it.LabelRu }
        [void]$cbProfile.Items.Add($label)
    }
    if ($cbProfile.Items.Count -gt 0) {
        # По умолчанию — "Баланс"
        $cbProfile.SelectedIndex = 1
    }
}

$lblProfileHint = New-Object Windows.Forms.Label
$lblProfileHint.Left = 560; $lblProfileHint.Top = 278; $lblProfileHint.Width = 340
$lblProfileHint.Height = 34
$lblProfileHint.ForeColor = [Drawing.Color]::FromArgb(105, 105, 105)
$lblProfileHint.Font = [Drawing.Font]::new('Segoe UI', 9)

$btnRun = New-Object Windows.Forms.Button
$btnRun.Left = 730; $btnRun.Top = 332; $btnRun.Width = 170; $btnRun.Height = 34
$btnRun.FlatStyle = 'Flat'
$btnRun.BackColor = [Drawing.Color]::FromArgb(0, 122, 255)
$btnRun.ForeColor = [Drawing.Color]::White

$btnPause = New-Object Windows.Forms.Button
$btnPause.Left = 530; $btnPause.Top = 332; $btnPause.Width = 90; $btnPause.Height = 34
$btnPause.Text = 'Пауза'
$btnPause.Enabled = $false
$btnPause.FlatStyle = 'Flat'

$btnStop = New-Object Windows.Forms.Button
$btnStop.Left = 630; $btnStop.Top = 332; $btnStop.Width = 90; $btnStop.Height = 34
$btnStop.Text = 'Стоп'
$btnStop.Enabled = $false
$btnStop.FlatStyle = 'Flat'

$btnSkip = New-Object Windows.Forms.Button
$btnSkip.Left = 430; $btnSkip.Top = 332; $btnSkip.Width = 90; $btnSkip.Height = 34
$btnSkip.Text = 'Пропуск'
$btnSkip.Enabled = $false
$btnSkip.FlatStyle = 'Flat'

$btnMinimize = New-Object Windows.Forms.Button
$btnMinimize.Left = 330; $btnMinimize.Top = 332; $btnMinimize.Width = 90; $btnMinimize.Height = 34
$btnMinimize.Text = 'Свернуть'
$btnMinimize.FlatStyle = 'Flat'

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Left = 20; $lblStatus.Top = 372; $lblStatus.Width = 880
$lblStatus.Text = 'Статус: ожидание запуска'
$lblStatus.ForeColor = [Drawing.Color]::FromArgb(45, 45, 45)

$lblDiag = New-Object Windows.Forms.Label
$lblDiag.Left = 20; $lblDiag.Top = 392; $lblDiag.Width = 120
$lblDiag.Text = 'Диагностика'
$lblDiag.ForeColor = [Drawing.Color]::FromArgb(85, 85, 85)

$tbDiag = New-Object Windows.Forms.TextBox
$tbDiag.Left = 120; $tbDiag.Top = 388; $tbDiag.Width = 780; $tbDiag.Height = 24
$tbDiag.ReadOnly = $true
$tbDiag.BorderStyle = 'FixedSingle'
$tbDiag.BackColor = [Drawing.Color]::FromArgb(252, 252, 253)
$tbDiag.Text = '-'

$lblTime = New-Object Windows.Forms.Label
$lblTime.Left = 20; $lblTime.Top = 332; $lblTime.Width = 390
$lblTime.Text = 'Старт: -   Прошло: 00:00:00   ETA: -'
$lblTime.ForeColor = [Drawing.Color]::FromArgb(80, 80, 80)

$pbOverall = New-Object Windows.Forms.ProgressBar
$pbOverall.Left = 20; $pbOverall.Top = 396; $pbOverall.Width = 880; $pbOverall.Height = 18
$pbOverall.Minimum = 0; $pbOverall.Maximum = 100; $pbOverall.Value = 0

$tbLog = New-Object Windows.Forms.TextBox
$tbLog.Left = 20; $tbLog.Top = 420; $tbLog.Width = 880; $tbLog.Height = 120
$tbLog.Multiline = $true
$tbLog.ScrollBars = 'Vertical'
$tbLog.ReadOnly = $true
$tbLog.WordWrap = $false
$tbLog.Font = [Drawing.Font]::new('Consolas', 9)
$tbLog.BackColor = [Drawing.Color]::FromArgb(252, 252, 253)
$tbLog.BorderStyle = 'FixedSingle'
$form.ClientSize = [Drawing.Size]::new(920, 560)

$lineTop = New-Object Windows.Forms.Panel
$lineTop.Height = 1
$lineTop.BackColor = [Drawing.Color]::FromArgb(223, 223, 228)

$lineBottom = New-Object Windows.Forms.Panel
$lineBottom.Height = 1
$lineBottom.BackColor = [Drawing.Color]::FromArgb(223, 223, 228)

function Set-SecondaryButtonStyle([System.Windows.Forms.Button]$btn) {
    if ($null -eq $btn) { return }
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(205, 205, 210)
    $btn.BackColor = [Drawing.Color]::FromArgb(252, 252, 253)
    $btn.ForeColor = [Drawing.Color]::FromArgb(33, 33, 33)
}

function Set-PrimaryButtonStyle([System.Windows.Forms.Button]$btn) {
    if ($null -eq $btn) { return }
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = [Drawing.Color]::FromArgb(0, 122, 255)
    $btn.ForeColor = [Drawing.Color]::White
}

Set-SecondaryButtonStyle $btnRoot
Set-SecondaryButtonStyle $btnSeries
Set-SecondaryButtonStyle $btnHtml
Set-SecondaryButtonStyle $btnMinimize
Set-SecondaryButtonStyle $btnSkip
Set-SecondaryButtonStyle $btnPause
Set-SecondaryButtonStyle $btnStop
Set-PrimaryButtonStyle $btnRun

function Update-Layout {
    $pad = 20
    $gap = 10
    $browseW = 90
    $smallBtnW = 90
    $runBtnW = 170
    $rowTop = 18
    $fullW = $form.ClientSize.Width
    $fullH = $form.ClientSize.Height
    if ($fullW -lt 900 -or $fullH -lt 520) { return }

    $lblLang.Left = $pad; $lblLang.Top = $rowTop; $lblLang.Width = 90
    $cbLang.Left = 110; $cbLang.Top = ($rowTop - 4); $cbLang.Width = 100

    $rbBatch.Left = $pad; $rbBatch.Top = 58; $rbBatch.Width = 280
    $rbManual.Left = 330; $rbManual.Top = 58; $rbManual.Width = 320

    $editW = $fullW - ($pad * 2) - $browseW - $gap
    $btnX = $fullW - $pad - $browseW

    $lblRoot.Left = $pad; $lblRoot.Top = 92; $lblRoot.Width = 220
    $tbRoot.Left = $pad; $tbRoot.Top = 112; $tbRoot.Width = $editW
    $btnRoot.Left = $btnX; $btnRoot.Top = 110; $btnRoot.Width = $browseW

    $lblSeries.Left = $pad; $lblSeries.Top = 146; $lblSeries.Width = 220
    $tbSeries.Left = $pad; $tbSeries.Top = 166; $tbSeries.Width = $editW
    $btnSeries.Left = $btnX; $btnSeries.Top = 164; $btnSeries.Width = $browseW

    $lblHtml.Left = $pad; $lblHtml.Top = 200; $lblHtml.Width = 240
    $tbHtml.Left = $pad; $tbHtml.Top = 220; $tbHtml.Width = $editW
    $btnHtml.Left = $btnX; $btnHtml.Top = 218; $btnHtml.Width = $browseW

    $cbTmdb.Left = $pad; $cbTmdb.Top = 256; $cbTmdb.Width = 220
    $cbDry.Left = 260; $cbDry.Top = 256; $cbDry.Width = 280
    $cbVerify.Left = 260; $cbVerify.Top = 280; $cbVerify.Width = 280

    $cbProfile.Left = $fullW - $pad - 260; $cbProfile.Top = 254; $cbProfile.Width = 260
    $lblProfile.Left = $cbProfile.Left - 130; $lblProfile.Top = 258; $lblProfile.Width = 125
    $lblProfileHint.Left = $lblProfile.Left; $lblProfileHint.Top = 278; $lblProfileHint.Width = ($fullW - $pad - $lblProfileHint.Left); $lblProfileHint.Height = 34

    $btnRowTop = 332
    $btnRun.Left = $fullW - $pad - $runBtnW; $btnRun.Top = $btnRowTop; $btnRun.Width = $runBtnW; $btnRun.Height = 34
    $btnStop.Left = $btnRun.Left - $gap - $smallBtnW; $btnStop.Top = $btnRowTop; $btnStop.Width = $smallBtnW; $btnStop.Height = 34
    $btnPause.Left = $btnStop.Left - $gap - $smallBtnW; $btnPause.Top = $btnRowTop; $btnPause.Width = $smallBtnW; $btnPause.Height = 34
    $btnSkip.Left = $btnPause.Left - $gap - $smallBtnW; $btnSkip.Top = $btnRowTop; $btnSkip.Width = $smallBtnW; $btnSkip.Height = 34
    $btnMinimize.Left = $btnSkip.Left - $gap - $smallBtnW; $btnMinimize.Top = $btnRowTop; $btnMinimize.Width = $smallBtnW; $btnMinimize.Height = 34

    $lblTime.Left = $pad; $lblTime.Top = $btnRowTop; $lblTime.Width = [Math]::Max(220, ($btnMinimize.Left - $pad - $gap))
    $lblStatus.Left = $pad; $lblStatus.Top = 370; $lblStatus.Width = ($fullW - $pad * 2)
    $lblDiag.Left = $pad; $lblDiag.Top = 394; $lblDiag.Width = 110
    $tbDiag.Left = ($lblDiag.Left + $lblDiag.Width + 6); $tbDiag.Top = 390; $tbDiag.Width = ($fullW - $pad - $tbDiag.Left); $tbDiag.Height = 24
    $lineTop.Left = $pad; $lineTop.Top = 422; $lineTop.Width = ($fullW - $pad * 2)
    $pbOverall.Left = $pad; $pbOverall.Top = 430; $pbOverall.Width = ($fullW - $pad * 2); $pbOverall.Height = 18
    $lineBottom.Left = $pad; $lineBottom.Top = 454; $lineBottom.Width = ($fullW - $pad * 2)
    $tbLog.Left = $pad; $tbLog.Top = 462; $tbLog.Width = ($fullW - $pad * 2); $tbLog.Height = [Math]::Max(120, ($fullH - $tbLog.Top - $pad))
}

function Refresh-Texts {
    $script:s = Get-ToolkitStrings -Lang $script:lang
    $form.Text = $script:s.AppTitle
    $rbBatch.Text = $script:s.BatchMode
    $rbManual.Text = $script:s.ManualMode
    $lblRoot.Text = $script:s.RootPath
    $lblSeries.Text = $script:s.SeriesPath
    $lblHtml.Text = $script:s.HtmlPath
    $cbTmdb.Text = $script:s.UseTmdb
    $cbDry.Text = $script:s.DryRun
    $cbVerify.Text = $script:s.VerifyOnly
    $lblProfile.Text = [string]$script:s.ExecutionProfile
    $selectedValue = 'Balanced'
    if ($cbProfile.SelectedIndex -ge 0 -and $cbProfile.SelectedIndex -lt $script:ProfileItems.Count) {
        $selectedValue = [string]$script:ProfileItems[$cbProfile.SelectedIndex].Value
    }
    Refresh-ProfileItems
    for ($i = 0; $i -lt $script:ProfileItems.Count; $i++) {
        if ([string]$script:ProfileItems[$i].Value -eq $selectedValue) {
            $cbProfile.SelectedIndex = $i
            break
        }
    }
    switch ($selectedValue) {
        'Fast' { $lblProfileHint.Text = [string]$script:s.ProfileHintFast }
        'Full' { $lblProfileHint.Text = [string]$script:s.ProfileHintFull }
        default { $lblProfileHint.Text = [string]$script:s.ProfileHintBalanced }
    }
    $btnRun.Text = $script:s.Start
    $btnRoot.Text = $script:s.Browse
    $btnSeries.Text = $script:s.Browse
    $btnHtml.Text = $script:s.Browse
    $btnMinimize.Text = [string]$script:s.Minimize
    $lblDiag.Text = [string]$script:s.Diagnostics
}

$cbProfile.Add_SelectedIndexChanged({
    if ($cbProfile.SelectedIndex -lt 0 -or $cbProfile.SelectedIndex -ge $script:ProfileItems.Count) { return }
    $selectedValue = [string]$script:ProfileItems[$cbProfile.SelectedIndex].Value
    switch ($selectedValue) {
        'Fast' { $lblProfileHint.Text = [string]$script:s.ProfileHintFast }
        'Full' { $lblProfileHint.Text = [string]$script:s.ProfileHintFull }
        default { $lblProfileHint.Text = [string]$script:s.ProfileHintBalanced }
    }
})

function Pick-Folder([System.Windows.Forms.TextBox]$Target) {
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dlg.SelectedPath
    }
}

function Pick-File([System.Windows.Forms.TextBox]$Target) {
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Filter = 'HTML (*.html;*.htm)|*.html;*.htm|All files|*.*'
    if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        $Target.Text = $dlg.FileName
    }
}

function Convert-ToCliArg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    $v = [string]$Value
    if ($v -notmatch '[\s"]') { return $v }
    $v = $v -replace '\\', '\\'
    $v = $v -replace '"', '\"'
    return '"' + $v + '"'
}

function Set-UiRunningState([bool]$running) {
    $btnRun.Enabled = -not $running
    $btnPause.Enabled = $running
    $btnStop.Enabled = $running
    $btnSkip.Enabled = $running
    if (-not $running) {
        $script:IsPaused = $false
        $btnPause.Text = 'Пауза'
    }
}

function Append-LogLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    $script:LastActivityAt = Get-Date
    if ($line -match '\[LibraryProgress\s+\d+%\s+(?<i>\d+)\/(?<n>\d+)\]\s+(?<p>.+)$') {
        $script:CurrentSeriesIndex = [int]$Matches['i']
        $script:TotalSeries = [int]$Matches['n']
        $script:CurrentSeriesPath = [string]$Matches['p']
        $script:CompletedSeries = [Math]::Max(0, $script:CurrentSeriesIndex - 1)
    }
    if ($line -match '\[SeriesProgress\s+(?<pct>\d+)%') {
        $script:CurrentSeriesPercent = [int]$Matches['pct']
        if ($script:CurrentSeriesPercent -ge 100) { $script:CompletedSeries = [Math]::Max($script:CompletedSeries, $script:CurrentSeriesIndex) }
    }
    if ($line -match '\[SeriesToolkit\]\[SeriesProgress\s+\d+%\s+\d+/\d+\]\s+(?<series>.+?)\s+::\s+(?<stage>.+)$') {
        $tbDiag.Text = ("Этап: {0}" -f [string]$Matches['stage'])
    }
    if ($line -match '\[SeriesToolkit\]\[Diag\]\s+(?<series>.+?)\s+::\s+(?<msg>.+)$') {
        $tbDiag.Text = ("{0}: {1}" -f $Matches['series'], $Matches['msg'])
    }
    $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + ' ' + $line + [Environment]::NewLine)
    $tbLog.SelectionStart = $tbLog.TextLength
    $tbLog.ScrollToCaret()
    Write-GuiTrace $line
}

function Update-RunMetrics {
    if (-not $script:RunInProgress -or -not $script:StartedAt) { return }
    $elapsed = (Get-Date) - $script:StartedAt
    $elapsedTxt = '{0:00}:{1:00}:{2:00}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds

    $overallPct = 0
    if ($script:TotalSeries -gt 0) {
        $doneFloat = [double]$script:CompletedSeries
        if ($script:CurrentSeriesIndex -gt 0 -and $script:CurrentSeriesIndex -le $script:TotalSeries -and $script:CurrentSeriesPercent -ge 0 -and $script:CurrentSeriesPercent -lt 100) {
            $doneFloat = [Math]::Max($doneFloat, ($script:CurrentSeriesIndex - 1) + ($script:CurrentSeriesPercent / 100.0))
        }
        $overallPct = [int][Math]::Floor((100.0 * $doneFloat) / $script:TotalSeries)
        if ($overallPct -lt 0) { $overallPct = 0 }
        if ($overallPct -gt 100) { $overallPct = 100 }
    }
    $pbOverall.Value = $overallPct

    $eta = '-'
    if ($script:TotalSeries -gt 0 -and $script:CompletedSeries -gt 0) {
        $avgSec = $elapsed.TotalSeconds / [Math]::Max(1, $script:CompletedSeries)
        $left = [Math]::Max(0, $script:TotalSeries - $script:CompletedSeries)
        $etaDt = (Get-Date).AddSeconds($avgSec * $left)
        $eta = $etaDt.ToString('HH:mm:ss')
    }
    $startTxt = $script:StartedAt.ToString('HH:mm:ss')
    $lblTime.Text = "Старт: $startTxt   Прошло: $elapsedTxt   ETA: $eta"
}

function Complete-RunUi([int]$exitCode) {
    try {
        if ($script:UserStopped) {
            $remaining = if ($script:TotalSeries -gt 0) { [Math]::Max(0, $script:TotalSeries - $script:CompletedSeries) } else { 0 }
            $lblStatus.Text = "Статус: прервано пользователем. Выполнено: $($script:CompletedSeries), осталось: $remaining."
        } else {
            $lblStatus.Text = if ($exitCode -eq 0) { 'Статус: завершено успешно.' } else { "Статус: завершено с ошибкой (код $exitCode)." }
        }
        Append-LogLine ("Завершено. Код: {0}" -f $exitCode)
        $script:RunInProgress = $false
        $script:CurrentProcess = $null
        $script:ProgressTailPath = $null
        $script:ProgressTailOffset = 0L
        Set-UiRunningState $false
        if ($script:UserStopped) {
            [Windows.Forms.MessageBox]::Show($lblStatus.Text, $script:s.Done, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        } elseif ($exitCode -eq 0) {
            $res = [Windows.Forms.MessageBox]::Show($script:s.DoneOpenLog, $script:s.Done, [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information)
            if ($res -eq [Windows.Forms.DialogResult]::Yes) {
                $logPath = Join-Path $ToolkitRoot 'LOGS'
                if (-not [string]::IsNullOrWhiteSpace($logPath) -and (Test-Path -LiteralPath $logPath)) {
                    Start-Process -FilePath explorer.exe -ArgumentList $logPath
                }
            }
        } else {
            [Windows.Forms.MessageBox]::Show("Запуск завершился с ошибкой (код $exitCode).", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    } catch {
        $script:RunInProgress = $false
        $script:CurrentProcess = $null
        $script:ProgressTailPath = $null
        $script:ProgressTailOffset = 0L
        Set-UiRunningState $false
        try { Append-LogLine ("[ERR] UI finalize failed: " + $_.Exception.Message) } catch { }
    }
}

$btnRoot.Add_Click({ Pick-Folder $tbRoot })
$btnSeries.Add_Click({ Pick-Folder $tbSeries })
$btnHtml.Add_Click({ Pick-File $tbHtml })

$cbLang.Add_SelectedIndexChanged({
    $script:lang = if ($cbLang.SelectedIndex -eq 1) { 'en' } else { 'ru' }
    Refresh-Texts
})

$cbVerify.Add_CheckedChanged({
    if ($cbVerify.Checked) {
        $cbDry.Checked = $true
        $cbDry.Enabled = $false
    } else {
        $cbDry.Enabled = $true
    }
})

$btnPause.Add_Click({
    if (-not $script:RunInProgress -or -not $script:CurrentProcess) { return }
    try {
        if (-not $script:IsPaused) {
            [void][ProcControl]::NtSuspendProcess($script:CurrentProcess.Handle)
            $script:IsPaused = $true
            $btnPause.Text = 'Продолжить'
            $lblStatus.Text = 'Статус: пауза.'
            $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + " Пауза." + [Environment]::NewLine)
        } else {
            [void][ProcControl]::NtResumeProcess($script:CurrentProcess.Handle)
            $script:IsPaused = $false
            $btnPause.Text = 'Пауза'
            $lblStatus.Text = 'Статус: выполняется...'
            $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + " Продолжено." + [Environment]::NewLine)
        }
    } catch {
        [Windows.Forms.MessageBox]::Show("Не удалось сменить состояние паузы: $($_.Exception.Message)", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnStop.Add_Click({
    if (-not $script:RunInProgress -or -not $script:CurrentProcess) { return }
    try {
        $script:UserStopped = $true
        $script:CurrentProcess.Kill()
        $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + " Остановлено пользователем." + [Environment]::NewLine)
        $lblStatus.Text = 'Статус: прервано пользователем.'
    } catch {
        [Windows.Forms.MessageBox]::Show("Не удалось остановить процесс: $($_.Exception.Message)", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnSkip.Add_Click({
    if (-not $script:RunInProgress) { return }
    if ([string]::IsNullOrWhiteSpace($script:CurrentSeriesPath)) { return }
    try {
        Add-Content -LiteralPath $script:SkipSignalFile -Value $script:CurrentSeriesPath -Encoding UTF8
        Append-LogLine ("[SeriesToolkit][GUI] Запрошен пропуск: " + $script:CurrentSeriesPath)
    } catch {
        [Windows.Forms.MessageBox]::Show("Не удалось отправить запрос пропуска: $($_.Exception.Message)", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnMinimize.Add_Click({
    try {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    } catch { }
})

$btnRun.Add_Click({
    try {
        if ($script:RunInProgress) { return }
        Write-GuiTrace 'Run button clicked.'
        $script:RunInProgress = $true
        $script:UserStopped = $false
        $script:StartedAt = Get-Date
        $script:TotalSeries = 0
        $script:CurrentSeriesIndex = 0
        $script:CurrentSeriesPercent = 0
        $script:CompletedSeries = 0
        $script:CurrentSeriesPath = ''
        $pbOverall.Value = 0
        if (Test-Path -LiteralPath $script:SkipSignalFile) { Remove-Item -LiteralPath $script:SkipSignalFile -Force -ErrorAction SilentlyContinue }
        Set-UiRunningState $true
        $tbLog.Clear()
        $tbDiag.Text = '-'
        $script:LastActivityAt = Get-Date
        Append-LogLine "Запуск..."
        $lblStatus.Text = 'Статус: выполняется...'
        if ([string]::IsNullOrWhiteSpace($enginePath) -or -not (Test-Path -LiteralPath $enginePath)) {
            throw "Не найден SeriesToolkit.ps1: $enginePath"
        }
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
        $argList = [System.Collections.Generic.List[string]]::new()
        function Add-Args([System.Collections.Generic.List[string]]$List, [string[]]$Items) {
            foreach ($it in $Items) { [void]$List.Add([string]$it) }
        }
        Add-Args $argList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $enginePath, '-SkipAutoVersion', '-SkipAutoBuildExe', '-SkipAutoSync')
        if ($rbManual.Checked) {
            $sp = $tbSeries.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($sp)) { throw 'Укажите папку одного сериала (Manual).' }
            Add-Args $argList @('-Mode', 'Manual', '-SeriesPath', $sp)
        } else {
            $rp = $tbRoot.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($rp)) { throw 'Укажите корень библиотеки (Batch).' }
            Add-Args $argList @('-Mode', 'Batch', '-RootPath', $rp)
        }
        if (-not [string]::IsNullOrWhiteSpace($tbHtml.Text)) {
            Add-Args $argList @('-HtmlPath', $tbHtml.Text.Trim())
        }
        if ($cbTmdb.Checked) { [void]$argList.Add('-UseTmdb') }
        if ($cbVerify.Checked) { [void]$argList.Add('-VerifyOnly') }
        if ($cbProfile.SelectedItem) {
            $profileValue = 'Balanced'
            if ($cbProfile.SelectedIndex -ge 0 -and $cbProfile.SelectedIndex -lt $script:ProfileItems.Count) {
                $profileValue = [string]$script:ProfileItems[$cbProfile.SelectedIndex].Value
            }
            Add-Args $argList @('-ExecutionProfile', $profileValue)
        }
        if ($cbDry.Checked) { [void]$argList.Add('-DryRun') } else { [void]$argList.Add('-Apply') }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $psExe
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        $psi.CreateNoWindow = $true
        $quotedArgs = @($argList.ToArray() | ForEach-Object { Convert-ToCliArg $_ })
        $psi.Arguments = ($quotedArgs -join ' ')
        $progressPath = Join-Path $ToolkitRoot ('LOGS\gui-progress-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        try { Set-Content -LiteralPath $progressPath -Value '' -Encoding UTF8 } catch { }
        $script:ProgressTailPath = $progressPath
        $script:ProgressTailOffset = 0L
        $psi.EnvironmentVariables['SERIESTOOLKIT_PROGRESS_LOG'] = $progressPath
        $psi.EnvironmentVariables['SERIESTOOLKIT_SKIP_FILE'] = $script:SkipSignalFile
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $script:CurrentProcess = $proc
        $drop = $null
        while ($script:LogQueue.TryDequeue([ref]$drop)) { }
        [void]$proc.Start()
        Write-GuiTrace ('Child started. PID=' + $proc.Id)
        Write-GuiTrace ('Progress tail file: ' + $progressPath)
    } catch {
        $lblStatus.Text = 'Статус: ошибка.'
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$form.Controls.AddRange(@($lblLang, $cbLang, $rbBatch, $rbManual, $lblRoot, $tbRoot, $btnRoot, $lblSeries, $tbSeries, $btnSeries, $lblHtml, $tbHtml, $btnHtml, $cbTmdb, $cbDry, $cbVerify, $lblProfile, $cbProfile, $lblProfileHint, $lblTime, $btnMinimize, $btnSkip, $btnPause, $btnStop, $btnRun, $lblStatus, $lblDiag, $tbDiag, $lineTop, $pbOverall, $lineBottom, $tbLog))
$form.Add_Shown({ Update-Layout })
$form.Add_SizeChanged({ Update-Layout })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    try {
        if ($script:RunInProgress -and -not [string]::IsNullOrWhiteSpace($script:ProgressTailPath) -and (Test-Path -LiteralPath $script:ProgressTailPath)) {
            $fs = $null
            $sr = $null
            try {
                $fs = [System.IO.File]::Open($script:ProgressTailPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
                if ($script:ProgressTailOffset -lt 0 -or $script:ProgressTailOffset -gt $fs.Length) { $script:ProgressTailOffset = 0L }
                $fs.Seek($script:ProgressTailOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.UTF8Encoding]::new($false), $true, 4096, $true)
                while (-not $sr.EndOfStream) {
                    $ln = $sr.ReadLine()
                    if (-not [string]::IsNullOrWhiteSpace($ln)) { $script:LogQueue.Enqueue([string]$ln) }
                }
                $script:ProgressTailOffset = $fs.Position
            } catch [System.IO.IOException] {
                # Файл прогресса может быть кратковременно залочен записью; пропускаем тик.
                $fs = $null
                $sr = $null
            } finally {
                if ($sr) { $sr.Dispose() }
                if ($fs) { $fs.Dispose() }
            }
        }
        $line = $null
        while ($script:LogQueue.TryDequeue([ref]$line)) {
            Append-LogLine $line
        }
        Update-RunMetrics
        if ($script:RunInProgress -and -not $script:UserStopped) {
            $idle = [int]((Get-Date) - $script:LastActivityAt).TotalSeconds
            $lblStatus.Text = "Статус: выполняется... (последняя активность ${idle}с назад)"
        }
        if ($script:RunInProgress -and $script:CurrentProcess -and $script:CurrentProcess.HasExited) {
            Complete-RunUi $script:CurrentProcess.ExitCode
        }
    } catch {
        try { Append-LogLine ("[ERR] Timer tick failed: " + $_.Exception.Message) } catch { }
    }
})
$timer.Start()
$null = [System.AppDomain]::CurrentDomain.add_UnhandledException({
    try {
        $exObj = $_.ExceptionObject
        $msg = if ($exObj -and $exObj -is [Exception]) { $exObj.ToString() } else { [string]$exObj }
        Write-GuiTrace ('[FATAL] UnhandledException: ' + $msg)
        [Windows.Forms.MessageBox]::Show("Критическая ошибка GUI. Подробности в логе: $script:GuiLogPath", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch { }
})
$form.Add_Load({
    [System.Windows.Forms.Application]::add_ThreadException({
        try {
            $msg = if ($_.Exception) { $_.Exception.Message } else { 'Unknown UI exception' }
            Append-LogLine ("[ERR] Unhandled UI exception: " + $msg)
            $lblStatus.Text = 'Статус: ошибка.'
        } catch { }
    })
})
$form.Add_FormClosing({
    $reason = [string]$_.CloseReason
    Write-GuiTrace ('FormClosing requested. Reason=' + $reason)
    if ($script:RunInProgress) {
        $_.Cancel = $true
        [Windows.Forms.MessageBox]::Show('Идёт выполнение. Дождитесь завершения процесса.', $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        Write-GuiTrace 'FormClosing cancelled: run in progress.'
        return
    }
    if (-not $script:AllowClose) {
        if ($_.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $ans = [Windows.Forms.MessageBox]::Show('Закрыть окно SeriesToolkit?', $script:s.AppTitle, [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
            if ($ans -ne [Windows.Forms.DialogResult]::Yes) {
                $_.Cancel = $true
                Write-GuiTrace 'FormClosing cancelled by user.'
                return
            }
            $script:AllowClose = $true
            Write-GuiTrace 'FormClosing confirmed by user.'
        } else {
            $_.Cancel = $true
            Write-GuiTrace ('FormClosing blocked for non-user reason: ' + $reason)
            return
        }
    }
})
Refresh-Texts
Update-Layout
[void]$form.ShowDialog()
Write-GuiTrace 'GUI closed.'

