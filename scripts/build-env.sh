#!/usr/bin/env bash
# build-env.sh - Shared build environment loader
# Source this from other build scripts: source "$(dirname "$0")/build-env.sh"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="$PLUGIN_DIR/build-config.json"

load_build_config() {
  if [[ ! -f "$BUILD_CONFIG" ]]; then
    echo "No build-config.json found" >&2
    return 1
  fi

  GENERATOR=$(jq -r '.generator // "Ninja"' "$BUILD_CONFIG")
  BUILD_TYPE=$(jq -r '.buildType // "Debug"' "$BUILD_CONFIG")
  BUILD_DIR=$(jq -r '.buildDir // "build"' "$BUILD_CONFIG")
  EXTRA_ARGS=$(jq -r '.extraArgs // ""' "$BUILD_CONFIG")
}

get_build_dir() {
  local profile="${1:-}"
  if [[ -n "$profile" ]]; then
    local dir
    dir=$(jq -r ".buildDirs[\"$profile\"] // \"build/$profile\"" "$BUILD_CONFIG")
    echo "$dir"
  else
    echo "$BUILD_DIR"
  fi
}
