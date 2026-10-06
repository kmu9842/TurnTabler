"""Lay out Korean release guides using unmodified captures of the 1.1.0 app.

Run publish.ps1 -Test first to refresh artifacts/single-file, then this script.
Screenshots are cropped/resized without changing their controls or displayed state.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / 'artifacts' / 'single-file'
OUTPUT = ROOT / 'output'
W = 1920
PAGE, INK, MUTED = '#f3f6fa', '#182636', '#536479'
BLUE, PALE, BORDER, DECK = '#155cbe', '#e7effb', '#d7e0ec', '#414f5f'


def font(size, bold=False, mono=False):
    name = 'consola.ttf' if mono else 'malgunbd.ttf' if bold else 'malgun.ttf'
    return ImageFont.truetype(str(Path('C:/Windows/Fonts') / name), size)


class Guide:
    def __init__(self, height):
        self.image = Image.new('RGB', (W, height), PAGE)
        self.draw = ImageDraw.Draw(self.image)

    def text(self, x, y, value, size=28, bold=False, fill=INK, mono=False, width=None):
        face = font(size, bold, mono)
        available = width if width is not None else W - 64 - x
        assert self.draw.textlength(value, font=face) <= available, f'Text too wide: {value}'
        self.draw.text((x, y), value, font=face, fill=fill, anchor='lt')

    def line(self, x1, y1, x2, y2, fill=BORDER, width=2):
        self.draw.line((x1, y1, x2, y2), fill=fill, width=width)

    def card(self, box, fill='white', outline=BORDER, radius=24):
        self.draw.rounded_rectangle(box, radius, fill=fill, outline=outline, width=2)

    def badge(self, x, y, number, radius=23):
        self.draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=BLUE, outline='white', width=3)
        self.draw.text((x, y-1), str(number), font=font(26, True), fill='white', anchor='mm')

    def screenshot(self, filename, x, y, width, crop=None):
        with Image.open(CAPTURES / filename) as source:
            source = source.convert('RGBA')
            if crop:
                source = source.crop(crop)
            height = round(source.height * width / source.width)
            source = source.resize((width, height), Image.Resampling.LANCZOS)
            self.image.paste(source, (x, y), source)
            return height

    def arrow(self, x1, y, x2):
        self.line(x1, y, x2, y, BLUE, 5)
        self.draw.polygon([(x2, y), (x2-17, y-11), (x2-17, y+11)], fill=BLUE)

    def save(self, name):
        OUTPUT.mkdir(parents=True, exist_ok=True)
        target = OUTPUT / name
        self.image.save(target, optimize=True)
        print(target)


with Image.open(CAPTURES / 'idle-on-background.png') as capture:
    assert capture.size == (460, 390)
with Image.open(CAPTURES / 'tray-options.png') as capture:
    assert capture.size == (320, 650), 'Refresh the captures with the 1.1.0 app'

g = Guide(2460)
g.text(64, 52, 'TURNTABLER  /  1.1.0 업데이트 가이드', 27, True, BLUE)
g.text(64, 112, '달라진 기능, 이렇게 쓰세요', 64, True)
g.text(68, 204, '브라우저 · 출력 스피커 · OBS 연결 · 재생 개선 · Mac 미리보기', 30, fill=MUTED)
g.card((64, 278, 1856, 1110), DECK, DECK)
sx, sy = 90, 310
g.screenshot('idle-on-background.png', sx, sy, 920)


def callout(number, target, marker):
    tx, ty = sx + target[0]*2, sy + target[1]*2
    mx, my = sx + marker[0]*2, sy + marker[1]*2
    g.line(tx, ty, mx, my, '#b5d8ff', 3)
    g.draw.ellipse((tx-5, ty-5, tx+5, ty+5), fill='#b5d8ff')
    g.badge(mx, my, number)


callout(1, (402, 165), (456, 143))
callout(2, (402, 191), (456, 202))
callout(3, (412, 316), (456, 340))
g.badge(1084, 369, 1)
g.text(1124, 348, '브라우저 열기', 37, True, 'white')
for index, value in enumerate([
    '설정 바로 위 창 모양 버튼을 누르세요.',
    '클릭·키보드 입력 오류를 수정했습니다.',
    '로그인·검색·목록을 직접 조작합니다.',
    '상단 ‘위젯으로 돌아가기’로 복귀합니다.',
    '앱에서 로그인한 세션을 유지합니다.',
    '평소 Chrome 로그인과는 별도입니다.',
]):
    g.text(1084, 414 + index*39, value, 27, fill='#e0e9f5', width=732)
g.badge(1084, 689, 2)
g.text(1124, 668, '작고 투명한 버튼', 37, True, 'white')
g.text(1084, 734, '두 버튼의 검은 배경을 없애고', 28, fill='#e0e9f5')
g.text(1084, 779, '크기와 간격을 줄였습니다.', 28, fill='#e0e9f5')
g.text(1084, 824, '톱니바퀴를 눌러 설정을 엽니다.', 28, fill='#e0e9f5')
g.badge(1084, 936, 3)
g.text(1124, 915, '재생목록 직접 선택', 37, True, 'white')
g.text(1084, 982, '≡ 버튼 → 목록에서 원하는 곡 선택', 28, fill='#e0e9f5')
g.text(1084, 1027, '재생목록·믹스 링크를 함께 지원합니다.', 27, fill='#e0e9f5')
g.text(82, 1152, '기본 조작', 28, True, BLUE)
g.text(245, 1152, '링크 붙여넣기 → Enter     |     판 클릭: 재생·정지     |     CC: 자막     |     슬라이더: 음량', 27)

g.card((64, 1220, 945, 1860))
g.text(96, 1256, '내가 들을 출력 스피커 선택', 35, True)
g.text(96, 1314, '설정 → 소리 출력 장치', 28, fill=MUTED)
g.screenshot('tray-options.png', 96, 1370, 640, (0, 390, 320, 490))
for index, value in enumerate([
    '목록에서 스피커·헤드폰·모니터를 선택하세요.',
    '선택은 저장되며 TurnTabler 소리에 적용됩니다.',
    '장치를 분리하면 시스템 기본 출력으로 돌아갑니다.',
    '새 장치를 연결했다면 새로고침 버튼을 누르세요.',
]):
    g.text(96, 1606 + index*51, value, 27, width=817)
g.card((975, 1220, 1856, 1860))
g.text(1007, 1256, 'OBS로 소리 보내기', 35, True)
g.text(1007, 1314, 'Windows 11에서 사용', 28, fill=MUTED)
g.screenshot('tray-options.png', 1007, 1370, 640, (0, 491, 320, 591))
for index, value in enumerate([
    '‘OBS로 소리 보내기’를 켜세요.',
    '활성화된 ‘OBS 연결 주소 복사’를 누르세요.',
    '복사한 주소를 OBS의 ‘미디어’ 소스에 넣습니다.',
    '자세한 설정값은 OBS 연결 가이드를 참고하세요.',
]):
    g.text(1007, 1606 + index*51, value, 27, width=817)

g.card((64, 1900, 1856, 2330))
g.line(959, 1934, 959, 2296)
g.text(96, 1938, '재생 중 자동으로 처리합니다', 35, True)
g.text(96, 2002, '스킵 버튼이 뜨면 자동 클릭', 30, True, BLUE)
g.text(96, 2050, '건너뛸 수 있는 광고에만 적용합니다.', 28)
g.text(96, 2120, '재생목록·믹스 자동 다음 곡', 30, True, BLUE)
g.text(96, 2168, '곡이 끝난 뒤 멈추는 경우의 복구를 보강했습니다.', 27, width=823)
g.text(96, 2216, '하단 ‹ / ›와 ≡ 목록 선택도 사용하세요.', 27)
g.text(1007, 1938, 'Mac 미리보기 배포', 35, True)
g.text(1007, 2002, 'macOS 15.4+ · Apple Silicon / Intel', 29, True, BLUE)
g.text(1007, 2052, 'ZIP 해제 → .app을 Applications로 이동', 28)
g.text(1007, 2100, '브라우저·재생목록·출력 선택·Chrome 연결 지원', 27, width=817)
g.text(1007, 2174, '실제 Mac 검증·Apple 공증은 아직입니다.', 26, fill=MUTED)
g.text(1007, 2220, 'OBS 직접 스트림은 Windows 11에서 지원합니다.', 26, fill=MUTED, width=817)
g.text(64, 2384, '실제 Windows 1.1.0 화면으로 작성  ·  로그인은 서비스의 세션 만료 시 다시 필요할 수 있습니다.', 24, fill=MUTED)
g.save('TurnTabler-guide-ko.png')

g = Guide(2180)
g.text(64, 52, 'TURNTABLER 1.1.0  /  WINDOWS 11  /  OBS 32.2', 27, True, BLUE)
g.text(64, 112, 'TurnTabler 소리를 OBS로', 64, True)
g.text(68, 204, '앱에서 연결 주소를 복사해 OBS의 ‘미디어’ 소스에 넣으면 됩니다.', 30, fill=MUTED)
g.card((64, 278, 1856, 410), PALE, PALE)
g.text(112, 325, 'TurnTabler 재생', 37, True, BLUE)
g.arrow(475, 346, 617)
g.text(690, 325, 'OBS ‘미디어’ 소스', 37, True, BLUE)
g.text(1210, 309, '내가 듣는 스피커는 그대로 사용', 27, True)
g.text(1210, 355, '가상 오디오 드라이버 설치 불필요', 26, fill=MUTED)

g.card((64, 452, 840, 1284))
g.badge(110, 507, 1)
g.text(150, 485, '앱 설정에서 켜기', 37, True)
g.text(96, 562, '설정 → OBS로 소리 보내기 → 켜기', 29, width=712)
g.screenshot('tray-options.png', 104, 626, 640, (0, 390, 320, 594))
g.text(96, 1084, 'OBS 연결 주소 복사', 32, True, BLUE)
g.text(96, 1138, '복사한 주소를 OBS 입력칸에 붙여넣으세요.', 27, width=712)
g.text(96, 1196, '위 화면은 켜기 전 상태입니다.', 24, fill=MUTED)
g.text(96, 1234, '스위치를 켜면 복사 버튼이 활성화됩니다.', 24, fill=MUTED)
g.card((880, 452, 1856, 1284))
g.badge(926, 507, 2)
g.text(966, 485, 'OBS에 ‘미디어’ 소스 추가', 37, True)
g.text(912, 562, '소스 목록의 + → 미디어 → 이름: TurnTabler Audio', 27, width=912)
for index, (label, value) in enumerate([
    ('로컬 파일', '체크 해제'),
    ('입력', '앱에서 복사한 주소'),
    ('입력 형식', 'wav'),
    ('재접속 지연', '1초'),
]):
    y = 638 + index*72
    g.text(928, y, label, 29, True, width=285)
    g.text(1255, y, value, 29, fill=BLUE, width=553)
    g.line(912, y+52, 1824, y+52)
g.text(928, 944, 'FFmpeg 설정', 29, True)
g.card((912, 994, 1824, 1068), '#edf2f8', '#edf2f8', 12)
g.text(933, 1018, 'ignore_length=1 analyzeduration=0 probesize=4096', 28, mono=True, width=870)
g.text(928, 1110, '비활성화 상태일 때 파일 닫기', 27, True, width=617)
g.text(1633, 1110, '체크 해제', 27, fill=BLUE)
g.text(928, 1174, '네트워크 버퍼링', 27, True)
g.text(1633, 1174, '1 MB', 27, fill=BLUE)

g.card((64, 1330, 1856, 1890))
g.badge(110, 1388, 3)
g.text(150, 1366, '소리 확인', 37, True)
for x, title, rows in [
    (104, '앱에서 재생', ['TurnTabler로 영상을 재생합니다.', '앱 볼륨을 0보다 높게 두세요.']),
    (700, 'OBS 오디오 미터 확인', ['‘TurnTabler Audio’의 음량 막대가', '움직이는지 확인하세요.']),
    (1296, '짧게 녹화 후 재생', ['녹화 파일을 열어 실제 소리가', '들리는지 확인하세요.']),
]:
    g.text(x, 1472, title, 31, True, BLUE, width=500)
    for index, row in enumerate(rows):
        g.text(x, 1532 + index*44, row, 26, width=500)
g.line(96, 1650, 1824, 1650)
g.text(104, 1692, '소리가 겹칠 때', 31, True)
g.text(104, 1750, '오디오 고급 설정 → 오디오 모니터링 → ‘모니터링 끔’', 29)
g.text(104, 1802, '같은 소리를 함께 받는 ‘데스크톱 오디오’도 끄세요.', 29)
g.card((64, 1930, 1856, 2070), PALE, PALE)
g.text(104, 1964, 'TurnTabler를 실행한 상태에서 사용하세요. 앱을 종료하면 소리 전달도 끝납니다.', 29, True)
g.text(104, 2015, '다시 실행하고 재생하면 저장된 같은 주소로 연결됩니다.', 27, fill=MUTED)
g.text(64, 2120, 'Windows 11용 직접 연결 안내  ·  Windows 10과 Mac 미리보기에는 이 직접 스트림 기능이 없습니다.', 24, fill=MUTED)
g.save('TurnTabler-OBS-guide-ko.png')
