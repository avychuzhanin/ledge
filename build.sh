#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
CONF="${1:-release}"

swift build -c "$CONF"
BIN=".build/$CONF/Ledge"

APP="Ledge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ledge"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Постоянная подпись: иначе macOS считает каждую пересборку новым приложением
# и заново спрашивает разрешения (запись экрана и прочее).
IDENTITY="OpenWeight Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1
else
  echo "нет личности «$IDENTITY» — подписываю на скорую руку"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1
fi
touch "$APP"
echo "готово → $(pwd)/$APP"
