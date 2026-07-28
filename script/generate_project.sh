#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen 2.45.4 is required on macOS." >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/../PixelDoneAppleCore/Package.swift" ]]; then
  echo "PixelDoneAppleCore must be cloned beside PixelDone-macOS." >&2
  exit 1
fi

cd "$ROOT_DIR"
xcodegen generate --spec project.yml
echo "Generated $ROOT_DIR/PixelDone-macOS.xcodeproj"
