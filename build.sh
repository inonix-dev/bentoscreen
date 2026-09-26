#!/bin/sh
# Builds a universal (Apple Silicon + Intel) BentoScreen.app, ad-hoc signed.
set -e
cd "$(dirname "$0")"
APP=build/BentoScreen.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 main.swift -o build/BentoScreen-$arch
done
swift icon.swift build/AppIcon.iconset
mkdir -p "$APP/Contents/Resources"
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
lipo -create build/BentoScreen-arm64 build/BentoScreen-x86_64 -output "$APP/Contents/MacOS/BentoScreen"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BentoScreen</string>
  <key>CFBundleIdentifier</key><string>org.inonix.bentoscreen</string>
  <key>CFBundleExecutable</key><string>BentoScreen</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign "${SIGN_ID:--}" "$APP"
"$APP/Contents/MacOS/BentoScreen" --check
(cd build && ditto -c -k --keepParent BentoScreen.app BentoScreen.zip)
echo "built build/BentoScreen.app and build/BentoScreen.zip"
