#!/bin/bash
# Package an assembled offline app. Requires macOS and a complete Orbita.app.
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-Orbita.app}"
OUT="${2:-$PWD/Orbita-2.3.1-Universal.dmg}"
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"
[[ ! -e "$OUT" ]] || { echo "Output already exists: $OUT" >&2; exit 1; }
for path in Contents/MacOS/Orbita Contents/Resources/Runtime/python/bin/python3 Contents/Resources/Runtime-arm64/python/bin/python3 Contents/Resources/bin/ffmpeg Contents/Resources/bin/arm64/ffmpeg Contents/Resources/Licenses/INDEX.json; do
  [[ -f "$APP/$path" ]] || { echo "Missing component: $path" >&2; exit 1; }
done
stage=$(mktemp -d "${TMPDIR:-/tmp}/orbita-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto --norsrc "$APP" "$stage/Orbita.app"
xattr -cr "$stage/Orbita.app"
codesign --force --deep --sign - "$stage/Orbita.app"
codesign --verify --deep --strict "$stage/Orbita.app"
ln -s /Applications "$stage/Applicazioni"
cp INSTALLAZIONE.txt "$stage/Leggimi.txt"
hdiutil create -volname 'Orbita 2.3.1' -srcfolder "$stage" -format ULMO -fs HFS+ -o "$OUT"
hdiutil verify "$OUT"
shasum -a 256 "$OUT"
