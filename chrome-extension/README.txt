TurnTabler Chrome 확장 프로그램 1.0.0

TurnTabler.exe와 별도로 설치하는 선택 기능입니다.
Windows 10/11 x64, Chrome 123 이상, 함께 배포된 TurnTabler 1.0.0을 사용합니다.

설치
1. TurnTabler.exe를 사용할 폴더에 저장합니다.
2. 이 ZIP을 압축 해제하고 Install.cmd를 더블클릭합니다.
3. 사용할 TurnTabler.exe를 선택합니다. 설치기가 파일 정보와 호환 여부를 확인합니다.
   앱을 실행하거나 바꾸지 않으며, 관리자 권한은 필요하지 않습니다.
4. Chrome 주소창에 chrome://extensions 를 입력합니다.
5. 오른쪽 위 '개발자 모드'를 켜고 '압축해제된 확장 프로그램을 로드합니다'를 누릅니다.
6. 설치 안내에서 복사한 폴더를 선택합니다:
   %LOCALAPPDATA%\TurnTablerChrome\extension
7. 확장 프로그램의 TurnTabler 아이콘을 클릭해 '앱이 연결되었습니다'를 확인합니다.

사용
- 유튜브의 영상, 썸네일 링크, Shorts, 실시간 영상, 재생목록을 우클릭한 뒤
  'TurnTabler로 재생'을 선택합니다.
- 영상 위에서 한 번 우클릭하면 유튜브 자체 메뉴 맨 위에 같은 아이콘과
  'TurnTabler로 재생'이 표시됩니다. 이 항목을 누르면 앱으로 재생을 보냅니다.
- 썸네일 링크·페이지 빈 공간에서는 Chrome 기본 우클릭 메뉴를 사용합니다.
- 앱이 실행 중이면 같은 위젯에서 재생하며, 숨겨진 위젯은 다시 표시합니다.
- 앱이 꺼져 있으면 자동 실행한 뒤 요청한 영상을 재생합니다.
- 믹스/재생목록, 곡 순서, 링크에 포함된 시작 시간을 유지합니다.
- Chrome에서 이미 재생 중인 영상은 그대로이므로 필요하면 일시정지해 주세요.
- 로그인/동의가 필요한 영상은 TurnTabler 설정의 '유튜브 페이지 보기'에서 진행합니다.

경로 변경
- 확장 아이콘 > '설정 · EXE 경로 변경'을 엽니다.
  chrome://extensions의 확장 세부정보 > 확장 프로그램 옵션에서도 열 수 있습니다.
- 현재 연결 경로와 실제 파일 버전을 확인할 수 있습니다.
- '파일 선택…'으로 다른 EXE를 선택하거나 전체 경로를 입력하고 '경로 저장'을 누릅니다.
- EXE가 이동되어 기존 경로에 없어도 설정에서 복구할 수 있습니다.
  잘못된 파일/경로를 선택하면 기존 설정을 유지합니다.
- 다른 폴더의 TurnTabler가 이미 실행 중이면 해당 경로를 선택하거나 그 앱을 종료하세요.

업데이트 / 문제 해결
- 확장을 업데이트하면 Install.cmd 실행 후 chrome://extensions의 새로고침을 누르고,
  열려 있던 유튜브 탭도 새로고침합니다. 확장 버전이 1.0.0인지 확인하세요.
- 이전에 ZIP 안의 extension 폴더를 직접 로드했다면, 새 ZIP의 extension 파일로
  해당 폴더를 갱신하거나 기존 확장을 제거하고 설치 안내의 폴더를 로드합니다.
- 툴바의 ! 표시나 알림이 뜨면 아이콘을 눌러 연결을 확인합니다.
- 조직 정책으로 개발자 모드/Native Messaging이 차단된 Chrome에서는 설치할 수 없습니다.

제거
1. Uninstall.cmd를 실행해 앱 연결을 해제합니다.
2. chrome://extensions 에서 'TurnTabler로 재생'을 제거합니다.
3. 필요하면 %LOCALAPPDATA%\TurnTablerChrome 폴더를 삭제합니다.
TurnTabler.exe와 기존 앱 설정은 유지됩니다.

설치 구조
- Chrome 웹 스토어에 게시하지 않은 로컬 설치용 확장입니다.
- 설치 스크립트가 확장 파일을 %LOCALAPPDATA%\TurnTablerChrome에 복사하고,
  현재 Windows 사용자에게만 Chrome Native Messaging 연결을 등록합니다.
- 별도 TurnTabler.ChromeHost.exe가 요청할 때만 실행되며, 상주하지 않습니다.
  Windows 기본 .NET Framework 4.8을 사용합니다. 앱 EXE는 교체하지 않습니다.
- 기존 배포본에는 Windows UI Automation으로 링크 입력/재생을 전달합니다.
  숨긴 창은 앱의 트레이 복원 동작으로 다시 표시합니다. 최신 연결 지원 빌드는 파이프를 사용합니다.
- 경로 설정은 %LOCALAPPDATA%\TurnTablerChrome\host\settings.json에 저장합니다.
- 확장 ID: ebnjhkdpohpgeipkalbfklpfibjadnhd
- 기존 EXE의 아이콘을 동일하게 사용합니다.
- 유튜브 플레이어의 우클릭 메뉴를 수정하기 위해 유튜브 사이트에 접근합니다.
  방문 기록은 수집하지 않으며, 선택한 유튜브 주소만 로컬 앱에 보냅니다.
- 요청 권한: 유튜브 메뉴 수정, Chrome 우클릭 메뉴, 로컬 앱 연결, 실패 알림,
  최근 요청 결과(주소 제외) 저장.

기술 문서
https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
https://developer.chrome.com/docs/extensions/reference/api/contextMenus
https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/ui-automation-control-patterns-overview
