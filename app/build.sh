#!/usr/bin/env bash
# Builds "Claude Switch.app" (universal, ad-hoc signed) into app/build/.
#   ./app/build.sh            build
#   ./app/build.sh --zip      build and pack build/ClaudeSwitch.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(sed -n 's/^VERSION = "\(.*\)"/\1/p' ../claude-switch)"
SDK="$(xcrun --show-sdk-path)"
OUT="build"
APP="$OUT/Claude Switch.app"
MIN_OS="13.0"

rm -rf "$OUT" && mkdir -p "$OUT/obj"

for arch in arm64 x86_64; do
  echo "==> Compiling ($arch)"
  swiftc -swift-version 5 -O -parse-as-library \
    -sdk "$SDK" -target "$arch-apple-macos$MIN_OS" \
    -framework SwiftUI -framework AppKit -framework ServiceManagement \
    Sources/*.swift -o "$OUT/obj/ClaudeSwitch-$arch"
done

echo "==> Bundling"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$OUT"/obj/ClaudeSwitch-* -output "$APP/Contents/MacOS/ClaudeSwitch"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp ../claude-switch "$APP/Contents/Resources/claude-switch"
chmod 755 "$APP/Contents/Resources/claude-switch"

echo "==> Icon"
swift tools/make-icon.swift "$OUT/icon-1024.png" >/dev/null
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
rm -rf "$OUT/obj" "$ICONSET"

if [ "${1:-}" = "--zip" ]; then
  (cd "$OUT" && ditto -c -k --keepParent "Claude Switch.app" ClaudeSwitch.zip)
  echo "==> $OUT/ClaudeSwitch.zip"
fi
echo "==> Built $APP ($VERSION)"
