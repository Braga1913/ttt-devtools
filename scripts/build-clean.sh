#!/usr/bin/env bash
# build-clean.sh - Clean build directory and reconfigure
# Usage: build-clean.sh <current_file> <project_root> [profile]

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

BUILD_DIR=$(get_build_dir "$PROFILE")

if [[ -d "$BUILD_DIR" ]]; then
  rm -rf "$BUILD_DIR"
  echo "Removed $BUILD_DIR"
fi

if [[ -f "CMakeLists.txt" ]]; then
  cmake -B "$BUILD_DIR" \
    -G "$GENERATOR" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    $EXTRA_ARGS \
    2>&1
else
  echo "No CMakeLists.txt in $ROOT" >&2
  exit 1
fi
