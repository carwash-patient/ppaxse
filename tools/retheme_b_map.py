# B안: 지도 화면(map.html) 손질 — retheme_b.py, retheme_b_fix.py 다음에 한 번
import re, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'map.html'
t = P.read_text(encoding='utf-8')
def I(k): return f'<svg class="ic" aria-hidden="true"><use href="icons/ui.svg#{k}"/></svg>'
DROP = '<svg class="ic" aria-hidden="true" style="width:1em;height:1em;color:#B5C95F"><use href="icons/ui.svg#drop-fill"/></svg>'
PHONE = '<svg class="ic" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4h3.5l1.8 4.5-2.3 1.5a11 11 0 0 0 6 6l1.5-2.3L20 15.5V19a1.5 1.5 0 0 1-1.6 1.5A16 16 0 0 1 3.5 5.6 1.5 1.5 0 0 1 5 4z"/></svg>'
R = [
('.logo-icon{width:34px;height:34px;border-radius:11px;background:#262B33;display:flex;align-items:center;justify-content:center;font-size:16px;color:#F2F1EC}',
 '.logo-icon{width:34px;height:34px;border-radius:10px;background:#262B33;display:flex;align-items:center;justify-content:center;color:#B5C95F}.logo-icon .ic{width:20px;height:20px}\n.ic{width:18px;height:18px;flex:none}\n.dp-addr .ic,.report-btn .ic,.dp-btn .ic{width:17px;height:17px;vertical-align:-3px}\n.report-btn .ic{color:#262B33}'),
('.logo-text em{color:var(--aqua);font-style:normal}', '.logo-text em{color:#E08A3C;font-style:normal}'),
('.search-input{width:100%;height:40px;border:1.5px solid var(--line);border-radius:12px;background:rgba(38,43,51,.042);', '.search-input{width:100%;height:40px;border:1.5px solid transparent;border-radius:12px;background:#EBE9E3;'),
('.search-input:focus{border-color:rgba(150,170,60,.65);background:rgba(181,201,95,.091)}', '.search-input:focus{border-color:#262B33;background:#FFFFFF}'),
('.search-icon{position:absolute;left:11px;top:50%;transform:translateY(-50%);font-size:15px;opacity:.45}', '.search-icon{position:absolute;left:11px;top:50%;transform:translateY(-50%);display:flex;color:#6B7078}.search-icon .ic{width:17px;height:17px}'),
('.my-btn{width:36px;height:36px;border-radius:11px;background:rgba(181,201,95,.195);border:1px solid rgba(150,170,60,.28);', '.my-btn{width:36px;height:36px;border-radius:11px;background:#EBE9E3;border:1px solid transparent;color:#262B33;'),
('.chip{display:flex;align-items:center;gap:5px;padding:7px 13px;border-radius:999px;border:1.5px solid rgba(38,43,51,.096);background:rgba(38,43,51,.035);font-size:12px;font-weight:700;color:rgba(38,43,51,.65);',
 '.chip{display:flex;align-items:center;gap:6px;padding:7px 13px;border-radius:999px;border:1px solid var(--line);background:#FFFFFF;font-size:12px;font-weight:700;color:#262B33;'),
('.chip.on{border-color:var(--sky);background:rgba(181,201,95,.234);color:#262B33;box-shadow:0 0 12px rgba(38,43,51,.06)}', '.chip.on{border-color:#262B33;background:#262B33;color:#F2F1EC}\n.chip .cd{width:8px;height:8px;border-radius:50%;flex:none}'),
('.region-btn{display:flex;align-items:center;gap:5px;padding:7px 13px;border-radius:999px;border:1.5px solid rgba(150,170,60,.45);background:rgba(181,201,95,.182);', '.region-btn{display:flex;align-items:center;gap:5px;padding:7px 13px;border-radius:999px;border:1px solid var(--line);background:#FFFFFF;'),
('background:rgba(255,255,255,.95);border:1px solid var(--line);color:var(--aqua);font-size:20px;', 'background:#FFFFFF;border:1px solid var(--line);color:#262B33;font-size:20px;'),
('.led-g{color:#39ff7a}.led-r{color:#C82828}.led-y{color:#ffb21e}.led-w{color:#f3efe4}.led-b{color:#56661A}', '.led-g{color:#C9DD6E}.led-r{color:#FF8A3D}.led-y{color:#ffd23e}.led-w{color:#f3efe4}.led-b{color:#7cc4ff}'),
('display:flex;align-items:center;gap:6px;padding:10px 15px;border-radius:999px;border:1px solid rgba(150,170,60,.4);background:rgba(255,255,255,.95);color:#262B33;', 'display:flex;align-items:center;gap:6px;padding:10px 15px;border-radius:12px;border:none;background:#E59A4F;color:#262B33;'),
('.add-btn b{color:var(--aqua);font-size:16px;line-height:1}', '.add-btn .ic{width:17px;height:17px}'),
('border-radius:999px;border:1px solid rgba(150,170,60,.35);background:rgba(255,255,255,.96);color:#262B33;font-family:inherit;font-size:14px;font-weight:900;box-shadow:0 8px 24px rgba(38,43,51,.225);cursor:pointer;white-space:nowrap}',
 'border-radius:999px;border:none;background:#262B33;color:#F2F1EC;font-family:inherit;font-size:14px;font-weight:900;box-shadow:0 8px 24px rgba(38,43,51,.25);cursor:pointer;white-space:nowrap}'),
('.list-toggle .lt-icon{color:var(--aqua);font-size:15px}', '.list-toggle .lt-icon{color:#B5C95F;display:flex}.list-toggle .lt-icon .ic{width:18px;height:18px}'),
('.list-toggle .lt-count{color:var(--aqua)}', '.list-toggle .lt-count{color:#B5C95F}'),
('.bottom-nav{position:fixed;bottom:0;left:0;right:0;z-index:600;display:flex;background:rgba(242,241,236,.97);', '.bottom-nav{position:fixed;bottom:0;left:0;right:0;z-index:600;display:flex;background:#FFFFFF;'),
('.nav-item.active{color:var(--aqua)}\n.nav-item-icon{font-size:22px}', '.nav-item.active{color:#262B33}\n.nav-item-icon{width:46px;height:28px;border-radius:999px;display:flex;align-items:center;justify-content:center}\n.nav-item-icon .ic{width:22px;height:22px}\n.nav-item.active .nav-item-icon{background:#DCE8A6}'),
('<div class="logo-icon">💧</div>', f'<div class="logo-icon">{I("drop-fill")}</div>'),
('<span class="search-icon">🔍</span>', f'<span class="search-icon">{I("search")}</span>'),
('<a href="mypage.html" class="my-btn">👤</a>', f'<a href="mypage.html" class="my-btn" aria-label="내 정보">{I("user")}</a>'),
('id="regionBtn" type="button">📍 <span id="regionLabel">', f'id="regionBtn" type="button">{I("pin")} <span id="regionLabel">'),
('<div class="chip" data-f="self">🚿 셀프세차</div>', '<div class="chip" data-f="self"><i class="cd" style="background:#3E7BD6"></i>셀프세차</div>'),
('<div class="chip" data-f="hand">🧽 손세차</div>', '<div class="chip" data-f="hand"><i class="cd" style="background:#E59A4F"></i>손세차</div>'),
('<div class="chip" data-f="detail">✨ 디테일링</div>', '<div class="chip" data-f="detail"><i class="cd" style="background:#8E6CC8"></i>디테일링</div>'),
('<div class="chip" data-f="notouch">💦 노터치</div>', '<div class="chip" data-f="notouch"><i class="cd" style="background:#9DB43F"></i>노터치</div>'),
('<div class="chip" data-f="auto">⛽ 자동세차</div>', '<div class="chip" data-f="auto"><i class="cd" style="background:#6B7078"></i>자동세차</div>'),
('aria-label="내 위치로 이동">📍</div>', f'aria-label="내 위치로 이동">{I("locate")}</div>'),
('id="addBtn" type="button"><b>＋</b> 세차장 제보</button>', f'id="addBtn" type="button">{I("plus")} 세차장 제보</button>'),
('<span class="lt-icon">☰</span>', f'<span class="lt-icon">{I("list")}</span>'),
('<div class="nav-item-icon">🗺️</div>', f'<div class="nav-item-icon">{I("map")}</div>'),
('<div class="nav-item-icon">📖</div>', f'<div class="nav-item-icon">{I("guide")}</div>'),
('<div class="nav-item-icon">🎁</div>', f'<div class="nav-item-icon">{I("event")}</div>'),
('<div class="nav-item-icon">👤</div>', f'<div class="nav-item-icon">{I("user")}</div>'),
('<div class="icon">💧</div>', f'<div class="icon">{DROP}</div>'),
('<div class="pc-icon ${p.type}">${typeIcon[p.type]||\'💧\'}</div>', f'<div class="pc-icon ${{p.type}}">{I("drop-fill")}</div>'),
("const typeIcon={self:'🚿',hand:'🧽',detail:'✨',notouch:'💦',auto:'⛽',wash:'💧',etc:'🔧'};",
 "const typeIcon={self:'<i class=\"tdot\" style=\"background:#3E7BD6\"></i>',hand:'<i class=\"tdot\" style=\"background:#E59A4F\"></i>',detail:'<i class=\"tdot\" style=\"background:#8E6CC8\"></i>',notouch:'<i class=\"tdot\" style=\"background:#9DB43F\"></i>',auto:'<i class=\"tdot\" style=\"background:#8A8F98\"></i>',wash:'<i class=\"tdot\" style=\"background:#262B33\"></i>',etc:'<i class=\"tdot\" style=\"background:#262B33\"></i>'};   // 2026-11-26: 이모지 대신 종류 색 점"),
("btn.querySelector('.lt-icon').textContent = '🗺️';", "btn.querySelector('.lt-icon').innerHTML = '" + I('map') + "';"),
("btn.querySelector('.lt-icon').textContent = '☰';", "btn.querySelector('.lt-icon').innerHTML = '" + I('list') + "';"),
('onclick="openNaverNavi(${p.id})">🗺️ 길찾기</button>', f'onclick="openNaverNavi(${{p.id}})">{I("map")} 길찾기</button>'),
('<div class="dp-addr">📍 ${esc(p.addr)}</div>', f'<div class="dp-addr">{I("pin")} ${{esc(p.addr)}}</div>'),
(">📞 전화</a>", f">{PHONE} 전화</a>"),
('onclick="checkPlace(${p.id})">👍 정보가 맞아요</button>', f'onclick="checkPlace(${{p.id}})">{I("thumb")} 정보가 맞아요</button>'),
('onclick="startReport(${p.id})">➕ 정보 추가하기</button>', f'onclick="startReport(${{p.id}})">{I("plus")} 정보 추가하기</button>'),
("btn.textContent = '👍 정보가 맞아요';", "btn.innerHTML = '" + I('thumb') + " 정보가 맞아요';"),
('🏪 이 세차장 사장님이세요?', I('store') + ' 이 세차장 사장님이세요?'),
('<div class="sh-title">📍 내 주변 세차장을 볼까요?</div>', '<div class="sh-title">내 주변 세차장을 볼까요?</div>'),
]
miss = 0
for a, b in R:
    if a not in t: print('못 찾음:', a[:70]); miss += 1
    else: t = t.replace(a, b)
