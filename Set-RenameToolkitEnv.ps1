#requires -Version 5.1
# Run once: sets user env RENAME_VIDEO_TOOLKIT to this toolkit folder (current script directory).
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
[Environment]::SetEnvironmentVariable('RENAME_VIDEO_TOOLKIT', $dir, 'User')
Write-Host "User env RENAME_VIDEO_TOOLKIT=$dir"
Write-Host 'Open a new CMD/PowerShell window so %%RENAME_VIDEO_TOOLKIT%% is visible to batch files.'
