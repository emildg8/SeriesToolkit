#requires -Version 5.1
# Dot-source from SeriesToolkit (SeriesToolkit.Engine.ps1) или legacy Script_Rename_ALLVideo_*.ps1. Возвращает список @{ season; episode; title } или $null.

$script:FetchUserAgent = 'RenameSeriesToolkit/1.0 (Windows; PowerShell)'
$script:LastResolveHint = ''

if (-not (Get-Command ConvertTo-DotNetFileSystemPath -ErrorAction SilentlyContinue)) {
    function ConvertTo-DotNetFileSystemPath([string]$Path) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
        $p = $Path.Trim()
        $prefix = 'Microsoft.PowerShell.Core\FileSystem::'
        if ($p.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $p.Substring($prefix.Length)
        }
        return $p
    }
}

function Initialize-WebClient {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-SeriesToolkitMetadataTimeoutSec([int]$Default = 60) {
    $raw = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_METADATA_TIMEOUT_SEC', 'Process')
    $v = 0
    if ([int]::TryParse($raw, [ref]$v) -and $v -ge 10 -and $v -le 300) {
        return $v
    }
    return $Default
}

function Get-UrlText([string]$Uri) {
    Initialize-WebClient
    $r = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec (Get-SeriesToolkitMetadataTimeoutSec 60)
    return $r.Content
}

# Kinopoisk/Yandex often block non-browser user-agents; use a Chrome-like UA for episode pages only.
$script:KinopoiskBrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

function Get-KinopoiskCookieHeaderFromEnvironment {
    foreach ($name in @('KINOPOISK_COOKIE', 'SERIESTOOLKIT_KINOPOISK_COOKIE')) {
        foreach ($scope in @('Process', 'User', 'Machine')) {
            $v = [Environment]::GetEnvironmentVariable($name, $scope)
            if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
        }
    }
    return $null
}

function Test-SeriesToolkitUseCurlForKinopoisk {
    $v = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_KP_USE_CURL', 'User')
    if ($v -eq '0' -or $v -eq 'false') { return $false }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    return (Test-Path -LiteralPath $curl)
}

function Invoke-KinopoiskHttpGet([string]$Uri) {
    if ([string]::IsNullOrWhiteSpace($Uri)) { return $null }
    Initialize-WebClient
    $dEnv = [Environment]::GetEnvironmentVariable('SERIESTOOLKIT_KP_DELAY_MS', 'User')
    $delayParsed = -1
    if ([int]::TryParse($dEnv, [ref]$delayParsed) -and $delayParsed -ge 0) {
        Start-Sleep -Milliseconds ([Math]::Min($delayParsed, 8000))
    } else {
        Start-Sleep -Milliseconds (Get-Random -Minimum 80 -Maximum 380)
    }

    $cookie = Get-KinopoiskCookieHeaderFromEnvironment
    $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
    if ((Test-SeriesToolkitUseCurlForKinopoisk) -and (Test-Path -LiteralPath $curlExe)) {
        $curlArgs = @(
            '-sSL', '--compressed', '--max-redirs', '12', '-m', '90',
            '-A', $script:KinopoiskBrowserUserAgent,
            '-H', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            '-H', 'Accept-Language: ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
            '-e', 'https://www.kinopoisk.ru/',
            '-H', 'Referer: https://www.kinopoisk.ru/',
            '-H', 'Sec-Fetch-Dest: document',
            '-H', 'Sec-Fetch-Mode: navigate',
            '-H', 'Upgrade-Insecure-Requests: 1'
        )
        if (-not [string]::IsNullOrWhiteSpace($cookie)) {
            $curlArgs += @('-b', $cookie)
        }
        $curlArgs += $Uri
        for ($ci = 1; $ci -le 2; $ci++) {
            try {
                $out = & $curlExe @curlArgs 2>$null
                if ($out -and ([string]$out).Length -gt 400) { return [string]$out }
            } catch { }
            Start-Sleep -Milliseconds (400 * $ci)
        }
    }

    $headers = @{
        'User-Agent'                = $script:KinopoiskBrowserUserAgent
        'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        'Accept-Language'           = 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7'
        'Referer'                   = 'https://www.kinopoisk.ru/'
        'Sec-Fetch-Dest'            = 'document'
        'Sec-Fetch-Mode'            = 'navigate'
        'Sec-Fetch-Site'            = 'same-origin'
        'Upgrade-Insecure-Requests' = '1'
    }
    if (-not [string]::IsNullOrWhiteSpace($cookie)) {
        $headers['Cookie'] = $cookie
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $r = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers $headers -MaximumRedirection 12 -TimeoutSec 90
            if ($r -and $r.Content) { return $r.Content }
        } catch {
            Start-Sleep -Milliseconds (450 * $attempt)
        }
    }
    return $null
}

function Get-KinopoiskUrlText([string]$Uri) {
    $html = Invoke-KinopoiskHttpGet $Uri
    if ($null -eq $html) {
        throw "Kinopoisk: пустой ответ для $Uri"
    }
    return $html
}

function Test-KinopoiskHtmlLooksLikeCaptchaPage([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return $false }
    # Normal episode HTML usually includes JSON with seasonNumber or __NEXT_DATA__.
    if ($html -match '"seasonNumber"\s*:\s*\d+') { return $false }
    if ($html -match 'id="__NEXT_DATA__"') { return $false }
    return [bool]($html -match '(?i)checkbox-captcha|CheckboxCaptcha|/checkcaptcha|smartcaptcha|Подтвердите,\s*что\s+запросы\s+отправляли\s+вы|Я\s+не\s+робот')
}

function Get-NextDataJsonText([string]$html) {
    $idx = $html.IndexOf('id="__NEXT_DATA__"', [System.StringComparison]::OrdinalIgnoreCase)
    if ($idx -lt 0) { return $null }
    $gt = $html.IndexOf('>', $idx)
    if ($gt -lt 0) { return $null }
    $start = $gt + 1
    $end = $html.IndexOf('</script>', $start, [System.StringComparison]::OrdinalIgnoreCase)
    if ($end -lt $start) { return $null }
    return $html.Substring($start, $end - $start).Trim()
}

function Find-KinopoiskEpisodeArrayInJson($node, [int]$depth = 0) {
    if ($depth -gt 25) { return $null }
    if ($null -eq $node) { return $null }
    if ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string]) -and -not ($node -is [char[]])) {
        $arr = @($node)
        if ($arr.Count -gt 0) {
            $f = $arr[0]
            if ($f -is [pscustomobject]) {
                if ($null -ne $f.seasonNumber -and $null -ne $f.episodeNumber) {
                    return $arr
                }
            }
        }
        foreach ($x in $arr) {
            $r = Find-KinopoiskEpisodeArrayInJson $x ($depth + 1)
            if ($r) { return $r }
        }
        return $null
    }
    if ($node -is [pscustomobject]) {
        foreach ($prop in $node.PSObject.Properties) {
            $r = Find-KinopoiskEpisodeArrayInJson $prop.Value ($depth + 1)
            if ($r) { return $r }
        }
    }
    return $null
}

function Get-WikipediaPageTitleFromUrl([string]$Url) {
    if ($Url -match '(?i)(?:https?://)?(?:[a-z0-9-]+\.)?wikipedia\.org/wiki/([^?#]+)') {
        return [uri]::UnescapeDataString($Matches[1].Replace('_', ' '))
    }
    return $null
}

function Get-WikipediaCanonicalTitleRu([string]$PageTitle) {
    if ([string]::IsNullOrWhiteSpace($PageTitle)) { return $null }
    $enc = [uri]::EscapeDataString($PageTitle)
    $api = "https://ru.wikipedia.org/w/api.php?action=query&format=json&prop=info&inprop=url&redirects=1&titles=$enc"
    try {
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        foreach ($p in $json.query.pages.PSObject.Properties) {
            $t = $p.Value.title
            if ($t -and $p.Name -ne '-1') { return [string]$t }
        }
    } catch { }
    return $null
}

function Get-KinopoiskFilmIdFromUrl([string]$Url) {
    if ($Url -match 'kinopoisk\.ru/(?:film|series)/(\d+)') {
        return $Matches[1]
    }
    return $null
}

function Normalize-KinopoiskOgTitle([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $t = $Raw.Trim()
    $t = $t -replace '\s+—\s*смотреть.*$', '' -replace '\s+—\s*Кинопоиск.*$', '' -replace '\s+-\s*смотреть.*$', ''
    $t = $t -replace '\s*\(\s*сериал[^)]*\)', '' -replace '\s*\(\s*мини-сериал[^)]*\)', ''
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-KinopoiskDisplayTitleFromMainHtml([string]$Html) {
    if ([string]::IsNullOrWhiteSpace($Html)) { return $null }
    if ($Html -match '(?is)property="og:title"\s+content="([^"]+)"') {
        $x = Normalize-KinopoiskOgTitle $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($x)) { return $x }
    }
    $nd = Get-NextDataJsonText $Html
    if (-not [string]::IsNullOrWhiteSpace($nd)) {
        try {
            $j = $nd | ConvertFrom-Json
            if ($j.props.pageProps.filmBrief.name) {
                $x = Normalize-KinopoiskOgTitle ([string]$j.props.pageProps.filmBrief.name)
                if (-not [string]::IsNullOrWhiteSpace($x)) { return $x }
            }
        } catch { }
    }
    return $null
}

function Get-KpTitleMatchScore([string]$Expected, [string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Candidate)) { return 0 }
    $norm = {
        param([string]$s)
        $t = $s.ToLowerInvariant() -replace '[^\p{L}\p{Nd}\s]', ' ' -replace '\s+', ' '
        return $t.Trim()
    }
    $e = & $norm $Expected
    $c = & $norm $Candidate
    if ([string]::IsNullOrWhiteSpace($e) -or [string]::IsNullOrWhiteSpace($c)) { return 0 }
    if ($c -eq $e) { return 1000 }
    if ($c.Contains($e) -or $e.Contains($c)) { return 450 }
    $sc = 0
    foreach ($w in ($e -split '\s+')) {
        if ($w.Length -lt 2) { continue }
        if ($c.Contains($w)) { $sc += 55 }
    }
    return $sc
}

