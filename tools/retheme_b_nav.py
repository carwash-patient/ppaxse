# B안: 아래 메뉴(bottom-nav) 아이콘·모양을 지도 화면과 같게 (이벤트·내 정보·세차용품 등)
import re, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
ICON = {'🗺️': 'map', '📖': 'guide', '🧴': 'goods', '🎁': 'event', '👤': 'user'}
CSS = ('.nav-item.active{color:#262B33}\n'
       '.nav-item-icon{width:46px;height:28px;border-radius:999px;display:flex;align-items:center;justify-content:center}\n'
       '.nav-item-icon .ic{width:22px;height:22px}\n'
       '.nav-item.active .nav-item-icon{background:#DCE8A6}')
for f in ['events.html', 'mypage.html', 'goods.html']:
    p = ROOT / f
    t = p.read_text(encoding='utf-8')
    n = 0
    for e, k in ICON.items():
        old = f'<div class="nav-item-icon">{e}</div>'
        if old in t:
            t = t.replace(old, f'<div class="nav-item-icon"><svg class="ic" aria-hidden="true"><use href="icons/ui.svg#{k}"/></svg></div>'); n += 1
    t, k1 = re.subn(r'\.nav-item\.active\{color:[^}]*\}\s*\n?\.nav-item-icon\{font-size:22px\}', CSS, t)
    t = re.sub(r'(\.bottom-nav\{[^}]*?background:)rgba\(242,241,236,\.97\)', r'\1#FFFFFF', t)
    t = re.sub(r'(\.nav-item\.has-dot::after\{[^}]*background:)#[0-9a-fA-F]{6}', r'\1#E59A4F', t)
    p.write_text(t, encoding='utf-8', newline='')
    print(f, 'icons', n, 'css', k1)
