"""빡세 카드뉴스(인포그래픽) 이미지 만들기 — 가이드 원고 한 편을 JPG 카드 여러 장으로

  python tools/guide_cards.py <slug>                 정사각형(1080x1080) 카드
  python tools/guide_cards.py <slug> --wide          가로형(1200x675) 카드
  python tools/guide_cards.py <slug> --out <폴더>     저장 폴더 지정 (기본: 윈도우 D:\\AI_Team\\reviews\\guide-cards\\<slug>, 그 외 ./cards/<slug>)
  python tools/guide_cards.py <slug> --site          사이트용: 저장소 guide-img/<slug>/ 에 저장 → build_seo.py 가 글 속에 넣음
  python tools/guide_cards.py all --site             모든 원고의 사이트용 카드를 다시 만듦 (원고를 고쳤을 때)

카드 구성: 표지(제목) → 소제목마다 1장(핵심 항목) → 팁 → 마무리(빡세 안내)
그림 카드(2026-11-21 운영자 결정): guide-src/cards/<slug>.json 이 있으면, 거기 적은 소제목 카드만
  글자 목록 대신 그림 위주 카드(흐름·비교표·해도 돼요/하지 마세요·아이콘 네 칸)로 바꿔 그림. 형식은 아래 VISUAL_HELP.
  - 그림 카드 내용도 원고에 있는 내용만 씀(지어낸 숫자·사실 금지). 가로형(--wide)은 그림 카드 없이 글자 카드로 만듦
- 글 내용에서만 뽑으므로 지어낸 숫자·사진이 들어가지 않음
- JPG는 사진 정보(EXIF 등 메타데이터) 없이 저장
- 브라우저: 윈도우는 Edge, 리눅스(클라우드)는 google-chrome/chromium. PPX_CHROME 환경변수로 바꿀 수 있음
- JPG 변환: Pillow가 있으면 Pillow, 없으면 윈도우 기본 기능(System.Drawing)
"""
import glob, html, os, re, shutil, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, 'guide-src')
META = re.compile(r'<!--\s*(\w+):\s*(.*?)\s*-->')
WIN = os.name == 'nt'


def browser():
    for p in [os.environ.get('PPX_CHROME', ''),
              r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
              r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
              r'C:\Program Files\Google\Chrome\Application\chrome.exe',
              '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser']:
        if p and os.path.exists(p):
            return p
    raise SystemExit('브라우저(Edge/Chrome)를 찾지 못했어요. PPX_CHROME 환경변수로 경로를 알려 주세요.')


def plain(s):
    s = re.sub(r'<[^>]+>', '', s)
    return html.unescape(re.sub(r'\s+', ' ', s)).strip()


def short(s, n):
    """첫 문장만, 너무 길면 n자 근처에서 자름"""
    s = plain(s)
    m = re.search(r'^(.{8,}?(?:요|다|죠)[.!?])', s)
    if m and len(m.group(1)) <= n:
        return m.group(1)
    if len(s) <= n:
        return s
    cut = s[:n].rsplit(' ', 1)[0]
    return cut.rstrip(',·—-') + '…'


