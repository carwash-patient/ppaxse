#!/usr/bin/env python3
"""
검색(구글·네이버) 유입용 페이지 만들기

만드는 것
  wash/                       전국 시·도 목록
  wash/<시도>/                 시·도 안의 시·군·구 목록 + 종류별 바로가기
  wash/<시도>/<시군구>/        그 지역 세차장 목록 (예: wash/인천/부평구/)
  wash/<시도>/<종류>/          시·도 종류별 목록 (예: wash/인천/셀프세차/)
  guide/                      세차 가이드 목록
  guide/<글주소>/              가이드 글 (guide-src/*.html 원고를 페이지로 감쌈)
  sitemap.xml, robots.txt

세차장 데이터
  기본: Supabase 에서 승인된(approved) 세차장을 공개 키로 직접 받음 (지도와 같은 데이터)
  --local: 인터넷 없이 시험할 때 places.json 을 씀 (예전 데이터라 실제 배포에는 쓰지 말 것)

실행
  python3 tools/build_seo.py            # 실제 데이터로 만들기 (GitHub Actions 가 매일 실행)
  python3 tools/build_seo.py --local    # 시험용
"""
import html, json, os, re, shutil, sys, urllib.request
from urllib.parse import quote
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = 'https://ppaxse.com'
KST = timezone(timedelta(hours=9))
TODAY = datetime.now(KST).strftime('%Y-%m-%d')
# 미리보기 전용: --local 과 함께 PPX_PREVIEW_TODAY=2026-11-30 처럼 주면 그날까지의 예약 글도 보이게 만듦 (실제 배포에는 쓰지 않음)
if '--local' in sys.argv and os.environ.get('PPX_PREVIEW_TODAY'):
    TODAY = os.environ['PPX_PREVIEW_TODAY']

# 검색에 쓰는 종류 이름 (주소에도 그대로 씀)
TYPES = [  # (코드, 이름, 아이콘)
    ('self', '셀프세차', '🚿'),
    ('notouch', '노터치세차', '💦'),
    ('hand', '손세차', '🧽'),
    ('detail', '디테일링샵', '✨'),
    ('auto', '자동세차', '⛽'),
]
TYPE_NAME = {c: n for c, n, _ in TYPES}
TYPE_NAME['wash'] = '종류 확인 중'
TYPE_ICON = {c: i for c, _, i in TYPES}
TYPE_ICON['wash'] = '💧'
FAC = [('foam', '💨 폼건'), ('under', '⬇️ 하부세차'), ('indoor', '🏠 실내'), ('h24', '🌙 24시간'), ('myitem', '🧴 개인용품 가능')]

COLS = 'id,name,addr,region,type,types,tel,hours,h24,foam,under,indoor,myitem,check_count,comment_count'


def esc(s):
    return html.escape(str(s or ''), quote=True)


# ── 데이터 ─────────────────────────────────────────
def supa_cfg():
    cfg = open(os.path.join(ROOT, 'js', 'config.js'), encoding='utf-8').read()
    return re.search(r"url:\s*'([^']+)'", cfg).group(1), re.search(r"key:\s*'([^']+)'", cfg).group(1)


# 조회수 세기: 기존 방문자 세기와 같은 기기 번호(ppxVisitor)를 써서 supabase 함수 ppx_track_page 호출
#  · 운영자 기기(ppxNoTrack), 검색엔진 로봇은 세지 않음 · 실패해도 화면에는 영향 없음
def track_script():
    url, key = supa_cfg()
    return '''<script>
(function(){try{
var ua=navigator.userAgent||'';
if(navigator.webdriver||/bot|crawl|spider|slurp|yeti|daumoa|bingpreview|headless|lighthouse/i.test(ua)||localStorage.getItem('ppxNoTrack'))return;
var v=localStorage.getItem('ppxVisitor');
if(!v||!/^[0-9a-f-]{36}$/.test(v)){v=crypto.randomUUID?crypto.randomUUID():'10000000-1000-4000-8000-100000000000'.replace(/[018]/g,function(c){return(c^crypto.getRandomValues(new Uint8Array(1))[0]&15>>c/4).toString(16)});localStorage.setItem('ppxVisitor',v);}
var r=document.referrer,h='';try{h=r?new URL(r).hostname:''}catch(e){}
var s=!r?'direct':/google\\./.test(h)?'google':/naver\\./.test(h)?'naver':/daum\\.|kakao/.test(h)?'daum':/bing\\./.test(h)?'bing':/ppaxse\\.com$/.test(h)?'ppaxse':'other';
var t=(document.querySelector('h1')||{}).textContent||document.title,P=decodeURI(location.pathname);
function rpc(f,b){return fetch('%s/rest/v1/rpc/'+f,{method:'POST',keepalive:true,headers:{'Content-Type':'application/json',apikey:'%s',Authorization:'Bearer %s'},body:JSON.stringify(b)}).catch(function(){})}
document.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('[data-cta]');if(a)rpc('ppx_track_click',{v:v,pth:P,b:a.getAttribute('data-cta')})});
setTimeout(function(){rpc('ppx_track_page',{v:v,pth:P,s:s,t:t.slice(0,120)})},800);
}catch(e){}})();
</script>''' % (url, key, key)


