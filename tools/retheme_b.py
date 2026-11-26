# 빡세 색 바꾸기 (B안: 아이보리 + 차콜 + 라임, 오렌지 섞기) — 2026-11-26
# 어두운 남색·하늘색 테마의 색 값을 '쓰이는 자리(글자/배경/테두리/그림자)'에 맞춰 밝은 테마 색으로 바꿈.
# 한 번만 돌리는 변환 도구. 돌린 뒤 화면을 하나씩 보고 손으로 다듬음.
#   python tools/retheme_b.py            → 바꿀 개수만 보여 줌
#   python tools/retheme_b.py --write    → 파일에 씀
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ['index.html', 'map.html', 'events.html', 'mypage.html', 'join.html', 'login.html', 'privacy.html',
         'delete-account.html', 'goods.html', 'community.html', 'landing.html', 'css/seo.css', 'css/ww.css',
         'js/ppx.js', 'js/feedback.js', 'js/install.js', 'js/ev.js', 'owner/index.html', 'r/index.html']

IVORY, WHITE, INK, OLIVE, LIME, ORANGE, ORANGE_T = (242,241,236), (255,255,255), (38,43,51), (86,102,26), (181,201,95), (229,154,79), (168,90,22)
FOAM_T, MUTED = (61,67,76), (107,112,120)

FAM = {}
def fam(name, *rgbs):
    for c in rgbs: FAM[c] = name
fam('deepbg', (4,17,30), (2,8,18))
fam('card', (7,24,40), (13,30,53), (11,29,51), (15,34,54), (8,22,38))
fam('cyan', (14,165,233), (34,211,238), (6,182,212), (56,189,248), (3,105,161), (12,74,110), (79,195,255), (59,130,246), (147,197,253))
fam('foam', (186,230,253), (224,242,254), (226,243,255), (207,232,255), (219,231,243), (240,249,255), (207,250,254), (226,232,240), (165,243,252))
fam('white', (255,255,255))
fam('black', (0,0,0))
fam('slate', (148,163,184), (100,116,139), (71,85,105), (51,65,85), (156,163,175))
fam('amber', (251,191,36), (245,183,43), (245,158,11), (249,115,22))
fam('amberl', (252,211,77), (253,230,138), (254,215,170))
fam('green', (52,211,153), (16,185,129), (74,222,128), (110,231,183), (167,243,208))
fam('red', (239,68,68), (248,113,113), (252,165,165), (244,63,94), (255,75,62))
fam('purple', (196,181,253), (167,139,250), (129,140,248), (199,210,254), (244,114,182))

ROLE = {}
for p in ('color', 'fill', '-webkit-text-fill-color', 'caret-color', 'stroke', 'text-decoration-color', 'stop-color'): ROLE[p] = 'text'
for p in ('background', 'background-color', 'background-image', 'accent-color'): ROLE[p] = 'bg'
for p in ('box-shadow', 'text-shadow', 'filter'): ROLE[p] = 'shadow'
VARS = {  # :root 변수는 이름으로
    '--deep': '#F2F1EC', '--deep2': '#FFFFFF', '--water': '#262B33', '--ocean': '#262B33', '--sky': '#262B33',
    '--cyan': '#3A404A', '--aqua': '#56661A', '--foam': '#3D434C', '--mist': '#262B33', '--white': '#262B33',
    '--line': 'rgba(38,43,51,.12)', '--glass': 'rgba(255,255,255,.86)', '--muted': 'rgba(38,43,51,.62)',
    '--card': '#FFFFFF', '--ok': '#2E7D4F', '--gold': '#A85A16', '--warn': '#A85A16',
}

def fmt(rgb, a):
    a = round(max(0, min(1, a)), 3)
    if a >= 1: return '#%02X%02X%02X' % rgb
    s = ('%.3f' % a).rstrip('0').rstrip('.')
    if s.startswith('0.'): s = s[1:]
    return 'rgba(%d,%d,%d,%s)' % (*rgb, s)

