"""
전국세차장표준데이터(행정안전부, 공공데이터포털) CSV → 빡세 지도용 places.json

사용법:
    python3 tools/build_places.py <다운로드한 CSV 경로> [출력 경로, 기본 places.json]

하는 일:
  - 서울·경기·인천만 남김
  - 운수회사·버스·택시 차고지처럼 일반 고객이 못 쓰는 세차시설 제외 (상호명 기준)
  - 위도/경도가 뒤바뀌었거나 단위가 틀린 좌표 보정, 고칠 수 없는 좌표(0 등)는 제외
  - 같은 이름·같은 좌표 중복 제거
  - 세차장 종류 분류 (셀프 / 손세차 / 디테일링 / 무인 / 자동 / 일반 / 정비·기타)
  - 대표자 이름 같은 개인정보는 넣지 않음
"""
import json
import re
import sys

import pandas as pd

SIDO = {"서울특별시": "서울", "경기도": "경기", "인천광역시": "인천"}

FLEET = re.compile(r"운수|여객|버스|차고지|청소차|교통\s*(?:㈜|\(주\))|㈜\s*\S*교통$|택시")

TYPE_RULES = [  # 위에서부터 먼저 맞는 것으로 분류
    ("detail", re.compile(r"디테일|광택|코팅|랩핑|카케어|유리막|PPF|썬팅", re.I)),
    ("self", re.compile(r"셀프(?!\s*(주유|충전))")),
    ("notouch", re.compile(r"무인|노터치|터치리스")),
    ("hand", re.compile(r"손세차")),
    ("auto", re.compile(r"주유|충전|오일뱅크|칼텍스|S-?OIL|에너지|자동세차|자동식|기계세차|터널|문형", re.I)),
    ("etc", re.compile(r"정비|공업사|카센타|카센터|모터스|수리|자동차서비스")),
]


def fix_coord(lat, lng):
    """뒤바뀐 위경도, 자릿수 오류를 보정. 고칠 수 없으면 None."""
    try:
        lat, lng = float(lat), float(lng)
    except (TypeError, ValueError):
        return None
    if lat > 100 and 30 < lng < 45:  # 위도·경도 자리 바뀜
        lat, lng = lng, lat
    while lng > 1000:  # 126838258 → 126.838258
        lng /= 10
    ok = 36.8 <= lat <= 38.4 and 126.0 <= lng <= 127.9  # 수도권 범위
    return (round(lat, 6), round(lng, 6)) if ok else None


def fix_sigungu(name):
    """'남양주' → '남양주시'처럼 끝 글자가 빠진 시군구명 보정"""
    name = str(name or "").strip()
    return name if re.search(r"[시군구]$", name) else name + "시"


def classify(row):
    text = " ".join(str(row.get(k) or "") for k in ("사업장명", "세차유형", "사업장업종명"))
    name_type = str(row.get("사업장명") or "") + " " + str(row.get("세차유형") or "")
    for t, rx in TYPE_RULES:
        # 종류 판단은 상호명과 세차유형을 우선하고, 업종명은 자동/정비 판단에만 씀
        if rx.search(name_type if t in ("detail", "self", "notouch", "hand") else text):
            return t
    return "wash"


def hours(row):
    s, e = row.get("평일운영시작시각"), row.get("평일운영종료시각")
    if not isinstance(s, str) or not isinstance(e, str):
        return None, False
    if s == e or (s == "00:00" and e in ("24:00", "23:59")):
        return "24시간", True
    return f"{s}~{e}", False


def main(src, out):
    df = pd.read_csv(src, encoding="cp949", dtype=str)
    df = df[df["시도명"].isin(SIDO)]
    stats = {"수도권 전체": len(df)}

    # 업종명으로 거르면 안 됨: 포천시·안산시 등은 모든 세차장 업종명을 '운수세차' 등으로 등록함
    fleet = df["사업장명"].fillna("").str.contains(FLEET)
    stats["운수·차고지 제외"] = int(fleet.sum())
    df = df[~fleet]

    places, seen, no_coord = [], set(), 0
    for _, r in df.iterrows():
        c = fix_coord(r["WGS84위도"], r["WGS84경도"])
        if not c:
            no_coord += 1
            continue
        name = re.sub(r"\s+", " ", str(r["사업장명"]).strip())
        key = (name, c)
        if key in seen:
            continue
        seen.add(key)
        h, is24 = hours(r)
        addr = r["소재지도로명주소"] if isinstance(r["소재지도로명주소"], str) else r["소재지지번주소"]
        p = {
            "id": len(places) + 1,
            "name": name,
            "addr": re.sub(r"\s+", " ", str(addr or "")).strip(),
            "region": SIDO[r["시도명"]] + " " + fix_sigungu(r["시군구명"]),
            "type": classify(r),
            "lat": c[0],
            "lng": c[1],
        }
        tel = r["세차장전화번호"]
        if isinstance(tel, str) and re.search(r"\d{3,}", tel):
            p["tel"] = tel.strip()
        if h:
            p["hours"] = h
        if is24:
            p["h24"] = True
        price = r["세차요금정보"]
        if isinstance(price, str) and not price.startswith("전화번호"):
            p["price"] = price.strip()[:200]
        places.append(p)

    stats["좌표 없음·오류 제외"] = no_coord
    stats["중복 제거"] = len(df) - no_coord - len(places)
    stats["지도에 올린 수"] = len(places)
    types = pd.Series([p["type"] for p in places]).value_counts().to_dict()

    with open(out, "w", encoding="utf-8") as f:
        json.dump(places, f, ensure_ascii=False, separators=(",", ":"))
    print(json.dumps({"stats": stats, "types": types}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "places.json")