def load_supabase():
    url, key = supa_cfg()
    out, step = [], 1000
    while True:
        q = f"{url}/rest/v1/places?select={COLS}&status=eq.approved&order=id&offset={len(out)}&limit={step}"
        req = urllib.request.Request(q, headers={'apikey': key, 'Authorization': f'Bearer {key}'})
        with urllib.request.urlopen(req, timeout=60) as r:
            rows = json.load(r)
        out += rows
        if len(rows) < step:
            return out


def load_local():
    return json.load(open(os.path.join(ROOT, 'places.json'), encoding='utf-8'))


def kinds(p):
    """세차장의 종류들 (대표 종류 먼저, 정비·기타 제외)"""
    ks = [p.get('type')] + list(p.get('types') or [])
    seen = []
    for k in ks:
        if k and k != 'etc' and k not in seen:
            seen.append(k)
    if len(seen) > 1 and 'wash' in seen:
        seen.remove('wash')
    return seen


def split_region(r):
    parts = (r or '').split()
    if not parts:
        return None, None
    return parts[0], (' '.join(parts[1:]) or parts[0])


# ── 페이지 틀 ───────────────────────────────────────
def bottom_nav(up):
    """지도·이벤트·내 정보 화면과 같은 아래 메뉴 (세차 가이드 페이지용, '세차 가이드' 칸이 켜짐)"""
    items = [('map.html', '🗺️', '지도', False), ('guide/', '📖', '세차 가이드', True),
             ('events.html', '🎁', '이벤트', False), ('mypage.html', '👤', '내 정보', False)]
    on_cls = ' class="on"'
    return '<nav class="bnav">' + ''.join(
        f'<a href="{up}{h}"{on_cls if on else ""}><i>{ic}</i><span>{t}</span></a>' for h, ic, t, on in items) + '</nav>'


def page(path, title, desc, body, crumbs=(), jsonld=None, bnav=False, og_image=None):
    url = f"{SITE}/{quote(path)}"
    depth = path.count('/')  # 'wash/인천/' → 2
    up = '../' * depth
    crumb_html = ''
    if crumbs:
        crumb_html = '<nav class="crumb">' + ' › '.join(
            f'<a href="{SITE}/{esc(h)}">{esc(t)}</a>' if h is not None else esc(t) for t, h in crumbs) + '</nav>'
    ld = ''
    if jsonld:
        # '<'를 <로: 세차장 이름에 </script> 같은 글자가 있어도 설명표가 중간에 끊기지 않게 (JSON 뜻은 그대로)
        ld = '<script type="application/ld+json">' + json.dumps(jsonld, ensure_ascii=False).replace('<', '\\u003c') + '</script>'
    return f'''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="canonical" href="{esc(url)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="빡세">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:url" content="{esc(url)}">
<meta property="og:image" content="{esc(og_image or SITE + '/icons/og.png?v=20261111')}">
<meta name="theme-color" content="#04111e">
<link rel="icon" href="{up}icons/icon.svg" type="image/svg+xml">
<link rel="icon" href="{up}icons/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="{up}icons/icon-192.png" sizes="192x192" type="image/png">
<link rel="apple-touch-icon" href="{up}icons/apple-touch-icon.png">
<link rel="stylesheet" href="{up}css/seo.css?v=20261121a">
{ld}
</head>
<body{' class="has-bnav"' if bnav else ''}>
<header class="top"><a class="brand" href="{up}">💧 빡<em>세</em></a><a class="go" href="{up}map.html">🗺️ 세차장 지도</a></header>
<main>
{crumb_html}
{body}
</main>
<footer>
<a href="{up}wash/">지역별 세차장</a> · <a href="{up}guide/">세차 가이드</a> · <a href="{up}privacy.html">개인정보처리방침</a><br>
세차장 기본 정보: 행정안전부 전국세차장표준데이터(공공데이터포털) · 이용자 제보<br>
운영시간·시설은 바뀔 수 있어요. 가기 전에 전화로 확인해 주세요. 틀린 정보는 지도에서 알려주세요.<br>
© 2026 빡세(Ppaxse)
</footer>
{bottom_nav(up) if bnav else ''}
{track_script()}
</body>
</html>
'''


