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
def page(path, title, desc, body, crumbs=(), jsonld=None):
    url = f"{SITE}/{quote(path)}"
    depth = path.count('/')  # 'wash/인천/' → 2
    up = '../' * depth
    crumb_html = ''
    if crumbs:
        crumb_html = '<nav class="crumb">' + ' › '.join(
            f'<a href="{SITE}/{esc(h)}">{esc(t)}</a>' if h is not None else esc(t) for t, h in crumbs) + '</nav>'
    ld = ''
    if jsonld:
        ld = '<script type="application/ld+json">' + json.dumps(jsonld, ensure_ascii=False) + '</script>'
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
<meta property="og:image" content="{SITE}/icons/og.png?v=20261111">
<meta name="theme-color" content="#04111e">
<link rel="icon" href="{up}icons/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{up}css/seo.css?v=20261117">
{ld}
</head>
<body>
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
        body = META_RE.sub('', raw).strip()
        slug, title, desc, date = meta['slug'], meta['title'], meta['description'], meta['date']
        path = f'guide/{slug}/'
        jl = {'@context': 'https://schema.org', '@type': 'Article', 'headline': title, 'description': desc,
              'datePublished': date, 'dateModified': meta.get('updated', date),
              'author': {'@type': 'Organization', 'name': '빡세'}, 'publisher': {'@type': 'Organization', 'name': '빡세'}}
        full = f'''<article><h1>{esc(title)}</h1><div class="date">{esc(date)} · 빡세 세차 가이드</div>
{body}
{cta('../../', '', equal=True)}</article>'''
        write(path, page(path, f'{title} | 빡세', desc, full, [('빡세', ''), ('세차 가이드', 'guide/'), (title, None)], jl))
        posts.append((date, slug, title, desc))
        urls.append(path)
    posts.sort(reverse=True)
    lis = ''.join(f'<li class="pl"><h3><a href="{esc(s)}/" style="color:#fff;text-decoration:none">{esc(t)}</a></h3><div class="meta">{esc(d)} · {esc(desc)}</div></li>'
                  for d, s, t, desc in posts)
    write('guide/', page('guide/', '세차 가이드 - 셀프세차 방법·순서·꿀팁 | 빡세',
                         '셀프세차 순서, 계절별 세차 방법, 세차장 고르는 법까지. 세차하는 사람들이 직접 쓰는 세차 가이드.',
                         f'<h1>세차 가이드</h1><p class="lead">세차하면서 궁금했던 것들을 하나씩 정리해요.</p><ul class="list">{lis}</ul>',
                         [('빡세', ''), ('세차 가이드', None)]))
    urls.append('guide/')
    return urls


def build_sitemap(urls):
    base = ['', 'map.html', 'community.html', 'events.html', 'r/']
    # 날짜(lastmod)는 넣지 않음 — 매일 바뀌면 데이터가 그대로여도 매일 커밋이 생김
    items = ''.join(f'<url><loc>{esc(SITE + "/" + quote(u))}</loc></url>' for u in base + urls)
    open(os.path.join(ROOT, 'sitemap.xml'), 'w', encoding='utf-8').write(
        f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{items}</urlset>\n')
    open(os.path.join(ROOT, 'robots.txt'), 'w', encoding='utf-8').write(
        'User-agent: *\nAllow: /\nDisallow: /admin.html\nDisallow: /owner/\nDisallow: /mypage.html\n\n'
        f'Sitemap: {SITE}/sitemap.xml\n')


def main():
    local = '--local' in sys.argv
    places = load_local() if local else load_supabase()
    print(f'세차장 {len(places):,}곳 ({"places.json 시험용" if local else "Supabase 승인된 곳"})')
    urls = build_wash(places) + build_guides()
    build_sitemap(urls)
    print(f'페이지 {len(urls):,}개 만듦, sitemap.xml·robots.txt 갱신')


if __name__ == '__main__':
    main()
