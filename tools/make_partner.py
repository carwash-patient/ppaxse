# 업체별 협찬 제안 페이지 만들기: python3 tools/make_partner.py
# partner/<slug>/index.html 을 같은 틀로 만든다. 업체가 늘면 BRANDS에 한 줄 추가.
import os, html

BRANDS = {
    'autogrooming': {
        'name': '오토그루밍',
        'greet': '먼저 긍정적으로 답해 주셔서 감사합니다.',
        'novice': '입문자는 브랜드 대신 ‘셀프세차 처음’, ‘유막 제거’를 찾습니다. ‘세차 초보부터 디테일링 고수까지’, 오토그루밍이 먼저 닿을 수 있는 사람입니다.',
        'flow': ['비 소식 · 세차날씨', '유막제거·발수코팅 가이드', '오토그루밍 클린뷰 유막제거제'],
    },
    'n09': {
        'name': '엔공구',
        'greet': '인스타그램에서 서로 팔로우만 하다가, 처음 인사드립니다.',
        'novice': '입문자는 브랜드 대신 ‘셀프세차 처음’, ‘세차용품 기본 구성’을 찾습니다. 300여 개 브랜드와 9,000가지가 넘는 상품을 갖춘 엔공구 스토어는 이 질문에 가장 넓게 답할 수 있는 곳입니다.',
        'flow': ['세차하기 좋은 날 · 세차날씨', '셀프세차용품 기본 구성 가이드', '엔공구 스토어 · 듀플렉스 듀'],
        'extra': '<div class="card hl" style="margin-top:6px"><p class="k">한 가지 더</p><h3>세차장 사장님과도 이어집니다</h3><p class="muted small">빡세에는 전국 세차장 1만 1,625곳과, 사장님이 매장 정보를 직접 보내는 통로가 있습니다. 세차장·시공업체에 상품을 공급하는 엔공구 B2B와도 나중에 함께 이야기할 수 있기를 기대합니다. 이번 제안의 범위는 아닙니다.</p></div>',
    },
}

