#!/usr/bin/env bash
# build-run.sh - Run the built executable
# Usage: build-run.sh <current_file> <project_root> [profile]

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
  echo "No $BUILD_DIR directory. Run configure and build first." >&2
  exit 1
fi

CMAKE_FILE="$ROOT/CMakeLists.txt"
if [[ ! -f "$CMAKE_FILE" ]]; then
  echo "No CMakeLists.txt in $ROOT" >&2
  exit 1
fi

PROJECT_NAME=$(grep -m1 'project(' "$CMAKE_FILE" | sed 's/.*project(\s*//' | sed 's/\s*.*//')
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME=$(basename "$ROOT")
fi

EXECUTABLE=""
for candidate in "$BUILD_DIR/$BUILD_TYPE/$PROJECT_NAME" "$BUILD_DIR/$PROJECT_NAME" "$BUILD_DIR/$BUILD_TYPE/$PROJECT_NAME.exe" "$BUILD_DIR/$PROJECT_NAME.exe" "$BUILD_DIR/src/$BUILD_TYPE/$PROJECT_NAME" "$BUILD_DIR/src/$PROJECT_NAME" "$BUILD_DIR/bin/$BUILD_TYPE/$PROJECT_NAME" "$BUILD_DIR/bin/$PROJECT_NAME"; do
  if [[ -x "$candidate" ]]; then
    EXECUTABLE="$candidate"
    break
  fi
done

if [[ -z "$EXECUTABLE" ]]; then
  EXECUTABLE=$(find "$BUILD_DIR" -path "*/CMakeFiles" -prune -o -maxdepth 3 -type f -executable -not -name "*.bin" -print 2>/dev/null | head -n 1)
fi

if [[ -z "$EXECUTABLE" ]]; then
  echo "No executable found in $BUILD_DIR/" >&2
  exit 1
fi

echo "Running: $EXECUTABLE"
"$EXECUTABLE" 2>&1
