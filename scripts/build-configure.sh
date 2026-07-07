#!/usr/bin/env bash
# build-configure.sh - Configure CMake project
# Usage: build-configure.sh <current_file> <project_root> [profile]

set -euo pipefail

FILE="${1:-}"
ROOT="${2:-}"
PROFILE="${3:-}"

source "$(dirname "$0")/build-env.sh"
load_build_config || exit 1

if [[ -z "$ROOT" ]]; then
  echo "No project root found" >&2
  exit 1
fi

cd "$ROOT"

if [[ ! -f "CMakeLists.txt" ]]; then
  echo "No CMakeLists.txt in $ROOT" >&2
  exit 1
fi

BUILD_DIR=$(get_build_dir "$PROFILE")

EXTRA=""
if [[ -n "$EXTRA_ARGS" ]]; then
  EXTRA="$EXTRA_ARGS"
fi

cmake -B "$BUILD_DIR" \
  -G "$GENERATOR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  $EXTRA \
  2>&1
