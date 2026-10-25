"""
전국세차장표준데이터(행정안전부, 공공데이터포털) CSV → 빡세 지도용 places.json

사용법:
    python3 tools/build_places.py <다운로드한 CSV 경로> [출력 경로, 기본 places.json] [--add-from <예전 places_seed.csv>]

하는 일:
  - 전국 16개 시·도 (지역 이름은 '부산 해운대구'처럼 줄여서 저장)
  - 운수회사·버스·택시 차고지처럼 일반 고객이 못 쓰는 세차시설 제외 (상호명 기준)
  - 위도/경도가 뒤바뀌었거나 단위가 틀린 좌표 보정, 고칠 수 없는 좌표(0 등)는 제외
  - 같은 이름·같은 좌표 중복 제거
  - 좌표를 믿을 수 없는 곳은 지도에서 빼고 '위치 확인 필요(unlocated)'로 보관 (주소로 나중에 위치를 다시 찾기 위함)
      · 시·도 범위를 벗어난 좌표 (예: 광주 주소인데 의정부 좌표)
      · 주소가 다른 세차장 8곳 이상이 똑같은 좌표 (지자체가 대표 지점 하나를 일괄 입력한 경우)
      · 같은 시·군·구 세차장들과 50km 넘게 떨어진 좌표 (섬 지역은 예외)
  - --add-from 을 주면, 그 파일에 이미 있는 세차장을 뺀 '추가분' CSV도 만듦 (Supabase에 이어 넣기용)
  - 세차장 종류 분류 (셀프 / 손세차 / 디테일링 / 노터치 / 자동 / 일반 / 정비·기타)
  - 대표자 이름 같은 개인정보는 넣지 않음
"""
import csv
import json
import os
import re
import sys

import pandas as pd

SIDO = {
    "서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천",
    "광주광역시": "광주", "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종",
    "경기도": "경기", "강원특별자치도": "강원", "강원도": "강원", "충청북도": "충북", "충청남도": "충남",
    "전북특별자치도": "전북", "전라북도": "전북", "전라남도": "전남", "전남광주통합특별시": "전남광주",
    "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주",
}

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
    ok = 32.9 <= lat <= 38.7 and 124.0 <= lng <= 132.0  # 대한민국 범위
    return (round(lat, 6), round(lng, 6)) if ok else None


def fix_sigungu(name):
    """'남양주' → '남양주시'처럼 끝 글자가 빠진 시군구명 보정"""
    name = str(name or "").strip()
    if name in ("", "없음", "nan"):      # 세종시처럼 시·군·구가 없는 곳
        return ""
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


# 시·도별 대략적인 범위 (위도 최소, 위도 최대, 경도 최소, 경도 최대) — 넉넉하게 잡음
SIDO_BOX = {
    "서울": (37.40, 37.73, 126.70, 127.30), "부산": (34.85, 35.42, 128.73, 129.36),
    "대구": (35.58, 36.36, 128.30, 128.92), "인천": (37.00, 38.02, 124.55, 126.85),
    "광주": (35.04, 35.28, 126.62, 127.03), "대전": (36.17, 36.51, 127.23, 127.57),
    "울산": (35.31, 35.74, 128.94, 129.48), "세종": (36.39, 36.75, 127.12, 127.41),
    "경기": (36.88, 38.31, 126.35, 127.87), "강원": (37.01, 38.63, 127.07, 129.38),
    "충북": (35.99, 37.28, 127.26, 128.67), "충남": (35.96, 37.08, 125.95, 127.66),
    "전북": (35.29, 36.17, 126.33, 127.93), "전남": (33.90, 35.54, 125.00, 127.92),
    "전남광주": (33.90, 35.54, 125.00, 127.92), "경북": (35.55, 37.56, 127.78, 131.90),
    "경남": (34.44, 35.93, 127.54, 129.26), "제주": (33.10, 34.01, 126.08, 127.00),
}
# 섬이 넓게 흩어져 있어 50km 규칙을 적용하지 않는 곳
ISLANDS = {"인천 옹진군", "인천 강화군", "경북 울릉군", "제주 제주시", "제주 서귀포시",
           "전남광주 신안군", "전남광주 완도군", "전남광주 진도군", "전남광주 여수시",
           "전남 신안군", "전남 완도군", "전남 진도군", "전남 여수시", "경남 통영시"}
