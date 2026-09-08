#!/usr/bin/env bash
# deai-skills installer (Unix). See install.ps1 for the Windows twin.
# Usage:
#   Online:      curl -fsSL https://raw.githubusercontent.com/Chendestiny/deai-skills/main/install.sh | bash
#   Offline:     bash install.sh
#   Check only:  bash install.sh --check
#   Mirror:      export DEAI_GH_PREFIX='https://ghfast.top/'
set -euo pipefail

SELF_REPO='https://github.com/Chendestiny/deai-skills'
AGENTS_ROOT="$HOME/.agents/skills"
DSH_ROOT="$HOME/.dsh/skills"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

roots=()
[ -d "$AGENTS_ROOT" ] && roots+=("$AGENTS_ROOT")
[ -d "$DSH_ROOT" ] && roots+=("$DSH_ROOT")

find_skill_dir() { # name aliases...
  local name="$1"; shift
  for root in "${roots[@]:-$AGENTS_ROOT}"; do
    for n in "$name" "$@"; do
      [ -n "$n" ] && [ -f "$root/$n/SKILL.md" ] && { echo "$root/$n"; return 0; }
    done
  done
  return 1
}

backup_and_clear() { # dest
  local dest="$1"
  if [ -d "$dest" ]; then
    local bak="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$bak"
    echo "      old copy backed up: $(basename "$bak")"
    local keep=2 base
    base="$(basename "$dest")"
    ls -1d "$(dirname "$dest")/${base}.bak-"* 2>/dev/null | head -n -$keep | while read -r old; do
      rm -rf "$old"; echo "      removed old backup: $(basename "$old")"
    done
  fi
}

get_repo_extracted() { # repo_url workdir -> echoes inner root
  local repo="$1" work="$2" prefix="${DEAI_GH_PREFIX:-}" zip="$2/repo.zip"
  for branch in main master; do
    if curl -fsSL --retry 3 -o "$zip" "${prefix}${repo}/archive/refs/heads/${branch}.zip"; then
      if command -v unzip >/dev/null 2>&1; then unzip -q -o "$zip" -d "$work/ex"
      else python3 -c "import sys,zipfile;zipfile.ZipFile('$zip').extractall('$work/ex')"; fi
      find "$work/ex" -mindepth 1 -maxdepth 1 -type d | head -n 1 | while read -r d; do echo "$d"; return 0; done
    fi
  done
  echo "download failed: $repo" >&2; return 1
}

mode=""; [ $CHECK_ONLY -eq 1 ] && mode='[CHECK-ONLY] '

echo "${mode}[1/4] Locate deai-skills source ..."
src_root=""
if [ -f "$(dirname "$0")/registry.json" ]; then
  src_root="$(cd "$(dirname "$0")" && pwd)"
else
  work="$(mktemp -d)"
  src_root="$(get_repo_extracted "$SELF_REPO" "$work")"
fi
echo "      source: $src_root"

# parse registry: need jq or python3
if command -v jq >/dev/null 2>&1; then
  read_registry() { jq -r '.skills[] | [.canonical, .repo, (.skill_path // "null"), ((.aliases // []) | join(",")), (.status // "")] | @tsv' "$src_root/registry.json"; }
elif command -v python3 >/dev/null 2>&1; then
  read_registry() { python3 -c "
import json
for s in json.load(open('$src_root/registry.json', encoding='utf-8'))['skills']:
    print('\t'.join([s['canonical'], s['repo'], s.get('skill_path') or 'null', ','.join(s.get('aliases') or []), s.get('status','')]))"; }
else
  echo 'need jq or python3 to parse registry.json' >&2; exit 1
fi

echo "${mode}[2/4] Router skill 'deai' ..."
router_dest=""
for root in "${roots[@]:-$AGENTS_ROOT}"; do
  [ -f "$root/deai/SKILL.md" ] && { router_dest="$root/deai"; break; }
done
[ -z "$router_dest" ] && router_dest="$AGENTS_ROOT/deai"
if [ $CHECK_ONLY -eq 1 ]; then
  echo "      would install/upgrade router at: $router_dest"
else
  mkdir -p "$(dirname "$router_dest")"
  backup_and_clear "$router_dest"
  mkdir -p "$router_dest"
  for item in SKILL.md AGENTS.md README.md registry.json install.ps1 install.sh LICENSE; do
    [ -e "$src_root/$item" ] && cp -R "$src_root/$item" "$router_dest/"
  done
  echo "      router installed: $router_dest"
fi

echo "${mode}[3/4] Sub-skills (fetch-at-install from upstream) ..."
installed=""; skipped=""; failed=""; deferred=""
while IFS=$'\t' read -r name repo path aliases status; do
  [ -z "$name" ] && continue
  if [ "$status" = "deferred" ] || [ "$path" = "null" ]; then
    deferred="$deferred $name"; echo "      [defer] $name (no skill package yet)"; continue
  fi
  if found="$(find_skill_dir "$name" ${aliases:+${aliases//,/ }})"; then
    skipped="$skipped $name"; echo "      [skip]   $name already present: $found"; continue
  fi
  if [ $CHECK_ONLY -eq 1 ]; then
    installed="$installed $name"; echo "      [would]  install $name from $repo"; continue
  fi
  work="$(mktemp -d)"
  if repo_root="$(get_repo_extracted "$repo" "$work")"; then
    skill_src="$repo_root"
    [ "$path" != "." ] && skill_src="$repo_root/$path"
    if [ ! -f "$skill_src/SKILL.md" ]; then
      alt="$(find "$skill_src" -name SKILL.md -type f 2>/dev/null | head -n 1)"
      [ -n "$alt" ] && skill_src="$(dirname "$alt")"
    fi
    if [ -f "$skill_src/SKILL.md" ]; then
      mkdir -p "$AGENTS_ROOT"
      backup_and_clear "$AGENTS_ROOT/$name"
      cp -R "$skill_src" "$AGENTS_ROOT/$name"
      installed="$installed $name"; echo "      [install] $name -> $AGENTS_ROOT/$name"
    else
      failed="$failed $name"; echo "      [FAIL]   $name : SKILL.md not found inside repo"
    fi
  else
    failed="$failed $name"
  fi
  rm -rf "$work"
done < <(read_registry)

echo "${mode}[4/4] Summary"
echo "      router    : $([ $CHECK_ONLY -eq 1 ] && echo 'check-only, no write' || echo "ok -> $router_dest")"
echo "      installed :${installed:- (none)}"
echo "      present  :${skipped:- (none)}"
echo "      deferred :${deferred:- (none)}"
[ -n "$failed" ] && echo "      FAILED   :$failed  (check repo url / branch / network)"
exit 0
