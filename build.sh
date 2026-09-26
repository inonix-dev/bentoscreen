#!/bin/sh
# Builds a universal (Apple Silicon + Intel) bentoscreen.app, ad-hoc signed.
set -e
cd "$(dirname "$0")"
APP=build/bentoscreen.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 main.swift -o build/bentoscreen-$arch
done
lipo -create build/bentoscreen-arm64 build/bentoscreen-x86_64 -output "$APP/Contents/MacOS/bentoscreen"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>bentoscreen</string>
  <key>CFBundleIdentifier</key><string>org.inonix.bentoscreen</string>
  <key>CFBundleExecutable</key><string>bentoscreen</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign "${SIGN_ID:--}" "$APP"
"$APP/Contents/MacOS/bentoscreen" --check
(cd build && ditto -c -k --keepParent bentoscreen.app bentoscreen.zip)
echo "built build/bentoscreen.app and build/bentoscreen.zip"
