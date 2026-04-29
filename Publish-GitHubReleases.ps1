#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PublishRepoPath = 'D:/Dev/Script_Rename_ALLVideo/.publish/SeriesToolkit',
    [string]$Repo = 'emildg8/SeriesToolkit',
    [string]$OutputDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$gh = 'C:/Program Files/GitHub CLI/gh.exe'
if (-not (Test-Path -LiteralPath $gh)) { throw "gh not found: $gh" }
if (-not (Test-Path -LiteralPath $PublishRepoPath)) { throw "publish repo not found: $PublishRepoPath" }

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot 'RELEASES'
}
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$tags = @(
    @{ Tag = 'v0.0.1'; Commit = '6ada686'; Title = 'SeriesToolkit 0.0.1' },
    @{ Tag = 'v0.0.3'; Commit = '95c32ca'; Title = 'SeriesToolkit 0.0.3' },
    @{ Tag = 'v0.0.4'; Commit = '5ecc839'; Title = 'SeriesToolkit 0.0.4' }
)

foreach ($t in $tags) {
    $exists = (git -C $PublishRepoPath tag --list $t.Tag)
    if ([string]::IsNullOrWhiteSpace($exists)) {
        git -C $PublishRepoPath tag $t.Tag $t.Commit
    }
}

git -C $PublishRepoPath push origin --tags

foreach ($t in $tags) {
    $zip = Join-Path $OutputDir ("SeriesToolkit-{0}.zip" -f $t.Tag.TrimStart('v'))
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    git -C $PublishRepoPath archive --format=zip --output="$zip" $t.Tag

    $body = @"
Стабильный снимок версии `$($t.Tag.TrimStart('v'))`.

Состав релиза:
- исходники toolkit;
- README и CHANGELOG в состоянии этой версии;
- архив для быстрого отката.
"@

    & $gh release view $t.Tag -R $Repo *> $null
    if ($LASTEXITCODE -eq 0) {
        & $gh release upload $t.Tag $zip -R $Repo --clobber
    } else {
        & $gh release create $t.Tag $zip -R $Repo --title $t.Title --notes $body
    }
}

Write-Host 'GitHub releases are ready.'
