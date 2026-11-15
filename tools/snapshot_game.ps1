param(
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [string]$ClientLog = '',
    [string]$OutputRoot = ''
)

# Read installed game data; write an independent, ignored evidence session.
# Never launch the game, alter installation files or redistribute this directory.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$game = (Resolve-Path -LiteralPath $GameRoot).Path
$bundle = Join-Path $game 'data/databundles/scripts.zip'
if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) { throw "Missing scripts bundle: $bundle" }
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repo ('.local/evidence/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
if (Test-Path -LiteralPath $output) { throw "Evidence directory already exists; choose a new path: $output" }

$manifestPath = Join-Path (Split-Path (Split-Path $game -Parent) -Parent) 'appmanifest_322330.acf'
$buildId = $null
if (Test-Path -LiteralPath $manifestPath) {
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    if ($manifestText -match '"buildid"\s+"(\d+)"') { $buildId = $Matches[1] }
}
$gameVersion = $null
foreach ($candidate in @((Join-Path $game 'version.txt'), (Join-Path $game 'data/version.txt'))) {
    if (Test-Path -LiteralPath $candidate) { $gameVersion = (Get-Content -LiteralPath $candidate -Raw).Trim(); break }
}
$bundleHash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
New-Item -ItemType Directory -Path $output | Out-Null
$native = Join-Path $output 'native'
New-Item -ItemType Directory -Path $native | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($bundle)
try {
    $prefix = [IO.Path]::GetFullPath($native) + [IO.Path]::DirectorySeparatorChar
    foreach ($entry in $archive.Entries) {
        # Only game Lua sources are needed. Validate every destination before extraction.
        if (-not $entry.FullName.StartsWith('scripts/', [StringComparison]::Ordinal)) { continue }
        $destination = [IO.Path]::GetFullPath((Join-Path $native $entry.FullName))
        if (-not $destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe scripts bundle entry: $($entry.FullName)"
        }
        if ($entry.FullName.EndsWith('/')) { continue }
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
    }
} finally { $archive.Dispose() }

$haptics = Join-Path $native 'scripts/haptics.lua'
if (-not (Test-Path -LiteralPath $haptics)) { throw 'Bundle did not contain scripts/haptics.lua' }
$events = @([regex]::Matches((Get-Content -LiteralPath $haptics -Raw), '(?m)^\s*\{\s*event\s*=\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value })
$logEvidence = $null
if ($ClientLog) {
    $log = Get-Item -LiteralPath $ClientLog
    $savedLog = Join-Path $output 'client_log.txt'
    Copy-Item -LiteralPath $log.FullName -Destination $savedLog
    $logEvidence = [ordered]@{
        source = $log.FullName
        sourceLastWriteTimeUtc = $log.LastWriteTimeUtc.ToString('o')
        sha256 = (Get-FileHash -LiteralPath $savedLog -Algorithm SHA256).Hash.ToLowerInvariant()
        matchingLines = @(Select-String -LiteralPath $savedLog -Pattern 'Loading mod:.*Haptics|\[DST Haptics Compat\]' |
            ForEach-Object { [ordered]@{ line = $_.LineNumber; text = $_.Line } })
    }
}
$head = & git -C $repo rev-parse HEAD
$snapshot = [ordered]@{
    schemaVersion = 1
    observedAtUtc = [DateTime]::UtcNow.ToString('o')
    modCommit = $head
    gameRoot = $game
    gameVersion = $gameVersion
    steamBuildId = $buildId
    scriptsBundleSha256 = $bundleHash
    hapticsSha256 = (Get-FileHash -LiteralPath $haptics -Algorithm SHA256).Hash.ToLowerInvariant()
    definitions = $events.Count
    uniqueEvents = @($events | Select-Object -Unique).Count
    originalScripts = Join-Path $native 'scripts'
    clientLog = $logEvidence
    limitation = 'Local snapshot and log observation only; no new game session or physical controller test.'
}
$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'snapshot.json') -Encoding utf8
Write-Host "Snapshot: $output"
Write-Host "Native scripts: $($snapshot.originalScripts)"
Write-Host "Game $gameVersion / Steam build $buildId / definitions=$($events.Count) / unique=$($snapshot.uniqueEvents)"
