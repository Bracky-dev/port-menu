#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=PortMenu.app
rm -rf $APP build.iconset build-makeicon
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O makeicon.swift -o build-makeicon && ./build-makeicon build.iconset
iconutil -c icns build.iconset -o $APP/Contents/Resources/AppIcon.icns
swiftc -O -parse-as-library -swift-version 5 main.swift -o $APP/Contents/MacOS/PortMenu
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PortMenu</string>
  <key>CFBundleIdentifier</key><string>local.portmenu</string>
  <key>CFBundleExecutable</key><string>PortMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $PWD/$APP"
