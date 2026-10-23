#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
export LC_ALL=en_US.UTF-8

if [ ! -x "$ROOT/Vendor/7zip/7zz" ]; then
  echo "7-Zip отсутствует. Выполните ./Scripts/fetch-engine.sh"
  exit 1
fi

CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)"
APP="$ROOT/build/MacZip.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/7zip"
cp "$BIN_DIR/MacZip" "$APP/Contents/MacOS/MacZip"
cp "$ROOT/Vendor/7zip/7zz" "$APP/Contents/Helpers/7zz"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Vendor/7zip/License.txt" "$ROOT/Vendor/7zip/readme.txt" "$ROOT/Vendor/7zip/History.txt" "$APP/Contents/Resources/7zip/"
cp -R "$ROOT/Vendor/7zip/MANUAL" "$APP/Contents/Resources/7zip/"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
swift "$ROOT/Scripts/make-icon.swift" "$ROOT/build"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP/Contents/Helpers/7zz"
codesign --force --sign - "$APP"
echo "Готово: $APP"
echo "Запуск: open \"$APP\""