def parse(slug):
    # slug 대신 원고 파일 경로를 줘도 됨 (저장소 밖 블로그 원고 등)
    f = slug if os.path.isfile(slug) else next((x for x in glob.glob(os.path.join(SRC, '*.html')) if dict(META.findall(open(x, encoding='utf-8').read()[:1500])).get('slug') == slug), None)
    if not f:
        raise SystemExit(f'그런 글이 없어요: {slug}')
    raw = open(f, encoding='utf-8').read()
    raw = re.sub(r'<p>\s*\[[^\]]*\]\s*</p>', '', raw)  # [직접 경험 한 줄 …] 같은 자리 표시는 카드에 넣지 않음
    meta = dict(META.findall(raw[:1500]))
    body = re.sub(r'<!--.*?-->', '', raw, flags=re.S)
    first_p = re.search(r'<p>(.*?)</p>', body, re.S)
    parts = re.split(r'<h2>(.*?)</h2>', body, flags=re.S)
    sections, tips = [], []
    for i in range(1, len(parts), 2):
        head, chunk = plain(parts[i]), parts[i + 1]
        tips += [plain(t).lstrip('💡').strip() for t in re.findall(r'<div class="tip">(.*?)</div>', chunk, re.S)]
        chunk = re.sub(r'<div class="tip">.*?</div>', '', chunk, flags=re.S)
        items = []
        for li in re.findall(r'<li>(.*?)</li>', chunk, re.S):
            b = re.match(r'\s*<b>(.*?)</b>\s*[—\-:]?\s*(.*)', li, re.S)
            if b:
                items.append((plain(b.group(1)), short(b.group(2), 64)))
            else:
                items.append((short(li, 40), ''))
        if not items:  # 목록이 없는 부분은 문단 첫 문장들
            items = [(short(p, 60), '') for p in re.findall(r'<p>(.*?)</p>', chunk, re.S)[:3]]
        if items:
            sections.append({'head': head, 'items': items[:4], 'more': max(0, len(items) - 4),
                             'ordered': '<ol>' in chunk and '<ul>' not in chunk})
    # 마지막 '내 주변 ~ 찾기' 소제목은 마무리 카드로 따로 만듦
    if sections and '찾기' in sections[-1]['head']:
        sections.pop()
    return meta, short(first_p.group(1), 70) if first_p else '', sections, tips


CSS = '''
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700;900&display=swap');
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:%(W)dpx;height:%(H)dpx;overflow:hidden;font-family:'Noto Sans KR','Malgun Gothic',sans-serif;color:#fff;word-break:keep-all}
body{background:radial-gradient(circle at 85%% 10%%,rgba(34,211,238,.20),transparent 45%%),radial-gradient(circle at 0%% 100%%,rgba(14,165,233,.22),transparent 50%%),#04111e;padding:%(P)dpx;display:flex;flex-direction:column}
.top{display:flex;justify-content:space-between;align-items:center;font-size:%(s)dpx;color:#bae6fd;letter-spacing:-.2px}
.brand{font-weight:900;color:#fff;font-size:%(b)dpx}.brand em{font-style:normal;color:#22d3ee}
.chip{padding:6px 16px;border-radius:999px;border:2px solid rgba(34,211,238,.45);color:#cffafe;font-weight:700}
.mid{flex:1;display:flex;flex-direction:column;justify-content:center}
.kicker{color:#22d3ee;font-weight:900;font-size:%(k)dpx;margin-bottom:%(g)dpx}
h1{font-size:%(t)dpx;line-height:1.25;font-weight:900;letter-spacing:-1.5px}
.lead{margin-top:%(g)dpx;font-size:%(l)dpx;line-height:1.55;color:#e0f2fe}
h2{font-size:%(h)dpx;line-height:1.3;font-weight:900;letter-spacing:-1px;margin-bottom:%(g)dpx}
.num{align-self:flex-start;display:inline-block;font-size:%(k)dpx;font-weight:900;color:#04111e;background:#22d3ee;border-radius:12px;padding:2px 14px;margin-bottom:%(g2)dpx}
.items{display:flex;flex-direction:column;gap:%(gi)dpx}
.it{display:flex;gap:18px;align-items:flex-start;background:rgba(255,255,255,.055);border:1.5px solid rgba(14,165,233,.28);border-radius:22px;padding:%(ip)dpx %(ip2)dpx}
.dot{flex:none;width:%(d)dpx;height:%(d)dpx;border-radius:50%%;background:linear-gradient(135deg,#0ea5e9,#06b6d4);display:flex;align-items:center;justify-content:center;font-weight:900;font-size:%(dn)dpx}
.it b{display:block;font-size:%(ib)dpx;line-height:1.35;font-weight:900}
.it span{display:block;margin-top:4px;font-size:%(is)dpx;line-height:1.45;color:#bae6fd}
.more{margin-top:14px;font-size:%(s)dpx;color:#7dd3fc}
.tipbox{background:linear-gradient(135deg,rgba(14,165,233,.25),rgba(6,182,212,.12));border:2px solid rgba(34,211,238,.45);border-radius:28px;padding:%(tp)dpx;font-size:%(tf)dpx;line-height:1.55;font-weight:700}
.tipbox i{font-style:normal;display:block;color:#22d3ee;font-size:%(k)dpx;font-weight:900;margin-bottom:14px}
.cta{font-size:%(l)dpx;line-height:1.55;color:#e0f2fe}.cta b{color:#fff}
.url{display:inline-block;margin-top:%(g)dpx;padding:14px 30px;border-radius:999px;background:#fff;color:#04111e;font-weight:900;font-size:%(k)dpx}
.foot{font-size:%(s)dpx;color:rgba(186,230,253,.7);display:flex;justify-content:space-between}
'''


