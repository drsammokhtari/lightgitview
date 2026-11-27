#!/bin/sh
# Builds dist/LightGitView.app with SwiftPM only (no full Xcode). The app is one binary and a logo.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
name="LightGitView"
app="$here/dist/$name.app"
# Universal binary: build each architecture, then merge with lipo (works with SwiftPM alone).
for arch in arm64 x86_64; do
  (cd "$here" && swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path ".build-$arch")
done
bin=$(mktemp -d)/LightGitView
lipo -create \
  "$(cd "$here" && swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build-arm64 --show-bin-path)/LightGitView" \
  "$(cd "$here" && swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86_64 --show-bin-path)/LightGitView" \
  -output "$bin"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
set_dir=$(mktemp -d)/AppIcon.iconset; mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
  sips -z $s $s "$here/branding/logo.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$here/branding/logo.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set_dir" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>com.thriveos.lightgitview</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.4.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>LightGitView lists the git repos in the folder you choose.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null
echo "$app"