CSS = """
:root{--bg:#F2F1EC;--ink:#262B33;--muted:#5A5F66;--line:#E2DFD6;--lime:#B5C95F;--olive:#56661A;--panel:#30353D;--orange:#9A4F12}
*{box-sizing:border-box;margin:0;padding:0}
html,body{background:var(--bg);color:var(--ink);font-family:'Noto Sans KR',-apple-system,sans-serif;font-size:16px;line-height:1.7;word-break:keep-all}
.wrap{max-width:760px;margin:0 auto;padding:20px 20px 60px}
.top{display:flex;align-items:center;justify-content:space-between;margin-bottom:28px}
.brand{display:flex;align-items:center;gap:8px;text-decoration:none;color:var(--ink);font-weight:900;font-size:17px}
.brand img{width:32px;height:32px;border-radius:9px}
.brand em{color:#D9822B;font-style:normal}
.top a.site{font-size:13px;color:var(--muted);text-decoration:none;border:1px solid var(--line);padding:6px 12px;border-radius:999px;background:#fff}
h1,h2{font-family:'Black Han Sans','Noto Sans KR',sans-serif;font-weight:400;letter-spacing:0;line-height:1.3}
h1{font-size:34px;margin:6px 0 18px}
h2{font-size:26px;margin:4px 0 14px}
h3{font-size:17px;font-weight:900;line-height:1.45}
.eyebrow{font-size:13px;font-weight:700;color:var(--olive)}
section{padding:34px 0;border-top:1px solid var(--line)}
section.first{border-top:none;padding-top:0}
p{margin-bottom:10px}
.muted{color:var(--muted)}
.small{font-size:14px}
.card{background:#fff;border:1px solid var(--line);border-radius:18px;padding:18px 20px;margin-bottom:12px}
.card.hl{border:2px solid var(--lime)}
.card.dark{background:var(--ink);border:none;color:#F2F1EC}
.card.dark .muted{color:#C2C4BC}
.card .k{font-size:13px;font-weight:700;color:var(--olive);margin-bottom:2px}
.dark .k{color:var(--lime)}
.shot{position:relative;margin:14px 0 8px}
.shot img{display:block;width:100%;height:auto;border-radius:14px;border:1px solid var(--line);background:#fff}
.shot .pc{position:absolute;left:10px;top:10px;font-size:12px;font-weight:700;padding:3px 9px;border-radius:7px;background:var(--ink);color:#F2F1EC}
.shot .ex{position:absolute;right:10px;top:10px;font-size:12px;font-weight:700;padding:3px 9px;border-radius:7px;background:var(--orange);color:#fff}
.cap{font-size:14px;color:var(--muted)}
.nums{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:14px 0}
.num{background:var(--ink);color:#F2F1EC;border-radius:16px;padding:16px 18px}
.num b{display:block;font-family:'Black Han Sans','Noto Sans KR',sans-serif;font-weight:400;font-size:28px;color:var(--lime);line-height:1.2}
.num span{font-size:13px;color:#C2C4BC}
.tl{list-style:none;margin:10px 0}
.tl li{display:flex;gap:14px;padding:10px 0;border-bottom:1px solid var(--line);font-size:15px}
.tl li b{flex:0 0 96px}
.grid3 .card{margin-bottom:10px}
.tag{display:inline-block;font-size:13px;font-weight:700;padding:5px 12px;border-radius:999px;background:#E6EFBE;color:#4A5716;margin:3px 2px}
.tag.dark{background:var(--ink);color:#F2F1EC}
.arrow{color:var(--muted);margin:0 2px}
table{width:100%;border-collapse:collapse;margin-top:6px}
td{padding:12px 6px;border-bottom:1px solid var(--line);vertical-align:top;font-size:15px}
td:first-child{width:92px;font-weight:900}
td .muted{display:block;font-size:13px;margin-top:2px}
.insta{background:var(--ink);border-radius:22px;padding:26px 24px;color:#F2F1EC;max-width:360px;margin:16px auto 8px}
.insta .t{font-family:'Black Han Sans','Noto Sans KR',sans-serif;font-size:32px;line-height:1.2;margin:12px 0 8px}
.insta .s{color:#C2C4BC;font-size:14px}
.insta .f{border-top:1px solid #454B55;margin-top:60px;padding-top:12px;font-size:13px;color:#C2C4BC}
.insta .pill{display:inline-block;font-size:12px;font-weight:700;padding:4px 10px;border-radius:999px;background:#3F4A22;color:#DCE8A6}
.cta{background:var(--lime);border-radius:24px;padding:28px 22px;margin-top:10px}
.cta h2{margin-top:0}
.btns{display:flex;flex-direction:column;gap:10px;margin-top:16px}
.btn{display:flex;align-items:center;justify-content:center;min-height:52px;border-radius:14px;font-weight:900;text-decoration:none;font-size:16px}
.btn.p{background:var(--ink);color:#F2F1EC}
.btn.g{background:#fff;color:var(--ink)}
footer{margin-top:30px;font-size:12px;color:var(--muted);text-align:center}
@media(min-width:700px){h1{font-size:44px}h2{font-size:30px}.nums{grid-template-columns:repeat(4,1fr)}.grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px}.btns{flex-direction:row}.btn{flex:1}}
"""

def shot(src, alt, ex=False):
    e = '<span class="ex">화면 예시(실제 제품 아님)</span>' if ex else ''
    return f'<div class="shot"><img src="../img/{src}" alt="{html.escape(alt)}" loading="lazy"><span class="pc">PC 화면</span>{e}</div>'

def page(slug, b):
    n = b['name']
    flow = ' <span class="arrow">→</span> '.join(
        f'<span class="tag{" dark" if i == len(b["flow"]) - 1 else ""}">{html.escape(x)}</span>' for i, x in enumerate(b['flow']))
    return f"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow">