VISUAL_HELP = """guide-src/cards/<slug>.json 형식 (head = 원고의 소제목(h2) 글자 그대로)
{"cards": [
 {"head": "언제 하면 좋을까요?", "type": "flow", "title": "하부세차, {언제} 하면 좋을까요?",
  "steps": [{"icon": "🧂", "title": "제설제 길|달린 뒤", "sub": "너무 오래|미루지 않기"}, ... 2~4개],
  "warn": {"icon": "🥶", "title": "영하인 날은 피하세요", "sub": "씻은 물이 얼 수 있어요"}},
     ← 아래 상자: 주의는 "warn"(빨강), 덧붙임·권하는 방법은 "tip"(하늘색). 없어도 됨
 {"head": "...", "type": "compare", "title": "셀프 vs {자동}", "cols": [{"icon": "🧽", "name": "셀프"}, {"icon": "🚿", "name": "자동"}],
  "rows": [["휠하우스", "◎ 잘 돼요", "△ 기계마다"], ... 최대 5줄], "note": "💡 한 줄 덧붙임(없어도 됨)"},
 {"head": "...", "type": "dodont", "title": "...", "do": ["짧게", ...최대 4], "dont": ["짧게", ...최대 4]},
 {"head": "...", "type": "grid", "title": "...", "items": [{"icon": "📖", "title": "제목", "sub": "설명"}, ... 2~4개]}
]}
- {글자} = 하늘색 강조, | = 줄바꿈. 비교표 칸이 ◎로 시작하면 초록, △는 노랑, ✕는 빨강
- 아이콘은 이모지 1개. 장난스러워 보이는 이모지(물총 등)는 피함"""

VCSS = """
.vt{font-size:58px;line-height:1.25;font-weight:900;letter-spacing:-1px;margin-bottom:40px}.vt em,.k{font-style:normal;color:#22d3ee}
.flow{display:flex;align-items:stretch;gap:16px}
.fb{flex:1;border-radius:28px;padding:34px 18px;text-align:center;background:rgba(255,255,255,.06);border:2px solid rgba(14,165,233,.35)}
.fb .ic{font-size:%(fi)dpx;line-height:1}.fb b{display:block;font-size:%(fbt)dpx;line-height:1.35;margin-top:20px}
.fb span{display:block;font-size:%(fbs)dpx;color:#bae6fd;margin-top:10px;line-height:1.4}
.ar{display:flex;align-items:center;font-size:44px;color:#22d3ee;font-weight:900}
.warn{margin-top:40px;display:flex;align-items:center;gap:26px;border-radius:28px;padding:28px 34px;background:rgba(248,113,113,.12);border:2px solid rgba(248,113,113,.55)}
.warn.tipb{background:rgba(34,211,238,.10);border-color:rgba(34,211,238,.5)}.warn.tipb b{color:#a5f3fc}.warn.tipb span{color:#e0f2fe}
.warn .ic{font-size:72px;line-height:1}.warn b{font-size:32px;color:#fecaca}.warn span{display:block;font-size:25px;color:#fde2e2;margin-top:6px;line-height:1.45}
table.cmp{width:100%%;border-collapse:separate;border-spacing:0 14px;font-size:28px}
.cmp th{font-size:30px;padding:6px 0;color:#cffafe}.cmp th .ic{display:block;font-size:64px;margin-bottom:8px}
.cmp td{background:rgba(255,255,255,.055);padding:22px 16px;text-align:center;line-height:1.35}
.cmp td:first-child{text-align:left;border-radius:20px 0 0 20px;color:#bae6fd;font-weight:700;width:30%%}
.cmp td:last-child{border-radius:0 20px 20px 0}
.g{color:#4ade80;font-weight:900}.m{color:#fbbf24;font-weight:900}.r{color:#f87171;font-weight:900}
.note{margin-top:20px;font-size:26px;color:#bae6fd;line-height:1.5}
.dd{display:flex;gap:22px}.dd>div{flex:1;border-radius:28px;padding:30px 28px}
.dd .ok{background:rgba(74,222,128,.10);border:2px solid rgba(74,222,128,.5)}.dd .no{background:rgba(248,113,113,.10);border:2px solid rgba(248,113,113,.5)}
.dd h3{font-size:34px;font-weight:900;margin-bottom:22px}.dd .ok h3{color:#86efac}.dd .no h3{color:#fca5a5}
.dd p{font-size:28px;line-height:1.4;padding:14px 0;border-top:1.5px solid rgba(255,255,255,.1)}
.gr{display:grid;grid-template-columns:1fr 1fr;gap:20px}.gi:nth-child(3):last-child{grid-column:span 2}
.gi{border-radius:26px;padding:28px 26px;background:rgba(255,255,255,.06);border:2px solid rgba(14,165,233,.35)}
.gi .ic{font-size:64px;line-height:1}.gi b{display:block;font-size:31px;margin-top:16px;line-height:1.3}.gi span{display:block;font-size:24px;color:#bae6fd;margin-top:8px;line-height:1.4}
"""