def write(path, content):
    full = os.path.join(ROOT, path, 'index.html') if path.endswith('/') or path == '' else os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'w', encoding='utf-8') as f:
        f.write(content)


def place_card(p, up):
    ks = kinds(p)
    badges = ''.join(f'<span class="bd t">{TYPE_ICON.get(k, "")} {esc(TYPE_NAME.get(k, k))}</span>' for k in ks)
    badges += ''.join(f'<span class="bd">{l}</span>' for k, l in FAC if p.get(k))
    meta = [esc(p.get('addr'))]
    if p.get('tel'):
        meta.append(f'☎ <a href="tel:{esc(p["tel"])}">{esc(p["tel"])}</a>')
    if p.get('hours'):
        meta.append(f'🕒 {esc(p["hours"])}')
    talk = p.get('comment_count') or 0
    talk_txt = f'💬 한마디 {talk}개 보기·남기기' if talk else '✏️ 이 세차장에 한마디 남기기'
    return f'''<li class="pl"><h3>{esc(p["name"])}</h3>
<div class="meta">{"<br>".join(meta)}</div>
<div class="badges">{badges}</div>
<div class="acts"><a class="main" href="{up}r/?p={p["id"]}" data-cta="card_review">{talk_txt}</a><a href="{up}map.html?p={p["id"]}" data-cta="card_map">🗺️ 지도에서 보기</a></div></li>'''


def cta(up, where, equal=False):
    """검색으로 들어온 사람을 빡세 지도로 보내는 안내 상자. where 가 비어 있으면 '우리 동네'
    equal=True(가이드 글): 두 버튼을 같은 모양으로 — 어느 쪽이 더 눌리는지 보려고"""
    w = where or '우리 동네'
    sub = '' if equal else ' class="sub"'
    map_url = f'{up}map.html?r={quote(where)}' if where else f'{up}map.html'   # 지역 페이지면 그 지역으로 바로
    return f'''<div class="cta"><b>🗺️ {esc(w)} 세차장, 지도에서 한눈에 보세요</b>
<p>셀프세차·노터치·손세차를 종류별로 골라 보고, 폼건·온수·하부세차 같은 시설 정보도 확인할 수 있어요.</p>
<a href="{map_url}" data-cta="cta_map">🗺️ 세차장 지도 열기</a><a{sub} href="{up}r/" data-cta="cta_review">✏️ 자주 가는 세차장에 한마디 남기기</a>
<p style="font-size:12.5px;margin:8px 0 0;color:var(--muted)">🎁 한마디를 남기면 가입 없이도 매주 기프티콘 추첨에 응모돼요.</p></div>'''


def ww_line(up):
    """가이드 글 끝 '세차하기 좋은 날' 한 줄 상자. 지역은 홈 달력에서 고른 곳(없으면 서울 중구)
    날씨 받기·판정은 js/ww-core.js (홈 달력·지도 띠와 같은 기준). 글을 못 불러와도 링크는 그대로 보임"""
    return f'''<link rel="stylesheet" href="{up}css/ww.css?v=20261121a">
<a class="ww-guide" id="wwGuide" href="{up}#washWeather"><span class="ww-gq">☀️ 오늘 세차하기 좋은 날일까요?</span>
<span class="ww-gl" id="wwGuideLine">날씨 보고 세차할 날 고르기</span><span class="ww-gb">10일 달력 보기 ›</span></a>
<script src="{up}js/ww-regions.js?v=20261120a" defer></script>
<script src="{up}js/ww-core.js?v=20261120a" defer></script>
<script>window.addEventListener('load',async function(){{if(!window.WW)return;var r=WW.savedRegion()||WW.find('서울 중구');if(!r)return;var w=await WW.load(r,false);if(!w)return;var s=WW.todayLine(w.d),el=document.getElementById('wwGuide');el.className='ww-guide '+s.j.k;document.getElementById('wwGuideLine').textContent=s.j.icon+' '+r[0]+' · '+s.text}})</script>'''