function Get-KinopoiskFilmIdFromSearchRedirect([string]$Query) {
    if ([string]::IsNullOrWhiteSpace($Query)) { return $null }
    $enc = [uri]::EscapeDataString($Query.Trim())
    $url = "https://www.kinopoisk.ru/index.php?kp_query=$enc"
    try {
        $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
        if ((Test-SeriesToolkitUseCurlForKinopoisk) -and (Test-Path -LiteralPath $curlExe)) {
            $cookie = Get-KinopoiskCookieHeaderFromEnvironment
            $curlArgs = @(
                '-sSIL', '--compressed', '--max-redirs', '16', '-m', '90',
                '-A', $script:KinopoiskBrowserUserAgent,
                '-H', 'Accept-Language: ru-RU,ru;q=0.9',
                '-e', 'https://www.kinopoisk.ru/',
                '-H', 'Referer: https://www.kinopoisk.ru/'
            )
            if (-not [string]::IsNullOrWhiteSpace($cookie)) { $curlArgs += @('-b', $cookie) }
            $curlArgs += $url
            $last = & $curlExe @curlArgs 2>$null
            if ($last) {
                foreach ($line in ($last -split "`n")) {
                    if ($line -match '(?i)^location:\s*(.+)$') {
                        $loc = $Matches[1].Trim()
                        $id = Get-KinopoiskFilmIdFromUrl $loc
                        if ($id) { return $id }
                    }
                }
            }
        }
        $headers = @{
            'User-Agent'      = $script:KinopoiskBrowserUserAgent
            'Accept'          = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
            'Accept-Language' = 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7'
            'Referer'         = 'https://www.kinopoisk.ru/'
        }
        if (-not [string]::IsNullOrWhiteSpace((Get-KinopoiskCookieHeaderFromEnvironment))) {
            $headers['Cookie'] = Get-KinopoiskCookieHeaderFromEnvironment
        }
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers -MaximumRedirection 16 -TimeoutSec 90
        $final = $r.BaseResponse.ResponseUri.AbsoluteUri
        return Get-KinopoiskFilmIdFromUrl $final
    } catch {
        return $null
    }
}

function Get-EpisodesFromKinopoiskVerifiedForSeries(
    [string]$FolderTitle,
    [string]$TmdbRuName,
    [string]$TmdbOriginalName,
    [int]$MinMatchScore = 120
) {
    if ([string]::IsNullOrWhiteSpace($FolderTitle)) { return $null }
    $id = Get-KinopoiskFilmIdFromSearchRedirect $FolderTitle
    if (-not $id) { return $null }
    $mainUrl = "https://www.kinopoisk.ru/film/$id/"
    try {
        $html = Get-KinopoiskUrlText $mainUrl
    } catch {
        return $null
    }
    if (Test-KinopoiskHtmlLooksLikeCaptchaPage $html) { return $null }
    $disp = Get-KinopoiskDisplayTitleFromMainHtml $html
    if ([string]::IsNullOrWhiteSpace($disp)) { return $null }
    $s1 = Get-KpTitleMatchScore $FolderTitle $disp
    $s2 = if (-not [string]::IsNullOrWhiteSpace($TmdbRuName)) { Get-KpTitleMatchScore $TmdbRuName $disp } else { 0 }
    $s3 = if (-not [string]::IsNullOrWhiteSpace($TmdbOriginalName)) { Get-KpTitleMatchScore $TmdbOriginalName $disp } else { 0 }
    $mx = [Math]::Max([Math]::Max($s1, $s2), $s3)
    if ($mx -lt $MinMatchScore) { return $null }
    return Get-EpisodesFromKinopoiskEpisodesPage $id
}

