# retheme_b.py 다음에 한 번: 예전 '하늘색 그라데이션 버튼'(지금은 차콜~올리브)을 차콜 단색 + 아이보리 글자로
import re, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from retheme_b import FILES

DARK = r'(?:var\(--(?:sky|aqua|ocean|cyan|water)\)|#262B33|#3A404A|#56661A)'
GRAD = re.compile(r'background(?:-image)?\s*:\s*linear-gradient\(\s*\d+deg\s*,\s*' + DARK + r'(?:\s+\d+%)?\s*,\s*' + DARK + r'(?:\s+\d+%)?(?:\s*,\s*' + DARK + r'(?:\s+\d+%)?)?\s*\)')
COLOR = re.compile(r'(?<![\w-])color\s*:\s*[^;}"\']+')

def fix_body(body):
    if not GRAD.search(body) or 'background-clip' in body: return body, 0
    body = GRAD.sub('background:#262B33', body)
    if COLOR.search(body): body = COLOR.sub('color:#F2F1EC', body)
    else: body = body.rstrip(';') + ';color:#F2F1EC'
    return body, 1

total = 0
only = sys.argv[1:]
for f in (only or FILES):
    p = ROOT / f
    t = p.read_text(encoding='utf-8')
    n = [0]
    def rule(m):
        b, k = fix_body(m.group(2)); n[0] += k
        return m.group(1) + b + m.group(3)
    t2 = re.sub(r'(\{)([^{}]*)(\})', rule, t)                 # CSS 규칙
    t2 = re.sub(r'(style=")([^"]*)(")', rule, t2)             # style="..."
    t2 = re.sub(r"(style=')([^']*)(')", rule, t2)
    if n[0]:
        print(f, n[0]); total += n[0]
        p.write_text(t2, encoding='utf-8', newline='')
print('total', total)
