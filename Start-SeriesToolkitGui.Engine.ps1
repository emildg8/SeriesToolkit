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

$btnPause = New-Object Windows.Forms.Button
$btnPause.Left = 360; $btnPause.Top = 292; $btnPause.Width = 90; $btnPause.Height = 34
$btnPause.Text = 'Пауза'
$btnPause.Enabled = $false

$btnStop = New-Object Windows.Forms.Button
$btnStop.Left = 460; $btnStop.Top = 292; $btnStop.Width = 90; $btnStop.Height = 34
$btnStop.Text = 'Стоп'
$btnStop.Enabled = $false

$lblStatus = New-Object Windows.Forms.Label
$lblStatus.Left = 20; $lblStatus.Top = 300; $lblStatus.Width = 520
$lblStatus.Text = 'Статус: ожидание запуска'

$tbLog = New-Object Windows.Forms.TextBox
$tbLog.Left = 20; $tbLog.Top = 330; $tbLog.Width = 720; $tbLog.Height = 120
$tbLog.Multiline = $true
$tbLog.ScrollBars = 'Vertical'
$tbLog.ReadOnly = $true
$tbLog.WordWrap = $false
$tbLog.Font = [Drawing.Font]::new('Consolas', 9)
$form.ClientSize = [Drawing.Size]::new(760, 470)

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
    if (-not $running) {
        $script:IsPaused = $false
        $btnPause.Text = 'Пауза'
    }
}

function Append-LogLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    $script:LastActivityAt = Get-Date
    $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + ' ' + $line + [Environment]::NewLine)
    $tbLog.SelectionStart = $tbLog.TextLength
    $tbLog.ScrollToCaret()
    Write-GuiTrace $line
}

function Complete-RunUi([int]$exitCode) {
    try {
        $lblStatus.Text = if ($exitCode -eq 0) { 'Статус: завершено успешно.' } else { "Статус: завершено с ошибкой (код $exitCode)." }
        Append-LogLine ("Завершено. Код: {0}" -f $exitCode)
        $script:RunInProgress = $false
        $script:CurrentProcess = $null
        $script:ProgressTailPath = $null
        $script:ProgressTailOffset = 0L
        Set-UiRunningState $false
        if ($exitCode -eq 0) {
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
        $script:CurrentProcess.Kill()
        $tbLog.AppendText((Get-Date -Format 'HH:mm:ss') + " Остановлено пользователем." + [Environment]::NewLine)
        $lblStatus.Text = 'Статус: остановлено.'
    } catch {
        [Windows.Forms.MessageBox]::Show("Не удалось остановить процесс: $($_.Exception.Message)", $script:s.Error, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnRun.Add_Click({
    try {
        if ($script:RunInProgress) { return }
        Write-GuiTrace 'Run button clicked.'
        $script:RunInProgress = $true
        Set-UiRunningState $true
        $tbLog.Clear()
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

$form.Controls.AddRange(@($lblLang, $cbLang, $rbBatch, $rbManual, $lblRoot, $tbRoot, $btnRoot, $lblSeries, $tbSeries, $btnSeries, $lblHtml, $tbHtml, $btnHtml, $cbTmdb, $cbDry, $btnPause, $btnStop, $btnRun, $lblStatus, $tbLog))
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
        if ($script:RunInProgress) {
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
[void]$form.ShowDialog()
Write-GuiTrace 'GUI closed.'

