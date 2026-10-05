# TurnTabler

투명한 Windows 네이티브 턴테이블 위젯입니다. 창과 레코드 회전, 설정, 볼륨 조작은 C# WPF로 구현하며 영상은 Windows WebView2에서 유튜브의 원래 재생 페이지를 엽니다. Electron과 Node.js는 실행에 필요하지 않습니다.

## 실행

[GitHub Releases](https://github.com/kmu9842/TurnTabler/releases/latest)에서 **TurnTabler.exe 하나만** 내려받아 실행하세요. 이미지와 재생 스크립트, .NET 런타임은 EXE에 포함됩니다.

Windows 10 2004 이상 / Windows 11의 x64 환경을 지원합니다. 영상은 Windows의 Microsoft Edge WebView2 Runtime을 사용합니다. WebView2가 없는 PC에는 [Microsoft 공식 런타임](https://developer.microsoft.com/microsoft-edge/webview2/)을 설치해야 합니다. 별도의 .NET 설치는 필요하지 않습니다.

소스에서 개발용으로 실행하려면 `Start-TurnTabler.cmd` 또는 `npm.cmd start`를 사용합니다.

## 사용

- 아래 입력칸에 유튜브 영상 또는 재생목록 링크를 붙여 넣고 Enter를 누릅니다. `RD…` 믹스 링크도 선택한 영상과 목록을 함께 유지합니다.
- 영상은 수평을 유지하며 레코드판 전체에 투사됩니다. 홈과 표면 무늬는 24초에 한 바퀴씩 천천히 회전하고, 부드러운 조명 반사는 고정됩니다. 일시정지하면 판이 멈춥니다.
- 영상 중심과 레코드 중심은 일치하며, 영상의 색은 받침대 윤곽에서 약 4px 안쪽에만 부드럽게 퍼집니다.
- 판이나 ▶ 버튼으로 재생/일시정지합니다. ‹ / › 버튼은 이전·다음 곡, 받침대 오른쪽 아래 슬라이더는 음량입니다.
- 음량 위의 작은 **CC** 버튼으로 유튜브 자막을 켜거나 끕니다. 흰색 밑줄은 켜짐 상태이며 곡을 바꾸거나 앱을 다시 실행해도 설정을 유지합니다. 볼륨·CC·재생바는 무색 투명 유리 테마입니다. 영상 자체에 새겨진 가사는 CC로 지울 수 없습니다.
- 주소창 오른쪽 **≡** 버튼으로 재생목록을 열어 곡을 직접 고를 수 있습니다. 곡이 끝나면 유튜브 재생목록 순서대로 다음 곡을 재생합니다.
- 톤암은 바늘 끝이 판 바깥쪽 홈에 살짝 걸치도록 배치했습니다. 주소창과 재생 버튼은 투명한 유리 테마로 묶고 받침대 아래에 여유를 두었습니다. 재생 중 조절바의 불투명도는 10%이며 하단 곡 제목은 표시하지 않습니다. 재생 안내는 조작부 바로 아래 표시됩니다.
- 받침대를 드래그해 이동합니다. CC 위의 설정 버튼과 트레이 우클릭의 **설정**은 같은 창을 엽니다. 무채색 유리 테마의 통합 설정에서 영상 불투명도, 항상 위 표시, 회전, 프로젝터 효과, 영상 색 반사, 빛 퍼짐 강도, 크기를 조정할 수 있습니다.
- ‘유튜브 페이지 보기’는 동일한 재생 세션의 원래 페이지를 엽니다. 로그인이나 동의가 필요한 경우 여기서 진행할 수 있으며, 창을 닫으면 위젯으로 돌아옵니다.
- ‘숨기기’ 후에는 시스템 트레이의 TurnTabler 아이콘을 더블클릭해 다시 표시합니다.
- 레코드 위 영상의 기본 불투명도는 **58%**입니다. 통합 설정에서 0~100%로 조절할 수 있으며, 변경 즉시 반영되고 재실행 후에도 유지됩니다.

설정과 마지막 링크는 `%LOCALAPPDATA%/TurnTablerNative`에 저장됩니다. 평소 실행 시 마지막 링크를 자동 재생하지 않습니다.

## Chrome에서 우클릭으로 재생

**TurnTabler 2.1.2 이상**과 별도 설치 파일 **TurnTabler-Chrome-1.2.0.zip**을 사용합니다. 기존 배포 EXE를 그대로 지원하며 `release/v2.1.4/TurnTabler.exe`의 실제 재생으로 검증했습니다. EXE만 실행하면 브라우저 확장은 설치되지 않습니다.

1. `TurnTabler.exe`를 사용할 폴더에 저장합니다.
2. 확장 ZIP을 풀고 `Install.cmd`를 실행해 사용할 EXE를 선택합니다. 관리자 권한은 필요하지 않습니다.
3. Chrome의 `chrome://extensions`에서 **개발자 모드 → 압축해제된 확장 프로그램을 로드합니다**를 선택합니다.
4. 설치 안내에서 복사한 `%LOCALAPPDATA%\TurnTablerChrome\extension` 폴더를 선택합니다.
5. 영상 위에서 한 번 우클릭하면 **유튜브 자체 메뉴 맨 위**에 **TurnTabler로 재생**이 표시됩니다. 썸네일 링크·페이지 빈 공간에서는 Chrome 기본 우클릭 메뉴를 사용합니다.

앱이 꺼져 있으면 자동 실행하며, 실행 중이면 같은 위젯에서 곡을 바꾸고 숨겨진 위젯을 다시 표시합니다. 재생목록·믹스와 링크의 시작 시간을 유지합니다. 브라우저에서 이미 재생하던 영상은 필요하면 직접 일시정지하세요. 툴바 아이콘을 누르면 앱 연결 상태를 확인할 수 있습니다.

EXE 위치를 옮겼다면 확장 아이콘의 **설정 · EXE 경로 변경**에서 파일을 선택하거나 경로를 입력해 저장합니다. 현재 경로와 실제 파일 버전이 표시되며, 기존 EXE가 없어도 다시 지정할 수 있습니다. 설치기는 앱 실행 없이 파일 정보와 최소 버전을 확인합니다. 제거할 때는 `Uninstall.cmd` 실행 후 Chrome에서 확장을 제거합니다. 앱과 기존 설정은 유지됩니다. 웹 스토어에 게시하지 않은 로컬 설치용 확장이며, 자세한 안내는 [확장 설치 안내](chrome-extension/README.txt)에 있습니다.

확장 업데이트 후에는 `chrome://extensions`에서 확장의 **새로고침**을 누르고 **유튜브 탭도 새로고침**하세요. 자체 메뉴 항목은 유튜브 사이트에만 적용되는 콘텐츠 스크립트로 추가합니다. 유튜브의 메뉴 구조가 바뀌면 확장 업데이트가 필요할 수 있으며, Chrome 기본 메뉴에서도 계속 재생할 수 있습니다.

연결은 Chrome의 [Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)을 사용합니다. 확장 패키지에 포함된 작은 연결 프로그램이 요청할 때만 실행됩니다. 기존 배포본에는 Windows UI Automation으로 링크 입력과 재생을 전달하고, 연결 기능이 추가된 빌드에는 현재 사용자 전용 파이프를 사용합니다. 설정은 `%LOCALAPPDATA%\TurnTablerChrome\host\settings.json`에 저장합니다. 확장 아이콘은 EXE의 ICO에서 같은 PNG 프레임을 추출해 사용합니다.

## 빌드와 검증

.NET 8 SDK를 사용합니다. `.tools/dotnet/dotnet.exe`가 있으면 해당 SDK를 우선 사용합니다. Chrome 확장 테스트와 `npm.cmd` 명령에는 Node.js가 필요하며, 외부 npm 패키지는 사용하지 않으므로 `npm install`은 필요하지 않습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-native.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File publish.ps1 -Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/package-chrome.ps1 -Test
node scripts/test-browser-integration.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-chrome.ps1
node scripts/test-chrome-host.mjs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-released-app.ps1
```

`build.ps1`은 개발용 파일을 `release/native`에 만들고, `publish.ps1`은 배포용 단일 EXE를 `release/single-file/TurnTabler.exe`에 만듭니다. 배포용 EXE를 실행하는 데 DLL·이미지·스크립트 파일을 함께 전달할 필요가 없습니다. 실행 시 내장 네이티브 라이브러리는 .NET의 임시 캐시에 풀립니다.

`scripts/package-chrome.ps1 -Test`는 확장을 검사하고 연결 프로그램을 빌드하여 앱 EXE와 별도인 `release/TurnTabler-Chrome-1.2.0.zip`을 만듭니다. 연결 프로그램 빌드는 Windows .NET Framework 4.x C# 컴파일러를 사용합니다. `scripts/test-browser-integration.mjs`는 연결 기능이 추가된 앱 빌드의 Native Messaging과 두 영상의 실제 재생을 별도 프로필에서 확인합니다.

`scripts/test-chrome.ps1`은 설치 패키지를 임시 폴더에 설치한 뒤 독립된 Chrome 프로필에 확장을 로드해 실제 유튜브 자체 메뉴 표시·재열기·재생성, 메뉴 클릭으로 앱 자동 실행·재생·창 재사용, 설정의 경로 변경·버전 표시·오류 처리·저장 유지, 연결 팝업과 제거를 검증합니다. 테스트가 끝나면 기존 Chrome 연결 등록을 복원합니다. 결과와 스크린샷은 `artifacts/chrome/`에 저장됩니다.

`scripts/test-chrome-host.mjs`는 기존 2.1.2/2.1.4 배포 파일 확인, 잘못된 요청 거부와 EXE 이동 후 설정 복구를 검증합니다. `scripts/test-released-app.ps1`은 지정한 실제 배포 EXE에서 재생·숨김 복원·정상 종료 후 자동 실행을 확인합니다. 이 검증은 해당 앱을 실제로 조작하고 다시 실행하며, EXE 파일이 변경되지 않았는지도 확인합니다. 결과는 `artifacts/released-app/`에 저장됩니다.

데스크톱 검증은 별도의 임시 프로필과 화면 밖 테스트 창을 사용하며, 요청받은 영상의 실제 재생, 이전·다음, 재생목록 직접 선택과 자동 다음 곡, CC 켜기·끄기 및 이동 후 유지, 볼륨, 회전/일시정지, 영상 중심, 받침대 밖 반사광 픽셀을 확인합니다. `publish.ps1 -Test`는 프로젝트 밖의 새 폴더에 EXE만 복사해서 동일한 검증을 실행합니다. 결과와 화면은 `artifacts/native` 또는 `artifacts/single-file`에 저장합니다.

앱 아이콘은 Forge에서 비공개로 생성하고 로컬로 내려받았습니다. 원본 PNG와 Windows용 ICO는 `native/Assets/Icon/`에, 생성 프롬프트·모델·비공개 확인 기록은 같은 폴더의 `provenance.json`에 있습니다. `scripts/package-icon.ps1`은 원본 이미지를 표준 아이콘 크기로 변환해 ICO를 다시 만듭니다.

앱 구현과 리소스는 `native/`에 있습니다. 턴테이블 원본 이미지는 `native/Assets/glass-turntable.png`에 있으며 EXE에 포함됩니다. Chrome 확장은 `chrome-extension/`, 연결 프로그램은 `chrome-native-host/`, 빌드·검증 스크립트는 `scripts/`, 확장 단위 테스트는 `test/`에 있습니다.

`artifacts/`는 테스트 결과, `native/bin/`과 `native/obj/`는 빌드 캐시입니다. `release/`의 개발용·단일 EXE·확장 패키지는 위 명령으로 다시 만들 수 있습니다. 단, Chrome 확장에 등록한 EXE와 기존 버전 호환성 테스트에 사용하는 `release/v2.1.2/TurnTabler.exe`, `release/v2.1.4/TurnTabler.exe`는 사용하는 동안 보존해야 합니다.
