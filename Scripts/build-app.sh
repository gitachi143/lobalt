#!/bin/bash
# Builds Pulse.app — a real, double-clickable macOS bundle.
#
#   ./Scripts/build-app.sh                    release build into ./build
#   ./Scripts/build-app.sh --install          also copy it into /Applications
#   ./Scripts/build-app.sh --install ~/Desktop   ...or wherever you keep it
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Pulse"
BUNDLE_ID="com.gitachi.Pulse"
VERSION="1.0.0"
BUILD_NUMBER="1"
OUT="$ROOT/build"
APP="$OUT/$APP_NAME.app"

echo "==> Building $APP_NAME $VERSION"

# Universal where the toolchain allows it, native otherwise.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
  echo "    universal binary (arm64 + x86_64)"
else
  echo "    universal build unavailable, falling back to this machine's architecture"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

echo "==> Rendering icon"
ICONSET="$OUT/$APP_NAME.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Pulse listens when you press the microphone button so you can say how long you want for a task.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Pulse turns what you say into a timer. Recognition runs on this Mac whenever your hardware supports it.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array><string>pulse</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="${2:-/Applications}"
  INSTALL_DIR="${INSTALL_DIR%/}"
  if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "!! $INSTALL_DIR does not exist" >&2
    exit 1
  fi
  DEST="$INSTALL_DIR/$APP_NAME.app"
  echo "==> Installing to $DEST"
  # Quit a running copy so the replacement isn't left in a half state.
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "==> Installed at $DEST"
fi
