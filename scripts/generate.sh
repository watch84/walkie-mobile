#!/usr/bin/env bash
# Generates Walkie.xcodeproj from project.yml and optionally opens it.
#   scripts/generate.sh          generate + open in Xcode
#   scripts/generate.sh --no-open
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate --spec project.yml

if [[ "${1:-}" != "--no-open" ]]; then
  open Walkie.xcodeproj
fi
