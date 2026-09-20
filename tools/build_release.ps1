param(
    [string]$Version = "",
    [string]$OutputRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) "build/release")
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourceInfo = Get-Content -LiteralPath (Join-Path $repo 'modinfo.lua') -Raw
if ($sourceInfo -notmatch 'version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') {
    throw 'Missing semantic version in modinfo.lua'
}
$sourceVersion = $Matches[1]
if ($Version -eq '') { $Version = $sourceVersion }
if ($Version -ne $sourceVersion) { throw 'Requested version differs from modinfo.lua' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$stage = Join-Path $OutputRoot "dst_haptics_compat"
$zip = Join-Path $OutputRoot ("dst_haptics_compat-{0}.zip" -f $Version)
$checksum = $zip + ".sha256"
$preview = Join-Path $OutputRoot "preview.jpg"

if (Test-Path -LiteralPath $stage) {
    $resolvedStage = (Resolve-Path -LiteralPath $stage).Path
    if ($resolvedStage -ne [IO.Path]::GetFullPath($stage) -or
        (Get-Item -LiteralPath $stage).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to clear a redirected staging folder'
    }
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$runtime = @("modinfo.lua", "modmain.lua", "scripts", "README.md", "README.en.md", "LICENSE", "modicon.tex", "modicon.xml")
foreach ($name in $runtime) {
    $source = Join-Path $repo $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release input: $source"
    }
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
}

# Source-relative developer links remain useful in a standalone Workshop ZIP.
foreach ($readmeName in @('README.md', 'README.en.md')) {
    $readmePath = Join-Path $stage $readmeName
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    $readmeText = [regex]::Replace($readmeText, '\]\((docs/[^)]+)\)', {
        param($match)
        '](' + 'https://github.com/Wuty-zju/dst-haptics-compatibility/blob/v' + $Version + '/' + $match.Groups[1].Value + ')'
    })
    [IO.File]::WriteAllText($readmePath, $readmeText, [Text.UTF8Encoding]::new($false))
}

$previewSource = Join-Path $repo "preview.jpg"
if (-not (Test-Path -LiteralPath $previewSource)) {
    throw "Missing Steam Workshop preview: $previewSource"
}
Copy-Item -LiteralPath $previewSource -Destination $preview -Force

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
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksum -Value ("{0}  {1}" -f $hash, (Split-Path $zip -Leaf)) -Encoding ascii

Write-Host "Workshop content: $stage"
Write-Host "Release archive:  $zip"
Write-Host "SHA-256:         $checksum"
Write-Host "Workshop preview: $preview"
