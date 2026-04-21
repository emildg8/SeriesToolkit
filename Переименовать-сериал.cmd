@echo off
setlocal
rem Copy only this file into the series folder. Toolkit path: set user env RENAME_VIDEO_TOOLKIT (once).
set "TOOLKIT=%RENAME_VIDEO_TOOLKIT%"
if "%TOOLKIT%"=="" set "TOOLKIT=D:\Dev\Script_Rename_ALLVideo"
rem after %~dp0 add dot: trailing backslash can break cmd quoting; PowerShell normalizes "\." in Normalize-SeriesRootPath
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TOOLKIT%\Script_Rename_ALLVideo_0.4.8.ps1" -RootPath "%~dp0." %*