SHARED_LIMIT = 8   # 주소가 다른 세차장 몇 곳 이상이 같은 좌표면 '대표 지점 일괄 입력'으로 봄


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def dist_km(a, b):
    import math
    r = math.pi / 180
    dlat, dlng = (b[0] - a[0]) * r, (b[1] - a[1]) * r
    h = math.sin(dlat / 2) ** 2 + math.cos(a[0] * r) * math.cos(b[0] * r) * math.sin(dlng / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def main(src, out, add_from=None):
    df = pd.read_csv(src, encoding="cp949", dtype=str)
    unknown = sorted(set(df["시도명"].dropna()) - set(SIDO))
    if unknown:
        print("⚠️ 모르는 시·도 이름 (제외됨):", unknown)
    df = df[df["시도명"].isin(SIDO)]
    stats = {"전체": len(df)}

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
        name = re.sub(r"\s+", " ", str(r["사업장명"]).strip())[:60]
        key = (name, c)
        if key in seen:
            continue
        seen.add(key)
        h, is24 = hours(r)
        addr = r["소재지도로명주소"] if isinstance(r["소재지도로명주소"], str) else r["소재지지번주소"]
        p = {
            "id": len(places) + 1,
            "name": name,
            "addr": re.sub(r"\s+", " ", str(addr or "")).strip()[:200],
            "region": (SIDO[r["시도명"]] + " " + fix_sigungu(r["시군구명"])).strip(),
            "type": classify(r),
            "lat": c[0],
            "lng": c[1],
        }
        p["_ref"] = f'{r["개방자치단체코드"]}-{r["관리번호"]}'  # 공공데이터 고유번호 (DB 중복 방지용)
        tel = r["세차장전화번호"]
        if isinstance(tel, str) and re.search(r"\d{3,}", tel):
            p["tel"] = tel.strip()[:30]
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

    # ── 좌표를 믿을 수 없는 곳 찾기 ──
    bad = {}   # id(p) -> 이유
    # ① 시·도 범위 밖
    for p in places:
        b = SIDO_BOX.get(p["region"].split(" ")[0])
        if b and not (b[0] <= p["lat"] <= b[1] and b[2] <= p["lng"] <= b[3]):
            bad[id(p)] = "시·도 범위 밖"
    # ② 대표 지점 일괄 입력 (주소가 다른 여러 곳이 똑같은 좌표)
    same = {}
    for p in places:
        same.setdefault((p["lat"], p["lng"]), []).append(p)
    for ps in same.values():
        if len({p["addr"] for p in ps}) >= SHARED_LIMIT:
            for p in ps:
                bad.setdefault(id(p), "여러 곳이 같은 좌표")
    # ③ 같은 시·군·구의 다른 세차장들과 50km 넘게 떨어짐 (①②로 걸러낸 곳은 가운데 계산에서 뺌, 섬은 예외)
    groups = {}
    for p in places:
        if id(p) not in bad:
            groups.setdefault(p["region"], []).append(p)
    for reg, ps in groups.items():
        if len(ps) < 5 or reg in ISLANDS:
            continue
        c = (median([p["lat"] for p in ps]), median([p["lng"] for p in ps]))
        for p in ps:
            if dist_km(c, (p["lat"], p["lng"])) > 50:
                bad[id(p)] = "지역과 50km 이상 떨어짐"
    unlocated = [p for p in places if id(p) in bad]
    places = [p for p in places if id(p) not in bad]
    for i, p in enumerate(places):
        p["id"] = i + 1
    reasons = pd.Series(list(bad.values())).value_counts().to_dict() if bad else {}
    stats["위치 확인 필요(지도에서 뺌)"] = {"합계": len(unlocated), **reasons}
    stats["지도에 올린 수"] = len(places)
    types = pd.Series([p["type"] for p in places]).value_counts().to_dict()

    # 1) 지도용 places.json (Supabase에 연결되지 않을 때 쓰는 예비 데이터)
    with open(out, "w", encoding="utf-8") as f:
        json.dump([{k: v for k, v in p.items() if k != "_ref"} for p in places],
                  f, ensure_ascii=False, separators=(",", ":"))

    # 2) Supabase 'places' 테이블에 가져올 CSV (Table Editor → Import data from CSV)
    seed = os.path.join(os.path.dirname(os.path.abspath(out)), "supabase", "places_seed.csv")
    os.makedirs(os.path.dirname(seed), exist_ok=True)
    cols = ["name", "addr", "region", "type", "lat", "lng", "tel", "hours", "price", "h24",
            "status", "source", "source_ref"]
    with open(seed, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for p, st in [(p, "approved") for p in places] + [(p, "unlocated") for p in unlocated]:
            row = dict(p, status=st, source="public_data", source_ref=p["_ref"])
            row["h24"] = "true" if p.get("h24") else ""
            w.writerow(["" if row.get(c) is None else row.get(c, "") for c in cols])
    stats["Supabase용 CSV"] = os.path.relpath(seed)

    # 3) 추가분: 이미 Supabase에 넣은 세차장(예전 CSV)을 뺀 나머지
    if add_from:
        with open(add_from, encoding="utf-8") as f:
            have = {row["source_ref"] for row in csv.DictReader(f)}
        add = os.path.join(os.path.dirname(seed), "places_seed_add.csv")
        n = 0
        with open(seed, encoding="utf-8") as fin, open(add, "w", encoding="utf-8", newline="") as fout:
            rd, w = csv.reader(fin), csv.writer(fout)
            head = next(rd)
            w.writerow(head)
            ref_i = head.index("source_ref")
            for row in rd:
                if row[ref_i] not in have:
                    w.writerow(row)
                    n += 1
        stats["추가분 CSV"] = f"{os.path.relpath(add)} ({n}곳)"
    by_sido = pd.Series([p["region"].split(" ")[0] for p in places]).value_counts().to_dict()
    stats["시·도별"] = by_sido
    # 이미 Supabase에 들어간 것 중 '위치 확인 필요'로 바꿔야 할 공공데이터 번호
    if add_from:
        fix = sorted(p["_ref"] for p in unlocated if p["_ref"] in have)
        path = os.path.join(os.path.dirname(seed), "unlocated_existing.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(fix))
        stats["이미 들어간 것 중 숨길 곳"] = f"{len(fix)}곳 → {os.path.relpath(path)}"
    print(json.dumps({"stats": stats, "types": types}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    args = sys.argv[1:]
    add_from = None
    if "--add-from" in args:
        i = args.index("--add-from")
        add_from = args[i + 1]
        del args[i:i + 2]
    main(args[0], args[1] if len(args) > 1 else "places.json", add_from)