def load_visual(slug):
    import json
    f = os.path.join(SRC, 'cards', f'{slug}.json')
    if not os.path.exists(f):
        return {}
    return {c['head']: c for c in json.load(open(f, encoding='utf-8')).get('cards', [])}


def vtxt(t):
    """{강조}·| 줄바꿈 처리 (그 외는 이스케이프)"""
    t = html.escape(t or '')
    return re.sub(r'\{(.*?)\}', r'<em>\1</em>', t).replace('|', '<br>')


def visual(v):
    t = v.get('type')
    head = f'<div class="vt">{vtxt(v.get("title") or v["head"])}</div>'
    if t == 'flow':
        st = v['steps'][:4]
        big = len(st) <= 3
        box = [f'<div class="fb"><div class="ic">{html.escape(x.get("icon", ""))}</div><b>{vtxt(x.get("title"))}</b>'
               + (f'<span>{vtxt(x["sub"])}</span>' if x.get('sub') else '') + '</div>' for x in st]
        body = f'<div class="flow">{"<div class=ar>›</div>".join(box)}</div>'
        w = v.get('warn') or v.get('tip')
        if w:
            body += (f'<div class="warn{"" if v.get("warn") else " tipb"}"><div class="ic">{html.escape(w.get("icon", "⚠️"))}</div><div><b>{vtxt(w.get("title"))}</b>'
                     + (f'<span>{vtxt(w["sub"])}</span>' if w.get('sub') else '') + '</div></div>')
        return head + body, ({'fi': 92, 'fbt': 31, 'fbs': 24} if big else {'fi': 70, 'fbt': 26, 'fbs': 21})
    if t == 'compare':
        def cell(c):
            c = c or ''
            k = 'g' if c.startswith('◎') else 'm' if c.startswith('△') else 'r' if c.startswith('✕') else ''
            return f'<td class="{k}">{vtxt(c)}</td>'
        th = '<tr><th></th>' + ''.join(f'<th><span class="ic">{html.escape(c.get("icon", ""))}</span>{vtxt(c.get("name"))}</th>' for c in v['cols']) + '</tr>'
        rows = ''.join('<tr><td>' + vtxt(r[0]) + '</td>' + ''.join(cell(c) for c in r[1:]) + '</tr>' for r in v['rows'][:5])
        note = f'<div class="note">{vtxt(v["note"])}</div>' if v.get('note') else ''
        return head + f'<table class="cmp">{th}{rows}</table>' + note, {}
    if t == 'dodont':
        col = lambda k, cls, h: f'<div class="{cls}"><h3>{h}</h3>' + ''.join(f'<p>{vtxt(x)}</p>' for x in v.get(k, [])[:4]) + '</div>'
        return head + '<div class="dd">' + col('do', 'ok', '⭕ 이렇게 해요') + col('dont', 'no', '❌ 피해 주세요') + '</div>', {}
    if t == 'grid':
        its = ''.join(f'<div class="gi"><div class="ic">{html.escape(x.get("icon", ""))}</div><b>{vtxt(x.get("title"))}</b>'
                      + (f'<span>{vtxt(x["sub"])}</span>' if x.get('sub') else '') + '</div>' for x in v['items'][:4])
        return head + f'<div class="gr">{its}</div>', {}
    raise SystemExit(f'그림 카드 종류를 모르겠어요: {t} (flow / compare / dodont / grid)')


