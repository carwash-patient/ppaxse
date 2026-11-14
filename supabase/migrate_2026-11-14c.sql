-- 2026-11-14c 운영자: '이상 요청'에 걸린 사람이 남긴 한마디 보기
-- 여러 번 실행해도 안전합니다. 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다.
--
-- 무엇을 바꾸나
--  · admin_user_comments(uid): 그 사람(기기)이 최근 7일 동안 남긴 한마디를 최신순으로 20개까지 돌려줌
--    (세차장 이름, 내용, 숨김 여부, 남긴 시각). 운영자만 실행 가능.
--  · 한마디의 작성자 칸(user_id)은 화면에서 직접 읽을 수 없게 막혀 있어서, 운영자 전용 함수로만 봄

create or replace function public.admin_user_comments(uid uuid)
returns table (id bigint, place_name text, body text, hidden boolean, created_at timestamptz)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 볼 수 있어요'; end if;
  return query
    select c.id, p.name, c.body, c.hidden, c.created_at
    from public.place_comments c
    left join public.places p on p.id = c.place_id
    where c.user_id = uid and c.created_at > now() - interval '7 days'
    order by c.created_at desc
    limit 20;
end $$;
revoke all on function public.admin_user_comments(uuid) from public, anon, authenticated;
grant execute on function public.admin_user_comments(uuid) to authenticated;
