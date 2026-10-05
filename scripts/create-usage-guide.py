"""Compose the guide from screenshots captured by the running native app."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / 'artifacts' / 'guide-captures'
OUTPUT = ROOT / 'output' / 'TurnTabler-guide-ko.png'
W, H = 1920, 2160
PAGE = '#f5f6f8'
INK = '#18212b'
MUTED = '#52606e'
BLUE = '#1465d9'
DECK = '#414f5f'
canvas = Image.new('RGB', (W, H), PAGE)
draw = ImageDraw.Draw(canvas)

def font(size, bold=False, mono=False):
    name = 'consola.ttf' if mono else 'malgunbd.ttf' if bold else 'malgun.ttf'
    return ImageFont.truetype(str(Path('C:/Windows/Fonts') / name), size)

def text(x, y, value, size=30, bold=False, fill=INK, mono=False):
    draw.text((x, y), value, font=font(size, bold, mono), fill=fill, anchor='lt')

def line(x1, y1, x2, y2, fill='#d5dce4', width=2):
    draw.line((x1, y1, x2, y2), fill=fill, width=width)

def badge(x, y, number, radius=22, fill=BLUE):
    draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=fill, outline='white', width=3)
    draw.text((x, y-1), str(number), font=font(25, True), fill='white', anchor='mm')

def screenshot(filename, box):
    # Preserve the captured UI; only resize and alpha-composite onto the page.
    img = Image.open(CAPTURES / filename).convert('RGBA')
    x, y, width, height = box
    assert abs(height - img.height * width / img.width) <= 0.5, 'Do not distort screenshots'
    img = img.resize((width, height), Image.Resampling.LANCZOS)
    canvas.paste(img, (x, y), img)

text(64, 48, 'TurnTabler 사용법', 70, True)
line(64, 146, 1856, 146)

text(66, 181, '1', 35, True, BLUE)
text(112, 184, 'TurnTabler.exe 실행', 31, True)
text(620, 181, '2', 35, True, BLUE)
text(666, 184, '유튜브 링크 붙여넣기', 31, True)
text(1320, 181, '3', 35, True, BLUE)
text(1366, 184, 'Enter로 재생', 31, True)
text(66, 243, '영상 · 재생목록 · 믹스 링크 지원', 26, fill=MUTED)

text(64, 314, '기본 조작', 38, True)
draw.rounded_rectangle((64, 385, 1856, 1170), 22, fill=DECK)
# Actual app capture, at 2x; no fabricated UI elements.
sx, sy = 94, 385
screenshot('idle-on-background.png', (sx, sy, 920, 780))

def callout(number, target, marker):
    tx, ty = sx + target[0]*2, sy + target[1]*2
    mx, my = sx + marker[0]*2, sy + marker[1]*2
    line(tx, ty, mx, my, '#b6d5ff', 3)
    draw.ellipse((tx-5, ty-5, tx+5, ty+5), fill='#b6d5ff')
    badge(mx, my, number)

callout(1, (245, 316), (245, 366))
callout(2, (187, 150), (67, 97))
callout(3, (76, 316), (76, 366))
callout(4, (412, 316), (412, 366))
callout(5, (367, 251), (455, 272))
callout(6, (402, 222), (455, 229))
callout(7, (402, 190), (455, 186))
callout(8, (46, 266), (17, 285))

items = [
    ('링크 입력 → Enter', '영상 · 재생목록 · 믹스 링크'),
    ('판 클릭', '재생 / 일시정지'),
    ('이전 · 재생/일시정지 · 다음', '하단 왼쪽 버튼 3개'),
    ('재생목록', '≡ 클릭 → 목록에서 곡 선택'),
    ('음량', '슬라이더 드래그'),
    ('CC 자막', '클릭해서 켜기 / 끄기'),
    ('설정', '불투명도 · 크기 · 효과 조절'),
    ('받침대 드래그', '창 이동'),
]
for index, (heading, body) in enumerate(items, 1):
    y = 421 + (index-1)*89
    badge(1100, y+21, index, 21)
    text(1143, y, heading, 29, True, 'white')
    text(1143, y+42, body, 24, fill='#d7e1ec')

text(64, 1200, '재생 중에는 하단 조절바가 흐리게 표시됩니다.', 24, fill=MUTED)

# The settings image is also a capture from the running native application.
draw.rounded_rectangle((64, 1262, 993, 2057), 18, fill='white', outline='#dce1e8', width=2)
text(94, 1298, '설정', 37, True)
screenshot('tray-options.png', (94, 1370, 352, 596))

settings_notes = [
    ('영상 불투명도', ['슬라이더로 조절']),
    ('항상 위 · 회전 · 효과', ['스위치로 켜기 / 끄기']),
    ('크기', ['작게 / 보통 / 크게']),
    ('유튜브 페이지 보기', ['로그인·동의가 필요할 때']),
    ('숨긴 창 다시 열기', ['시스템 트레이의', 'TurnTabler 아이콘 더블클릭']),
]
for i, (heading, body) in enumerate(settings_notes):
    y = 1401 + i*115
    text(485, y, heading, 28, True)
    for j, row in enumerate(body):
        text(485, y+43+j*36, row, 24, fill=MUTED)

draw.rounded_rectangle((1023, 1262, 1856, 2057), 18, fill='white', outline='#dce1e8', width=2)
text(1061, 1298, 'Chrome 우클릭 재생', 37, True)
text(1061, 1356, '확장 프로그램 별도 설치', 24, fill=MUTED)

steps = [
    (1433, '확장 ZIP 압축 해제', 'Install.cmd 실행 → 사용할 EXE 선택'),
    (1555, 'chrome://extensions', '개발자 모드 켜기'),
    (1677, '압축해제된 확장 프로그램 로드', '아래 폴더 선택'),
    (1891, '유튜브 영상 우클릭', '“TurnTabler로 재생” 선택'),
]
for i, (y, heading, body) in enumerate(steps, 1):
    badge(1084, y+18, i, 21)
    text(1123, y, heading, 27, True)
    text(1123, y+45, body, 24, fill=MUTED)

draw.rounded_rectangle((1061, 1775, 1818, 1846), 8, fill='#edf2f8')
path = r'%LOCALAPPDATA%\TurnTablerChrome\extension'
assert draw.textlength(path, font=font(26, mono=True)) < 720
text(1081, 1797, path, 26, mono=True)
text(1061, 2001, '소리가 겹치면 Chrome 영상 일시정지', 24, fill=MUTED)

line(64, 2100, 1856, 2100)
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
canvas.save(OUTPUT, optimize=True)
print(OUTPUT)
