-- 2026-11-14e 사장님이 직접 보내는 매장 정보 (ppaxse.com/owner/)
-- 무엇을 바꾸나: 정보 제보(place_reports)가 들어온 곳(via)에 'owner'(사장님 페이지)를 추가
--   · 지금 허용값: 'map'(지도) / 'review'(후기 페이지) → 'owner' 추가
--   · 사장님 제보도 일반 제보와 똑같이 '대기'로 들어가고, 운영자가 매장 전화 등으로 확인한 뒤 반영
--   · 새 표·새 칸·새 함수 없음. 권한·정책·트리거는 바꾸지 않음
-- migrate_2026-11-14d.sql 다음에 실행. 여러 번 실행해도 안전함 (via 칸에 걸린 검사 규칙만 다시 만듦)
do $$
declare c record;
begin
  -- via 칸 하나에만 걸린 CHECK 규칙을 찾아 지움 (이름이 달라도 찾음)
  for c in
    select k.conname
    from pg_constraint k
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any(k.conkey)
    where k.conrelid = 'public.place_reports'::regclass and k.contype = 'c'
      and a.attname = 'via' and array_length(k.conkey, 1) = 1
  loop
    execute format('alter table public.place_reports drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.place_reports add constraint place_reports_via_check
  check (via in ('map', 'review', 'owner'));

-- 확인: 아래 한 줄이 나오면 정상
select conname, pg_get_constraintdef(oid) as 규칙
from pg_constraint
where conrelid = 'public.place_reports'::regclass and conname = 'place_reports_via_check';
