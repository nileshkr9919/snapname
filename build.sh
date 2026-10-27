#!/bin/zsh
# Builds Snapname.app.
#
#   ./build.sh             build build/Snapname.app (ad-hoc signed)
#   ./build.sh --install   also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-local.snapname}"
APP="build/Snapname.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Snapname"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Snapname"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Snapname</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Snapname</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSDesktopFolderUsageDescription</key><string>Snapname renames the screenshots saved on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Snapname renames the screenshots saved in your Documents folder.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Snapname renames the screenshots saved in your Downloads folder.</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --timestamp=none \
    --entitlements Resources/Snapname.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Snapname || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Snapname.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Snapname.app
    echo "Installed and launched ~/Applications/Snapname.app"
fi
