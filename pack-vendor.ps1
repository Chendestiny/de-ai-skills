# Rebuild the vendor/*.zip fallback bundles from the skills' GitHub heads.
# vendor/ is a snapshot by design (upstream outage / rename / deletion fallback), so it
# goes stale whenever a sub-skill is updated. This script refreshes every registry entry
# marked "bundled": true, straight from the repo URL in registry.json.
#
# Layout rule (do not change): each zip holds the skill folder CONTENTS at the zip root
# (SKILL.md at top level), because install.ps1 / install.sh expand the zip directly into
# ~/.agents/skills/<canonical>. Keeping zips (instead of plain folders) keeps this repo at
# two directory levels for strict skill-market packagers.
#
# License rule: only MIT-style, redistributable skills may land here, and their original
# LICENSE must survive inside the zip. Entries with license "none" are never bundled.
#
# Usage:
#   .\pack-vendor.ps1                      # refresh all bundled entries from GitHub
#   .\pack-vendor.ps1 -Only slop-gauge     # refresh one (comma-separated list also works)
#   .\pack-vendor.ps1 -Check               # report which zips differ from GitHub, write nothing
param(
    [string]$Only,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$srcRoot = $PSScriptRoot
$registry = Get-Content (Join-Path $srcRoot 'registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$vendorDir = Join-Path $srcRoot 'vendor'
if (-not (Test-Path $vendorDir)) { New-Item -ItemType Directory -Path $vendorDir | Out-Null }

function Get-RepoExtracted([string]$RepoUrl, [string]$WorkDir) {
    $prefix = [string]$env:DEAI_GH_PREFIX
    $zip = Join-Path $WorkDir 'repo.zip'
    foreach ($branch in @('main', 'master')) {
        $url = "${prefix}${RepoUrl}/archive/refs/heads/${branch}.zip"
        try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 30 } catch { }
        if (Test-Path $zip) {
            $ex = Join-Path $WorkDir 'ex'
            Expand-Archive -Path $zip -DestinationPath $ex -Force
            $top = Get-ChildItem $ex -Directory | Select-Object -First 1
            if ($top) { return $top.FullName }
        }
    }
    throw "download failed: $RepoUrl"
}

function Get-TreeHash([string]$Dir) {
    # order-insensitive content fingerprint of a directory tree, for -Check diffing
    $items = Get-ChildItem $Dir -Recurse -File | Sort-Object FullName
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $items) {
        [void]$sb.AppendLine($f.FullName.Substring($Dir.Length) + '|' + (Get-FileHash $f.FullName -Algorithm SHA1).Hash)
    }
    return (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))) -Algorithm SHA256).Hash
}

# -File passes a comma list as one string, so split it here instead of trusting [string[]]
$onlyList = @()
if ($Only) { $onlyList = @($Only -split '[,;\s]+' | Where-Object { $_ }) }

foreach ($s in $registry.skills) {
    $name = $s.canonical
    if (-not $s.bundled) { continue }
    if ($onlyList.Count -and ($onlyList -notcontains $name)) { continue }
    if ($s.license -eq 'none') { Write-Host "      [skip]   $name has license=none - never bundle it"; continue }
    $tmp = Join-Path $env:TEMP ('deaivendor-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $repoRoot = Get-RepoExtracted $s.repo $tmp
        $skillSrc = if ($s.skill_path -eq '.' -or -not $s.skill_path) { $repoRoot } else { Join-Path $repoRoot $s.skill_path }
        if (-not (Test-Path (Join-Path $skillSrc 'SKILL.md'))) { throw 'SKILL.md not found at skill_path' }
        if (-not (Get-ChildItem $skillSrc -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|LICEN[CS]E|COPYING)' })) {
            Write-Host "      [warn]   ${name}: no LICENSE inside - refusing to pretend this is redistributable"
        }
        $stage = Join-Path $tmp 'stage'
        Copy-Item $skillSrc $stage -Recurse -Force
        Get-ChildItem $stage -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $newZip = Join-Path $tmp 'new.zip'
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $newZip -CompressionLevel Optimal
        $dst = Join-Path $vendorDir ($name + '.zip')
        if ($Check) {
            $status = 'STALE'
            if (Test-Path $dst) {
                $a = Join-Path $tmp 'a'; $b = Join-Path $tmp 'b'
                Expand-Archive -Path $dst -DestinationPath $a -Force
                Expand-Archive -Path $newZip -DestinationPath $b -Force
                if ((Get-TreeHash $a) -eq (Get-TreeHash $b)) { $status = 'current' }
            }
            Write-Host ("      {0,-8} {1}" -f $status, $name)
        } else {
            Copy-Item $newZip $dst -Force
            Write-Host ("      [pack]   {0} -> vendor/{0}.zip ({1} bytes) from {2}" -f $name, (Get-Item $dst).Length, $s.repo)
        }
    } catch {
        Write-Host "      [FAIL]   $name : $($_.Exception.Message)"
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
