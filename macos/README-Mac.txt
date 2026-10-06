TurnTabler 1.1.0 — macOS preview

macOS 15.4 이상, Apple Silicon 및 Intel을 지원하는 Universal 앱입니다.
TurnTabler.app을 Applications 폴더로 옮긴 뒤 실행하세요.
Apple Developer ID 서명과 공증은 포함되지 않았습니다. 출처 확인 후 macOS 시스템 설정 → 개인정보 보호 및 보안 → 확인 없이 열기로 이 앱의 실행을 허용할 수 있습니다.

아래 입력칸에 YouTube 영상/재생목록 링크를 붙여 넣고 Enter를 누르세요.
설정 위의 브라우저 버튼으로 YouTube 원래 페이지에서 로그인·검색할 수 있습니다.
로그인은 앱의 WebKit 프로필에 유지되며 Safari/Chrome의 로그인과는 별도입니다.
설정과 마지막 링크는 macOS UserDefaults(com.turntabler.player)에 저장됩니다.
앱을 다시 실행해도 마지막 링크를 자동 재생하지 않습니다.
창을 숨겼다면 메뉴 막대의 레코드 아이콘에서 다시 표시할 수 있습니다.

설정에서 출력 장치를 선택할 수 있습니다. macOS WebKit은 출력 장치 목록을 위해 마이크 권한을 요구합니다. '출력 장치 목록 허용'을 누른 경우에만 권한을 요청하며, 생성된 마이크 트랙은 즉시 해제합니다. 마이크를 녹음하거나 OBS에 보내지 않습니다. 허용하지 않으면 시스템 기본 출력을 사용합니다.

Chrome 우클릭 연결은 선택 사항입니다. 앱을 Applications에 옮긴 다음 Install-Chrome.command를 실행하고 chrome://extensions → 개발자 모드 → 압축해제된 확장 프로그램 로드에서 extension 폴더를 선택하세요. 앱 위치가 달라졌다면 확장 설정에서 .app 경로를 다시 선택합니다.

Windows의 OBS 직접 스트림 연결은 이 Mac 미리보기 버전에 포함되지 않았습니다. Mac에서는 OBS의 macOS 오디오 캡처 소스에서 앱을 선택하는 기능을 사용해야 하며, 이 조합은 실제 Mac에서 검증되지 않았습니다.

Mac 빌드 서버에서 컴파일·URL 검증·WebKit 화면 전환을 검사했습니다. 실제 Mac의 YouTube 로그인, 장시간 재생, 하드웨어 출력 전환, OBS 캡처는 아직 검증하지 못했습니다.