<link rel="icon" href="../../icons/favicon-32.png" type="image/png">
<link rel="apple-touch-icon" href="../../icons/apple-touch-icon.png">
<meta name="theme-color" content="#F2F1EC">
<title>{n} 창립 파트너 제안 · 빡세</title>
<meta name="description" content="세차하러 가기 직전의 사람들, 빡세에서 만나 보세요. 빡세가 {n}에 드리는 이벤트 경품 협찬 제안입니다.">
<meta property="og:type" content="website">
<meta property="og:site_name" content="빡세">
<meta property="og:title" content="빡세 × {n} · 창립 파트너 제안">
<meta property="og:description" content="세차하러 가기 직전의 사람들, 빡세에서 만나 보세요.">
<meta property="og:url" content="https://ppaxse.com/partner/{slug}/">
<meta property="og:image" content="https://ppaxse.com/icons/og.png">
<link href="https://fonts.googleapis.com/css2?family=Black+Han+Sans&family=Noto+Sans+KR:wght@400;700;900&display=swap" rel="stylesheet">
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
<div class="top"><a class="brand" href="../../"><img src="../../icons/icon-192.png" alt="">빡<em>세</em></a><a class="site" href="../../">빡세 둘러보기 →</a></div>

<section class="first">
<p class="eyebrow">{n} 창립 파트너 제안 · 세차장 지도 빡세 · 2026년 11월</p>
<h1>세차하러 가기 직전의 사람들,<br>빡세에서 만나 보세요.</h1>
<div class="card"><p class="k">빡세는</p><p>전국 세차장 1만 1,625곳을 <b>세차하는 사람 기준</b>으로 정리한 지도 + 세차날씨 + 세차 가이드</p></div>
<div class="card hl"><p class="k">부탁드리는 것</p><p><b>이벤트 경품 협찬.</b> 돈이 아니라 제품입니다. 경품 배송은 빡세가 직접 합니다.</p></div>
<div class="card"><p class="k">그다음</p><p>2027년 7월, 협찬 기간의 숫자를 들고 정식 광고·입점을 제안드립니다. <b>창립 파트너는 우대합니다.</b></p></div>
{shot('map.jpg', '빡세 세차장 지도 PC 화면')}
<p class="cap">이 페이지에 담긴 화면은 모두 PC에서 찍은 실제 빡세 화면입니다(2026년 11월 27일). 같은 화면이 휴대폰과 앱에서도 열립니다.</p>
</section>

<section>
<p class="eyebrow">빡세를 만든 이유</p>
<h2>세차장은 많은데, 가 보기 전엔 아무것도 알 수 없었습니다.</h2>
<p class="muted">폼건을 쓸 수 있는지, 온수가 나오는지, 하부세차가 되는지. 셀프세차를 20년 넘게 하면서 매번 직접 가 봐야 알았습니다. 지도 앱은 위치는 알려 주지만, 세차하는 사람이 궁금한 건 알려 주지 않습니다.</p>
<p><b>그래서 직접 만들었습니다.</b> 세차하는 사람의 눈으로 정리한 세차장 지도, 빡세.</p>
{shot('d1.jpg', '세차장 상세: 최근 확인, 폼건·하부세차·24시간')}
</section>