def ww_box(up, where):
    """지역 페이지의 '세차하기 좋은 날' 10일 달력 (그 지역으로 고정). 그리는 일은 js/wash-weather.js
    지역 대표 좌표는 js/ww-regions.js — 거기 없는 새 지역이면 상자가 저절로 숨음"""
    short = where.split(' ', 1)[-1]
    return f'''<link rel="stylesheet" href="{up}css/ww.css?v=20261121a">
<section class="ww ww-in" id="washWeather" data-region="{esc(where)}" aria-label="{esc(short)} 세차하기 좋은 날">
<div class="ww-head"><h2 class="ww-title">☀️ {esc(short)} 세차하기 좋은 날</h2></div>
<div class="ww-sum" id="wwSum"></div><div class="ww-grid" id="wwGrid"></div><div class="ww-dust" id="wwDust"></div>
<div class="ww-legend"><span class="good">✨ 추천: 7일 안에 비 없음</span><span>⛅ 보통: 4~7일 뒤 비</span><span>🙅 비추: 1~3일 뒤 비</span><span>☔ 비·눈</span><span>🥶 영하 5도 이하</span><span><i class="ww-lo">최저</i>/<i class="ww-hi">최고</i> 기온(℃)</span></div>
<p class="ww-note">예보 기준이라 바뀔 수 있어요 · 날씨 정보: <a href="https://open-meteo.com/" target="_blank" rel="noopener">Open-Meteo</a></p>
</section>
<script src="{up}js/ww-regions.js?v=20261120a" defer></script>
<script src="{up}js/ww-core.js?v=20261120a" defer></script>
<script src="{up}js/wash-weather.js?v=20261120h" defer></script>'''


def type_summary(ps):
    c = Counter()
    for p in ps:
        for k in kinds(p):
            c[k] += 1
    return c


def summary_text(c):
    return ', '.join(f'{TYPE_NAME[k]} {c[k]}곳' for k, _, _ in TYPES if c.get(k))


