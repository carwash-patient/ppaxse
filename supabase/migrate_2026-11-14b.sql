-- 2026-11-14b 당첨번호 가려서 공개 + 관리자 화면에 응모권별 한마디
-- migrate_2026-11-14.sql 다음에 실행. 여러 번 실행해도 안전합니다.
-- 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다.
--
-- 무엇을 바꾸나
--  · 누구나 보는 '지난 회차 당첨 번호'를 뒤 두 자리를 가려서 돌려줌 (예: A7K-2**)
--      - 전체 번호는 응모한 본인(기기·계정)의 '내 응모번호'에서만 보임 → 당첨자만 아는 번호로 본인 확인
--      - 가리는 건 DB에서 하므로 화면 코드를 뜯어봐도 전체 번호는 안 보임
--  · 운영자 응모 목록에 응모권마다 남긴 한마디(날짜·세차장·내용)를 모두 보여 줌 (comments 열 추가)

begin;

-- ── 누구나 보는 현황: 당첨 번호는 가려서 ──
create or replace function public.ppx_event_status()
returns json language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v uuid := auth.uid();
  w date := greatest(public.ppx_event_week(now()), public.ppx_event_start());
  today date := (now() at time zone 'Asia/Seoul')::date;
  lw date;
begin
  select max(week) into lw from public.event_winners;
  return json_build_object(
    'start', public.ppx_event_start(),
    'week', w, 'week_end', w + 6, 'draw_date', w + 9,
    'max_tickets', public.ppx_event_max_tickets(),
    'all_count',    (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e)),
    'member_count', (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
    'winners_all', 2, 'winners_member', 2,
    'last', case when lw is null then null else json_build_object(
      'week', lw,
      'all_count',    (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e)),
      'member_count', (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
      'winners', (select json_agg(json_build_object('code', left(e.code, 5) || '**', 'pool', x.pool) order by x.pool desc, e.code)
                  from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = lw)
    ) end,
    'mine', case when v is null then '[]'::json else coalesce((
      select json_agg(json_build_object('week', e.week, 'code', e.code,
                      'won', (select x.pool from public.event_winners x where x.entry_id = e.id),
                      'valid', public.ppx_entry_valid(e),
                      'tickets', (select count(*) from public.event_tickets t where t.entry_id = e.id),
                      'valid_tickets', public.ppx_entry_weight(e),
                      'today', exists (select 1 from public.event_tickets t where t.entry_id = e.id and t.day = today))
                      order by e.week desc)
      from (select * from public.event_entries where user_id = v order by week desc limit 6) e), '[]'::json) end,
    'member', case when v is null then false else public.ppx_is_member(v) end
  );
end $$;
revoke all on function public.ppx_event_status() from public, anon, authenticated;
grant execute on function public.ppx_event_status() to anon, authenticated;

-- ── 운영자: 한 주의 응모 목록 (+ 응모권별 한마디) ──
drop function if exists public.admin_event_week(date);
create function public.admin_event_week(w date)
returns table (entry_id bigint, code text, created_at timestamptz, is_member boolean, nickname text, email text,
               place_name text, body text, valid boolean, won text, tickets int, valid_tickets int, places text, comments text)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 볼 수 있어요'; end if;
  return query
    select e.id, e.code, e.created_at, public.ppx_is_member(e.user_id),
           coalesce(pr.nickname, c.nickname), case when public.ppx_is_member(e.user_id) then u.email::text end,
           pl.name, c.body, public.ppx_entry_valid(e),
           (select x.pool from public.event_winners x where x.entry_id = e.id),
           (select count(*)::int from public.event_tickets t where t.entry_id = e.id),
           public.ppx_entry_weight(e),
           (select string_agg(coalesce(p2.name, '?') || case when c2.hidden then '(숨김)' else '' end, ', ' order by t.day)
              from public.event_tickets t
              left join public.place_comments c2 on c2.id = t.comment_id
              left join public.places p2 on p2.id = t.place_id
              where t.entry_id = e.id),
           (select string_agg(to_char(t.day, 'MM/DD') || ' ' || coalesce(p3.name, '?') || case when c3.hidden then '(숨김)' else '' end
                              || ': ' || coalesce(c3.body, '(삭제된 한마디)'), E'\n' order by t.day)
              from public.event_tickets t
              left join public.place_comments c3 on c3.id = t.comment_id
              left join public.places p3 on p3.id = t.place_id
              where t.entry_id = e.id)
    from public.event_entries e
    left join public.profiles pr on pr.id = e.user_id
    left join auth.users u on u.id = e.user_id
    left join public.place_comments c on c.id = e.comment_id
    left join public.places pl on pl.id = c.place_id
    where e.week = w
    order by e.created_at;
end $$;
revoke all on function public.admin_event_week(date) from public, anon, authenticated;
grant execute on function public.admin_event_week(date) to authenticated;

commit;
