"""빡세 가이드 글 도우미 — 날짜 정하기 · 쓸 편수 계산 · 링크 점검 (윈도우·클라우드 공용)

  python tools/guide_tools.py next-date            다음 글을 넣을 가장 빠른 날 1개
  python tools/guide_tools.py plan [일수] [최대]    앞으로 며칠(기본 7일) 동안 비어 있는 자리 → 오늘 써야 할 날짜 목록
  python tools/guide_tools.py check-links          공개 전 글로 걸린 링크·없는 글 링크 찾기
  python tools/guide_tools.py titles               지금까지 쓴 글 제목 목록(주제 겹침 확인용)
  python tools/guide_tools.py check-length [slug]  글자 수(공백 제외 2,000자 이상)·검색어 반복 횟수 확인

규칙(docs/seo-guide.md): 글이 60편이 될 때까지 하루 2편, 60편부터 하루 1편.
이미 예약된 글은 뒤로 밀지 않음. 공개 전인 글로는 링크를 걸지 않음.
윈도우에서는 py -3 -X utf8 로 실행하면 한글이 깨지지 않음.
"""
import datetime, glob, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, 'guide-src')
META = re.compile(r'<!--\s*(\w+):\s*(.*?)\s*-->')
KST = datetime.timezone(datetime.timedelta(hours=9))
LIMIT = 60  # 이 편수가 되기 전까지 하루 2편, 그 뒤 하루 1편


def posts():
    out = []
    for f in sorted(glob.glob(os.path.join(SRC, '*.html'))):
        if os.path.basename(f).startswith('_'):
            continue
        raw = open(f, encoding='utf-8').read()
        m = dict(META.findall(raw[:1500]))
        if m.get('draft') == 'yes':
            continue
        out.append({'file': f, 'slug': m.get('slug', ''), 'date': m.get('date', ''),
                    'title': m.get('title', ''), 'raw': raw})
    return out


def per_day(total):
    return 2 if total < LIMIT else 1


def plan(days=7, most=10, show=True):
    """내일부터 days일 동안 하루 정원(2 또는 1)을 채우려면 어느 날짜에 몇 편이 필요한지.
    채워 나가면서 편수가 60에 닿으면 그때부터 정원 1로 계산. 최대 most편."""
    ps = posts()
    total = len(ps)
    count = {}
    for p in ps:
        count[p['date']] = count.get(p['date'], 0) + 1
    today = datetime.datetime.now(KST).date()
    need = []
    for i in range(1, days + 1):
        d = (today + datetime.timedelta(days=i)).isoformat()
        while count.get(d, 0) < per_day(total) and len(need) < most:
            need.append(d)
            count[d] = count.get(d, 0) + 1
            total += 1
    if show:
        print(f'지금 글 {len(ps)}편 → 하루 {per_day(len(ps))}편까지 (60편부터 하루 1편)')
        for k in sorted(c for c in count if c > today.isoformat()):
            print(f'  {k}: {count[k]}편' + ('  ← 새로 채울 자리 포함' if k in need else ''))
        print(f'오늘 쓸 편수: {len(need)}편')
        for d in need:
            print('  쓸 날짜:', d)
    return need


def next_date():
    ps = posts()
    today = datetime.datetime.now(KST).date()
    count = {}
    for p in ps:
        count[p['date']] = count.get(p['date'], 0) + 1
    d = today + datetime.timedelta(days=1)  # 오늘 글은 이미 새벽에 공개됐으므로 내일부터
    while count.get(d.isoformat(), 0) >= per_day(len(ps)):
        d += datetime.timedelta(days=1)
    print(f'글 {len(ps)}편 → 하루 {per_day(len(ps))}편까지')
    for k in sorted(c for c in count if c >= today.isoformat()):
        print(f'  {k}: {count[k]}편')
    print('다음 글 날짜:', d.isoformat())
    return d.isoformat()


def check_links():
    ps = posts()
    by = {p['slug']: p for p in ps}
    bad = 0
    for p in ps:
        for s in sorted(set(re.findall(r'href="\.\./([a-z0-9-]+)/"', p['raw']))):
            t = by.get(s)
            if not t:
                print(f'없는 글로 링크: {os.path.basename(p["file"])} → {s}'); bad += 1
            elif t['date'] > p['date']:
                print(f'공개 전 글로 링크: {os.path.basename(p["file"])} ({p["date"]}) → {s} ({t["date"]} 공개)'); bad += 1
    print('링크 문제 없음' if not bad else f'링크 문제 {bad}건')
    return bad


MIN_CHARS = 2000   # 본문 글자 수(공백 제외) 하한 — 운영자 결정 2026-11-19
MAX_REPEAT = 10    # 한 검색어가 본문에 이보다 많이 나오면 '반복이 많다'고 알림(참고용 기준)


def body_text(raw):
    t = re.sub(r'<!--.*?-->', '', raw, flags=re.S)
    t = re.sub(r'<[^>]+>', '', t)
    for a, b in (('&amp;', '&'), ('&lt;', '<'), ('&gt;', '>'), ('&quot;', '"'), ('&nbsp;', ' ')):
        t = t.replace(a, b)
    return t


def check_length(only=None):
    """글자 수(공백 제외)와 검색어 반복 횟수. 검색어는 원고의 <!-- keywords: a, b --> 줄에서 읽음."""
    bad = 0
    for p in sorted(posts(), key=lambda x: x['date']):
        if only and p['slug'] != only:
            continue
        t = body_text(p['raw'])
        n = len(re.sub(r'\s', '', t))
        m = dict(META.findall(p['raw'][:1500]))
        kws = [k.strip() for k in m.get('keywords', '').split(',') if k.strip()]
        compact = re.sub(r'\s', '', t)
        reps = {k: compact.count(k.replace(' ', '')) for k in kws}
        warn = []
        if n < MIN_CHARS:
            warn.append(f'글자 수 부족({MIN_CHARS}자 이상 필요)')
        warn += [f"'{k}' {c}번 — 반복이 많아요" for k, c in reps.items() if c > MAX_REPEAT]
        if not kws:
            warn.append('keywords 줄 없음')
        bad += bool(warn)
        rep = ', '.join(f'{k} {c}번' for k, c in reps.items())
        print(f"{p['date']} {p['slug']}: 공백 제외 {n:,}자" + (f' · {rep}' if rep else '') + (' ← ' + ' / '.join(warn) if warn else ''))
    return bad


def titles():
    for p in sorted(posts(), key=lambda x: x['date']):
        print(f"{p['date']}  {p['slug']}  {p['title']}")


if __name__ == '__main__':
    a = sys.argv[1:]
    cmd = a[0] if a else ''
    if cmd == 'next-date':
        next_date()
    elif cmd == 'plan':
        plan(int(a[1]) if len(a) > 1 else 7, int(a[2]) if len(a) > 2 else 10)
    elif cmd == 'check-links':
        sys.exit(1 if check_links() else 0)
    elif cmd == 'check-length':
        sys.exit(1 if check_length(a[1] if len(a) > 1 else None) else 0)
    elif cmd == 'titles':
        titles()
    else:
        print(__doc__)
