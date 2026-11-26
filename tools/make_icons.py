"""
빡세 앱 아이콘 만들기 (B안 2026-11-26: 차콜 + 라임 물방울. 예전 D2안은 git 기록에)

사용법:  python3 tools/make_icons.py
결과:    icons/ 폴더에 브라우저·휴대폰 홈 화면용 아이콘들
"""
import io
import os

import cairosvg
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")


def svg(rounded=True, scale=1.0):
    """B안(2026-11-26): 차콜 바탕 + 라임 물방울 + 오렌지·아이보리 반짝임 (사이트 로고와 같은 물방울)
    rounded=False 는 꽉 찬 정사각형 (휴대폰이 알아서 모양을 깎는 용도)
    scale 은 그림 크기 비율 (가장자리가 잘리는 아이콘용으로 조금 작게)
    ※ 이 PC에는 cairosvg가 없어 2026-11-26 파일은 브라우저로 그려 넣음 (같은 그림)"""
    r = 112 if rounded else 0
    t = f"translate(256 256) scale({scale}) translate(-256 -256)"
    def spark(x, y, k, c):
        return (f'<path fill="{c}" d="M{x} {y-k}Q{x+k*.15:g} {y-k*.15:g} {x+k} {y}Q{x+k*.15:g} {y+k*.15:g} {x} {y+k}'
                f'Q{x-k*.15:g} {y+k*.15:g} {x-k} {y}Q{x-k*.15:g} {y-k*.15:g} {x} {y-k}Z"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="{r}" fill="#262B33"/>
  <g transform="{t}">
    <path fill="#B5C95F" transform="translate(256 262) scale(.92) translate(-256 -256)" d="M256 70s150 156 150 262a150 150 0 0 1-300 0c0-106 150-262 150-262z"/>
    <ellipse cx="214" cy="310" rx="24" ry="40" fill="#ffffff" fill-opacity=".35" transform="rotate(-20 214 310)"/>
    {spark(388, 128, 58, '#E59A4F')}{spark(318, 92, 22, '#F2F1EC')}
  </g>
</svg>'''


def png(svg_text, size):
    data = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    rounded, full, safe = svg(True), svg(False, 1.0), svg(False, 0.8)
    open(os.path.join(OUT, "icon.svg"), "w", encoding="utf-8").write(rounded)      # 최신 브라우저 탭
    png(rounded, 192).save(os.path.join(OUT, "icon-192.png"))                       # 안드로이드 홈 화면
    png(rounded, 512).save(os.path.join(OUT, "icon-512.png"))
    png(safe, 512).save(os.path.join(OUT, "icon-maskable-512.png"))                 # 안드로이드가 모양을 깎는 용
    png(full, 180).save(os.path.join(OUT, "apple-touch-icon.png"))                  # 아이폰 홈 화면 (모서리는 아이폰이 깎음)
    png(rounded, 32).save(os.path.join(OUT, "favicon-32.png"))
    png(rounded, 64).save(os.path.join(OUT, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    print("완료:", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
