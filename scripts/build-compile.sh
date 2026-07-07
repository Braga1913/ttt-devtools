#!/usr/bin/env bash
# build-compile.sh - Build CMake project
# Usage: build-compile.sh <current_file> <project_root> [profile]

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

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "No $BUILD_DIR directory. Run configure first." >&2
  exit 1
fi

cmake --build "$BUILD_DIR" --config "$BUILD_TYPE" 2>&1