<section>
<p class="eyebrow">만든 사람 · 대표 안수일</p>
<h2>지점을 세우고 안정시켜 온 10년의 운영 경험으로 빡세를 키웁니다.</h2>
<div class="card"><h3>여러 지역·계열사 지점 안정화</h3><p class="muted small">교육서비스업 10년 넘게. 어려운 지점을 맡아 안정 궤도에 올리는 역할</p></div>
<div class="card"><h3>중소도시 첫 프로젝트 총괄</h3><p class="muted small">일산 첫 지점을 설립부터 안정화까지 총괄</p></div>
<div class="card"><h3>지점 대표자</h3><p class="muted small">운영·관리·인사를 직접 총괄</p></div>
<div class="card"><h3>마케팅 10년 이상, 직접</h3><p class="muted small">키워드 광고·바이럴을 직접 기획하고 집행</p></div>
<div class="card dark"><p class="k">그래서 빡세는</p><p><b>이용자에게는</b> 정확한 정보. 검수와 확인을 운영의 기본으로 둡니다.</p><p><b>세차장 점주·세차용품 업체에게는</b> 실제로 작동하는 새 마케팅 창구.</p><p class="muted small">빠르게, 그러나 무너지지 않게 키우는 일. 지난 10년 동안 해 온 일입니다. 저 역시 셀프세차 20년 차, 빡세의 이용자입니다.</p></div>
</section>

<section>
<p class="eyebrow">이용자에게 주는 것 ① 세차장 정보</p>
<h2>세차장마다, 세차하는 사람이 궁금한 것만 정리합니다.</h2>
{shot('d2.jpg', '지도와 세차장 상세 시설 정보')}
<p class="cap"><b>종류별 지도</b> 셀프·손세차·디테일링·노터치·자동세차를 핀 색으로 구분 · <b>시설 정보</b> 폼건·하부세차·매트 세척기·24시간 등을 이용자 확인으로 계속 갱신 · <b>사장님 통로</b> 상세 화면마다 ‘매장 정보 직접 알려주기’</p>
</section>

<section>
<p class="eyebrow">이용자에게 주는 것 ② 언제, 어떻게</p>
<h2>언제 세차할지, 어떻게 할지까지 알려 줍니다.</h2>
{shot('weather.jpg', '세차하기 좋은 날 10일 달력')}
<p class="cap"><b>세차하기 좋은 날.</b> 비 소식으로 날마다 추천·비추</p>
{shot('guide.jpg', '세차 가이드 목록')}
<p class="cap"><b>세차 가이드 21편.</b> 입문·차 상태별·계절·더 깔끔하게</p>
</section>

<section>
<p class="eyebrow">지금까지, 그리고 진행 중</p>
<h2>11월 14일 공개. 작게 시작했지만 빠르게 움직이고 있습니다.</h2>
<div class="nums">
<div class="num"><b>11,625곳</b><span>전국 세차장</span></div>
<div class="num"><b>1,330명</b><span>공개 12일 방문자(11/14~25), 광고비 0원</span></div>
<div class="num"><b>72건</b><span>이용자가 남긴 한마디</span></div>
<div class="num"><b>92건</b><span>이용자 세차장 제보</span></div>
</div>
<ul class="tl">
<li><b>11월 14일</b><span>웹 공개. 매주 ‘한마디 남기고 기프티콘 받기’ 이벤트 운영 중</span></li>
<li><b>11월 26일</b><span>새 디자인 적용, 세차장 사장님이 매장 정보를 직접 보내는 페이지 운영</span></li>
<li><b>12월</b><span>안드로이드 앱 비공개 테스트. 세차용품 탭을 테스터에게 먼저 공개</span></li>
<li><b>2027년 1월</b><span>Play 스토어 정식 출시, 세차용품 탭 공개. 아이폰 앱은 이어서 준비</span></li>
</ul>
<p class="cap">숫자 출처: 빡세 운영 DB. 방문자 = 하루 기준 서로 다른 기기 수</p>
</section>

<section>
<p class="eyebrow">준비 중 · 세차용품 탭</p>
<h2>제품보다 쓰는 법을 먼저. 그다음에 제품으로 잇습니다.</h2>
{shot('goods_use.jpg', '세차용품 탭: 용도별·오염별로 고르기')}
<p class="cap"><b>무엇을, 언제 쓰는지.</b> 입문 5단계·용도별 10가지·오염별 8가지(유막·철분·제설제 등)</p>
{shot('goods_rec.jpg', '추천 제품·브랜드 소개 예시 화면', ex=True)}
<p class="cap"><b>추천 제품·브랜드 소개.</b> 직접 사용·제품 제공·광고·제휴를 숨기지 않고 표시. 아직 비공개이며, 화면 속 제품명·브랜드는 모두 자리 표시입니다.</p>
</section>