def conv(rgb, a, role):
    f = FAM.get(rgb)
    if not f: return None
    if f == 'deepbg':
        if role == 'text': return fmt(IVORY, a)          # 밝은 버튼 위 어두운 글자 → 버튼이 차콜이 되므로 아이보리 글자
        if role == 'shadow': return fmt(INK, a * .25)
        if role == 'border': return fmt(INK, a * .12)
        return fmt(IVORY, a)
    if f == 'card':
        if role == 'text': return fmt(INK, a)
        if role == 'shadow': return fmt(INK, a * .25)
        if role == 'border': return fmt(INK, a * .12)
        return fmt(WHITE, a)
    if f == 'cyan':
        if role == 'text': return fmt(OLIVE, a)
        if role == 'shadow': return fmt(INK, a * .3)
        if role == 'border': return fmt(INK, a * .6) if a <= .25 else fmt((150,170,60), a)
        return fmt(INK, a) if a >= .95 else fmt(LIME, min(.55, a * 1.3))
    if f == 'foam':
        if role == 'text': return fmt(FOAM_T, max(a, .65))
        if role == 'shadow': return fmt(INK, a * .2)
        return fmt(INK, a * .45)
    if f == 'white':
        if role == 'text': return fmt(INK, max(a, .5))
        if role == 'shadow': return fmt(INK, a * .3)
        if role == 'border': return fmt(WHITE, 1) if a >= .95 else fmt(INK, a * .8)
        return fmt(WHITE, 1) if a >= .95 else fmt(INK, a * .7)
    if f == 'black':
        if role == 'shadow': return fmt(INK, a * .45)
        return None
    if f == 'slate':
        return fmt(MUTED, a) if role == 'text' else None
    if f == 'amber':
        if role == 'text': return fmt(ORANGE_T, a)
        return fmt(ORANGE, a)
    if f == 'amberl':
        return fmt((154,79,18), a) if role == 'text' else fmt(ORANGE, a * .5)
    if f == 'green': return fmt((46,125,79), a) if role == 'text' else None
    if f == 'red': return fmt((200,40,40), a) if role == 'text' else None
    if f == 'purple': return fmt((109,40,217), a) if role == 'text' else None
    return None

COLOR_RE = re.compile(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b|rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)')
def parse(m):
    if m.group(1):
        h = m.group(1)
        if len(h) == 3: h = ''.join(c * 2 for c in h)
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)), 1.0
    return (int(m.group(2)), int(m.group(3)), int(m.group(4))), float(m.group(5)) if m.group(5) else 1.0

def recolor(val, role, stat):
    def rep(m):
        rgb, a = parse(m)
        out = conv(rgb, a, role)
        if out is None: return m.group(0)
        stat[0] += 1
        return out
    return COLOR_RE.sub(rep, val)

DECL_RE = re.compile(r'(?<![\w-])(--[a-zA-Z0-9-]+|[a-zA-Z-]+)\s*:\s*([^;{}"\'`<>\n]*)')
def role_of(prop):
    p = prop.lower()
    if p in ROLE: return ROLE[p]
    if p.startswith('border') or p.startswith('outline'): return 'border'
    return None

def transform(text, stat):
    def rep(m):
        prop, val = m.group(1), m.group(2)
        if prop in VARS and COLOR_RE.search(val):
            stat[0] += 1
            return f'{prop}:{VARS[prop]}'
        role = role_of(prop)
        if not role or not COLOR_RE.search(val): return m.group(0)
        return m.group(0)[:m.start(2) - m.start(0)] + recolor(val, role, stat)
    text = DECL_RE.sub(rep, text)
    text = re.sub(r'(name="theme-color" content=")#04111e', r'\1#F2F1EC', text)
    return text

if __name__ == '__main__':
    write = '--write' in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith('--')]
    for f in (only or FILES):
        p = ROOT / f
        t = p.read_text(encoding='utf-8')
        stat = [0]
        n = transform(t, stat)
        left = [m.group(0) for m in COLOR_RE.finditer(n) if FAM.get(parse(m)[0]) in ('deepbg', 'card', 'cyan', 'foam')]
        print(f'{f:22} 바꿈 {stat[0]:4}  남은 어두운/하늘색 {len(left):3} {sorted(set(left))[:6]}')
        if write and n != t: p.write_text(n, encoding='utf-8', newline='')
