"""
빡세 앱 아이콘 만들기 (D2안: 밝은 물빛 바탕의 반짝이는 차)

사용법:  python3 tools/make_icons.py
결과:    icons/ 폴더에 브라우저·휴대폰 홈 화면용 아이콘들
"""
import io
import os

import cairosvg
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")


def svg(rounded=True, scale=1.0):
    """D2안: 밝은 물빛 바탕 + 흰 차 + 큰 반짝임
    rounded=False 는 꽉 찬 정사각형 (휴대폰이 알아서 모양을 깎는 용도)
    scale 은 그림 크기 비율 (가장자리가 잘리는 아이콘용으로 조금 작게)"""
    r = 112 if rounded else 0
    t = f"translate(256 256) scale({scale}) translate(-256 -256)"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0369a1"/>
      <stop offset="1" stop-color="#22d3ee"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="{r}" fill="url(#bg)"/>
  <g transform="{t}">
    <!-- 반짝임 -->
    <circle cx="392" cy="128" r="70" fill="#ffffff" fill-opacity="0.2"/>
    <path d="M392 50 Q404 116 470 128 Q404 140 392 206 Q380 140 314 128 Q380 116 392 50 Z" fill="#ffffff"/>
    <path d="M290 72 Q296 98 322 104 Q296 110 290 136 Q284 110 258 104 Q284 98 290 72 Z" fill="#ffffff" fill-opacity="0.85"/>
    <!-- 차 -->
    <g transform="translate(0 34)">
      <path d="M86 340 L86 298 Q90 268 122 262 L186 252 L238 202 Q250 192 268 192 L340 192 Q358 192 370 204 L412 254 L432 260 Q450 266 450 288 L450 340 Z" fill="#ffffff"/>
      <path d="M250 212 L218 252 L300 252 L300 212 Z" fill="#0369a1"/>
      <path d="M316 212 L316 252 L398 252 L366 212 Z" fill="#0369a1"/>
      <circle cx="164" cy="342" r="38" fill="#04111e" stroke="#ffffff" stroke-width="14"/>
      <circle cx="372" cy="342" r="38" fill="#04111e" stroke="#ffffff" stroke-width="14"/>
    </g>
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
