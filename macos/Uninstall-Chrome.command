#!/bin/bash
set -euo pipefail
manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.turntabler.player.json"
if [[ -f "$manifest" ]]; then /bin/rm -- "$manifest"; fi
echo 'TurnTabler Chrome 연결 등록을 해제했습니다. Chrome 확장 목록에서도 TurnTabler를 제거하세요. 앱과 로그인 데이터는 보존됩니다.'