<section>
<p class="eyebrow">{n}에게 빡세가 의미 있는 이유</p>
<h2>구제 청바지가 필요한 사람은 백화점이 아니라 구제숍에 갑니다.</h2>
<p class="muted">유튜브·인스타·네이버는 노출이 많고, 빡세는 적습니다. 대신 들어오는 사람이 다릅니다.</p>
<div class="grid3">
<div class="card"><p class="k">1. 목적</p><h3>세차하려고 들어온 사람</h3><p class="muted small">세차장을 찾으러 온 사람이 같은 곳에서 가이드와 용품을 만납니다. 빡세를 찾는 사람에게 닿는 것이 곧 {n}의 노출입니다.</p></div>
<div class="card"><p class="k">2. 시점</p><h3>세차 직전, 문제를 겪는 순간</h3><p class="muted small">‘주말이 세차하기 좋은 날’을 본 사람은 용품을 챙기기 직전이고, 유막 가이드를 읽는 사람은 지금 앞유리가 뿌연 사람입니다.</p></div>
<div class="card"><p class="k">3. 입문자</p><h3>아직 브랜드를 모르는 사람</h3><p class="muted small">{html.escape(b['novice'])}</p></div>
</div>
<p style="margin-top:8px">{flow}</p>
<p class="cap">이렇게 이어지는 흐름을 만듭니다.</p>
{b.get('extra','')}
</section>

<section>
<p class="eyebrow">제안</p>
<h2>지금은 돈이 아니라, 이벤트 경품을 부탁드립니다.</h2>
{shot('event.jpg', '빡세 주간 이벤트: 한마디 남기고 기프티콘 받기')}
<p class="cap">지금 매주 진행 중인 이벤트. 이용자가 세차장에 한마디를 남기면 응모됩니다. 이 경품을 {n} 제품으로 바꾸고 싶습니다.</p>
<table>
<tr><td>무엇을</td><td>매주 이벤트 경품을 {n} 제품으로. 품목과 수량은 협의<span class="muted">수량에 맞춰 당첨 구성을 조정합니다(예: 회원은 세차용품, 그 외는 기프티콘)</span></td></tr>
<tr><td>기간</td><td>합의 시점부터 앱 출시 후 6개월(2027년 7월)까지<span class="muted">협찬은 언제든지 멈추셔도 괜찮습니다</span></td></tr>
<tr><td>배송</td><td>빡세가 제품을 받아 당첨자에게 직접 발송. 당첨자 개인정보는 넘기지 않습니다</td></tr>
<tr><td>표시</td><td>이벤트의 주인은 빡세. 경품을 주신 곳으로 ‘경품 협찬 {n}’을 밝힙니다</td></tr>
<tr><td>상품 소개</td><td>{n} 측이 원하시는 상품 설명을 빡세 세차용품 탭에 ‘협찬 제품 제공’ 표시와 함께 담아 드립니다<span class="muted">12월 앱 테스트 때 테스터에게 먼저, 2027년 1월 정식 공개</span></td></tr>
<tr><td>하지 않는 것</td><td>이용자에게 사용 후기를 요구하지 않습니다. 빡세는 평가하는 곳이 아니라 연결하는 곳입니다</td></tr>
</table>
<div class="card dark" style="margin-top:16px"><p><b>작다는 것, 알고 있습니다.</b></p><p class="muted small">그래서 지금은 비용이 아니라 제품을 부탁드립니다. 이 협찬은 빡세의 이용자를 늘리는 데 쓰입니다.</p></div>
</section>