# ── 만들기 ──────────────────────────────────────────
def build_wash(places):
    shutil.rmtree(os.path.join(ROOT, 'wash'), ignore_errors=True)
    by_sido = defaultdict(lambda: defaultdict(list))
    for p in places:
        if not kinds(p):
            continue
        sido, gu = split_region(p.get('region'))
        if sido:
            by_sido[sido][gu].append(p)
    urls = []

    for sido, gus in by_sido.items():
        all_ps = [p for ps in gus.values() for p in ps]
        sc = type_summary(all_ps)

        # 시·군·구 페이지
        for gu, ps in gus.items():
            path = f'wash/{sido}/{gu}/' if gu != sido else f'wash/{sido}/전체/'
            where = f'{sido} {gu}' if gu != sido else sido
            c = type_summary(ps)
            ps.sort(key=lambda p: ([k for k, _, _ in TYPES] + ['wash']).index(kinds(p)[0]) if kinds(p)[0] in TYPE_NAME else 9)
            groups = ''
            for code in [k for k, _, _ in TYPES] + ['wash']:
                g = [p for p in ps if kinds(p)[0] == code]
                if g:
                    groups += f'<h2>{TYPE_ICON[code]} {esc(where)} {esc(TYPE_NAME[code])} ({len(g)}곳)</h2><ul class="list">' + ''.join(place_card(p, '../../../') for p in g) + '</ul>'
            fac = Counter(k for p in ps for k, _ in FAC if p.get(k))
            fac_txt = ', '.join(f'{l.split(" ",1)[1]} {fac[k]}곳' for k, l in FAC if fac.get(k))
            lead = f'{esc(where)}에 있는 세차장 {len(ps)}곳을 모았어요. {esc(summary_text(c))}.'
            if fac_txt:
                lead += f' 이용자 제보로 확인된 시설: {esc(fac_txt)}.'
            stats = ''.join(f'<span class="stat">{TYPE_ICON[k]} {TYPE_NAME[k]} {c[k]}</span>' for k, _, _ in TYPES if c.get(k))
            body = f'''<h1>{esc(where)} 세차장 {len(ps)}곳 · 셀프세차·노터치·손세차</h1>
<p class="lead">{lead}</p><div class="stats">{stats}</div>
<p class="lead" style="font-size:12px">※ 종류별 숫자는 두 가지를 함께 하는 곳(예: 노터치+셀프)도 각각 셉니다. 아래 목록은 대표 종류로 나눴어요.</p>
{ww_box('../../../', where)}
{cta('../../../', where)}
{groups}
{cta('../../../', where)}
<h2>{esc(sido)} 다른 지역</h2><ul class="grid">''' + ''.join(
                f'<li><a href="../{esc(g2)}/">{esc(g2)}<span>{len(v)}</span></a></li>' for g2, v in sorted(gus.items()) if g2 != gu and g2 != sido) + '</ul>'
            title = f'{where} 세차장 {len(ps)}곳 - 셀프세차·노터치·손세차 위치와 시설 | 빡세'
            desc = f'{where} 세차장 {len(ps)}곳: {summary_text(c)}. 주소·전화·폼건·하부세차 정보를 한 번에 확인하세요.'
            jl = {'@context': 'https://schema.org', '@type': 'ItemList', 'name': f'{where} 세차장',
                  'itemListElement': [{'@type': 'ListItem', 'position': i + 1,
                                       'item': {'@type': 'AutoWash', 'name': p['name'], 'address': p.get('addr'),
                                                **({'telephone': p['tel']} if p.get('tel') else {})}}
                                      for i, p in enumerate(ps[:100])]}
            write(path, page(path, title, desc, body, [('빡세', ''), ('지역별 세차장', 'wash/'), (sido, f'wash/{sido}/'), (where, None)], jl))
            urls.append(path)

        # 시·도 종류별 페이지 (예: 인천 셀프세차장)
        type_links = ''
        for code, name, icon in TYPES:
            g = [p for p in all_ps if code in kinds(p)]
            if not g:
                continue
            path = f'wash/{sido}/{name}/'
            per_gu = defaultdict(list)
            for p in g:
                per_gu[split_region(p['region'])[1]].append(p)
            sections = ''.join(
                f'<h2>{esc(sido)} {esc(gu)} {esc(name)} ({len(v)}곳)</h2><ul class="list">' + ''.join(place_card(p, '../../../') for p in v) + '</ul>'
                for gu, v in sorted(per_gu.items(), key=lambda x: -len(x[1])))
            body = f'''<h1>{esc(sido)} {esc(name)}장 {len(g)}곳 모음</h1>
<p class="lead">{esc(sido)}에서 {esc(name)}가 되는 곳 {len(g)}곳을 시·군·구별로 정리했어요. 많은 순: ''' + ', '.join(
                f'{esc(gu)} {len(v)}곳' for gu, v in sorted(per_gu.items(), key=lambda x: -len(x[1]))[:5]) + f'''.</p>
{cta('../../../', sido)}{sections}{cta('../../../', sido)}'''
            title = f'{sido} {name}장 {len(g)}곳 - 지역별 위치·전화·시설 | 빡세'
            desc = f'{sido} {name}장 {len(g)}곳을 시·군·구별로 모았어요. 주소·전화번호·폼건·하부세차 정보를 확인하세요.'
            write(path, page(path, title, desc, body, [('빡세', ''), ('지역별 세차장', 'wash/'), (sido, f'wash/{sido}/'), (name, None)]))
            urls.append(path)
            type_links += f'<span class="stat"><a style="color:#fff;text-decoration:none" href="{esc(name)}/">{icon} {esc(sido)} {esc(name)} {len(g)}</a></span>'

        # 시·도 페이지
        path = f'wash/{sido}/'
        grid = ''.join(f'<li><a href="{esc(gu if gu != sido else "전체")}/">{esc(gu)}<span>{len(v)}</span></a></li>' for gu, v in sorted(gus.items()))
        body = f'''<h1>{esc(sido)} 세차장 {len(all_ps)}곳 · 지역별 모음</h1>
<p class="lead">{esc(summary_text(sc))}. 시·군·구를 고르거나 종류별로 보세요.</p>
<div class="stats">{type_links}</div><h2>시·군·구별</h2><ul class="grid">{grid}</ul>{cta('../../', sido)}'''
        write(path, page(path, f'{sido} 세차장 {len(all_ps)}곳 - 셀프세차·노터치·손세차 지역별 | 빡세',
                         f'{sido} 세차장 {len(all_ps)}곳: {summary_text(sc)}. 시·군·구별로 위치와 시설을 확인하세요.',
                         body, [('빡세', ''), ('지역별 세차장', 'wash/'), (sido, None)]))
        urls.append(path)

    # 전국
    total = sum(len(v) for g in by_sido.values() for v in g.values())
    grid = ''.join(f'<li><a href="{esc(s)}/">{esc(s)}<span>{sum(len(v) for v in g.values())}</span></a></li>'
                   for s, g in sorted(by_sido.items(), key=lambda x: -sum(len(v) for v in x[1].values())))
    body = f'''<h1>전국 세차장 {total:,}곳 · 지역별 모음</h1>
<p class="lead">셀프세차·노터치·손세차·디테일링샵·자동세차를 지역별로 정리했어요. 공공데이터에 이용자 제보를 더해 계속 고쳐가고 있어요.</p>
<ul class="grid">{grid}</ul>{cta('../', '')}'''
    write('wash/', page('wash/', f'전국 세차장 {total:,}곳 지역별 모음 - 셀프세차·노터치·손세차 | 빡세',
                        '전국 세차장을 시·도, 시·군·구별로 모았어요. 셀프세차·노터치·손세차 위치와 폼건·하부세차 정보.',
                        body, [('빡세', ''), ('지역별 세차장', None)]))
    urls.append('wash/')
    return urls


