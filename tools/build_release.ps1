param(
    [string]$Version = "",
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "build/release")
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$sourceInfo = Get-Content -LiteralPath (Join-Path $repo "modinfo.lua") -Raw
if ($sourceInfo -notmatch '(?m)^\s*version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$') {
    throw 'Missing semantic version in modinfo.lua'
}
$sourceVersion = $Matches[1]
if ($Version -eq '') { $Version = $sourceVersion }
if ($Version -ne $sourceVersion) { throw 'Requested version differs from modinfo.lua' }
if ($sourceInfo -notmatch '(?m)^\s*client_only_mod\s*=\s*true\s*$' -or
    $sourceInfo -notmatch '(?m)^\s*all_clients_require_mod\s*=\s*false\s*$' -or
    $sourceInfo -notmatch '(?m)^\s*server_only_mod\s*=\s*false\s*$') {
    throw "Client-only Workshop flags are invalid"
}

if (Test-Path -LiteralPath (Join-Path $repo ".git")) {
    [string[]]$modules = @(git -C $repo -c core.quotepath=false ls-files --cached --deduplicate -- scripts)
    if ($LASTEXITCODE -ne 0) { throw "Cannot list the runtime modules tracked by Git" }
} else {
    # A clean source archive has the same flat runtime directory as a checkout.
    $scriptRoot = Join-Path $repo "scripts"
    [string[]]$modules = @(Get-ChildItem -LiteralPath $scriptRoot -File -Filter "*.lua" |
        ForEach-Object { "scripts/" + $_.Name })
}
if ($modules.Count -eq 0 -or @($modules | Where-Object {
    $_ -cnotmatch '^scripts/[^/\\]+\.lua$' -or $_ -ieq "scripts/haptics.lua"
}).Count -gt 0) {
    throw "Expected the mod's own flat scripts/*.lua modules"
}
[Array]::Sort($modules, [StringComparer]::Ordinal)
$runtime = @("modinfo.lua", "modmain.lua", "README.md", "README.en.md", "LICENSE", "modicon.tex", "modicon.xml") + $modules
foreach ($name in ($runtime + "preview.jpg")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $name) -PathType Leaf)) {
        throw "Missing release input: $name"
    }
}

$OutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
$stage = Join-Path $OutputRoot "dst_haptics_compat"
$zip = Join-Path $OutputRoot ("dst_haptics_compat-{0}.zip" -f $Version)
$checksum = $zip + ".sha256"
$preview = Join-Path $OutputRoot "preview.jpg"

foreach ($existing in @($stage, $zip, $checksum, $preview)) {
    if (Test-Path -LiteralPath $existing) {
        throw "Build output already exists. Preserve it and choose a new -OutputRoot: $existing"
    }
}
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "scripts") | Out-Null
foreach ($name in $runtime) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $stage $name)
}
Copy-Item -LiteralPath (Join-Path $repo "preview.jpg") -Destination $preview

# Source-relative developer links remain useful in a standalone Workshop ZIP.
foreach ($readmeName in @('README.md', 'README.en.md')) {
    $readmePath = Join-Path $stage $readmeName
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    $readmeText = [regex]::Replace($readmeText, '\]\((docs/[^)]+|CONTRIBUTING\.md|CHANGELOG\.md|AGENTS\.md)\)', {
        param($match)
        '](' + 'https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v' + $Version + '/' + $match.Groups[1].Value + ')'
    })
    [IO.File]::WriteAllText($readmePath, $readmeText, [Text.UTF8Encoding]::new($false))
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$entryTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $runtime) {
        $entry = $archive.CreateEntry("dst_haptics_compat/$name", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $entryTime
        $source = [IO.File]::OpenRead((Join-Path $stage $name))
        try {
            $target = $entry.Open()
            try { $source.CopyTo($target) } finally { $target.Dispose() }
        } finally { $source.Dispose() }
    }
} finally {
    $archive.Dispose()
}
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($checksum, ("{0}  {1}" -f $hash, (Split-Path $zip -Leaf)) + [char]10, [Text.Encoding]::ASCII)

Write-Host "Workshop content: $stage"
Write-Host "Release archive:  $zip"
Write-Host "SHA-256:         $checksum"
Write-Host "Workshop preview: $preview"
