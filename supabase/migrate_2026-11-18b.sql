-- 2026-11-18b: 지도 화면을 가볍게 — 세차장 목록을 '한 번에, 필요한 칸만, 짧은 모양'으로
-- 여러 번 실행해도 안전합니다. 표·데이터는 바꾸지 않고 '읽는 함수' 2개만 추가합니다.
--
-- 왜: map.html이 열릴 때마다 승인된 세차장 1만 1천여 곳의 모든 칸(약 3.9MB)을
--      1,000개씩 13번 나눠 받아 4초 넘게 걸림 (휴대폰 데이터에서는 더 느림)
-- 바꾸는 것:
--  1) map_places()         : 지도·목록·필터에 필요한 칸만, 배열 모양(이름표 없이)으로 한 번에 돌려줌
--                            전화·운영시간·가격·시설 상세(info)는 세차장을 눌렀을 때 그 한 곳만 따로 받음
--  2) map_places_version() : '바뀐 게 있는지'만 알려 주는 짧은 글자
--                            (승인된 세차장 수 + 세차장 표의 마지막 수정 시각)
--                            휴대폰에 저장해 둔 목록과 같으면 다시 받지 않음
--  · security invoker: 부르는 사람의 권한(RLS) 그대로 → 지금처럼 '승인된 곳'만 보임
--
-- map_places() 한 줄의 모양:
--   [id, name, addr, region, type, types, lat, lng, 시설비트, comment_count, check_count, checked_at]
--   시설비트: foam=1, under=2, indoor=4, h24=8 (값이 true인 것만 더함)

create or replace function public.map_places_version()
returns text language sql stable security invoker set search_path = pg_catalog, public, pg_temp as $$
  select (select count(*) from public.places where status = 'approved')::text || '-' ||
         coalesce((select extract(epoch from max(updated_at))::bigint from public.places), 0)::text
$$;
revoke all on function public.map_places_version() from public, anon, authenticated;
grant execute on function public.map_places_version() to anon, authenticated;

create or replace function public.map_places()
returns json language sql stable security invoker set search_path = pg_catalog, public, pg_temp as $$
  select json_build_object(
    'v', public.map_places_version(),
    'rows', coalesce(json_agg(json_build_array(
      id, name, coalesce(addr, ''), coalesce(region, ''), type, types,
      round(lat::numeric, 6), round(lng::numeric, 6),
      (case when foam then 1 else 0 end) + (case when under then 2 else 0 end) +
      (case when indoor then 4 else 0 end) + (case when h24 then 8 else 0 end),
      comment_count, check_count, checked_at
    ) order by id), '[]'::json))
  from public.places
  where status = 'approved' and lat is not null and lng is not null
$$;
revoke all on function public.map_places() from public, anon, authenticated;
grant execute on function public.map_places() to anon, authenticated;

-- 확인용 (읽기만 함):
--   select public.map_places_version();
--   select json_array_length(public.map_places() -> 'rows');   -- 승인된 세차장 수와 같으면 정상