META_RE = re.compile(r'<!--\s*(\w+)\s*:\s*(.*?)\s*-->')


# 가이드 꼬리표 색 (원고의 <!-- category: … --> 값). 목록에 없는 값도 회색 꼬리표로 나옴
CATEGORY_CLS = {'입문': 'c1', '차 상태별': 'c2', '계절': 'c3', '더 깔끔하게': 'c4'}
NEW_DAYS = 3   # 올린 지 이 날수 안 된 글에 '새 글'


def guide_item(no, p, pinned):
    d = p['date']
    md = f'{int(d[5:7])}/{int(d[8:10])}' if re.match(r'\d{4}-\d{2}-\d{2}$', d) else d
    try:
        age = (datetime.strptime(TODAY, '%Y-%m-%d') - datetime.strptime(d, '%Y-%m-%d')).days
    except ValueError:
        age = 99
    cat = p['category']
    tag = f'<span class="cat {CATEGORY_CLS.get(cat, "c0")}">{esc(cat)}</span>' if cat else ''
    new = '<span class="new">새 글</span>· ' if 0 <= age < NEW_DAYS else ''
    no_html = '<span class="no pin" aria-label="추천">🔰</span>' if pinned else f'<span class="no">{no}</span>'
    return (f'<li data-cat="{esc(cat)}"><a class="gl{" start" if pinned else ""}" href="{esc(p["slug"])}/">'
            f'{no_html}<div><div class="t">{esc(p["title"])}</div>'
            f'<div class="m">{tag}{new}{esc(md)}</div></div></a></li>')


def guide_nav(prev, nxt):
    """가이드 글 위·아래의 '이전 글 · 목록 · 다음 글' 버튼. 이전 = 먼저 쓴 글, 다음 = 나중에 쓴 글 (공개된 글끼리만)"""
    def btn(p, label, cls):
        if not p:
            return f'<span class="gn-b {cls} off">{label}</span>'
        return f'<a class="gn-b {cls}" href="../{esc(p["slug"])}/" title="{esc(p["title"])}">{label}</a>'
    return (f'<nav class="gnav" aria-label="글 이동">{btn(prev, "‹ 이전 글", "prev")}'
            f'<a class="gn-b list" href="../">☰ 목록</a>{btn(nxt, "다음 글 ›", "next")}</nav>')


# 가이드 글 주소 → 마지막 수정일(updated 또는 date). 사이트맵 lastmod 에 씀
GUIDE_LASTMOD = {}


def add_cards(slug, body):
    """guide-img/<slug>/cards.json (tools/guide_cards.py --site 가 만듦)이 있으면 카드뉴스 이미지를 글 속에 넣음.
    표지 = 첫 문단 뒤, 소제목 카드 = 같은 소제목(h2) 바로 뒤. 팁·마무리 카드는 글에 이미 있는 내용이라 넣지 않음."""
    f = os.path.join(ROOT, 'guide-img', slug, 'cards.json')
    if not os.path.exists(f):
        return body, None
    m = json.load(open(f, encoding='utf-8'))
    w, h = m.get('width', 1080), m.get('height', 1080)
    fig = lambda c: (f'<figure class="gcard"><img src="../../guide-img/{esc(slug)}/{esc(c["file"])}" alt="{esc(c["head"])} 요약 카드" '
                     f'width="{w}" height="{h}" loading="lazy" decoding="async"></figure>')
    og = None
    for c in m.get('cards', []):
        if c['kind'] == 'cover':
            og = f'{SITE}/guide-img/{quote(slug)}/{quote(c["file"])}'
            body = re.sub(r'(</p>)', lambda x: x.group(1) + '\n' + fig(c).replace(' loading="lazy"', ''), body, count=1)
        elif c['kind'] == 'section':
            pat = re.compile(r'(<h2>\s*' + re.escape(esc(c['head'])).replace('\\ ', r'\s+') + r'\s*</h2>)')
            if not pat.search(body):  # 원고 속 h2 가 이스케이프 안 된 경우
                pat = re.compile(r'(<h2>\s*' + re.escape(c['head']).replace('\\ ', r'\s+') + r'\s*</h2>)')
            body = pat.sub(lambda x: x.group(1) + '\n' + fig(c), body, count=1)
    return body, og


