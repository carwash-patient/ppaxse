"""
빡세 후기 페이지(r/) 아이콘 만들기 — 지도 아이콘(파란색)과 헷갈리지 않게 주황 바탕 + 말풍선 별

사용법:  python3 tools/make_review_icons.py
결과:    icons/review-*.png, icons/review.svg
"""
import io
import os

import cairosvg
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")


def svg(rounded=True, scale=1.0):
    r = 112 if rounded else 0
    t = f"translate(256 256) scale({scale}) translate(-256 -256)"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ea580c"/>
      <stop offset="1" stop-color="#fbbf24"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="{r}" fill="url(#bg)"/>
  <g transform="{t}">
    <!-- 말풍선 -->
    <path d="M120 112 H392 Q440 112 440 160 V318 Q440 366 392 366 H236 L156 430 L170 366 H120 Q72 366 72 318 V160 Q72 112 120 112 Z" fill="#ffffff"/>
    <!-- 별 -->
    <path d="M256 150 L284 208 L348 216 L301 260 L313 324 L256 293 L199 324 L211 260 L164 216 L228 208 Z" fill="#f97316"/>
    <!-- 반짝임 -->
    <path d="M420 44 Q428 84 468 92 Q428 100 420 140 Q412 100 372 92 Q412 84 420 44 Z" fill="#ffffff"/>
  </g>
</svg>'''


def png(svg_text, size):
    data = cairosvg.svg2png(bytestring=svg_text.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def main():
    rounded, full, safe = svg(True), svg(False, 0.92), svg(False, 0.78)
    open(os.path.join(OUT, "review.svg"), "w", encoding="utf-8").write(rounded)
    png(rounded, 192).save(os.path.join(OUT, "review-192.png"))
    png(rounded, 512).save(os.path.join(OUT, "review-512.png"))
    png(safe, 512).save(os.path.join(OUT, "review-maskable-512.png"))
    png(full, 180).save(os.path.join(OUT, "review-apple-touch-icon.png"))
    print("완료")


if __name__ == "__main__":
    main()
