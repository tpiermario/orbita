#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Orbita.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/orbita-universal-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
for arch in x86_64 arm64; do
  xcrun swiftc -swift-version 5 -O -target "$arch-apple-macosx12.0" Sources/Model.swift Sources/Studio.swift Sources/Wheel.swift Sources/Integration.swift Sources/main.swift -o "$build_dir/Orbita-$arch" -framework AppKit -framework AVKit -framework PDFKit -framework Carbon
  xcrun swiftc -swift-version 5 -O -parse-as-library -target "$arch-apple-macosx12.0" Sources/VisionMain.swift -o "$build_dir/vision-$arch" -framework Vision -framework AppKit
done
xcrun lipo -create "$build_dir/Orbita-x86_64" "$build_dir/Orbita-arm64" -output "$APP/Contents/MacOS/Orbita"
xcrun lipo -create "$build_dir/vision-x86_64" "$build_dir/vision-arm64" -output "$APP/Contents/Resources/bin/orbita-vision"
cp -R Engine "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>Orbita</string><key>CFBundleExecutable</key><string>Orbita</string><key>CFBundleIdentifier</key><string>it.orbita.converter</string><key>CFBundleName</key><string>Orbita</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>2.3</string><key>CFBundleVersion</key><string>5</string><key>LSMinimumSystemVersion</key><string>12.0</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Orbita usa Pages e Keynote per salvare copie nei loro formati nativi.</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Orbita action</string><key>CFBundleURLSchemes</key><array><string>orbita</string></array></dict></array>
<key>NSServices</key><array><dict><key>NSMenuItem</key><dict><key>default</key><string>Apri in Orbita</string></dict><key>NSMessage</key><string>openInOrbita</string><key>NSPortName</key><string>Orbita</string><key>NSSendTypes</key><array><string>public.file-url</string><string>NSFilenamesPboardType</string></array></dict></array>
</dict></plist>
PLIST
xattr -cr "$APP"
# Run package.sh after adding the bundled engines to sign the completed app.
echo "Interfaccia compilata: $PWD/$APP"
