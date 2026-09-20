param(
    [string]$Version = "1.4.0",
    [string]$OutputRoot = (Join-Path $PSScriptRoot "..\build\release")
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stage = Join-Path $OutputRoot "dst_haptics_compat"
$zip = Join-Path $OutputRoot ("dst_haptics_compat-{0}.zip" -f $Version)

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$runtime = @("modinfo.lua", "modmain.lua", "scripts", "README.md", "LICENSE")
foreach ($name in $runtime) {
    $source = Join-Path $repo $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release input: $source"
    }
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
}

foreach ($name in @("modicon.tex", "modicon.xml")) {
    $source = Join-Path $repo $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stage -Force
    }
}

$modinfo = Get-Content -LiteralPath (Join-Path $stage "modinfo.lua") -Raw
if ($modinfo -notmatch ('version\s*=\s*"' + [regex]::Escape($Version) + '"')) {
    throw "modinfo.lua version does not match $Version"
}
if ($modinfo -notmatch 'client_only_mod\s*=\s*true' -or
    $modinfo -notmatch 'all_clients_require_mod\s*=\s*false' -or
    $modinfo -notmatch 'server_only_mod\s*=\s*false') {
    throw "Client-only Workshop flags are invalid"
}

if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

Write-Host "Workshop content: $stage"
Write-Host "Release archive:  $zip"
