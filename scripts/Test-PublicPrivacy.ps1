[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [switch]$Json
)

# Read-only release gate. Findings contain locations and rule names, never values.
# This is a practical guard against accidental publication, not a secret detector guarantee.
$ErrorActionPreference = 'Stop'
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$repo = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([char[]]'\/')
if (-not [IO.Directory]::Exists($repo)) { throw 'Repository root does not exist.' }
$findings = New-Object 'System.Collections.Generic.List[object]'
$files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
$pending = New-Object 'System.Collections.Generic.Stack[string]'
$pending.Push($repo)
$excludedFolders = @('.git', 'dist', '.build', '.validation', '.qa', 'node_modules', 'obj', 'bin')

function Add-PrivacyFinding([string]$Path, [int]$Line, [string]$Rule) {
    $relative = $Path.Substring($repo.Length).TrimStart([char[]]'\/').Replace('\', '/')
    $findings.Add([pscustomobject]@{ Path = $relative; Line = $Line; Rule = $Rule })
}

while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-PrivacyFinding $item.FullName 0 'Linked path cannot be audited safely'
        } elseif ($item.PSIsContainer) {
            if ($item.Name -notin $excludedFolders) { $pending.Push($item.FullName) }
        } else { $files.Add($item) }
    }
}

function Test-ExampleAddress([string]$Value) {
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$address)) { return $true }
    $bytes = $address.GetAddressBytes()
    if ($bytes.Length -ne 4) { return $false }
    return ($bytes[0] -eq 127 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0 -and $bytes[3] -eq 1) -or
        ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -eq 2) -or
        ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
        ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113)
}

function Test-PublicHost([string]$HostName) {
    $hostValue = $HostName.ToLowerInvariant().TrimEnd('.')
    if ($hostValue -in @('localhost', 'example.com', 'example.net', 'example.org')) { return $true }
    if ($hostValue.EndsWith('.invalid') -or $hostValue.EndsWith('.example.com') -or $hostValue.EndsWith('.example.net') -or $hostValue.EndsWith('.example.org')) { return $true }
    foreach ($domain in @('microsoft.com', 'github.com', 'githubusercontent.com', 'nuget.org', 'dot.net', 'powershellgallery.com')) {
        if ($hostValue -eq $domain -or $hostValue.EndsWith('.' + $domain)) { return $true }
    }
    $address = $null
    if ([Net.IPAddress]::TryParse($hostValue, [ref]$address)) { return (Test-ExampleAddress $hostValue) }
    return $false
}

$textExtensions = @('.ps1', '.psm1', '.psd1', '.cs', '.csproj', '.xaml', '.xml', '.json', '.md', '.txt', '.yml', '.yaml', '.cmd', '.bat', '.py', '.js', '.mjs', '.ts', '.html', '.css', '.config', '.props', '.targets', '.toml', '.sh')
$ipv4Pattern = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'
$absolutePathPattern = '(?<![A-Za-z0-9_])[A-Za-z]:[\\/](?![\\/])'
$urlPattern = 'https?://[^\s<>"''`{}]+'
$privateKeyPattern = '-{5}BEGIN\s+(?:[A-Z0-9 ]+\s+)?PRIVATE\s+KEY-{5}'
$dpapiHeader = '01000000' + 'd08c9ddf0115d1118c7a00c04fc297eb'
# Generic identifiers and labels used by private server inventories.
$personalPattern = '(?i)(?:direct|phone|computer)relay|\b[a-z]{2}-(?:home|relay)-\d+\b|[\u4e00-\u9fff]{1,4}\u540c\u5b66(?:\u51fa\u54c1|\s*3X)|\u4f4f\u5b85\u9762\u677f'
$secretPattern = '(?i)["'']?(?:password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret)["'']?\s*[:=]\s*["'']([^"''\r\n]{8,})["'']'
$hostLiteralPattern = '(?i)["'']?(?:host|hostname|domain|address)["'']?\s*[:=]\s*["'']([a-z0-9][a-z0-9.-]*\.[a-z]{2,})["'']'
$emailPattern = '(?i)\b[a-z0-9._%+-]+@([a-z0-9.-]+\.[a-z]{2,})\b'
$checked = 0

