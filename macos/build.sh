#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/release/macos}"
artwork_dir="${2:-$project_dir/artifacts/mac-artwork}"
stage="$(mktemp -d "${TMPDIR:-/tmp}/turntabler-build.XXXXXX")"
bundle="$stage/TurnTabler-macOS/TurnTabler.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$output_dir"
for arch in arm64 x86_64; do
  xcrun swiftc -parse-as-library -O -target "$arch-apple-macos15.4" -framework AppKit -framework WebKit -framework QuartzCore "$project_dir/macos/YouTubeAddress.swift" "$project_dir/macos/TurnTabler.swift" -o "$stage/TurnTabler-$arch"
  xcrun swiftc -parse-as-library -O -target "$arch-apple-macos15.4" -framework AppKit "$project_dir/macos/YouTubeAddress.swift" "$project_dir/macos/ChromeHost.swift" -o "$stage/ChromeHost-$arch"
done
lipo -create "$stage/TurnTabler-arm64" "$stage/TurnTabler-x86_64" -output "$bundle/Contents/MacOS/TurnTabler"
lipo -create "$stage/ChromeHost-arm64" "$stage/ChromeHost-x86_64" -output "$bundle/Contents/MacOS/TurnTablerChromeHost"
cp "$project_dir/macos/Info.plist" "$bundle/Contents/Info.plist"
cp "$project_dir/native/YouTubeBridge.js" "$bundle/Contents/Resources/"
for name in body record highlights tonearm; do cp "$artwork_dir/$name.png" "$bundle/Contents/Resources/"; done
mkdir -p "$stage/TurnTabler.iconset"
icon="$project_dir/native/Assets/Icon/forge-gpt-image-2-5-sunburst-1.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon" --out "$stage/TurnTabler.iconset/icon_${size}x${size}.png" >/dev/null
  twice=$((size * 2))
  sips -z "$twice" "$twice" "$icon" --out "$stage/TurnTabler.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/TurnTabler.iconset" -o "$bundle/Contents/Resources/TurnTabler.icns"
codesign --force --sign - "$bundle/Contents/MacOS/TurnTablerChromeHost"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
"$bundle/Contents/MacOS/TurnTabler" --self-test
"$bundle/Contents/MacOS/TurnTablerChromeHost" --self-test
lipo -archs "$bundle/Contents/MacOS/TurnTabler"
cp "$project_dir/macos/Install-Chrome.command" "$project_dir/macos/Uninstall-Chrome.command" "$stage/TurnTabler-macOS/"
cp "$project_dir/macos/README-Mac.txt" "$stage/TurnTabler-macOS/"
cp -R "$project_dir/chrome-extension/extension" "$stage/TurnTabler-macOS/extension"
chmod +x "$stage/TurnTabler-macOS/"*.command
ditto -c -k --sequesterRsrc --keepParent "$stage/TurnTabler-macOS" "$output_dir/TurnTabler-macOS-1.1.0-universal.zip"
ditto "$bundle" "$output_dir/TurnTabler.app"
echo "Built: $output_dir/TurnTabler-macOS-1.1.0-universal.zip"