function Format-RussianEpisodeTitleFromWikipedia([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $t = Normalize-WikiCellText $text
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    # «Друзья» и др.: в одной ячейке англ. название и рус. через типографский разделитель » «
    if ($t -match '»\s*«\s*(.+)') {
        $tail = $Matches[1].Trim()
        if ($tail -match '\p{IsCyrillic}') {
            $t = $tail
        }
    }
    $t = $t -replace '(?i)^\s*«?\s*Глава\s+\d+\s*:\s*', ''
    $t = $t -replace '(?i)\s*Глава\s+\d+\s*:\s*', ' '
    # Англ. дубль «Chapter N: …» в той же ячейке (Википедия); часто после русского идёт «…» «Chapter …»
    $t = $t -replace '(?i)»\s*«\s*Chapter\s+[^»]+»', ''
    $t = $t -replace '(?i)«\s*Chapter\s+[^»]+»', ''
    $t = $t -replace '(?i)\bChapter\s+\d+\s*:\s*[^\r\n«»]+', ''
    # Второй ряд в ячейке: русское «…» и латинское «English» / » « Aang (без слова Chapter)
    $t = $t -replace '(?i)»\s*«\s*[A-Za-z][^«\r\n]*»', ''
    $t = $t -replace '(?i)\s*»\s*«\s*[A-Za-z][^\r\n]*$', ''
    $t = $t -replace '(?i)\s*«\s*[A-Za-z][^»\r\n]*»\s*$', ''
    $t = $t -replace '^[«\s]+', ''
    $t = $t -replace '[»«\s]+$', ''
    $t = $t.Trim()
    # Ссылка «[англ.]» на en.wikipedia в ячейке (часто у 3-го сезона «Мандалорца» и др.)
    $t = $t -replace '(?i)\s*\[\s*англ\.\s*\]', ''
    $t = $t -replace ':', '-'
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Normalize-WikiCellText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    $v = $text
    try {
        $v = [System.Net.WebUtility]::HtmlDecode($v)
    } catch { }
    $v = $v -replace '<ref[^>]*>.*?</ref>', ''
    # Сноски со ссылкой на англ. статью ([англ.]), иначе после снятия тегов остаётся «… [англ.]» в названии
    $v = $v -replace '(?is)<sup\b[^>]*>.*?</sup>', ''
    $v = $v -replace '<[^>]+>', ''
    $v = $v -replace '\{\{[^{}]*\}\}', ''
    $v = $v -replace '\[\[([^|\]]+)\|([^\]]+)\]\]', '$2'
    $v = $v -replace '\[\[([^\]]+)\]\]', '$1'
    $v = $v -replace "'''?", ''
    $v = $v -replace "''", ''
    $v = $v -replace '&nbsp;', ' '
    $v = $v -replace '\s+', ' '
    return $v.Trim(' ', '"', '''', '«', '»')
}

function Get-EpisodesFromRuWikiEpisodeListTemplates([string]$wikitext) {
    $list = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($wikitext)) { return $null }
    $seasonHdrEq = [regex]::new('(?m)^={2,6}\s*(?:Сезон|Season)\s+(\d+)(?:\s*\([^)]*\))?\s*={2,6}\s*$')
    $marks = $seasonHdrEq.Matches($wikitext)
    if ($marks.Count -eq 0) { return $null }
    for ($i = 0; $i -lt $marks.Count; $i++) {
        $seasonNum = [int]$marks[$i].Groups[1].Value
        $start = $marks[$i].Index + $marks[$i].Length
        $end = if ($i + 1 -lt $marks.Count) { $marks[$i + 1].Index } else { $wikitext.Length }
        $chunk = $wikitext.Substring($start, [Math]::Max(0, $end - $start))
        $blocks = [regex]::Split($chunk, '(?=\{\{\s*(?:Episode list|Список серий)\s*\|)')
        foreach ($b in $blocks) {
            if ($b -notmatch '(?i)Episode list|Список серий') { continue }
            $epIn = $null
            if ($b -match '(?i)\|\s*EpisodeNumber2\s*=\s*(\d+)') {
                $epIn = [int]$Matches[1]
            }
            elseif ($b -match '(?i)\|\s*EpisodeNumber\s*=\s*(\d+)') {
                $epIn = [int]$Matches[1]
            }
            if (-not $epIn) { continue }
            $mTitle = [regex]::Match($b, '(?is)\|\s*Title\s*=\s*(.+?)(?=\r?\n\s*\|WrittenBy|\r?\n\s*\|DirectedBy|\r?\n\s*\|Aux\d*\s*=)')
            if (-not $mTitle.Success) { continue }
            $title = Normalize-WikiCellText $mTitle.Groups[1].Value
            if (-not $title) { continue }
            if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) { continue }
            $list.Add([pscustomobject]@{ season = $seasonNum; episode = $epIn; title = $title })
        }
    }
    if ($list.Count -gt 0) { return $list }
    return $null
}

function Get-EpisodesFromWikipediaWikitext([string]$wikitext) {
    $list = [System.Collections.Generic.List[object]]::new()

    $tpl = Get-EpisodesFromRuWikiEpisodeListTemplates $wikitext
    if ($tpl -and -not (Test-EpisodeListLooksLikeRussianAirDateJunk @($tpl))) { return $tpl }

    $seasonHdrEq = [regex]::new('(?m)^={2,6}\s*(?:Сезон|Season)\s+(\d+)(?:\s*\([^)]*\))?\s*={2,6}\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $seasonHdrHash = [regex]::new('(?m)^#{2,6}\s*(?:Сезон|Season)\s+(\d+)(?:\s*\([^)]*\))?\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)

    foreach ($seasonHdr in @($seasonHdrEq, $seasonHdrHash)) {
        $marks = $seasonHdr.Matches($wikitext)
        if ($marks.Count -eq 0) { continue }
        for ($i = 0; $i -lt $marks.Count; $i++) {
            $seasonNum = [int]$marks[$i].Groups[1].Value
            $start = $marks[$i].Index + $marks[$i].Length
            $end = if ($i + 1 -lt $marks.Count) { $marks[$i + 1].Index } else { $wikitext.Length }
            $chunk = $wikitext.Substring($start, [Math]::Max(0, $end - $start))
            $rowRx = [regex]::new('\|\s*(?:\d+)\s*\|\|\s*(\d+)\s*\|\|\s*([^\r\n|]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $rowRx.Matches($chunk)) {
                $title = Normalize-WikiCellText $m.Groups[2].Value
                if (-not $title) { continue }
                if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) { continue }
                $list.Add([pscustomobject]@{
                        season  = $seasonNum
                        episode = [int]$m.Groups[1].Value
                        title   = $title
                    })
            }
            $rowRxAlt = [regex]::new('\|\s*\|\s*(\d+)\s*\|\|\s*(\d+)\s*\|\|\s*([^\r\n|]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $rowRxAlt.Matches($chunk)) {
                $title = Normalize-WikiCellText $m.Groups[3].Value
                if (-not $title) { continue }
                if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) { continue }
                $list.Add([pscustomobject]@{
                        season  = $seasonNum
                        episode = [int]$m.Groups[2].Value
                        title   = $title
                    })
            }
            $rowRx2 = [regex]::new('\|\s*\|\s*(\d+)\s*\|\|\s*«([^»]+)»', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            foreach ($m in $rowRx2.Matches($chunk)) {
                $title = Normalize-WikiCellText $m.Groups[2].Value
                if (-not $title) { continue }
                if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) { continue }
                $list.Add([pscustomobject]@{
                        season  = $seasonNum
                        episode = [int]$m.Groups[1].Value
                        title   = $title
                    })
            }
        }
        if ($list.Count -gt 0) { return $list }
    }

    # Fallback: two first columns are season and episode (rare)
    $rx = [regex]::new('\|\s*(\d+)\s*\|\|\s*(\d+)\s*\|\|\s*([^\r\n|]+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $rx.Matches($wikitext)) {
        $title = Normalize-WikiCellText $m.Groups[3].Value
        if (-not $title) { continue }
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $title) { continue }
        $list.Add([pscustomobject]@{ season = [int]$m.Groups[1].Value; episode = [int]$m.Groups[2].Value; title = $title })
    }
    if ($list.Count -gt 0) { return $list }

    return $null
}

function Strip-HtmlToPlain([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return '' }
    $t = $html -replace '(?is)<script[^>]*>.*?</script>', ' '
    $t = $t -replace '(?is)<style[^>]*>.*?</style>', ' '
    $t = $t -replace '<[^>]+>', ' '
    $t = $t -replace '&nbsp;', ' '
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-EpisodesFromWikipediaHtmlFragment([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return $null }
    $list = [System.Collections.Generic.List[object]]::new()
    $trRx = [regex]::new('(?is)<tr[^>]*>(.*?)</tr>')
    $cellRx = [regex]::new('(?is)<t[hd][^>]*>(.*?)</t[hd]>')
    $tdRx = [regex]::new('(?is)<td[^>]*>(.*?)</td>')

    function Add-WikiEpisodeRow {
        param([int]$Season, [string]$EpInSeasonStr, [string]$TitleRaw)
        if ([string]::IsNullOrWhiteSpace($EpInSeasonStr) -or [string]::IsNullOrWhiteSpace($TitleRaw)) { return }
        # «12—13» и т.п.: брать первый номер, иначе склейка цифр даёт недопустимый ключ (напр. 1213)
        if ($EpInSeasonStr -notmatch '(\d+)') { return }
        $epIn = $Matches[1]
        $titN = Format-RussianEpisodeTitleFromWikipedia $TitleRaw
        if ([string]::IsNullOrWhiteSpace($titN)) { $titN = Normalize-WikiCellText $TitleRaw }
        if (-not (Test-WikipediaEpisodeTitleCellPlausible $titN)) { return }
        if ($titN -match '^(?:Номинация|Победа|Награда|Премия)\s*$') { return }
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $titN) { return }
        try {
            $list.Add([pscustomobject]@{ season = $Season; episode = [int]$epIn; title = $titN })
        } catch { }
    }

    # 1) Таблицы списка эпизодов:
    #    A) <th>№ общий</th> + <td>№ в сезоне</td> + <td class="summary">название</td> (Мандалорец и др.)
    #    B) <th>№ в сезоне</th> + <td class="summary">название</td> без колонки «№ общий» (Аватар 2024 и др.)
    #    C) Только `wikitable` без `wikiepisodetable` (шаблон «Список серий» и др., напр. «Заговор сестёр Гарви»): те же строки vevent, фильтр по class="summary".
    # Раньше для (B) ошибочно брались режиссёр и дата как «название».
    $tablePatterns = @(
        @{ Pattern = '(?is)<table[^>]*\bwikiepisodetable\b[^>]*>(.*?)</table>'; RequireEpisodeSummary = $false }
        @{ Pattern = '(?is)<table[^>]*\bwikitable\b[^>]*>(.*?)</table>'; RequireEpisodeSummary = $true }
    )
    foreach ($tp in $tablePatterns) {
        $tableRx = [regex]::new($tp.Pattern)
        foreach ($tbl in $tableRx.Matches($html)) {
            $tableInner = $tbl.Groups[1].Value
            if ($tp.RequireEpisodeSummary) {
                if ($tableInner -notmatch 'vevent') { continue }
                if ($tableInner -notmatch 'class="summary"') { continue }
            }
            $tableStart = $tbl.Index
            $seasonNum = 1
            if ($tableStart -gt 0) {
                $before = $html.Substring(0, $tableStart)
                # «Сезон N», «Season N», «N сезон: …» (ru.wikipedia «Друзья» и др.) — раньше учитывался только «Сезон N»
                $hdrRx = '(?is)<h[23][^>]*>.*?(?:(\d+)\s*сезон\b|(?:Сезон|Season)\s*(\d+))'
                $hdrAll = [regex]::Matches($before, $hdrRx)
                if ($hdrAll.Count -gt 0) {
                    $hm = $hdrAll[$hdrAll.Count - 1]
                    if ($hm.Groups[1].Success -and $hm.Groups[1].Value) {
                        $seasonNum = [int]$hm.Groups[1].Value
                    }
                    elseif ($hm.Groups[2].Success -and $hm.Groups[2].Value) {
                        $seasonNum = [int]$hm.Groups[2].Value
                    }
                }
            }
            foreach ($tm in $trRx.Matches($tableInner)) {
                # class="vevent" задаётся в открывающем <tr>, а не во внутренности — проверять весь фрагмент <tr>…</tr>
                if ($tm.Value -notmatch 'vevent') { continue }
                $row = $tm.Groups[1].Value
                if ($row -match '(?i)Название|Режиссёр|Режиссер|Автор сценария|Дата премьеры') { continue }
                $cells = @()
                foreach ($cm in $cellRx.Matches($row)) {
                    $cells += (Strip-HtmlToPlain $cm.Groups[1].Value)
                }
                if ($cells.Count -ge 3) {
                    if ($cells[0] -match '^(?:№|Название)') { continue }
                    $c0 = ($cells[0] -replace '\s', '').Trim()
                    $c1 = ($cells[1] -replace '\s', '').Trim()
                    # Две ведущие числовые колонки — эпизод в сезоне во второй, название в третьей
                    if ($c0 -match '^\d+$' -and $c1 -match '^\d+$') {
                        Add-WikiEpisodeRow -Season $seasonNum -EpInSeasonStr $cells[1] -TitleRaw $cells[2]
                    }
                    # Первая колонка — только номер в сезоне, вторая — название (нет «№ общий»)
                    elseif ($c0 -match '^\d+$' -and $c1 -notmatch '^\d+$') {
                        Add-WikiEpisodeRow -Season $seasonNum -EpInSeasonStr $cells[0] -TitleRaw $cells[1]
                    }
                }
                elseif ($cells.Count -ge 2) {
                    if ($cells[0] -match '^(?:№|Название)') { continue }
                    $c0 = ($cells[0] -replace '\s', '').Trim()
                    if ($c0 -match '^\d+$') {
                        Add-WikiEpisodeRow -Season $seasonNum -EpInSeasonStr $cells[0] -TitleRaw $cells[1]
                    }
                }
            }
        }
    }

    if ($list.Count -gt 0) { return $list }

    # 2) Запасной разбор (старые таблицы без wikiepisodetable): только <td>, эвристика по числу ячеек
    $seasonNum = 1
    foreach ($tm in $trRx.Matches($html)) {
        $row = $tm.Groups[1].Value
        if ($row -match '(?i)Сезон\s*(\d+)|Season\s*(\d+)') {
            $g = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            $seasonNum = [int]$g
            continue
        }
        $cells = @()
        foreach ($dm in $tdRx.Matches($row)) {
            $cells += (Strip-HtmlToPlain $dm.Groups[1].Value)
        }
        if ($cells.Count -ge 4) {
            $snM = [regex]::Match($cells[1], '\d+')
            $enM = [regex]::Match($cells[2], '\d+')
            $sn = if ($snM.Success) { $snM.Value } else { '' }
            $en = if ($enM.Success) { $enM.Value } else { '' }
            $tit = $cells[3]
            $titN = Format-RussianEpisodeTitleFromWikipedia $tit
            if ([string]::IsNullOrWhiteSpace($titN)) { $titN = Normalize-WikiCellText $tit }
            if ($sn -and $en -and $tit -and $tit.Length -gt 1 -and -not (Test-KinopoiskTitleLooksLikeRussianAirDate $titN)) {
                try {
                    $list.Add([pscustomobject]@{ season = [int]$sn; episode = [int]$en; title = $titN })
                } catch { }
            }
        }
        elseif ($cells.Count -ge 3) {
            $aM = [regex]::Match($cells[0], '\d+')
            $bM = [regex]::Match($cells[1], '\d+')
            $a = if ($aM.Success) { $aM.Value } else { '' }
            $b = if ($bM.Success) { $bM.Value } else { '' }
            $tit = $cells[2]
            $titN = Format-RussianEpisodeTitleFromWikipedia $tit
            if ([string]::IsNullOrWhiteSpace($titN)) { $titN = Normalize-WikiCellText $tit }
            if ($a -and $b -and $tit -and $tit.Length -gt 1 -and -not (Test-KinopoiskTitleLooksLikeRussianAirDate $titN)) {
                try {
                    $list.Add([pscustomobject]@{ season = [int]$a; episode = [int]$b; title = $titN })
                } catch { }
            }
        }
        elseif ($cells.Count -ge 2) {
            $b = $cells[0] -replace '\D', ''
            $tit = $cells[1]
            $titN = Format-RussianEpisodeTitleFromWikipedia $tit
            if ([string]::IsNullOrWhiteSpace($titN)) { $titN = Normalize-WikiCellText $tit }
            if ($b -and $tit -and $tit.Length -gt 1 -and $tit -notmatch '^(?:Сезон|Season|\#)' -and -not (Test-KinopoiskTitleLooksLikeRussianAirDate $titN)) {
                try {
                    $list.Add([pscustomobject]@{ season = $seasonNum; episode = [int]$b; title = $titN })
                } catch { }
            }
        }
    }
    if ($list.Count -gt 0) { return $list }
    return $null
}

function Get-EpisodesFromWikipediaParseHtmlApi([string]$PageTitle) {
    if ([string]::IsNullOrWhiteSpace($PageTitle)) { return $null }
    $enc = [uri]::EscapeDataString($PageTitle)
    $api = "https://ru.wikipedia.org/w/api.php?action=parse&format=json&prop=text&redirects=1&page=$enc"
    try {
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        if ($json.error) { return $null }
        $html = $null
        if ($json.parse -and $json.parse.text) {
            $t = $json.parse.text
            if ($t.PSObject.Properties['*']) { $html = $t.'*' }
            elseif ($t -is [string]) { $html = $t }
        }
        if (-not $html) { return $null }
        return Get-EpisodesFromWikipediaHtmlFragment $html
    } catch {
        return $null
    }
}

function Get-WikipediaWikitextByTitle([string]$PageTitle) {
    if ([string]::IsNullOrWhiteSpace($PageTitle)) { return $null }
    $canon = Get-WikipediaCanonicalTitleRu $PageTitle
    if ($canon) { $PageTitle = $canon }
    $enc = [uri]::EscapeDataString($PageTitle)
    $api = "https://ru.wikipedia.org/w/api.php?action=parse&format=json&prop=wikitext&redirects=1&page=$enc"
    try {
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        $wt = $json.parse.wikitext.'*'
        if (-not $wt) { return $null }
        return [string]$wt
    } catch {
        return $null
    }
}

function Get-EpisodesFromWikipediaPageTitle([string]$PageTitle) {
    $canon = Get-WikipediaCanonicalTitleRu $PageTitle
    if ($canon) { $PageTitle = $canon }
    $wt = Get-WikipediaWikitextByTitle $PageTitle
    if ($wt) {
        $r = Get-EpisodesFromWikipediaWikitext $wt
        if ($r -and @($r).Count -gt 0 -and -not (Test-EpisodeListLooksLikeRussianAirDateJunk @($r)) -and (Test-EpisodeListSeasonEpisodeLooksSane @($r))) { return $r }
    }
    $rHtml = Get-EpisodesFromWikipediaParseHtmlApi $PageTitle
    if ($rHtml -and @($rHtml).Count -gt 0 -and -not (Test-EpisodeListLooksLikeRussianAirDateJunk @($rHtml)) -and (Test-EpisodeListSeasonEpisodeLooksSane @($rHtml))) { return $rHtml }
    return $null
}

function Get-EpisodesFromWikipediaPageTitleOrLinked([string]$PageTitle) {
    $r = Get-EpisodesFromWikipediaPageTitle $PageTitle
    if ($r -and (Test-WikipediaEpisodeExtractLooksUsable $PageTitle @($r))) { return $r }
    $wt = Get-WikipediaWikitextByTitle $PageTitle
    if (-not $wt) { return $null }
    $links = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($wt, '\[\[([^\]|]+)(?:\|[^\]]+)?\]\]')) {
        $t = $m.Groups[1].Value.Trim()
        if ($t -match 'Список эпизодов') {
            $links.Add($t)
        }
    }
    foreach ($lt in ($links | Select-Object -Unique)) {
        $r2 = Get-EpisodesFromWikipediaPageTitle $lt
        if ($r2 -and (Test-WikipediaEpisodeExtractLooksUsable $lt @($r2))) { return $r2 }
    }
    return $null
}

function Get-EpisodesFromWikipediaRuTailSeasonPages([string]$Tail) {
    if ([string]::IsNullOrWhiteSpace($Tail)) { return $null }
    $merged = [System.Collections.Generic.List[object]]::new()
    $gotAny = $false
    $miss = 0
    for ($si = 1; $si -le 24; $si++) {
        $seasonTitle = $Tail + ' (' + $si + '-й сезон)'
        $part = Get-EpisodesFromWikipediaPageTitle $seasonTitle
        if ($part -and @($part).Count -gt 0) {
            $gotAny = $true
            $miss = 0
            foreach ($x in $part) {
                $merged.Add($x)
            }
        }
        elseif ($gotAny) {
            $miss++
            if ($miss -ge 2) { break }
        }
    }
    if ($merged.Count -lt 3) { return $null }
    return @($merged)
}

function Search-WikipediaPageTitle([string]$Query) {
    $enc = [uri]::EscapeDataString($Query)
    $api = "https://ru.wikipedia.org/w/api.php?action=query&format=json&list=search&srsearch=$enc&srlimit=8"
    try {
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        foreach ($hit in $json.query.search) {
            if ($hit.title -match 'Список|эпизод|эпизоды|Сезон|телесериал|сериал') {
                return $hit.title
            }
        }
        foreach ($hit in $json.query.search) {
            if ($hit.title -match '(?i)episode|season|list|serial') {
                return $hit.title
            }
        }
        if ($json.query.search.Count -gt 0) {
            return $json.query.search[0].title
        }
    } catch { }
    return $null
}

function Get-EnglishTitleFromRuWikipedia([string]$Query) {
    $title = Search-WikipediaPageTitle $Query
    if (-not $title) { return $null }
    try {
        $enc = [uri]::EscapeDataString($title)
        $api = "https://ru.wikipedia.org/w/api.php?action=query&format=json&prop=langlinks&lllang=en&titles=$enc"
        $json = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        foreach ($p in $json.query.pages.PSObject.Properties) {
            $lang = $p.Value.langlinks
            if ($lang -and $lang[0] -and $lang[0].'*') {
                return [string]$lang[0].'*'
            }
        }
    } catch { }
    return $null
}

function Test-KinopoiskTitleLooksLikeRussianAirDate([string]$tit) {
    if ([string]::IsNullOrWhiteSpace($tit)) { return $false }
    $t = $tit.Trim()
    return [bool]($t -match '^(?:\d{1,2})\s+(?:января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)\s+(?:\d{4})$')
}

# Те же даты часто попадают из инфобокса/хронологии статьи о сериале (не из списка эпизодов).
function Test-EpisodeListLooksLikeRussianAirDateJunk([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $false }
    $n = @($list).Count
    $bad = 0
    foreach ($p in $list) {
        if (Test-KinopoiskTitleLooksLikeRussianAirDate ([string]$p.title)) { $bad++ }
    }
    return ($bad -gt ($n / 2))
}

# Статья о сериале (не «Список эпизодов…») с 1–4 строками почти всегда ложное срабатывание таблиц — идём по ссылке на список эпизодов.
function Test-WikipediaEpisodeExtractLooksUsable([string]$PageTitle, [object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $false }
    if (-not (Test-EpisodeListSeasonEpisodeLooksSane @($list))) { return $false }
    $n = @($list).Count
    if ($n -ge 5) { return $true }
    if ([string]::IsNullOrWhiteSpace($PageTitle)) { return $false }
    return [bool]($PageTitle -match '(?i)Список\s+эпизодов|эпизодов\s+сериала|эпизодов\s+телесериала')
}

function Test-WikipediaEpisodeTitleCellPlausible([string]$tit) {
    if ([string]::IsNullOrWhiteSpace($tit)) { return $false }
    $t = $tit -replace '&(?:#\d+|[a-zA-Z]+);', ' '
    $t = $t.Trim()
    if ($t.Length -lt 2) { return $false }
    if ($t -match '^(?:TBA|tbd)$') { return $false }
    # Числа с разделителями тысяч (12.345 / 1,234) — из чужих таблиц, не названия эпизодов
    if ($t -match '^(?:\d+[.,])+\d+$') { return $false }
    # Чисто цифровое название эпизода (напр. «1969», «2001» в Звёздных вратах SG-1): раньше
    # отсекалось правилом «только цифры» и проверкой на букву — эпизод не попадал в CSV.
    if ($t -match '^\d+$') {
        if ($t.Length -lt 3) { return $false }
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $tit) { return $false }
        return $true
    }
    if ($t -notmatch '\p{L}') { return $false }
    if (Test-KinopoiskTitleLooksLikeRussianAirDate $t) { return $false }
    return $true
}

# Отсекаем таблицы не из списка эпизодов (годы, кассовые сборы, ID), где «сезон»/«серия» превращаются в огромные числа.
function Test-EpisodeListSeasonEpisodeLooksSane([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $false }
    $n = @($list).Count
    $ok = 0
    $okTit = 0
    foreach ($p in $list) {
        try {
            $sn = [int]$p.season
            $en = [int]$p.episode
        } catch { continue }
        if ($sn -ge 1 -and $sn -le 99 -and $en -ge 1 -and $en -le 500) { $ok++ }
        if (Test-WikipediaEpisodeTitleCellPlausible ([string]$p.title)) { $okTit++ }
    }
    return (($ok -gt ($n / 2)) -and ($okTit -gt ($n / 2)))
}

# Старые сохранённые страницы Кинопоиска (XHTML, таблицы «Сезон N» / «Эпизод N») без __NEXT_DATA__ / JSON эпизодов.
# Разбор по <tr>, чтобы в <b> не попадала дата из соседней ячейки.
function Parse-KinopoiskLegacyEpisodesTableHtml([string]$html) {
    $out = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($html)) { return $out }
    if ($html -notmatch '(?i)Сезон\s*\d+') { return $out }
    if ($html -notmatch '(?i)Эпизод\s*\d+') { return $out }

    $trRx = [regex]::new('(?is)<tr\b[^>]*>(.*?)</tr>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $currentSeason = 0
    foreach ($tm in $trRx.Matches($html)) {
        $tr = $tm.Groups[1].Value
        if ($tr -match '(?is)<h1[^>]*\bclass="[^"]*moviename-big[^"]*"[^>]*style="[^"]*font-size:\s*21px[^"]*"[^>]*>\s*Сезон\s+(\d+)\s*</h1>') {
            $currentSeason = [int]$Matches[1]
            continue
        }
        if ($tr -match '(?i)эпизодов\s*:') {
            $m = [regex]::Match($tr, '(?i)Сезон\s+(\d+)')
            if ($m.Success) {
                $currentSeason = [int]$m.Groups[1].Value
            }
            continue
        }
        if ($currentSeason -le 0) { continue }
        if ($tr -notmatch '(?is)<span[^>]*>\s*(?:Эпизод|Серия)\s+(\d+)\s*</span>') { continue }
        $en = [int]$Matches[1]
        if ($tr -notmatch '(?is)<h1[^>]*\bclass="[^"]*moviename-big[^"]*"[^>]*style="[^"]*font-size:\s*16px[^"]*"[^>]*>\s*<(?:b|strong)>([^<]+)</(?:b|strong)>') { continue }
        $tit = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($tit)) { continue }
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $tit) { continue }
        $out.Add([pscustomobject]@{ season = $currentSeason; episode = $en; title = $tit })
    }
    return $out
}

function Test-EpisodeListLooksSparseOrDateLikeJunk([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $true }
    $n = @($list).Count
    if ($n -lt 30) { return $true }
    $bad = 0
    foreach ($p in $list) {
        $t = [string]$p.title
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $t) { $bad++ }
    }
    return ($bad -gt ($n / 4))
}

function Test-EpisodeTitleLooksLikeKinopoiskEpisodeLabel([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }
    $t = $Title.Trim()
    # Кинопоиск (legacy HTML): «Эпизод #1.1» — подпись из интерфейса; это не «Эпизод 1» из TV Maze и не должно
    # попадать под Test-EpisodeTitleLooksLikePlaceholder (иначе обнуляются имена файлов и wiki подменяет весь список).
    return [bool]($t -match '^(?i)(?:Эпизод|Серия|Episode)\s*#\s*\d+(?:\.\d+)?\s*$')
}

function Test-EpisodeTitleLooksLikePlaceholder([string]$Title) {
    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }
    $t = $Title.Trim()
    # TV Maze / запасные подписи в CSV: «Эпизод 1», «Серия 2» — не настоящие названия, но с кириллицей
    return [bool]($t -match '^(?i)(?:Эпизод|Серия|Episode)\s*\d+\s*$')
}

function Test-EpisodeListLooksLikePlaceholderEpisodeTitles([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $false }
    $n = @($list).Count
    $ph = 0
    foreach ($p in $list) {
        $t = if ($null -ne $p.title) { [string]$p.title } elseif ($null -ne $p.Title) { [string]$p.Title } else { '' }
        if (Test-EpisodeTitleLooksLikePlaceholder $t) { $ph++ }
    }
    return ($ph -gt ($n * 0.35))
}

function Test-EpisodeListLooksLikeKinopoiskEpisodeLabels([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $false }
    $n = @($list).Count
    $kp = 0
    foreach ($p in $list) {
        $t = if ($null -ne $p.title) { [string]$p.title } elseif ($null -ne $p.Title) { [string]$p.Title } else { '' }
        if (Test-EpisodeTitleLooksLikeKinopoiskEpisodeLabel $t) { $kp++ }
    }
    return ($kp -gt ($n * 0.35))
}

function Convert-EpisodeListToUniqueBySeasonEpisode([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return $list }
    $byKey = @{}
    foreach ($p in $list) {
        if ($null -eq $p) { continue }
        $snRaw = if ($null -ne $p.season) { $p.season } else { $p.Season }
        $enRaw = if ($null -ne $p.episode) { $p.episode } else { $p.Episode }
        if (-not $snRaw -or -not $enRaw) { continue }
        $sn = [int]$snRaw
        $en = [int]$enRaw
        if ($sn -le 0 -or $en -le 0) { continue }
        $title = if ($null -ne $p.title) { [string]$p.title } else { [string]$p.Title }
        $key = "$sn`:$en"
        if (-not $byKey.ContainsKey($key)) {
            $byKey[$key] = [pscustomobject]@{ season = $sn; episode = $en; title = $title }
            continue
        }
        $prev = $byKey[$key]
        $prevTitle = [string]$prev.title
        $prevBad = [string]::IsNullOrWhiteSpace($prevTitle) -or (Test-EpisodeTitleLooksLikePlaceholder $prevTitle) -or (Test-KinopoiskTitleLooksLikeRussianAirDate $prevTitle)
        $curBad = [string]::IsNullOrWhiteSpace($title) -or (Test-EpisodeTitleLooksLikePlaceholder $title) -or (Test-KinopoiskTitleLooksLikeRussianAirDate $title)
        if ($prevBad -and -not $curBad) {
            $byKey[$key] = [pscustomobject]@{ season = $sn; episode = $en; title = $title }
        }
    }
    return @(
        $byKey.Values |
            Sort-Object `
            @{ Expression = { [int]$_.season } }, `
            @{ Expression = { [int]$_.episode } }
    )
}

function Get-EpisodeListQualityScore([object[]]$list) {
    if (-not $list -or @($list).Count -eq 0) { return -1 }
    $rows = @($list)
    $total = $rows.Count
    if ($total -eq 0) { return -1 }
    $unique = @(Convert-EpisodeListToUniqueBySeasonEpisode $rows)
    $uniqueCount = @($unique).Count
    $cyr = 0
    $placeholder = 0
    $dateLike = 0
    $plausible = 0
    foreach ($r in $unique) {
        $t = if ($null -ne $r.title) { [string]$r.title } else { [string]$r.Title }
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        if ($t -match '\p{IsCyrillic}') { $cyr++ }
        if (Test-EpisodeTitleLooksLikePlaceholder $t) { $placeholder++ }
        if (Test-EpisodeTitleLooksLikeKinopoiskEpisodeLabel $t) { $placeholder++ }
        if (Test-KinopoiskTitleLooksLikeRussianAirDate $t) { $dateLike++ }
        if (Test-WikipediaEpisodeTitleCellPlausible $t) { $plausible++ }
    }
    $dupPenalty = ($total - $uniqueCount) * 15
    return ($uniqueCount * 100) + ($cyr * 25) + ($plausible * 10) - ($placeholder * 60) - ($dateLike * 60) - $dupPenalty
}

function Expand-EpisodeListWithRussianWikipedia([object[]]$Primary, [string]$SearchQuery) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return $Primary }
    if ($Primary -and @($Primary).Count -gt 0) {
        if (Test-EpisodeListLooksLikeKinopoiskEpisodeLabels @($Primary)) {
            return $Primary
        }
        $cyr = 0
        foreach ($p in $Primary) {
            if ([string]$p.title -match '\p{IsCyrillic}') { $cyr++ }
        }
        if ($cyr -ge [math]::Ceiling(@($Primary).Count * 0.92) -and -not (Test-EpisodeListLooksSparseOrDateLikeJunk @($Primary)) -and -not (Test-EpisodeListLooksLikePlaceholderEpisodeTitles @($Primary))) {
            return $Primary
        }
    }
    $wiki = Get-EpisodesFromWikipediaSearchQueries $SearchQuery
    if (-not $wiki -or @($wiki).Count -eq 0) { return $Primary }
    if (Test-EpisodeListLooksSparseOrDateLikeJunk @($Primary)) {
        $wl = [System.Collections.Generic.List[object]]::new()
        foreach ($w in $wiki) {
            $wl.Add([pscustomobject]@{
                    season  = $w.season
                    episode = $w.episode
                    title   = (Format-RussianEpisodeTitleFromWikipedia ([string]$w.title))
                })
        }
        return @($wl)
    }
    return (Merge-EpisodeTitlesPreferRu @($Primary) @($wiki))
}

function Parse-KinopoiskEpisodesFromHtml([string]$html) {
    $list = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($html)) { return $list }

    $jsonText = Get-NextDataJsonText $html
    if (-not $jsonText) {
        $idx2 = $html.IndexOf('__NEXT_DATA__', [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx2 -ge 0) {
            $gt = $html.IndexOf('{', $idx2)
            if ($gt -ge 0) {
                $depth = 0
                for ($i = $gt; $i -lt $html.Length; $i++) {
                    $c = $html[$i]
                    if ($c -eq '{') { $depth++ }
                    elseif ($c -eq '}') {
                        $depth--
                        if ($depth -eq 0) {
                            $jsonText = $html.Substring($gt, $i - $gt + 1)
                            break
                        }
                    }
                }
            }
        }
    }
    if ($jsonText) {
        try {
            $next = $jsonText | ConvertFrom-Json
            $eps = $next.props.pageProps.state.data.series.episodes
            if (-not $eps) { $eps = $next.props.pageProps.data.episodes }
            if (-not $eps) { $eps = Find-KinopoiskEpisodeArrayInJson $next }
            if ($eps -is [array] -and $eps.Count -gt 0) {
                foreach ($e in $eps) {
                    try {
                        $sn = [int]$e.seasonNumber
                        $en = [int]$e.episodeNumber
                        $tit = $e.titleRu
                        if (-not $tit) { $tit = $e.nameRu }
                        if (-not $tit) { $tit = $e.title }
                        if (-not $tit) { $tit = $e.name }
                        if (-not $tit) { $tit = $e.titleEn }
                        if (-not $tit) { $tit = $e.nameEn }
                        if (-not $tit) { $tit = $e.originalName }
                        if ($sn -gt 0 -and $en -gt 0) {
                            $list.Add([pscustomobject]@{ season = $sn; episode = $en; title = [string]$tit })
                        }
                    } catch { }
                }
            }
        } catch { }
    }

    if ($list.Count -eq 0) {
        $rx = [regex]::new('"seasonNumber"\s*:\s*(\d+).*?"episodeNumber"\s*:\s*(\d+).*?"titleRu"\s*:\s*"([^"]*)"', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in $rx.Matches($html)) {
            $list.Add([pscustomobject]@{ season = [int]$m.Groups[1].Value; episode = [int]$m.Groups[2].Value; title = $m.Groups[3].Value })
        }
    }
    if ($list.Count -eq 0) {
        $rx2 = [regex]::new('"seasonNumber"\s*:\s*(\d+)[^}]*?"episodeNumber"\s*:\s*(\d+)[^}]*?"titleRu"\s*:\s*"((?:\\.|[^"\\])*)"', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in $rx2.Matches($html)) {
            $tit = $m.Groups[3].Value -replace '\\"', '"' -replace '\\/', '/'
            $list.Add([pscustomobject]@{ season = [int]$m.Groups[1].Value; episode = [int]$m.Groups[2].Value; title = $tit })
        }
    }
    if ($list.Count -eq 0) {
        $rx3 = [regex]::new('"episodeNumber"\s*:\s*(\d+)[^}]*?"seasonNumber"\s*:\s*(\d+)[^}]*?"titleRu"\s*:\s*"((?:\\.|[^"\\])*)"', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($m in $rx3.Matches($html)) {
            $tit = $m.Groups[3].Value -replace '\\"', '"' -replace '\\/', '/'
            $list.Add([pscustomobject]@{ season = [int]$m.Groups[2].Value; episode = [int]$m.Groups[1].Value; title = $tit })
        }
    }

    # Старый HTML «все сезоны на одной странице» даёт полный список; JSON иногда — только фрагмент (несколько эпизодов).
    $legacy = Parse-KinopoiskLegacyEpisodesTableHtml $html
    if ($legacy.Count -gt $list.Count) {
        $list.Clear()
        foreach ($x in $legacy) {
            $list.Add($x)
        }
    }

    return $list
}

function Get-KinopoiskFilmIdFromSsoStubHtml([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return $null }
    foreach ($pattern in @(
            '(?i)kinopoisk\.ru/film/(\d+)/episodes',
            '(?i)kinopoisk\.ru\\u002Ffilm\\u002F(\d+)\\u002Fepisodes',
            '(?i)"retpath"\s*:\s*"[^"]*film\\u002F(\d+)\\u002Fepisodes'
        )) {
        $m = [regex]::Match($html, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

function Test-HtmlLooksLikeKinopoiskEpisodesPage([string]$html) {
    if ([string]::IsNullOrWhiteSpace($html)) { return $false }
    # Сохранённая страница списка эпизодов: в теле или canonical есть film|series/<id>
    if ($html -match '(?i)kinopoisk\.ru/(?:film|series)/\d+') { return $true }
    # Редкий случай: только относительные пути без домена
    if ($html -match '(?i)(?:href|content)\s*=\s*["''][^"'']*/(?:film|series)/\d+/episodes') { return $true }
    return $false
}

function Get-EpisodesFromKinopoiskSavedHtmlFile([string]$Path) {
    $Path = ConvertTo-DotNetFileSystemPath $Path
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $bytes = $null
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
    } catch {
        return $null
    }
    $html = $null
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $html = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        $html = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    if ([string]::IsNullOrWhiteSpace($html)) { return $null }
    $candidates = [System.Collections.Generic.List[object]]::new()
    $list = Parse-KinopoiskEpisodesFromHtml $html
    if ($list.Count -gt 0) {
        $candidates.Add([pscustomobject]@{ source = 'kp_utf8'; list = @(Convert-EpisodeListToUniqueBySeasonEpisode @($list)) })
    }
    try {
        $cp1251 = [System.Text.Encoding]::GetEncoding(1251)
        $html2 = $cp1251.GetString($bytes)
        $list2 = Parse-KinopoiskEpisodesFromHtml $html2
        if ($list2.Count -gt 0) {
            $candidates.Add([pscustomobject]@{ source = 'kp_cp1251'; list = @(Convert-EpisodeListToUniqueBySeasonEpisode @($list2)) })
        }
    } catch { }
    # Википедийный парсер по тому же файлу: на странице Кинопоиска иногда есть фрагменты, похожие на wikitable,
    # из-за чего выбирается чужой список эпизодов с лучшим quality score. Для явного HTML Кинопоиска — только kp_*.
    if (-not (Test-HtmlLooksLikeKinopoiskEpisodesPage $html)) {
        $wikiList = Get-EpisodesFromWikipediaHtmlFragment $html
        if ($wikiList -and @($wikiList).Count -gt 0 -and (Test-EpisodeListSeasonEpisodeLooksSane @($wikiList))) {
            $candidates.Add([pscustomobject]@{ source = 'wiki_utf8'; list = @(Convert-EpisodeListToUniqueBySeasonEpisode @($wikiList)) })
        }
        try {
            $cp1251w = [System.Text.Encoding]::GetEncoding(1251)
            $htmlWikiRu = $cp1251w.GetString($bytes)
            $wikiList2 = Get-EpisodesFromWikipediaHtmlFragment $htmlWikiRu
            if ($wikiList2 -and @($wikiList2).Count -gt 0 -and (Test-EpisodeListSeasonEpisodeLooksSane @($wikiList2))) {
                $candidates.Add([pscustomobject]@{ source = 'wiki_cp1251'; list = @(Convert-EpisodeListToUniqueBySeasonEpisode @($wikiList2)) })
            }
        } catch { }
    }
    if ($candidates.Count -gt 0) {
        $best = $null
        $bestScore = -999999
        foreach ($c in $candidates) {
            $score = Get-EpisodeListQualityScore @($c.list)
            if ($score -gt $bestScore) {
                $bestScore = $score
                $best = $c
            }
        }
        if ($best -and $best.list -and @($best.list).Count -gt 0) {
            return @($best.list)
        }
    }
    # Сохранили не страницу эпизодов, а редирект SSO (~несколько КБ): в retpath часто есть film/<id>/episodes/
    $kid = Get-KinopoiskFilmIdFromSsoStubHtml $html
    if ($kid) {
        $net = Get-EpisodesFromKinopoiskEpisodesPage $kid
        $n = @($net).Count
        # Живая страница /episodes/ часто отдаёт в HTML только фрагмент (1–N строк) — не подменяем им полный список
        if ($n -ge 20) { return $net }
    }
    return $null
}

function Get-EpisodesFromKinopoiskEpisodesPage([string]$FilmId) {
    $script:LastResolveHint = ''
    $url = "https://www.kinopoisk.ru/film/$FilmId/episodes/"
    try {
        $html = Get-KinopoiskUrlText $url
    } catch {
        return $null
    }

    $list = Parse-KinopoiskEpisodesFromHtml $html
    if ($list.Count -gt 0) { return $list }

    if (Test-KinopoiskHtmlLooksLikeCaptchaPage $html) {
        $script:LastResolveHint = 'kinopoisk_captcha'
    }

    return $null
}

function Get-TmdbApiKeyFromEnvironment {
    foreach ($name in @('TMDB_API_KEY', 'RENAME_VIDEO_TMDB_API_KEY', 'THEMOVIEDB_API_KEY')) {
        $k = [Environment]::GetEnvironmentVariable($name, 'User')
        if (-not [string]::IsNullOrWhiteSpace($k)) { return $k.Trim() }
        $k = [Environment]::GetEnvironmentVariable($name, 'Machine')
        if (-not [string]::IsNullOrWhiteSpace($k)) { return $k.Trim() }
        $k = [Environment]::GetEnvironmentVariable($name, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($k)) { return $k.Trim() }
    }
    return $null
}

function Get-TmdbTvIdFromUrlOrString([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    if ($t -match '(?i)^tmdb:(\d+)\s*$') { return [int]$Matches[1] }
    if ($t -match '(?i)themoviedb\.org/tv/(\d+)') { return [int]$Matches[1] }
    return $null
}

# Поиск сериала по строке (для автозаполнения tmdb_tv_id из имени папки). Возвращает массив объектов API (id, name, original_name, popularity, first_air_date).
function Search-TmdbTvSeries([string]$Query, [string]$ApiKey, [string]$Language = 'ru-RU') {
    if ([string]::IsNullOrWhiteSpace($Query) -or [string]::IsNullOrWhiteSpace($ApiKey)) { return @() }
    Initialize-WebClient
    $keyEnc = [uri]::EscapeDataString($ApiKey)
    $qEnc = [uri]::EscapeDataString($Query.Trim())
    $langEnc = [uri]::EscapeDataString($Language)
    $uri = "https://api.themoviedb.org/3/search/tv?api_key=$keyEnc&language=$langEnc&query=$qEnc"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
    } catch {
        return @()
    }
    if (-not $resp -or -not $resp.results) { return @() }
    return @($resp.results)
}

function Get-EpisodesFromTmdbTvSeries([int]$TvId, [string]$ApiKey) {
    if ($TvId -le 0) { return $null }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
    Initialize-WebClient
    $keyEnc = [uri]::EscapeDataString($ApiKey)
    $base = "https://api.themoviedb.org/3/tv/$TvId"
    try {
        $tvUri = "$base`?api_key=$keyEnc&language=ru-RU"
        $tv = Invoke-RestMethod -Uri $tvUri -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 90
        if (-not $tv) { return $null }
    } catch {
        return $null
    }
    $list = [System.Collections.Generic.List[object]]::new()
    $maxSn = 0
    if ($null -ne $tv.number_of_seasons) { $maxSn = [int]$tv.number_of_seasons }
    if ($maxSn -le 0 -and $tv.seasons) {
        foreach ($s in @($tv.seasons)) {
            if ($null -ne $s.season_number -and [int]$s.season_number -gt $maxSn) { $maxSn = [int]$s.season_number }
        }
    }
    for ($sn = 1; $sn -le $maxSn; $sn++) {
        try {
            $su = "https://api.themoviedb.org/3/tv/$TvId/season/$sn`?api_key=$keyEnc&language=ru-RU"
            $se = Invoke-RestMethod -Uri $su -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 90
            if (-not $se -or -not $se.episodes) { continue }
            foreach ($ep in @($se.episodes)) {
                $en = [int]$ep.episode_number
                if ($en -le 0) { continue }
                $ti = [string]$ep.name
                if ([string]::IsNullOrWhiteSpace($ti)) { $ti = "Episode $en" }
                $list.Add([pscustomobject]@{ season = $sn; episode = $en; title = $ti.Trim() })
            }
        } catch {
            continue
        }
    }
    if ($list.Count -eq 0) { return $null }
    return @($list)
}

function Get-EpisodeListFromSeriesMetaJson([string]$JsonPath, [string]$TmdbApiKey) {
    $JsonPath = ConvertTo-DotNetFileSystemPath $JsonPath
    if (-not (Test-Path -LiteralPath $JsonPath)) { return $null }
    $raw = $null
    try {
        $raw = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8
    } catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $meta = $null
    try {
        $meta = $raw | ConvertFrom-Json
    } catch {
        return $null
    }
    $tvId = $null
    if ($null -ne $meta.tmdb_tv_id) { $tvId = [int]$meta.tmdb_tv_id }
    elseif ($null -ne $meta.tmdb_id) { $tvId = [int]$meta.tmdb_id }
    if (-not $tvId -or $tvId -le 0) { return $null }
    $key = $TmdbApiKey
    if ([string]::IsNullOrWhiteSpace($key)) { $key = Get-TmdbApiKeyFromEnvironment }
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }
    $items = Get-EpisodesFromTmdbTvSeries $tvId $key
    if (-not $items -or @($items).Count -eq 0) { return $null }
    $wikiQuery = $null
    if ($null -ne $meta.wikipedia_ru_query -and -not [string]::IsNullOrWhiteSpace([string]$meta.wikipedia_ru_query)) {
        $wikiQuery = [string]$meta.wikipedia_ru_query
    }
    elseif ($null -ne $meta.wikipedia_ru -and -not [string]::IsNullOrWhiteSpace([string]$meta.wikipedia_ru)) {
        $wikiQuery = [string]$meta.wikipedia_ru
    }
    if (-not [string]::IsNullOrWhiteSpace($wikiQuery)) {
        $wikiRu = Get-EpisodesFromWikipediaSearchQueries $wikiQuery
        if ($wikiRu -and @($wikiRu).Count -gt 0) {
            $items = Merge-EpisodeTitlesPreferRu @($items) @($wikiRu)
        }
    }
    else {
        $folderHint = $null
        if ($null -ne $meta.series_title_ru -and -not [string]::IsNullOrWhiteSpace([string]$meta.series_title_ru)) {
            $folderHint = [string]$meta.series_title_ru
        }
        if (-not [string]::IsNullOrWhiteSpace($folderHint)) {
            $items = Expand-EpisodeListWithRussianWikipedia @($items) $folderHint
        }
    }
    return @($items)
}

function Get-EpisodesFromTvMaze([string]$Query) {
    if ([string]::IsNullOrWhiteSpace($Query)) { return $null }
    try {
        $q = [uri]::EscapeDataString($Query)
        $show = Invoke-RestMethod -Uri ("https://api.tvmaze.com/singlesearch/shows?q=" + $q) -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        if (-not $show -or -not $show.id) { return $null }
        $eps = Invoke-RestMethod -Uri ("https://api.tvmaze.com/shows/" + $show.id + "/episodes") -Headers @{ 'User-Agent' = $script:FetchUserAgent } -TimeoutSec 60
        if (-not $eps -or $eps.Count -eq 0) { return $null }
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $eps) {
            $sn = [int]$e.season
            $en = [int]$e.number
            $ti = [string]$e.name
            if ($sn -gt 0 -and $en -gt 0 -and -not [string]::IsNullOrWhiteSpace($ti)) {
                $list.Add([pscustomobject]@{ season = $sn; episode = $en; title = $ti.Trim() })
            }
        }
        if ($list.Count -gt 0) { return $list }
    } catch { }
    return $null
}

function Search-DuckDuckGoHtmlForWikipediaUrls([string]$SearchQuery, [int]$Max = 14) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return @() }
    Initialize-WebClient
    $enc = [uri]::EscapeDataString($SearchQuery.Trim())
    try {
        $r = Invoke-WebRequest -Uri 'https://html.duckduckgo.com/html/' -Method Post -Body "q=$enc" `
            -ContentType 'application/x-www-form-urlencoded; charset=UTF-8' -UseBasicParsing -Headers @{
            'User-Agent'      = $script:KinopoiskBrowserUserAgent
            'Accept-Language' = 'ru-RU,ru;q=0.9'
        } -TimeoutSec 55
    } catch { return @() }
    if (-not $r -or [string]::IsNullOrWhiteSpace($r.Content)) { return @() }
    $html = $r.Content
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($html, 'uddg=([^&"''<]+)')) {
        try {
            $decoded = [uri]::UnescapeDataString($m.Groups[1].Value)
            if ($decoded -match '(?i)ru\.wikipedia\.org/wiki/') {
                $clean = ($decoded -split '\?')[0]
                if ($clean.Length -gt 24) { [void]$found.Add($clean) }
            }
        } catch { }
    }
    foreach ($m in [regex]::Matches($html, 'https?://ru\.wikipedia\.org/wiki/[^\s"''<>]+')) {
        [void]$found.Add((($m.Value -split '\?')[0]))
    }
    return @(@($found) | Select-Object -First $Max)
}

function Search-YandexHtmlForWikipediaUrls([string]$SearchQuery, [int]$Max = 14) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return @() }
    Initialize-WebClient
    $enc = [uri]::EscapeDataString($SearchQuery.Trim())
    $uri = "https://yandex.ru/search/?text=$enc"
    try {
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{
            'User-Agent'      = $script:KinopoiskBrowserUserAgent
            'Accept-Language' = 'ru-RU,ru;q=0.9'
        } -TimeoutSec 55
    } catch { return @() }
    if (-not $r -or [string]::IsNullOrWhiteSpace($r.Content)) { return @() }
    $html = $r.Content
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($html, 'https?://ru\.wikipedia\.org/wiki/[^\s"''<>]+')) {
        [void]$found.Add((($m.Value -split '\?')[0]))
    }
    foreach ($m in [regex]::Matches($html, 'https?%3A%2F%2Fru\.wikipedia\.org%2Fwiki%2F[^"&<>]+')) {
        try {
            $decoded = [uri]::UnescapeDataString($m.Value)
            [void]$found.Add((($decoded -split '\?')[0]))
        } catch { }
    }
    return @(@($found) | Select-Object -First $Max)
}

function Search-GoogleHtmlForWikipediaUrls([string]$SearchQuery, [int]$Max = 14) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return @() }
    Initialize-WebClient
    $enc = [uri]::EscapeDataString($SearchQuery.Trim())
    $uri = "https://www.google.com/search?q=$enc&hl=ru"
    try {
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -Headers @{
            'User-Agent'      = $script:KinopoiskBrowserUserAgent
            'Accept-Language' = 'ru-RU,ru;q=0.9'
        } -TimeoutSec 55
    } catch { return @() }
    if (-not $r -or [string]::IsNullOrWhiteSpace($r.Content)) { return @() }
    $html = $r.Content
    $found = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($html, '/url\?q=(https?://ru\.wikipedia\.org/wiki/[^&"''<>]+)')) {
        try {
            $decoded = [uri]::UnescapeDataString($m.Groups[1].Value)
            [void]$found.Add((($decoded -split '\?')[0]))
        } catch { }
    }
    foreach ($m in [regex]::Matches($html, 'https?://ru\.wikipedia\.org/wiki/[^\s"''<>]+')) {
        [void]$found.Add((($m.Value -split '\?')[0]))
    }
    return @(@($found) | Select-Object -First $Max)
}

function Get-EpisodesFromWikipediaViaDuckDuckGoWebSearch([string]$SearchQuery, [string]$Base, [string]$Tail) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return $null }
    $queries = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Tail)) {
        [void]$queries.Add("site:ru.wikipedia.org список эпизодов $Tail")
        [void]$queries.Add("site:ru.wikipedia.org $Tail эпизоды сериала")
    }
    if (-not [string]::IsNullOrWhiteSpace($Base)) {
        [void]$queries.Add("site:ru.wikipedia.org список эпизодов $Base")
        [void]$queries.Add("site:ru.wikipedia.org $Base телесериал эпизоды")
    }
    [void]$queries.Add("site:ru.wikipedia.org список эпизодов $SearchQuery")
    $seenTitle = @{}
    foreach ($dq in ($queries | Select-Object -Unique)) {
        foreach ($pageUrl in (Search-DuckDuckGoHtmlForWikipediaUrls $dq)) {
            $t = Get-WikipediaPageTitleFromUrl $pageUrl
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            if ($seenTitle.ContainsKey($t)) { continue }
            $seenTitle[$t] = $true
            $r = Get-EpisodesFromWikipediaPageTitleOrLinked $t
            if ($r -and @($r).Count -gt 0) { return $r }
        }
        Start-Sleep -Milliseconds (320 + (Get-Random -Maximum 280))
    }
    return $null
}

function Get-EpisodesFromWikipediaAggressiveDdgMerge([string]$SearchQuery) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return $null }
    $base = ($SearchQuery.Trim() -replace '\s*\([^)]*\)\s*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $SearchQuery.Trim() }
    $tail = $null
    $parts = $base -split '\s*[-\u2013\u2014]\s*'
    if ($parts.Count -ge 2) {
        $tail = $parts[-1].Trim()
        if ($tail.Length -lt 2) { $tail = $null }
    }
    $queries = [System.Collections.Generic.List[string]]::new()
    [void]$queries.Add("site:ru.wikipedia.org $SearchQuery список эпизодов")
    [void]$queries.Add("site:ru.wikipedia.org $SearchQuery телесериал эпизоды")
    [void]$queries.Add("site:ru.wikipedia.org $base список серий мультсериал")
    [void]$queries.Add("site:ru.wikipedia.org $base эпизоды сериал")
    [void]$queries.Add("site:ru.wikipedia.org $base мультсериал серии")
    if ($tail) {
        [void]$queries.Add("site:ru.wikipedia.org $tail список эпизодов мультсериал")
        [void]$queries.Add("site:ru.wikipedia.org $tail телесериал все серии")
        [void]$queries.Add("site:ru.wikipedia.org сезон 1 $tail эпизоды")
    }
    $allRows = [System.Collections.Generic.List[object]]::new()
    $seenUrls = @{}
    foreach ($dq in ($queries | Select-Object -Unique)) {
        foreach ($pageUrl in (Search-DuckDuckGoHtmlForWikipediaUrls $dq 24)) {
            if ($seenUrls.ContainsKey($pageUrl)) { continue }
            $seenUrls[$pageUrl] = $true
            $t = Get-WikipediaPageTitleFromUrl $pageUrl
            if ([string]::IsNullOrWhiteSpace($t)) { continue }
            $r = Get-EpisodesFromWikipediaPageTitleOrLinked $t
            if (-not $r) { continue }
            foreach ($x in @($r)) { [void]$allRows.Add($x) }
        }
        Start-Sleep -Milliseconds (300 + (Get-Random -Maximum 250))
    }
    if ($allRows.Count -eq 0) { return $null }
    return @(Convert-EpisodeListToUniqueBySeasonEpisode @($allRows))
}

function Get-EpisodesFromWikipediaAggressiveWebMerge([string]$SearchQuery) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return $null }
    $base = ($SearchQuery.Trim() -replace '\s*\([^)]*\)\s*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $SearchQuery.Trim() }
    $tail = $null
    $parts = $base -split '\s*[-\u2013\u2014]\s*'
    if ($parts.Count -ge 2) {
        $tail = $parts[-1].Trim()
        if ($tail.Length -lt 2) { $tail = $null }
    }
    $queries = [System.Collections.Generic.List[string]]::new()
    [void]$queries.Add("site:ru.wikipedia.org $SearchQuery список эпизодов")
    [void]$queries.Add("site:ru.wikipedia.org $SearchQuery телесериал эпизоды")
    [void]$queries.Add("site:ru.wikipedia.org $base список серий мультсериал")
    if ($tail) {
        [void]$queries.Add("site:ru.wikipedia.org $tail список эпизодов мультсериал")
        [void]$queries.Add("site:ru.wikipedia.org $tail телесериал все серии")
    }

    $allRows = [System.Collections.Generic.List[object]]::new()
    $seenUrls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($q in ($queries | Select-Object -Unique)) {
        $urlBuckets = @(
            @(Search-DuckDuckGoHtmlForWikipediaUrls $q 24),
            @(Search-YandexHtmlForWikipediaUrls $q 24),
            @(Search-GoogleHtmlForWikipediaUrls $q 24)
        )
        foreach ($bucket in $urlBuckets) {
            foreach ($pageUrl in @($bucket)) {
                if ([string]::IsNullOrWhiteSpace($pageUrl)) { continue }
                if (-not $seenUrls.Add($pageUrl)) { continue }
                $t = Get-WikipediaPageTitleFromUrl $pageUrl
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                $r = Get-EpisodesFromWikipediaPageTitleOrLinked $t
                if (-not $r) { continue }
                foreach ($x in @($r)) { [void]$allRows.Add($x) }
            }
            Start-Sleep -Milliseconds (220 + (Get-Random -Maximum 200))
        }
    }
    if ($allRows.Count -eq 0) { return $null }
    return @(Convert-EpisodeListToUniqueBySeasonEpisode @($allRows))
}

function Get-EpisodesFromWikipediaSearchQueries([string]$SearchQuery) {
    if ([string]::IsNullOrWhiteSpace($SearchQuery)) { return $null }
    $base = ($SearchQuery.Trim() -replace '\s*\([^)]*\)\s*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $SearchQuery.Trim() }

    # «Звёздные войны - Мандалорец» → пробуем «Мандалорец» (страница списка эпизодов чаще по короткому названию).
    $tail = $null
    $parts = $base -split '\s*[-\u2013\u2014]\s*'
    if ($parts.Count -ge 2) {
        $tail = $parts[-1].Trim()
    }
    if ([string]::IsNullOrWhiteSpace($tail) -or $tail.Length -lt 2) { $tail = $null }

    $fromTail = @()
    if ($tail) {
        $fromTail = @(
            ("Список эпизодов сериала «" + $tail + "»"),
            ("Список эпизодов телесериала «" + $tail + "»"),
            ("Список эпизодов телесериала " + $tail),
            ("Список эпизодов " + $tail),
            $tail
        )
    }

    $directTitles = $fromTail + @(
        ("Список эпизодов сериала «" + $base + "»"),
        ("Список эпизодов сериала " + $base),
        ("Список эпизодов телесериала «" + $base + "»"),
        ("Список эпизодов телесериала " + $base),
        ("Список эпизодов телесериала " + $SearchQuery.Trim()),
        ("Список эпизодов " + $SearchQuery.Trim()),
        ($SearchQuery.Trim() + " (телесериал)"),
        $SearchQuery.Trim(),
        $base
    )
    foreach ($dt in ($directTitles | Select-Object -Unique)) {
        $r = Get-EpisodesFromWikipediaPageTitleOrLinked $dt
        if ($r) { return $r }
    }

    # У многих сериалов на ru.wikipedia нет одной страницы «Список эпизодов», зато есть «Название (k-й сезон)».
    if ($tail) {
        $r = Get-EpisodesFromWikipediaRuTailSeasonPages $tail
        if ($r) { return $r }
    }

    $queries = @(
        ("Список эпизодов телесериала " + $SearchQuery.Trim()),
        ("Список эпизодов " + $SearchQuery.Trim()),
        ("Список эпизодов " + $base),
        ($SearchQuery.Trim() + " список эпизодов"),
        ($base + " эпизоды")
    )
    if ($tail) {
        $queries = @(
            ("Список эпизодов телесериала " + $tail),
            ("Список эпизодов " + $tail),
            ($tail + " список эпизодов"),
            ($tail + " эпизоды")
        ) + $queries
    }
    foreach ($q in ($queries | Select-Object -Unique)) {
        $st = Search-WikipediaPageTitle $q
        if (-not $st) { continue }
        $r = Get-EpisodesFromWikipediaPageTitleOrLinked $st
        if ($r) { return $r }
    }
    try {
        $rDd = Get-EpisodesFromWikipediaViaDuckDuckGoWebSearch -SearchQuery $SearchQuery.Trim() -Base $base -Tail $tail
        if ($rDd) { return $rDd }
    } catch { }
    return $null
}

function Merge-EpisodeTitlesPreferRu([object[]]$Primary, [object[]]$WikiRu) {
    if (-not $Primary -or $Primary.Count -eq 0) { return $Primary }
    if (-not $WikiRu -or $WikiRu.Count -eq 0) { return $Primary }
    $map = @{}
    foreach ($w in $WikiRu) {
        if (-not $w.season -or -not $w.episode) { continue }
        $sn = [int]$w.season
        $en = [int]$w.episode
        $t = Format-RussianEpisodeTitleFromWikipedia ([string]$w.title)
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $map["$sn`:$en"] = $t.Trim()
    }
    if ($map.Count -eq 0) { return $Primary }
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $Primary) {
        $sn = [int]$p.season
        $en = [int]$p.episode
        $key = "$sn`:$en"
        $tit = [string]$p.title
        if ($map.ContainsKey($key)) {
            $wikiTit = $map[$key]
            if ([string]::IsNullOrWhiteSpace($tit) -or ($tit -notmatch '\p{IsCyrillic}')) {
                $tit = $wikiTit
            }
            elseif (Test-EpisodeTitleLooksLikePlaceholder $tit) {
                $tit = $wikiTit
            }
        }
        $out.Add([pscustomobject]@{ season = $sn; episode = $en; title = $tit })
    }
    return $out
}

function Save-EpisodeListToCsv([object[]]$Items, [string]$CsvPath) {
    $CsvPath = ConvertTo-DotNetFileSystemPath $CsvPath
    $lines = @($Items | ConvertTo-Csv -NoTypeInformation)
    Set-Content -LiteralPath $CsvPath -Value $lines -Encoding utf8
}

function Export-CsvUtf8BomEpisodeList([object[]]$Objects, [string]$LiteralPath) {
    $LiteralPath = ConvertTo-DotNetFileSystemPath $LiteralPath
    if (-not $Objects -or @($Objects).Count -eq 0) {
        Set-Content -LiteralPath $LiteralPath -Value '' -Encoding utf8
        return
    }
    $lines = @($Objects | ConvertTo-Csv -NoTypeInformation)
    Set-Content -LiteralPath $LiteralPath -Value $lines -Encoding utf8
}

function Try-ResolveEpisodeList {
    param(
        [string]$SourceUrl,
        [string]$SearchQuery
    )
    $script:LastResolveHint = ''

    if ($SourceUrl) {
        $u = $SourceUrl.Trim()
        $tmdbId = Get-TmdbTvIdFromUrlOrString $u
        if ($tmdbId) {
            $apiKey = Get-TmdbApiKeyFromEnvironment
            if ($apiKey) {
                $r = Get-EpisodesFromTmdbTvSeries $tmdbId $apiKey
                if ($r) { return $r }
            }
        }
        if ($u -match '\.(html?|htm)\s*$' -and (Test-Path -LiteralPath $u)) {
            $r = Get-EpisodesFromKinopoiskSavedHtmlFile $u
            if ($r) { return $r }
        }
        if ($u -match '(?i)wikipedia') {
            $pt = Get-WikipediaPageTitleFromUrl $u
            if ($pt) {
                $r = Get-EpisodesFromWikipediaPageTitleOrLinked $pt
                if ($r) { return $r }
                $tail = ($pt -split '\s*[-\u2013\u2014]\s*')[-1].Trim()
                if ([string]::IsNullOrWhiteSpace($tail)) { $tail = $pt }
                $r = Get-EpisodesFromWikipediaRuTailSeasonPages $tail
                if ($r) { return $r }
            }
        }
        $kid = Get-KinopoiskFilmIdFromUrl $u
        if ($kid) {
            $r = Get-EpisodesFromKinopoiskEpisodesPage $kid
            if ($r) { return $r }
        }
    }

    if ($SearchQuery) {
        $r = Get-EpisodesFromWikipediaSearchQueries $SearchQuery
        if ($r) { return $r }
    }

    return $null
}