foreach ($file in $files) {
    if ($file.Extension.ToLowerInvariant() -in @('.dpapi', '.pem', '.key', '.pfx', '.p12', '.vpsaccounts', '.db', '.sqlite', '.sqlite3', '.log') -or $file.Name -in @('known_hosts', 'id_rsa', 'id_ed25519', '.env')) {
        Add-PrivacyFinding $file.FullName 0 'Credential, host identity, database, or runtime file'
        continue
    }
    if ($file.Name -match '(?i)^(?:servers|inventory|accounts|purchases|metadata|服务器列表|服务器元数据|购买来源|界面设置)\.json$') {
        Add-PrivacyFinding $file.FullName 0 'Runtime inventory must not be published'
    }
    if ($file.Extension.ToLowerInvariant() -notin $textExtensions -and $file.Name -notin @('.gitignore', '.gitattributes', 'LICENSE', 'NOTICE')) { continue }
    if ($file.Length -gt 8MB) { Add-PrivacyFinding $file.FullName 0 'Oversized text file requires manual review'; continue }
    $checked++
    $lines = [IO.File]::ReadAllLines($file.FullName)
    for ($index = 0; $index -lt $lines.Length; $index++) {
        $line = $lines[$index]
        $number = $index + 1
        if ($line -match $privateKeyPattern -and $line -notmatch '(?i)(?:-notmatch|-match|\.Contains\(|\.StartsWith\()') { Add-PrivacyFinding $file.FullName $number 'Private key material' }
        if ($line.IndexOf($dpapiHeader, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Add-PrivacyFinding $file.FullName $number 'Encrypted Windows credential payload' }
        if ($line -match $absolutePathPattern) { Add-PrivacyFinding $file.FullName $number 'Absolute drive path' }
        if ($line -match '(?i)(?:\\\\[^\\\s]+\\(?:Users|home)\\|/(?:Users|home)/[^/\s]+/)') { Add-PrivacyFinding $file.FullName $number 'Personal home path' }
        if ($line -match $personalPattern) { Add-PrivacyFinding $file.FullName $number 'Private server or personal product label' }
        foreach ($match in [regex]::Matches($line, $ipv4Pattern)) {
            if ($line -match '(?i)(?:Assembly(?:File)?Version|<Version>|<FileVersion>|<AssemblyVersion>)') { continue }
            $prefix = $line.Substring(0, $match.Index)
            $suffix = $line.Substring($match.Index + $match.Length)
            if ($prefix -match '(?i)(?:Chrome|Firefox|Edg|Safari|Version)/$' -or ($prefix -match '(?:^|[\\/])v\d+\.\d+_$' -and $suffix -match '^__[a-f0-9]{16}[\\/]')) { continue }
            if (-not (Test-ExampleAddress $match.Value)) { Add-PrivacyFinding $file.FullName $number 'Non-example IPv4 address' }
        }
        foreach ($match in [regex]::Matches($line, $urlPattern)) {
            $uri = $null
            $candidate = $match.Value.TrimEnd([char[]]'),.;')
            if ([Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref]$uri) -and $uri.Host) {
                if ($uri.UserInfo) { Add-PrivacyFinding $file.FullName $number 'Credentials in URL' }
                if (-not (Test-PublicHost $uri.Host)) { Add-PrivacyFinding $file.FullName $number 'Unapproved URL host; use a reserved example or review public allowlist' }
            }
        }
        foreach ($match in [regex]::Matches($line, $hostLiteralPattern)) {
            if (-not (Test-PublicHost $match.Groups[1].Value)) { Add-PrivacyFinding $file.FullName $number 'Unapproved hostname literal' }
        }
        foreach ($match in [regex]::Matches($line, $emailPattern)) {
            if (-not (Test-PublicHost $match.Groups[1].Value)) { Add-PrivacyFinding $file.FullName $number 'Non-example email address' }
        }
        foreach ($match in [regex]::Matches($line, $secretPattern)) {
            $value = $match.Groups[1].Value
            if ($value -match '^(?:<[^>]+>|\$.*|example.*|demo.*|test.*|change[-_ ]?me.*|replace[-_ ].*|your[-_ ].*)$') { continue }
            # Field declarations and dynamic expressions are legitimate; only literals above match.
            Add-PrivacyFinding $file.FullName $number 'Non-placeholder credential literal'
        }
    }
}

$unique = @($findings | Sort-Object Path, Line, Rule -Unique)
$result = [pscustomobject]@{
    Passed = ($unique.Count -eq 0)
    TextFilesChecked = $checked
    Findings = $unique
    Note = 'Read-only static checks. Review binary artifacts separately and publish only the release allowlist.'
}
if ($Json) { $result | ConvertTo-Json -Depth 6 } else {
    if ($unique.Count) { $unique | Format-Table -AutoSize | Out-String | Write-Host }
    Write-Host ('Public privacy gate: {0}; {1} text files; {2} findings.' -f $(if ($result.Passed) { 'PASS' } else { 'FAIL' }), $checked, $unique.Count)
}
if (-not $result.Passed) { throw 'Public privacy gate failed. Remove or replace the reported data before publishing.' }
