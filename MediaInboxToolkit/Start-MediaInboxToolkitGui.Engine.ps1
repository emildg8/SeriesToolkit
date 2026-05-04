#requires -Version 5.1
# Минимальный GUI (MVP): пути, DryRun/Apply/UseTmdb, запуск MediaInboxToolkit.ps1.
[CmdletBinding()]
param(
    [string]$ToolkitRoot = ''
)

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch { }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolkitRoot)) {
    $ToolkitRoot = $PSScriptRoot
}
$ToolkitRoot = $ToolkitRoot.Trim().TrimEnd('\', '/')
$launcher = Join-Path $ToolkitRoot 'MediaInboxToolkit.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "MediaInboxToolkit.ps1 not found: $launcher"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'MediaInboxToolkit'
$form.Size = New-Object System.Drawing.Size(560, 420)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$y = 16
$lblIn = New-Object System.Windows.Forms.Label
$lblIn.Text = 'Inbox (папка с загрузками):'
$lblIn.Location = New-Object System.Drawing.Point(16, $y)
$lblIn.AutoSize = $true
$form.Controls.Add($lblIn)
$y += 28
$tbInbox = New-Object System.Windows.Forms.TextBox
$tbInbox.Location = New-Object System.Drawing.Point(16, $y)
$tbInbox.Size = New-Object System.Drawing.Size(500, 24)
$form.Controls.Add($tbInbox)
$y += 40
$lblPol = New-Object System.Windows.Forms.Label
$lblPol.Text = 'Политика JSON (пусто = sort-inbox.example.json):'
$lblPol.Location = New-Object System.Drawing.Point(16, $y)
$lblPol.AutoSize = $true
$form.Controls.Add($lblPol)
$y += 28
$tbPolicy = New-Object System.Windows.Forms.TextBox
$tbPolicy.Location = New-Object System.Drawing.Point(16, $y)
$tbPolicy.Size = New-Object System.Drawing.Size(500, 24)
$tbPolicy.Text = (Join-Path $ToolkitRoot 'sort-inbox.example.json')
$form.Controls.Add($tbPolicy)
$y += 44
$cbTmdb = New-Object System.Windows.Forms.CheckBox
$cbTmdb.Text = 'UseTmdb (TMDB_API_KEY)'
$cbTmdb.Location = New-Object System.Drawing.Point(16, $y)
$cbTmdb.AutoSize = $true
$form.Controls.Add($cbTmdb)
$y += 32
$cbDry = New-Object System.Windows.Forms.CheckBox
$cbDry.Text = 'DryRun (только план, без переноса)'
$cbDry.Checked = $true
$cbDry.Location = New-Object System.Drawing.Point(16, $y)
$cbDry.AutoSize = $true
$form.Controls.Add($cbDry)
$y += 32
$cbApply = New-Object System.Windows.Forms.CheckBox
$cbApply.Text = 'Apply (перенос файлов)'
$cbApply.Location = New-Object System.Drawing.Point(16, $y)
$cbApply.AutoSize = $true
$form.Controls.Add($cbApply)
$y += 44
$btn = New-Object System.Windows.Forms.Button
$btn.Text = 'Запустить'
$btn.Location = New-Object System.Drawing.Point(16, $y)
$btn.Size = New-Object System.Drawing.Size(120, 32)
$form.Controls.Add($btn)
$y += 48
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Location = New-Object System.Drawing.Point(16, $y)
$txtLog.Size = New-Object System.Drawing.Size(500, 120)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog)

$btn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($tbInbox.Text)) {
            [System.Windows.Forms.MessageBox]::Show('Укажите путь к inbox.', 'MediaInboxToolkit') | Out-Null
            return
        }
        $pol = $tbPolicy.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($pol)) {
            $pol = Join-Path $ToolkitRoot 'sort-inbox.example.json'
        }
        $args = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcher,
            '-InboxPath', $tbInbox.Text.Trim(),
            '-PolicyPath', $pol,
            '-SkipAutoSync'
        )
        if ($cbTmdb.Checked) { $args += '-UseTmdb' }
        if ($cbApply.Checked) { $args += '-Apply' }
        elseif ($cbDry.Checked) { $args += '-DryRun' }
        $argLine = ($args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
        $txtLog.Text = "Запуск: powershell $argLine`r`n..."
        [System.Windows.Forms.Application]::DoEvents()
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -Wait -NoNewWindow `
                -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
            $code = $p.ExitCode
            $so = if (Test-Path -LiteralPath $tmpOut) { Get-Content -LiteralPath $tmpOut -Raw -Encoding UTF8 } else { '' }
            $se = if (Test-Path -LiteralPath $tmpErr) { Get-Content -LiteralPath $tmpErr -Raw -Encoding UTF8 } else { '' }
            $txtLog.Text = "Exit: $code`r`n$so`r`n$se"
        } catch {
            $txtLog.Text = 'Ошибка: ' + $_.Exception.Message
        } finally {
            Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $tmpErr -Force -ErrorAction SilentlyContinue
        }
    })

[System.Windows.Forms.Application]::Run($form)
