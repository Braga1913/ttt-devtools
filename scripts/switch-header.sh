#!/usr/bin/env bash
# switch-header.sh - Switch between C/C++ header and source files
# Usage: switch-header.sh <current_file> <project_root>

set -euo pipefail

FILE="${1:-}"
ROOT="${2:-}"

if [[ -z "$FILE" ]]; then
  echo "No file provided" >&2
  exit 1
fi

BASENAME="$(basename "$FILE")"
DIR="$(dirname "$FILE")"
NAME="${BASENAME%.*}"
EXT="${BASENAME##*.}"

declare -A HEADER_EXTS=( [cpp]=h [cc]=h [cxx]=hxx [c]=h [hpp]=cpp [hxx]=cxx [hh]=cc [h]=cpp )
declare -A SEARCH_EXTS=( [cpp]="h hpp" [cc]="h hh" [cxx]="hxx hxx" [c]="h" [hpp]="cpp cxx" [hxx]="cxx cpp" [hh]="cc cpp" [h]="cpp cc c" )

EXT_LOWER="$(echo "$EXT" | tr '[:upper:]' '[:lower:]')"

if [[ -v "SEARCH_EXTS[$EXT_LOWER]" ]]; then
  IFS=' ' read -r -a CANDIDATES <<< "${SEARCH_EXTS[$EXT_LOWER]}"
  for candidate_ext in "${CANDIDATES[@]}"; do
    candidate="$DIR/$NAME.$candidate_ext"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      exit 0
    fi
  done
  if [[ -n "$ROOT" && "$ROOT" != "$DIR" ]]; then
    for candidate_ext in "${CANDIDATES[@]}"; do
      while IFS= read -r -r found; do
        if [[ -n "$found" ]]; then
          echo "$found"
          exit 0
        fi
      done < <(find "$ROOT" -name "$NAME.$candidate_ext" -type f 2>/dev/null | head -n 1)
    done
  fi
  echo "No matching file found for $BASENAME" >&2
  exit 1
fi

for src_ext in cpp cc c cxx; do
  candidate="$DIR/$NAME.$src_ext"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
done

if [[ -n "$ROOT" && "$ROOT" != "$DIR" ]]; then
  for src_ext in cpp cc c cxx; do
    while IFS= read -r -r found; do
      if [[ -n "$found" ]]; then
        echo "$found"
        exit 0
      fi
    done < <(find "$ROOT" -name "$NAME.$src_ext" -type f 2>/dev/null | head -n 1)
  done
fi

echo "No matching file found for $BASENAME" >&2
exit 1
