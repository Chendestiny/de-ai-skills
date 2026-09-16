# de-ai-skills installer (de-AI skill router + sub-skills, fetch-at-install)
# Usage (any agent or terminal):
#   Online:  irm https://raw.githubusercontent.com/Chendestiny/de-ai-skills/main/install.ps1 | iex
#   Offline: download the repo zip, extract, then inside de-ai-skills-main run
#            powershell -ExecutionPolicy Bypass -File .\install.ps1
#   Check only (no writes):  .\install.ps1 -CheckOnly
#   Explicit source:         .\install.ps1 -Source <path to repo zip OR extracted folder>
#   Mirror prefix (optional, prepended to the GitHub download URL):
#            $env:DEAI_GH_PREFIX = 'https://ghfast.top/'
# Effects:
#   1. Router skill 'de-ai' lands in a cross-agent skills dir (%USERPROFILE%\.agents\skills\de-ai),
#      upgraded in place if it already exists there (old copy backed up, newest 2 kept)
#   2. Sub-skills listed in registry.json are fetched from their upstream repos at install
#      time (MIT core packages bundled under vendor/ as fallback). Skills already present (canonical or alias) are skipped.
#   3. Deferred / null-path entries are reported but not installed.
#   4. Every landed skill is validated against what agent skill loaders require (frontmatter
#      name == install dir name, kebab-case, description present); mismatched names are fixed,
#      other problems are reported as LOAD-RISK because the agent would silently not see the skill.
# NOTE: keep this file ASCII-only and BOM-less. It must survive `irm | iex` on both
#       PowerShell 5.1 and PowerShell 7. Chinese docs live in README.md / SKILL.md / AGENTS.md.
param(
    [switch]$CheckOnly,
    [string]$Source
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$selfRepo = 'https://github.com/Chendestiny/de-ai-skills'
$agentsRoot = Join-Path $HOME '.agents\skills'
$dshRoot    = Join-Path $HOME '.dsh\skills'
$roots = @($agentsRoot, $dshRoot) | Where-Object { Test-Path $_ }
if (-not $roots) { $roots = @($agentsRoot) }
$script:loadRisk = @()

function Find-SkillDir([string]$Name, [string[]]$Aliases) {
    foreach ($root in $roots) {
        foreach ($n in @($Name) + @($Aliases)) {
            if ($n) {
                $p = Join-Path $root $n
                if (Test-Path (Join-Path $p 'SKILL.md')) { return $p }
            }
        }
    }
    return $null
}

function Backup-AndClear([string]$Dest) {
    if (Test-Path $Dest) {
        $bak = "$Dest.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        while (Test-Path -LiteralPath $bak) { Start-Sleep -Milliseconds 500; $bak = "$Dest.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss') }
        Move-Item -LiteralPath $Dest -Destination $bak -Force
        Write-Host "      old copy backed up: $(Split-Path $bak -Leaf)"
    }
    $keep = 2
    $baks = @(Get-ChildItem -LiteralPath (Split-Path $Dest -Parent) -Filter ((Split-Path $Dest -Leaf) + '.bak-*') -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($baks.Count -gt $keep) {
        $baks | Select-Object -First ($baks.Count - $keep) | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force; Write-Host "      removed old backup: $($_.Name)" }
    }
}

# Agent skill loaders key a skill by the frontmatter name in SKILL.md and parse that
# block as YAML. A name that is not lowercase kebab-case, a missing name/description, or
# a bare "colon+space" inside an unquoted value makes the loader skip the file silently:
# installed, yet invisible to the agent. On copies we just placed we fix what is safely
# fixable (rewrite the name, quote the value); a skill that was already installed is only
# reported, since it is the user's copy.
function Repair-SkillManifest([string]$Dir, [string]$Canonical, [switch]$ReadOnly) {
    if (-not (Test-Path -LiteralPath $Dir)) { return }
    $p = Join-Path $Dir 'SKILL.md'
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "      [warn]   $Canonical SKILL.md missing after copy"
        $script:loadRisk += $Canonical; return
    }
    $raw = [System.IO.File]::ReadAllText($p)
    $m = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $m.Success) {
        Write-Host "      [warn]   $Canonical has no YAML frontmatter; strict agent loaders will skip it"
        $script:loadRisk += $Canonical; return
    }
    $fm = $m.Groups[1].Value
    $fmStart = $m.Groups[1].Index; $fmLen = $m.Groups[1].Length
    $nl = if ($raw.IndexOf("`r`n") -ge 0) { "`r`n" } else { "`n" }
    $lines = @($fm -split "\r?\n")
    $hasName = $false; $hasDesc = $false; $fixed = $false; $oldName = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^name:[ \t]*(.*)$') {
            $hasName = $true
            $v = $Matches[1].Trim().Trim([char]34, [char]39).Trim()
            if ($v -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
                if ($ReadOnly) {
                    Write-Host "      [warn]   $Canonical has invalid skill name '$v'; agents cannot load it (reinstall it)"
                    $script:loadRisk += $Canonical
                } else {
                    $lines[$i] = "name: $Canonical"; $fixed = $true; $oldName = $v
                }
            } elseif ($v -cne $Canonical) {
                Write-Host "      [note]   $Canonical is visible to agents as '$v' (frontmatter name != dir name); registry aliases must list it"
            }
            continue
        }
        if ($line -match '^description:[ \t]*\S') { $hasDesc = $true }
        if ($line -match '^([A-Za-z0-9_-]+):[ \t]+(.*)$') {
            $key = $Matches[1]; $v = $Matches[2]
            $c = if ($v.Length -gt 0) { $v.Substring(0, 1) } else { '' }
            $plain = $c -ne '"' -and $c -ne "'" -and $c -ne '>' -and $c -ne '|' -and $c -ne '[' -and $c -ne '&' -and $c -ne '*'
            if ($plain -and $v.Contains(': ')) {
                if ($ReadOnly) {
                    Write-Host "      [warn]   $Canonical frontmatter '$key' holds an unquoted colon; some agents fail to parse that YAML"
                    $script:loadRisk += $Canonical
                } else {
                    $esc = $v.Replace('\', '\\').Replace('"', '\"')
                    $lines[$i] = "$($key): `"$esc`""; $fixed = $true
                    Write-Host "      [fix]    $Canonical quoted frontmatter '$key' (bare colon breaks YAML)"
                }
            }
        }
    }
    if (-not $hasName) { Write-Host "      [warn]   $Canonical frontmatter has no name; strict agent loaders will skip it"; $script:loadRisk += $Canonical }
    if (-not $hasDesc) { Write-Host "      [warn]   $Canonical frontmatter has no description; strict agent loaders will skip it"; $script:loadRisk += $Canonical }
    if ($fixed) {
        $newRaw = $raw.Substring(0, $fmStart) + ($lines -join $nl) + $raw.Substring($fmStart + $fmLen)
        [System.IO.File]::WriteAllText($p, $newRaw, (New-Object System.Text.UTF8Encoding($false)))
        if ($oldName) { Write-Host "      [fix]    $Canonical frontmatter name was '$oldName' (not a valid skill name); rewritten to the dir name" }
    }
}

function Get-HttpFile([string]$Url, [string]$Out) {
    # fail fast: tight timeouts so the vendor fallback kicks in quickly when upstream is unreachable
    try { Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing -TimeoutSec 15; return $true } catch { }
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -fsSL --connect-timeout 8 --max-time 60 --retry 1 --ssl-no-revoke -o $Out $Url
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}

function Get-RepoExtracted([string]$RepoUrl, [string]$WorkDir) {
    # GitHub codeload zip; try main then master
    $prefix = [string]$env:DEAI_GH_PREFIX
    $zip = Join-Path $WorkDir 'repo.zip'
    foreach ($branch in @('main', 'master')) {
        $url = "${prefix}${RepoUrl}/archive/refs/heads/${branch}.zip"
        if (Get-HttpFile $url $zip) {
            $ex = Join-Path $WorkDir 'ex'
            Expand-Archive -Path $zip -DestinationPath $ex -Force
            $top = Get-ChildItem $ex -Directory | Select-Object -First 1
            if ($top) { return $top.FullName }
        }
    }
    throw "download failed: $RepoUrl"
}

$mode = if ($CheckOnly) { '[CHECK-ONLY] ' } else { '' }

# ---- [1/4] locate this project's source ----
Write-Host "${mode}[1/4] Locate de-ai-skills source ..."
$srcRoot = $null
if ($Source) {
    if (Test-Path $Source -PathType Leaf) {
        $tmp = Join-Path $env:TEMP ('deai-' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -Path $Source -DestinationPath $tmp -Force
        $hit = Get-ChildItem $tmp -Recurse -Filter registry.json -File | Where-Object { $_.Directory.Name -notmatch 'bak' } | Select-Object -First 1
        if (-not $hit) { throw 'Unexpected content: registry.json not found' }
        $srcRoot = $hit.DirectoryName
    } elseif (Test-Path $Source -PathType Container) {
        $srcRoot = (Resolve-Path $Source).Path
    } else { throw "Source not found: $Source" }
} elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'registry.json'))) {
    $srcRoot = $PSScriptRoot
} else {
    $tmp = Join-Path $env:TEMP ('deai-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $srcRoot = Get-RepoExtracted $selfRepo $tmp
}
Write-Host "      source: $srcRoot"

$registry = Get-Content (Join-Path $srcRoot 'registry.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- [2/4] install / upgrade router skill 'de-ai' ----
Write-Host "${mode}[2/4] Router skill 'de-ai' ..."
$routerDest = $null
foreach ($root in $roots) {
    $p = Join-Path $root 'de-ai'
    if (Test-Path (Join-Path $p 'SKILL.md')) { $routerDest = $p; break }
}
if (-not $routerDest) { $routerDest = Join-Path $agentsRoot 'de-ai' }
$bundle = 'SKILL.md', 'AGENTS.md', 'README.md', 'README_EN.md', 'registry.json', 'install.ps1', 'install.sh', 'pack-vendor.ps1', 'LICENSE'
if ($CheckOnly) {
    Write-Host ("      would {0} router at: {1}" -f (@{ $true = 'upgrade' }[$routerDest -ne $null] -replace '^$', 'install'), $routerDest)
} else {
    Backup-AndClear $routerDest
    New-Item -ItemType Directory -Path $routerDest -Force | Out-Null
    foreach ($item in $bundle) {
        $p = Join-Path $srcRoot $item
        if (Test-Path $p) { Copy-Item $p $routerDest -Recurse -Force }
    }
    Repair-SkillManifest $routerDest 'de-ai'
    Write-Host "      router installed: $routerDest"
}

# ---- [3/4] sub-skills per registry ----
Write-Host "${mode}[3/4] Sub-skills (fetch-at-install from upstream) ..."
$installed = @(); $skipped = @(); $failed = @(); $deferred = @()
foreach ($s in $registry.skills) {
    $name = $s.canonical
    if ($s.status -eq 'deferred' -or -not $s.skill_path -or $s.skill_path -eq 'null') {
        $deferred += $name
        Write-Host "      [defer] $name (no skill package yet)"
        continue
    }
    $existing = Find-SkillDir $name @($s.aliases)
    if ($existing) {
        $skipped += $name
        Write-Host "      [skip]   $name already present: $existing"
        Repair-SkillManifest $existing (Split-Path $existing -Leaf) -ReadOnly
        continue
    }
    # offline cache: env DEAI_OFFLINE_DIR (your local repo downloads) or <srcRoot>\offline.
    # Tolerant match: dir named <canonical> or <canonical>-main (case-insensitive), must contain SKILL.md.
    $offlineHit = $null
    foreach ($base in @(([string]$env:DEAI_OFFLINE_DIR), (Join-Path $srcRoot 'offline'))) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        foreach ($suffix in @('', '-main')) {
            $want = $name + $suffix
            $hit = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $want } | Select-Object -First 1
            if ($hit -and (Test-Path (Join-Path $hit.FullName 'SKILL.md'))) { $offlineHit = $hit.FullName; break }
        }
        if ($offlineHit) { break }
    }
    if ($offlineHit) {
        if ($CheckOnly) {
            $installed += $name
            Write-Host "      [would]  install $name from offline cache ($offlineHit)"
        } else {
            $dest = Join-Path $agentsRoot $name
            Backup-AndClear $dest
            Copy-Item $offlineHit $dest -Recurse -Force
            Repair-SkillManifest $dest $name
            $installed += $name
            Write-Host "      [install] $name <- offline cache ($offlineHit)"
        }
        continue
    }
    if ($CheckOnly) {
        $installed += $name
        $bundled = Test-Path (Join-Path $srcRoot ("vendor\" + $name + '.zip'))
        Write-Host ("      [would]  install $name from $($s.repo)" + $(if ($bundled) { ' (bundle fallback ready)' }))
        continue
    }
    try {
        $tmp = Join-Path $env:TEMP ('deai-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $repoRoot = Get-RepoExtracted $s.repo $tmp
        $skillSrc = if ($s.skill_path -eq '.') { $repoRoot } else { Join-Path $repoRoot $s.skill_path }
        if (-not (Test-Path (Join-Path $skillSrc 'SKILL.md'))) {
            $alt = Get-ChildItem $skillSrc -Recurse -Filter SKILL.md -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($alt) { $skillSrc = $alt.DirectoryName } else { throw 'SKILL.md not found inside repo' }
        }
        $dest = Join-Path $agentsRoot $name
        Backup-AndClear $dest
        Copy-Item $skillSrc $dest -Recurse -Force
        Repair-SkillManifest $dest $name
        $installed += $name
        Write-Host "      [install] $name -> $dest"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        # fallback: repo-bundled vendor zip (MIT skills shipped in this repo; zip form keeps
        # the repo two-level on disk so strict skill markets accept the layout)
        $vendorZip = Join-Path $srcRoot ("vendor\" + $name + '.zip')
        if (Test-Path $vendorZip) {
            $dest = Join-Path $agentsRoot $name
            Backup-AndClear $dest
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Expand-Archive -Path $vendorZip -DestinationPath $dest -Force
            Repair-SkillManifest $dest $name
            $installed += $name
            Write-Host "      [install] $name <- repo bundle zip (upstream failed: $($_.Exception.Message))"
        } else {
            $failed += $name
            Write-Host "      [FAIL]   $name : $($_.Exception.Message)"
        }
    }
}

# ---- [4/4] summary ----
Write-Host "${mode}[4/4] Summary"
Write-Host ("      router : {0}" -f $(if ($CheckOnly) { 'check-only, no write' } else { "ok -> $routerDest" }))
Write-Host ("      installed : {0}" -f $(if ($installed) { $installed -join ', ' } else { '(none)' }))
Write-Host ("      present   : {0}" -f $(if ($skipped) { $skipped -join ', ' } else { '(none)' }))
Write-Host ("      deferred  : {0}" -f $(if ($deferred) { $deferred -join ', ' } else { '(none)' }))
if ($failed) { Write-Host ("      FAILED    : {0}  (check repo url / branch / network)" -f ($failed -join ', ')) }
$risk = @($script:loadRisk | Select-Object -Unique)
if ($risk.Count) { Write-Host ("      LOAD-RISK : {0}  (installed, but the agent may not list it - see the [warn] lines above)" -f ($risk -join ', ')) }
if (-not $CheckOnly) { Write-Host '      done. say "de-AI this article" (or Chinese) to any agent to start.' }
