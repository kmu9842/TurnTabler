#!/bin/bash
set -euo pipefail
app_path="${1:-/Applications/TurnTabler.app}"
if [[ ! -x "$app_path/Contents/MacOS/TurnTablerChromeHost" ]]; then
  echo 'TurnTabler.app을 먼저 Applications 폴더로 옮겨 주세요.'
  exit 1
fi
/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app_path/Contents/Info.plist" | /usr/bin/grep -qx 'com.turntabler.player'
host_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
settings_dir="$HOME/Library/Application Support/TurnTablerChrome"
mkdir -p "$host_dir" "$settings_dir"
host_temp="$(mktemp "$host_dir/.turntabler.XXXXXX")"
settings_temp="$(mktemp "$settings_dir/.turntabler.XXXXXX")"
trap 'rm -f "$host_temp" "$settings_temp"' EXIT
printf '{}\n' > "$host_temp"
printf '{}\n' > "$settings_temp"
/usr/bin/plutil -insert name -string com.turntabler.player "$host_temp"
/usr/bin/plutil -insert description -string 'TurnTabler YouTube player' "$host_temp"
/usr/bin/plutil -insert path -string "$app_path/Contents/MacOS/TurnTablerChromeHost" "$host_temp"
/usr/bin/plutil -insert type -string stdio "$host_temp"
/usr/bin/plutil -insert allowed_origins -json '["chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/"]' "$host_temp"
/usr/bin/plutil -insert appPath -string "$app_path" "$settings_temp"
mv -f "$host_temp" "$host_dir/com.turntabler.player.json"
mv -f "$settings_temp" "$settings_dir/settings.json"
echo 'Chrome 연결 등록 완료. chrome://extensions에서 개발자 모드를 켜고, 이 패키지의 extension 폴더를 압축해제된 확장으로 로드하세요.'
