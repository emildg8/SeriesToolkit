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

function Ensure-OriginRemote {
    $remote = (git -C "$PublishRepoPath" remote)
    if ([string]::IsNullOrWhiteSpace($remote)) {
        try { & $gh repo view $GitHubRepo | Out-Null; git -C "$PublishRepoPath" remote add origin "https://github.com/$GitHubRepo.git" } catch { }
    } else {
        try { git -C "$PublishRepoPath" remote set-url origin "https://github.com/$GitHubRepo.git" } catch { }
    }
}

function Invoke-GhOrThrow {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$ErrorContext = 'gh command failed'
    )
    & $gh @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorContext (exit code $LASTEXITCODE): gh $($Arguments -join ' ')"
    }
}

function Test-GhReleaseExists {
    param(
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$Repo
    )
    try {
        & $gh release view $Tag -R $Repo 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-ReleaseNotesFromChangelog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Version
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $lines = @($raw -split "`r?`n")
    $header = "## $Version"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith($header, [System.StringComparison]::Ordinal)) {
            $start = $i + 1
            break
        }
    }
    if ($start -lt 0) { return $null }
    $items = [System.Collections.Generic.List[string]]::new()
    for ($j = $start; $j -lt $lines.Count; $j++) {
        $ln = [string]$lines[$j]
        if ($ln -match '^##\s+') { break }
        if ($ln -match '^\s*-\s+') { [void]$items.Add($ln.Trim()) }
    }
    if ($items.Count -eq 0) { return $null }
    $body = @(
        "Что добавлено и улучшено в версии ${Version}:",
        ''
    ) + @($items)
    return ($body -join [Environment]::NewLine)
}

$allowedFiles = @(
    'Build-SeriesToolkitExe.ps1',
    'Bump-Version.ps1',
    'CHANGELOG.md',
    'README.md',
    'SeriesToolkit.Engine.ps1',
    'SeriesToolkit.ps1',
    'SeriesToolkit.settings.example.json',
    'SeriesToolkit.settings.README.md',
    'series-aliases.example.json',
    'Start-SeriesToolkitGui.Engine.ps1',
    'Start-SeriesToolkitGui.ps1',
    'Sync-GitHub.ps1',
    'UiStrings.ps1',
    'version.json'
)
$allowedDirs = @('assets', 'docs')
foreach ($name in $allowedFiles) {
    $src = Join-Path $ProjectRoot $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $PublishRepoPath $name) -Force
    }
}
foreach ($dirName in $allowedDirs) {
    $srcDir = Join-Path $ProjectRoot $dirName
    if (Test-Path -LiteralPath $srcDir) {
        Copy-Item -LiteralPath $srcDir -Destination (Join-Path $PublishRepoPath $dirName) -Recurse -Force
    }
}
# Секреты только локально — никогда не публиковать на GitHub
foreach ($secret in @('SeriesToolkit.settings.json', '.env', 'secrets.json', 'tmdb.key', 'kinopoisk.cookie.txt')) {
    $sp = Join-Path $PublishRepoPath $secret
    if (Test-Path -LiteralPath $sp) { Remove-Item -LiteralPath $sp -Force }
}
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
foreach ($extra in @(
    'CartoonSeriesToolkit.ps1',
    'Start-CartoonSeriesToolkitGui.ps1',
    'Publish-GitHubReleases.ps1',
    '_make-icon.ps1',
    'SeriesToolkit.GUI.exe.bak',
    'SeriesToolkit.GUI.new.exe',
    'SeriesToolkit.GUI.new.exe.bak'
)) {
    $p = Join-Path $PublishRepoPath $extra
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
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
    Ensure-OriginRemote
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

# Автоматический релиз текущей версии (tag + release + zip asset)
if ($version -match '^\d+\.\d+\.\d+$') {
    Ensure-OriginRemote
    $tag = "v$version"
    $head = (git -C "$PublishRepoPath" rev-parse HEAD).Trim()
    $existsTag = (git -C "$PublishRepoPath" tag --list $tag)
    if ([string]::IsNullOrWhiteSpace($existsTag)) {
        git -C "$PublishRepoPath" tag $tag $head
    }
    git -C "$PublishRepoPath" push origin $tag | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # Разрешаем сценарий, когда tag уже существует в remote.
        git -C "$PublishRepoPath" fetch --tags origin | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Не удалось обновить теги из origin." }
    }

    $releasesDir = Join-Path $ProjectRoot 'RELEASES'
    if (-not (Test-Path -LiteralPath $releasesDir)) { New-Item -ItemType Directory -Path $releasesDir -Force | Out-Null }
    $zip = Join-Path $releasesDir ("SeriesToolkit-{0}.zip" -f $version)
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    git -C "$PublishRepoPath" archive --format=zip --output="$zip" $tag
    if ($LASTEXITCODE -ne 0) { throw "Не удалось собрать zip-архив релиза: $zip" }

    $body = Get-ReleaseNotesFromChangelog -Path (Join-Path $ProjectRoot 'CHANGELOG.md') -Version $version
    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = @"
Что добавлено и улучшено в версии ${version}:

- Автоматический релиз SeriesToolkit $version.
- Исходники toolkit в состоянии тега $tag.
- README/CHANGELOG/version.json текущей версии.
- ZIP-архив для быстрого тестирования и отката.
"@
    }
    $releaseExists = Test-GhReleaseExists -Tag $tag -Repo $GitHubRepo
    if ($releaseExists) {
        Invoke-GhOrThrow -Arguments @('release', 'upload', $tag, $zip, '-R', $GitHubRepo, '--clobber') -ErrorContext "Не удалось загрузить asset в release $tag"
    } else {
        Invoke-GhOrThrow -Arguments @('release', 'create', $tag, $zip, '-R', $GitHubRepo, '--title', "SeriesToolkit $version", '--notes', $body) -ErrorContext "Не удалось создать release $tag"
    }
}

# Обновляем gist: если edit не получится, создаём новый.
try {
    $gistArgs = @(
        (Join-Path $ProjectRoot 'README.md'),
        (Join-Path $ProjectRoot 'CHANGELOG.md'),
        (Join-Path $ProjectRoot 'version.json'),
        (Join-Path $ProjectRoot 'SeriesToolkit.ps1'),
        (Join-Path $ProjectRoot 'SeriesToolkit.Engine.ps1'),
        (Join-Path $ProjectRoot 'Start-SeriesToolkitGui.ps1'),
        (Join-Path $ProjectRoot 'Start-SeriesToolkitGui.Engine.ps1'),
        (Join-Path $ProjectRoot 'UiStrings.ps1'),
        (Join-Path $ProjectRoot 'Bump-Version.ps1'),
        (Join-Path $ProjectRoot 'SeriesToolkit.settings.example.json'),
        (Join-Path $ProjectRoot 'SeriesToolkit.settings.README.md')
    )
    foreach ($extra in @('docs/SCREENSHOTS-RU.md')) {
        $ep = Join-Path $ProjectRoot $extra
        if (Test-Path -LiteralPath $ep) { $gistArgs += $ep }
    }
    & $gh gist create @gistArgs `
        --desc "SeriesToolkit v$version — см. репозиторий github.com/emildg8/SeriesToolkit" | Out-Null
} catch { }
