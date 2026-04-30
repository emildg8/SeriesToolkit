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
. $uiPath

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$lang = 'ru'
$s = Get-ToolkitStrings -Lang $lang

$form = New-Object Windows.Forms.Form
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(248, 248, 250)
$form.Font = [Drawing.Font]::new('Segoe UI', 9.5)
$form.ClientSize = [Drawing.Size]::new(760, 360)

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
$tbRoot.Left = 20; $tbRoot.Top = 112; $tbRoot.Width = 620
$tbRoot.Text = '\\Emilian_TNAS\emildg8\Video\Мультсериалы'
$btnRoot = New-Object Windows.Forms.Button
$btnRoot.Left = 650; $btnRoot.Top = 110; $btnRoot.Width = 90

$lblSeries = New-Object Windows.Forms.Label
$lblSeries.Left = 20; $lblSeries.Top = 146; $lblSeries.Width = 180
$tbSeries = New-Object Windows.Forms.TextBox
$tbSeries.Left = 20; $tbSeries.Top = 166; $tbSeries.Width = 620
$btnSeries = New-Object Windows.Forms.Button
$btnSeries.Left = 650; $btnSeries.Top = 164; $btnSeries.Width = 90

$lblHtml = New-Object Windows.Forms.Label
$lblHtml.Left = 20; $lblHtml.Top = 200; $lblHtml.Width = 210
$tbHtml = New-Object Windows.Forms.TextBox
$tbHtml.Left = 20; $tbHtml.Top = 220; $tbHtml.Width = 620
$btnHtml = New-Object Windows.Forms.Button
$btnHtml.Left = 650; $btnHtml.Top = 218; $btnHtml.Width = 90

$cbTmdb = New-Object Windows.Forms.CheckBox
$cbTmdb.Left = 20; $cbTmdb.Top = 256; $cbTmdb.Width = 220
$cbDry = New-Object Windows.Forms.CheckBox
$cbDry.Left = 260; $cbDry.Top = 256; $cbDry.Width = 280
$cbDry.Checked = $true

$btnRun = New-Object Windows.Forms.Button
$btnRun.Left = 560; $btnRun.Top = 292; $btnRun.Width = 180; $btnRun.Height = 34
$btnRun.FlatStyle = 'Flat'
$btnRun.BackColor = [Drawing.Color]::FromArgb(0, 122, 255)
$btnRun.ForeColor = [Drawing.Color]::White

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
    $btnRun.Text = $script:s.Start
    $btnRoot.Text = $script:s.Browse
    $btnSeries.Text = $script:s.Browse
    $btnHtml.Text = $script:s.Browse
}

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

$btnRoot.Add_Click({ Pick-Folder $tbRoot })
$btnSeries.Add_Click({ Pick-Folder $tbSeries })
$btnHtml.Add_Click({ Pick-File $tbHtml })

$cbLang.Add_SelectedIndexChanged({
    $script:lang = if ($cbLang.SelectedIndex -eq 1) { 'en' } else { 'ru' }
    Refresh-Texts
})

$btnRun.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($enginePath) -or -not (Test-Path -LiteralPath $enginePath)) {
            throw "Не найден SeriesToolkit.ps1: $enginePath"
        }
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
        $argList = [System.Collections.Generic.List[string]]::new()
        [void]$argList.AddRange(@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $enginePath))
        if ($rbManual.Checked) {
            $sp = $tbSeries.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($sp)) { throw 'Укажите папку одного сериала (Manual).' }
            [void]$argList.AddRange(@('-Mode', 'Manual', '-SeriesPath', $sp))
        } else {
            $rp = $tbRoot.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($rp)) { throw 'Укажите корень библиотеки (Batch).' }
            [void]$argList.AddRange(@('-Mode', 'Batch', '-RootPath', $rp))
        }
        if (-not [string]::IsNullOrWhiteSpace($tbHtml.Text)) {
            [void]$argList.AddRange(@('-HtmlPath', $tbHtml.Text.Trim()))
        }
        if ($cbTmdb.Checked) { [void]$argList.Add('-UseTmdb') }
        if ($cbDry.Checked) { [void]$argList.Add('-DryRun') } else { [void]$argList.Add('-Apply') }

        & $psExe @($argList.ToArray())
        $res = [Windows.Forms.MessageBox]::Show($script:s.DoneOpenLog, $script:s.Done, [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information)
        if ($res -eq [Windows.Forms.DialogResult]::Yes) {
            $logPath = Join-Path $ToolkitRoot 'LOGS'
            if (-not [string]::IsNullOrWhiteSpace($logPath) -and (Test-Path -LiteralPath $logPath)) {
                Start-Process -FilePath explorer.exe -ArgumentList $logPath
            }
        }
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$form.Controls.AddRange(@($lblLang, $cbLang, $rbBatch, $rbManual, $lblRoot, $tbRoot, $btnRoot, $lblSeries, $tbSeries, $btnSeries, $lblHtml, $tbHtml, $btnHtml, $cbTmdb, $cbDry, $btnRun))
Refresh-Texts
[void]$form.ShowDialog()

