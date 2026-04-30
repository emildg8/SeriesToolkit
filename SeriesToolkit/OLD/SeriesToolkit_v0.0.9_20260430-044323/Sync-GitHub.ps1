#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$PublishRepoPath = 'D:/Dev/Script_Rename_ALLVideo/.publish/SeriesToolkit',
    [string]$GitHubRepo = 'emildg8/SeriesToolkit',
    [string]$GistId = '2bf8d27559d9caf2abaa15bfe5c97ac6',
    [string]$SecondaryRemoteName = '',
    [string]$SecondaryRemoteUrl = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$gh = 'C:/Program Files/GitHub CLI/gh.exe'
if (-not (Test-Path -LiteralPath $gh)) { return }

if (-not (Test-Path -LiteralPath $PublishRepoPath)) {
    New-Item -ItemType Directory -Path $PublishRepoPath -Force | Out-Null
    git init "$PublishRepoPath" | Out-Null
}

Copy-Item -Path (Join-Path $ProjectRoot '*') -Destination $PublishRepoPath -Recurse -Force
$parentFetch = Join-Path (Split-Path -Parent $ProjectRoot) 'Fetch-VideoMetadata.ps1'
if (Test-Path -LiteralPath $parentFetch) {
    Copy-Item -LiteralPath $parentFetch -Destination (Join-Path $PublishRepoPath 'Fetch-VideoMetadata.ps1') -Force
}
if (Test-Path -LiteralPath (Join-Path $PublishRepoPath 'LOGS')) {
    Remove-Item -LiteralPath (Join-Path $PublishRepoPath 'LOGS') -Recurse -Force
}
if (Test-Path -LiteralPath (Join-Path $PublishRepoPath 'OLD')) {
    Remove-Item -LiteralPath (Join-Path $PublishRepoPath 'OLD') -Recurse -Force
}

$version = 'unknown'
try {
    $v = Get-Content -LiteralPath (Join-Path $ProjectRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $version = [string]$v.version
} catch { }

git -C "$PublishRepoPath" add . | Out-Null
$changes = (git -C "$PublishRepoPath" status --porcelain)
if (-not [string]::IsNullOrWhiteSpace($changes)) {
    git -C "$PublishRepoPath" commit -m "Auto sync SeriesToolkit v$version" | Out-Null
    $remote = (git -C "$PublishRepoPath" remote)
    if ([string]::IsNullOrWhiteSpace($remote)) {
        try { & $gh repo view $GitHubRepo | Out-Null; git -C "$PublishRepoPath" remote add origin "https://github.com/$GitHubRepo.git" } catch { }
    } else {
        try { git -C "$PublishRepoPath" remote set-url origin "https://github.com/$GitHubRepo.git" } catch { }
    }
    git -C "$PublishRepoPath" push -u origin master | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SecondaryRemoteUrl) -and -not [string]::IsNullOrWhiteSpace($SecondaryRemoteName)) {
        $remotes = @((git -C "$PublishRepoPath" remote) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($remotes -notcontains $SecondaryRemoteName) {
            git -C "$PublishRepoPath" remote add $SecondaryRemoteName $SecondaryRemoteUrl
        } else {
            git -C "$PublishRepoPath" remote set-url $SecondaryRemoteName $SecondaryRemoteUrl
        }
        git -C "$PublishRepoPath" push -u $SecondaryRemoteName master | Out-Null
    }
}

# Обновляем gist: если edit не получится, создаём новый.
try {
    & $gh gist create `
        (Join-Path $ProjectRoot 'README.md') `
        (Join-Path $ProjectRoot 'CHANGELOG.md') `
        (Join-Path $ProjectRoot 'version.json') `
        (Join-Path $ProjectRoot 'SeriesToolkit.ps1') `
        (Join-Path $ProjectRoot 'SeriesToolkit.Engine.ps1') `
        (Join-Path $ProjectRoot 'Start-SeriesToolkitGui.ps1') `
        (Join-Path $ProjectRoot 'Start-SeriesToolkitGui.Engine.ps1') `
        (Join-Path $ProjectRoot 'UiStrings.ps1') `
        (Join-Path $ProjectRoot 'Bump-Version.ps1') `
        --desc "SeriesToolkit auto-sync v$version" | Out-Null
} catch { }
