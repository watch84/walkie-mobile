#!/usr/bin/env bash
# Pre-build check: fails the build when Walkie.xcodeproj is older than the sources it was
# generated from. The project is git-ignored, so `git pull` alone never adds new files to it.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PBXPROJ="$ROOT/Walkie.xcodeproj/project.pbxproj"
FIX="Run 'make project' (or 'xcodegen generate') in $ROOT, then build again."

if [[ ! -f "$PBXPROJ" ]]; then
  echo "error: $PBXPROJ not found. $FIX"
  exit 1
fi

if [[ "$ROOT/project.yml" -nt "$PBXPROJ" ]]; then
  echo "error: project.yml changed after Walkie.xcodeproj was generated. $FIX"
  exit 1
fi

missing=0
while IFS= read -r -d '' file; do
  name="$(basename "$file")"
  if ! grep -qF "/* $name in Sources */" "$PBXPROJ"; then
    echo "error: ${file#"$ROOT"/} is not in Walkie.xcodeproj. $FIX"
    missing=1
  fi
done < <(find "$ROOT/Walkie" "$ROOT/WalkieTests" -name '*.swift' -print0)

exit "$missing"
