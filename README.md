# TurnTabler

투명한 Windows 네이티브 턴테이블 위젯입니다. 창과 레코드 회전, 설정, 볼륨 조작은 C# WPF로 구현하며 영상은 Windows WebView2에서 유튜브의 원래 재생 페이지를 엽니다. Electron과 Node.js는 실행에 필요하지 않습니다.

## 실행

[GitHub Releases](https://github.com/kmu9842/TurnTabler/releases/latest)에서 **TurnTabler.exe 하나만** 내려받아 실행하세요. 이미지와 재생 스크립트, .NET 런타임은 EXE에 포함됩니다.

Windows 10 2004 이상 / Windows 11의 x64 환경을 지원합니다. 영상은 Windows의 Microsoft Edge WebView2 Runtime을 사용합니다. WebView2가 없는 PC에는 [Microsoft 공식 런타임](https://developer.microsoft.com/microsoft-edge/webview2/)을 설치해야 합니다. 별도의 .NET 설치는 필요하지 않습니다.

소스에서 개발용으로 실행하려면 `Start-TurnTabler.cmd` 또는 `npm.cmd start`를 사용합니다.

## 사용

- 아래 입력칸에 유튜브 영상 또는 재생목록 링크를 붙여 넣고 Enter를 누릅니다. `RD…` 믹스 링크도 선택한 영상과 목록을 함께 유지합니다.
- 영상은 수평을 유지하며 레코드판 전체에 투사됩니다. 레코드판의 홈과 반사광은 24초에 한 바퀴씩 천천히 회전하고, 일시정지하면 멈춥니다.
- 영상 중심과 레코드 중심은 일치하며, 영상의 색은 받침대 윤곽 안쪽에만 부드럽게 퍼집니다.
- 판이나 ▶ 버튼으로 재생/일시정지합니다. ‹ / › 버튼은 이전·다음 곡, 받침대 오른쪽 아래 슬라이더는 음량입니다.
- 음량 위의 작은 **CC** 버튼으로 유튜브 자막을 켜거나 끕니다. 청색은 켜짐 상태이며 곡을 바꾸거나 앱을 다시 실행해도 설정을 유지합니다. 영상 자체에 새겨진 가사는 CC로 지울 수 없습니다.
- 주소창 오른쪽 **≡** 버튼으로 재생목록을 열어 곡을 직접 고를 수 있습니다. 곡이 끝나면 유튜브 재생목록 순서대로 다음 곡을 재생합니다.
- 톤암은 바늘 끝이 판 바깥쪽 홈에 살짝 걸치도록 배치했으며, 주소창과 재생 버튼은 하나의 유리·크롬 테마 조작부로 모았습니다.
- 받침대를 드래그해 이동하고 ⚙에서 항상 위 표시, 회전, 프로젝터 효과, 영상 색 반사, 빛 퍼짐 강도, 크기를 조정할 수 있습니다.
- ‘유튜브 페이지 보기’는 동일한 재생 세션의 원래 페이지를 엽니다. 로그인이나 동의가 필요한 경우 여기서 진행할 수 있으며, 창을 닫으면 위젯으로 돌아옵니다.
- ‘숨기기’ 후에는 시스템 트레이의 TurnTabler 아이콘을 더블클릭해 다시 표시합니다.

설정과 마지막 링크는 `%LOCALAPPDATA%/TurnTablerNative`에 저장됩니다. 평소 실행 시 마지막 링크를 자동 재생하지 않습니다.

## 빌드와 검증

.NET 8 SDK를 사용합니다. `.tools/dotnet/dotnet.exe`가 있으면 해당 SDK를 우선 사용합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-native.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File publish.ps1 -Test
```

`build.ps1`은 개발용 파일을 `release/native`에 만들고, `publish.ps1`은 배포용 단일 EXE를 `release/single-file/TurnTabler.exe`에 만듭니다. 배포용 EXE를 실행하는 데 DLL·이미지·스크립트 파일을 함께 전달할 필요가 없습니다. 실행 시 내장 네이티브 라이브러리는 .NET의 임시 캐시에 풀립니다.

데스크톱 검증은 별도의 임시 프로필과 화면 밖 테스트 창을 사용하며, 요청받은 영상의 실제 재생, 이전·다음, 재생목록 직접 선택과 자동 다음 곡, CC 켜기·끄기 및 이동 후 유지, 볼륨, 회전/일시정지, 영상 중심, 받침대 밖 반사광 픽셀을 확인합니다. `publish.ps1 -Test`는 프로젝트 밖의 새 폴더에 EXE만 복사해서 동일한 검증을 실행합니다. 결과와 화면은 `artifacts/native` 또는 `artifacts/single-file`에 저장합니다.

앱 아이콘은 Forge에서 비공개로 생성하고 로컬로 내려받았습니다. 원본 PNG와 Windows용 ICO는 `native/Assets/Icon/`에, 생성 프롬프트·모델·비공개 확인 기록은 같은 폴더의 `provenance.json`에 있습니다. `scripts/package-icon.ps1`은 원본 이미지를 표준 아이콘 크기로 변환해 ICO를 다시 만듭니다.

현재 구현은 `native/`에 있습니다. 루트의 이전 `.cjs` 파일과 `ui`의 웹 화면 코드는 실행에 사용하지 않으며, `ui/assets/glass-turntable.png`의 기존 레코드 이미지는 그대로 재사용합니다.