def build_guides():
    src = os.path.join(ROOT, 'guide-src')
    shutil.rmtree(os.path.join(ROOT, 'guide'), ignore_errors=True)
    posts, urls = [], []
    for fn in sorted(os.listdir(src)) if os.path.isdir(src) else []:
        if not fn.endswith('.html') or fn.startswith('_'):
            continue
        raw = open(os.path.join(src, fn), encoding='utf-8').read()
        meta = dict(META_RE.findall(raw[:1500]))
        if meta.get('draft') == 'yes':
            continue
        # 예약 공개: date 가 오늘(한국 시간)보다 뒤면 아직 숨김 → 그날 새벽 자동 실행 때 공개
        if meta.get('date', '') > TODAY:
            continue
        body = META_RE.sub('', raw).strip()
        slug, title, desc, date = meta['slug'], meta['title'], meta['description'], meta['date']
        path = f'guide/{slug}/'
        jl = {'@context': 'https://schema.org', '@type': 'Article', 'headline': title, 'description': desc,
              'datePublished': date, 'dateModified': meta.get('updated', date),
              'author': {'@type': 'Organization', 'name': '빡세'}, 'publisher': {'@type': 'Organization', 'name': '빡세'}}
        body, og = add_cards(slug, body)
        if og:
            jl['image'] = og
        pin = meta.get('pin', '').strip()
        GUIDE_LASTMOD[path] = meta.get('updated', date)
        posts.append({'date': date, 'slug': slug, 'title': title, 'category': meta.get('category', '').strip(),
                      'pin': int(pin) if pin.isdigit() else None,
                      '_w': (path, desc, body, jl, og)})
        urls.append(path)
    # 쓴 순서(날짜 → 파일 이름)대로 줄 세워 이전 글·다음 글을 정한 뒤 글 페이지를 씀
    order = sorted(posts, key=lambda p: (p['date'], p['slug']))
    for k, p in enumerate(order):
        path, desc, body, jl, og = p.pop('_w')
        title, date = p['title'], p['date']
        nav = guide_nav(order[k - 1] if k > 0 else None, order[k + 1] if k + 1 < len(order) else None)
        full = f'''<article>{nav}<h1>{esc(title)}</h1><div class="date">{esc(date)} · 빡세 세차 가이드</div>
{body}
{cta('../../', '', equal=True)}{ww_line('../../')}{nav}</article>'''
        write(path, page(path, f'{title} | 빡세', desc, full, [('빡세', ''), ('세차 가이드', 'guide/'), (title, None)], jl, bnav=True, og_image=og))
    # 맨 위 '처음이라면 이것부터' = pin 숫자 순서, 나머지 = 최신순으로 보여 주되 번호는 먼저 쓴 글이 1번 (추천 글은 번호 없이 🔰)
    pinned = sorted([p for p in posts if p['pin'] is not None], key=lambda p: (p['pin'], p['date']))
    rest = sorted([p for p in posts if p['pin'] is None], key=lambda p: (p['date'], p['slug']), reverse=True)
    body = '<h1>📖 세차 가이드</h1><p class="lead">세차하면서 궁금했던 것들을 하나씩 정리해요.</p>'
    cats = [c for c in CATEGORY_CLS if any(p['category'] == c for p in posts)]
    cats += sorted({p['category'] for p in posts if p['category'] and p['category'] not in CATEGORY_CLS})
    if len(cats) > 1:
        body += '<div class="chips" id="gChips"><button type="button" class="on" data-c="">전체</button>' + ''.join(
            f'<button type="button" data-c="{esc(c)}">{esc(c)}</button>' for c in cats) + '</div>'
    if pinned:
        body += '<div class="gsec">🔰 처음이라면 이것부터</div><ul class="glist">' + ''.join(
            guide_item(i + 1, p, True) for i, p in enumerate(pinned)) + '</ul>'
    if rest:
        body += '<div class="gsec">📚 전체 글 <small>최신순</small></div><ul class="glist">' + ''.join(
            guide_item(len(rest) - i, p, False) for i, p in enumerate(rest)) + '</ul>'
    if len(cats) > 1:
        # 분류 버튼: 그 분류 글만 보이기 (글이 하나도 없는 묶음은 제목도 숨김)
        body += '''<script>
(function(){var box=document.getElementById('gChips');if(!box)return;
box.addEventListener('click',function(e){var b=e.target.closest('button');if(!b)return;var c=b.getAttribute('data-c');
box.querySelectorAll('button').forEach(function(x){x.classList.toggle('on',x===b)});
document.querySelectorAll('.glist').forEach(function(ul){var n=0;ul.querySelectorAll('li').forEach(function(li){var ok=!c||li.getAttribute('data-cat')===c;li.hidden=!ok;if(ok)n++});
ul.hidden=!n;var h=ul.previousElementSibling;if(h&&h.classList.contains('gsec'))h.hidden=!n;});});})();
</script>'''
    write('guide/', page('guide/', '세차 가이드 - 셀프세차 방법·순서·꿀팁 | 빡세',
                         '셀프세차 순서, 계절별 세차 방법, 세차장 고르는 법까지. 세차하는 사람들이 직접 쓰는 세차 가이드.',
                         body, [('빡세', ''), ('세차 가이드', None)], bnav=True))
    if GUIDE_LASTMOD:
        GUIDE_LASTMOD['guide/'] = max(GUIDE_LASTMOD.values())
    urls.append('guide/')
    return urls