def sizes(wide):
    if wide:  # 1200x675
        return dict(W=1200, H=675, P=56, s=20, b=26, k=24, g=14, g2=12, t=60, l=26, h=40, gi=12, ip=14, ip2=20, d=36, dn=18, ib=24, is_=19, tp=34, tf=30)
    return dict(W=1080, H=1080, P=80, s=24, b=32, k=30, g=24, g2=18, t=78, l=32, h=56, gi=18, ip=22, ip2=26, d=46, dn=22, ib=32, is_=24, tp=50, tf=38)


def page(inner, z, cat, n, total, vz=None):
    css = CSS % {**z, 'is': z['is_']}
    if vz is not None:
        css += VCSS % {'fi': 92, 'fbt': 31, 'fbs': 24, **vz}
    top = f'<div class="top"><div class="brand">💧 빡<em>세</em></div><div class="chip">{html.escape(cat or "세차 가이드")}</div></div>'
    foot = f'<div class="foot"><span>ppaxse.com 세차 가이드</span><span>{n} / {total}</span></div>'
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>{top}<div class="mid">{inner}</div>{foot}</body></html>'


def cards(slug, wide=False):
    meta, lead, sections, tips = parse(slug)
    z = sizes(wide)
    maxitems = 3 if wide else 4
    vis = {} if wide else load_visual(meta.get('slug') or slug)
    for h in set(vis) - {x['head'] for x in sections}:
        print(f'  ※ 그림 카드 소제목이 원고에 없어요(글자가 똑같아야 해요): {h}')
    vzs = {}
    out, kinds = [], [('cover', meta.get('title', ''))]
    kinds += [('section', s['head']) for s in sections] + [('tip', '')] * len(tips[:2]) + [('end', '')]
    out.append(f'<div class="kicker">빡세 세차 가이드</div><h1>{html.escape(meta.get("title", "").split(" — ")[0])}</h1>'
               + (f'<div class="lead">{html.escape(meta.get("title", "").split(" — ")[1])}</div>' if ' — ' in meta.get('title', '') else
                  f'<div class="lead">{html.escape(lead)}</div>'))
    for i, s in enumerate(sections, 1):
        if s['head'] in vis:
            inner, vz = visual(vis[s['head']])
            vzs[len(out)] = vz
            out.append(inner)
            continue
        its = ''.join(f'<div class="it"><div class="dot">{j if s["ordered"] else "✓"}</div><div><b>{html.escape(a)}</b>'
                      + (f'<span>{html.escape(b)}</span>' if b and not wide else '') + '</div></div>'
                      for j, (a, b) in enumerate(s['items'][:maxitems], 1))
        more = len(s['items']) - maxitems + s['more']
        out.append(f'<div class="num">{i:02d}</div><h2>{html.escape(s["head"])}</h2><div class="items">{its}</div>'
                   + (f'<div class="more">+ {more}가지 더, 본문에서 확인하세요</div>' if more > 0 else ''))
    for t in tips[:2]:
        out.append(f'<div class="tipbox"><i>💡 알아 두면 좋아요</i>{html.escape(short(t, 120 if not wide else 90))}</div>')
    out.append('<h2>내 주변 세차장,<br>지도에서 찾아보세요</h2><div class="cta">셀프·손세차·노터치·자동세차·디테일링 종류와<br>'
               '<b>하부세차·폼건·온수</b> 같은 시설 정보를<br>이용자들이 함께 채워가고 있어요.</div><div><span class="url">ppaxse.com</span></div>')
    return meta, [page(c, z, meta.get('category', ''), i, len(out), vzs.get(i - 1)) for i, c in enumerate(out, 1)], z, kinds


