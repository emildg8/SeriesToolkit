#requires -Version 5.1
<#
.SYNOPSIS
  Заготовка зеркалирования MediaInboxToolkit на GitHub (отдельный репозиторий или ветка).
.DESCRIPTION
  Настройте параметры ниже под свой remote. По умолчанию скрипт только проверяет наличие каталога публикации.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PublishRepoPath = ''
)

Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($PublishRepoPath)) {
    Write-Host '[MediaInboxToolkit] Sync-GitHub: задайте -PublishRepoPath к клону зеркала или добавьте логику копирования.'
    return
}
Write-Host "[MediaInboxToolkit] Publish root: $PublishRepoPath (реализуйте копирование файлов по образцу SeriesToolkit/Sync-GitHub.ps1)."
