#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LC_ALL=en_US.UTF-8
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fL --retry 2 https://github.com/ip7z/7zip/releases/download/26.05/7z2605-mac.tar.xz -o "$WORK/7zip.tar.xz"
# Pinned checksum recorded from the official macOS distribution.
EXPECTED="12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570"
ACTUAL="$(shasum -a 256 "$WORK/7zip.tar.xz" | awk '{print $1}')"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "Контрольная сумма 7-Zip не совпала. Загрузка остановлена." >&2
  exit 1
fi
mkdir -p "$ROOT/Vendor/7zip"
tar -xf "$WORK/7zip.tar.xz" -C "$ROOT/Vendor/7zip"
echo "7-Zip 26.05 установлен в Vendor/7zip."