def to_jpg(pngs, jpgs):
    try:
        from PIL import Image
        for p, j in zip(pngs, jpgs):
            Image.open(p).convert('RGB').save(j, 'JPEG', quality=85, optimize=True)  # exif 없이 저장
        return
    except ImportError:
        if not WIN:
            raise SystemExit('JPG 변환에 Pillow가 필요해요: pip install pillow')
    ps = r'''
Add-Type -AssemblyName System.Drawing
$codec=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep=New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality),([long]85)
$pairs=Get-Content -LiteralPath $args[0] -Encoding UTF8
foreach($line in $pairs){ $a,$b=$line -split '\|'
  $src=[System.Drawing.Image]::FromFile($a); $bmp=New-Object System.Drawing.Bitmap $src.Width,$src.Height
  $g=[System.Drawing.Graphics]::FromImage($bmp); $g.DrawImage($src,0,0,$src.Width,$src.Height)   # 새 그림에 옮겨 그려서 메타데이터 없이 저장
  $bmp.Save($b,$codec,$ep); $g.Dispose(); $bmp.Dispose(); $src.Dispose() }
'''
    tmp = tempfile.mkdtemp(prefix='ppx_jpg_')
    lst = os.path.join(tmp, 'list.txt')
    open(lst, 'w', encoding='utf-8-sig').write('\n'.join(f'{p}|{j}' for p, j in zip(pngs, jpgs)))
    sc = os.path.join(tmp, 'conv.ps1')
    open(sc, 'w', encoding='utf-8-sig').write(ps)
    r = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', sc, lst], capture_output=True, timeout=120)
    if r.returncode:
        raise SystemExit('JPG 변환 실패: ' + r.stderr.decode('utf-8', 'ignore')[-400:])
    shutil.rmtree(tmp, ignore_errors=True)


def main(a):
    if not a or a[0].startswith('-'):
        print(__doc__); return
    slugs = [s for s in a if not s.startswith('-') and (a.index(s) == 0 or a[a.index(s) - 1] != '--out')]
    if slugs == ['all']:
        slugs = sorted({dict(META.findall(open(f, encoding='utf-8').read()[:1500])).get('slug') for f in glob.glob(os.path.join(SRC, '[!_]*.html'))} - {None})
    for slug in slugs:
        one(slug, a)


def one(slug, a):
    wide, site = '--wide' in a, '--site' in a
    if site:  # 사이트용: 저장소 guide-img/<slug>/ 에 정사각형 카드 + 어디에 넣을지 목록(cards.json)
        out, wide = os.path.join(REPO, 'guide-img', slug), False
    else:
        out = a[a.index('--out') + 1] if '--out' in a else (
            os.path.join(r'D:\AI_Team\reviews\guide-cards', slug + ('-wide' if wide else '')) if WIN else os.path.join('cards', slug + ('-wide' if wide else '')))
    meta, pages, z, kinds = cards(slug, wide)
    slug = meta.get('slug') or os.path.splitext(os.path.basename(slug))[0]
    tmp = tempfile.mkdtemp(prefix='ppx_cards_')
    br = browser()
    pngs = []
    for i, h in enumerate(pages, 1):
        f = os.path.join(tmp, f'c{i:02d}.html')
        open(f, 'w', encoding='utf-8').write(h)
        png = os.path.join(tmp, f'c{i:02d}.png')
        subprocess.run([br, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                        '--virtual-time-budget=6000', f'--window-size={z["W"]},{z["H"]}', f'--screenshot={png}',
                        'file:///' + f.replace('\\', '/').lstrip('/')], capture_output=True, timeout=90)
        if not os.path.exists(png):
            raise SystemExit(f'{i}번 카드 캡처 실패')
        pngs.append(png)
    os.makedirs(out, exist_ok=True)
    for old in glob.glob(os.path.join(out, '*.jpg')):
        os.remove(old)
    jpgs = [os.path.join(out, f'{slug}-{i:02d}.jpg') for i in range(1, len(pngs) + 1)]
    to_jpg(pngs, jpgs)
    shutil.rmtree(tmp, ignore_errors=True)
    import json
    json.dump({'slug': slug, 'width': z['W'], 'height': z['H'],
               'cards': [{'file': os.path.basename(j), 'kind': k, 'head': h} for j, (k, h) in zip(jpgs, kinds)]},
              open(os.path.join(out, 'cards.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'카드 {len(jpgs)}장 → {out}')
    for j in jpgs:
        print(' ', j)


if __name__ == '__main__':
    main(sys.argv[1:])