<section>
<p class="eyebrow">창립 파트너께 드리는 것</p>
<h2>창립 파트너는 빡세 안에서 오래 기억되게 하겠습니다.</h2>
<div class="card"><h3>이벤트 크레딧</h3><p class="muted small">이벤트 페이지·당첨 발표·인스타 이벤트 게시물에 ‘경품 협찬 {n}’</p></div>
<div class="card"><h3>가이드에서 연결</h3><p class="muted small">관련 가이드에 ‘협찬 제품 제공’ 표시와 함께 소개하고 {n} 판매처로 연결</p></div>
<div class="card"><h3>세차용품 탭 메인 화면 파트너 영역</h3><p class="muted small">1월 공개 때 창립 파트너 브랜드로 소개(파트너 브랜드는 늘어날 수 있습니다)</p></div>
<div class="card"><h3>매월 리포트</h3><p class="muted small">{n} 링크 클릭 수, 빡세 이벤트 참여 수, 월별 방문자 수 등</p></div>
<div class="card hl"><h3>7월 첫 계약 우대</h3><p class="muted small">정식 광고·입점 제안 때 협찬 기간을 반영한 첫 계약 우대</p></div>
<div class="insta"><span class="pill">빡세 주간 이벤트</span><p class="t">한마디 남기고<br>세차용품 받자</p><p class="s">다녀온 세차장에 한마디 → 매주 추첨</p><p class="f">경품 협찬 · {n}</p></div>
<p class="cap" style="text-align:center">인스타 게시물 표기 예시. 이벤트는 빡세가 주최하고, 경품을 주신 곳을 아래에 밝힙니다.</p>
</section>

<section>
<p class="eyebrow">앞으로의 흐름</p>
<h2>6개월 동안 숫자를 쌓고, 7월에 정식으로 제안드리겠습니다.</h2>
<ul class="tl">
<li><b>12월</b><span>협찬 합의, 첫 경품 이벤트</span></li>
<li><b>12월</b><span>앱 비공개 테스트, 세차용품 탭 테스터 공개</span></li>
<li><b>2027년 1월</b><span>앱 정식 출시, 세차용품 탭 공개</span></li>
<li><b>매월</b><span>클릭·참여·방문자 리포트</span></li>
<li><b>2027년 7월</b><span>정식 광고·입점 제안</span></li>
</ul>
<div class="card"><p class="k">7월 제안 방향(안)</p><p><b>월 고정 광고</b>(세차용품 탭·관련 가이드 노출) 또는 <b>3·6·12개월 입점 계약</b>. 금액은 협찬 기간의 숫자를 함께 보고 정하겠습니다.</p></div>
</section>

<div class="cta">
<p class="eyebrow" style="color:#262B33">마지막으로</p>
<h2>빡세의 창립 파트너가 되어 주세요.</h2>
<p>{html.escape(b['greet'])} 편하신 방법으로 회신 주시면 품목과 일정을 맞춰 바로 시작하겠습니다.</p>
<div class="btns">
<a class="btn p" href="https://www.instagram.com/ppaxse.official/" target="_blank" rel="noopener">인스타그램 DM으로 답하기</a>
<a class="btn g" href="mailto:ppaxse@gmail.com?subject=%5B%EB%B9%A1%EC%84%B8%20%ED%98%91%EC%B0%AC%5D%20{html.escape(n)}">메일 보내기 · ppaxse@gmail.com</a>
</div>
<p class="small" style="margin-top:14px">대표 안수일 · ppaxse.com</p>
</div>
<footer>© 2026 빡세(Ppaxse) · 이 페이지는 {n}께만 보내 드린 제안 페이지입니다.</footer>
</div>
</body>
</html>
"""

if __name__ == '__main__':
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'partner')
    for slug, b in BRANDS.items():
        os.makedirs(f'{root}/{slug}', exist_ok=True)
        open(f'{root}/{slug}/index.html', 'w').write(page(slug, b))
        print('wrote', slug)