def build_sitemap(urls):
    base = ['', 'map.html', 'events.html', 'r/']  # community.html은 noindex라 뺌
    # 날짜(lastmod)는 가이드 글에만 넣음 — 글의 date/updated 라서 매일 바뀌지 않음.
    # 지역 페이지 등은 넣지 않음 — 매일 바뀌면 데이터가 그대로여도 매일 커밋이 생김
    def item(u):
        lm = GUIDE_LASTMOD.get(u)
        return f'<url><loc>{esc(SITE + "/" + quote(u))}</loc>' + (f'<lastmod>{lm}</lastmod>' if lm else '') + '</url>'
    items = ''.join(item(u) for u in base + urls)
    open(os.path.join(ROOT, 'sitemap.xml'), 'w', encoding='utf-8').write(
        f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{items}</urlset>\n')
    open(os.path.join(ROOT, 'robots.txt'), 'w', encoding='utf-8').write(
        'User-agent: *\nAllow: /\nDisallow: /admin.html\nDisallow: /owner/\nDisallow: /mypage.html\n\n'
        f'Sitemap: {SITE}/sitemap.xml\n')


def check_place_count(n):
    """안전장치 (2026-11-20): 받아 온 세차장 수가 갑자기 크게 줄면 지역 페이지를 지우기 전에 멈춤.
    DB 장애·권한 변경으로 목록이 비거나 일부만 오면, wash/를 통째로 지우고 그대로 올려 버리는 사고를 막음.
    기준: 지난번 지역 페이지(wash/index.html)에 적힌 세차장 수의 80% 미만이거나 1,000곳 미만이면 중단.
    정말로 많이 줄어든 게 맞다면(대량 정리 등) 환경변수 PPX_ALLOW_DROP=1 로 한 번 실행하면 됨."""
    if os.environ.get('PPX_ALLOW_DROP') == '1':
        return
    prev = 0
    try:
        with open(os.path.join(ROOT, 'wash', 'index.html'), encoding='utf-8') as f:
            m = re.search(r'([\d,]+)곳', f.read())
        if m:
            prev = int(m.group(1).replace(',', ''))
    except OSError:
        pass
    if n < 1000 or (prev and n < prev * 0.8):
        sys.exit(f'중단: 세차장이 {n:,}곳만 받아졌어요 (지난번 {prev:,}곳). '
                 f'DB나 연결 문제일 수 있어 지역 페이지를 지우지 않고 멈춥니다.')


def main():
    local = '--local' in sys.argv
    places = load_local() if local else load_supabase()
    print(f'세차장 {len(places):,}곳 ({"places.json 시험용" if local else "Supabase 승인된 곳"})')
    if not local:
        check_place_count(len(places))
    urls = build_wash(places) + build_guides()
    build_sitemap(urls)
    print(f'페이지 {len(urls):,}개 만듦, sitemap.xml·robots.txt 갱신')


if __name__ == '__main__':
    main()