# 목록 종류 그림 상자
t, n = re.subn(r'\.pc-icon\.self\{[^\n]*\n(?:\.pc-icon\.[^\n]*\n){5}',
  '.pc-icon .ic{width:24px;height:24px}\n.pc-icon.self{background:#E3ECF9;color:#3E7BD6}\n.pc-icon.detail{background:#ECE5F7;color:#8E6CC8}\n.pc-icon.notouch{background:#E6EFBE;color:#6F8424}\n.pc-icon.hand{background:#F8E1CB;color:#C77420}\n.pc-icon.auto{background:#EBE9E3;color:#6B7078}\n.pc-icon.wash,.pc-icon.etc{background:#EBE9E3;color:#262B33}\n.tdot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:2px;vertical-align:1px}\n', t)
if not n: print('못 찾음: pc-icon'); miss += 1
t, n = re.subn(r"(\.nav-item\.has-dot::after\{[^}]*background:)#[0-9a-fA-F]{6}", r"\1#E59A4F", t)
# 지도 위 표시(핀·묶음)
a = t.index('const markerColors = {'); b = t.index('// 묶음(클러스터) 아이콘')
t = t[:a] + '''// 2026-11-26 B안: 차콜 물방울 핀 + 가운데 종류 색 점 (종류 색은 위 필터 버튼 점과 같음)
const markerColors = {
  self:'#3E7BD6', hand:'#E59A4F', detail:'#8E6CC8', notouch:'#9DB43F', auto:'#8A8F98', wash:'#F2F1EC', etc:'#F2F1EC',
};

function dropMarkerHTML(p, selected) {
  const dot = selected ? '#262B33' : (markerColors[p.type] || markerColors.wash);
  const scale = selected ? 'transform:scale(1.25);' : '';
  const body = selected ? '#E59A4F' : '#262B33';
  const short = p.name.length>9 ? p.name.slice(0,9)+'…' : p.name;
  // 바깥 div는 크기 0 + translate로 "아래 가운데"가 좌표에 오도록 맞춤
  // (휴대폰 성능을 위해 흐림 효과·애니메이션은 넣지 않음)
  return `<div style="position:relative;width:0;height:0">
   <div style="position:absolute;left:0;bottom:4px;transform:translateX(-50%)">
    <div style="display:flex;flex-direction:column;align-items:center;cursor:pointer;${scale}transform-origin:50% 100%">
      <div style="position:relative;width:32px;height:41px">
        <svg width="32" height="41" viewBox="0 0 32 41" style="display:block;filter:drop-shadow(0 3px 5px rgba(38,43,51,.3))"><path d="M16 39.5S29 27.6 29 16.6A13 13 0 0 0 3 16.6C3 27.6 16 39.5 16 39.5z" fill="${body}" stroke="#fff" stroke-width="2.2"/><circle cx="16" cy="16.5" r="5.6" fill="${dot}"/></svg>
        ${p.comment_count ? `<span style="position:absolute;top:-8px;right:-18px;min-width:22px;padding:1px 6px;border-radius:999px;background:#E59A4F;color:#262B33;font-size:11px;font-weight:900;line-height:16px;border:2px solid #fff;font-family:'Noto Sans KR',sans-serif;white-space:nowrap">${p.comment_count}</span>` : ''}
      </div>
      <div style="margin-top:3px;background:#FFFFFF;border:1px solid rgba(38,43,51,.14);padding:3px 8px;border-radius:7px;font-size:11px;font-weight:700;color:#262B33;white-space:nowrap;font-family:'Noto Sans KR',sans-serif;box-shadow:0 2px 6px rgba(38,43,51,.12)">
        ${esc(short)}
      </div>
    </div>
   </div>
  </div>`;
}

''' + t[b:]
a = t.index('function clusterHTML(count, selfCount) {'); b = t.index('// 이 줌보다 축소하면')
t = t[:a] + '''function clusterHTML(count, selfCount) {
  const size = count < 10 ? 40 : count < 50 ? 48 : count < 200 ? 56 : 64;
  const badge = selfCount > 0
    ? `<div style="position:absolute;top:-6px;right:-12px;background:#FFFFFF;border:1px solid rgba(38,43,51,.15);color:#262B33;border-radius:999px;padding:1px 6px 1px 5px;font-size:10px;font-weight:900;white-space:nowrap;font-family:'Noto Sans KR',sans-serif;display:flex;align-items:center;gap:3px"><i style="width:6px;height:6px;border-radius:50%;background:#3E7BD6"></i>${selfCount}</div>`
    : '';
  return `<div style="position:relative;width:0;height:0">
   <div style="position:absolute;left:0;top:0;transform:translate(-50%,-50%);width:${size}px;height:${size}px;border-radius:50%;
     background:#262B33;border:2px solid #fff;
     box-shadow:0 0 0 5px rgba(181,201,95,.55),0 4px 12px rgba(38,43,51,.25);display:flex;align-items:center;justify-content:center;
     color:#F2F1EC;font-size:${size>50?15:13}px;font-weight:900;font-family:'Noto Sans KR',sans-serif;cursor:pointer">
     ${count.toLocaleString()}${badge}
   </div>
  </div>`;
}

''' + t[b:]
P.write_text(t, encoding='utf-8', newline='')
print('못 찾은 것', miss)
