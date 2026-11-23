-- 2026-11-23: 주간 추첨 발표를 '다음 주 월요일 17시' → '다음 날 토요일 17시'로 변경 (운영자 결정 11/23)
-- 여러 번 실행해도 안전합니다. 응모·응모권·당첨 데이터는 지우거나 바꾸지 않습니다.
-- 되돌리기: supabase/rollback_2026-11-23.sql
--
--  · 응모 기간은 그대로 토요일 0시 ~ 금요일 밤 12시(한국)
--  · 2026-11-21 주(2회차)부터: 응모가 끝난 바로 다음 날 토요일 17시에 추첨·발표 (주 시작일 + 7일)
--  · 2026-11-14 주(1회차)까지: 원래 안내대로 월요일 17시 (주 시작일 + 9일) — 이미 안내한 날짜를 바꾸지 않음
--  · 당첨 연락 기한: 발표일 + 7일 (전과 같은 '발표 후 7일')
--  · 새로 추가: 당첨 결과는 발표 시각(17시)이 지나야 사이트에 보임.
--    (추첨을 미리 해 둬도 17시 전에는 회차 목록·지난 회차·내 당첨 여부에 나오지 않음. 운영자 화면은 미리 보임)
--  · 자동 추첨 작업(ppx-weekly-draw)을 매주 토요일 08:00 UTC(= 한국 17:00)로 변경

-- 1) 회차별 발표일
create or replace function public.ppx_event_draw_date(w date)
returns date
language sql immutable set search_path = pg_catalog, public, pg_temp as $$
  select case when w <= date '2026-11-14' then w + 9 else w + 7 end
$$;
revoke all on function public.ppx_event_draw_date(date) from public, anon, authenticated;

-- 2) 발표 시각 (발표일 17시, 한국)
create or replace function public.ppx_event_draw_at(w date)
returns timestamptz
language sql stable set search_path = pg_catalog, public, pg_temp as $$
  select (public.ppx_event_draw_date(w)::timestamp + time '17:00') at time zone 'Asia/Seoul'
$$;
revoke all on function public.ppx_event_draw_at(date) from public, anon, authenticated;

-- 3) 회차 목록: 발표 시각이 지난 회차만, 발표일·연락 기한은 새 계산
create or replace function public.ppx_event_rounds()
returns json
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(json_agg(r order by r.week desc), '[]'::json) from (
    select w.week, w.week + 6 as week_end,
      public.ppx_event_draw_date(w.week) as draw_date,
      public.ppx_event_draw_date(w.week) + 7 as claim_until,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e)) as all_count,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)) as member_count,
      (select json_agg(json_build_object('code', left(e.code, 4) || '***', 'pool', x.pool) order by x.pool desc, e.code)
         from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = w.week) as winners
    from (select distinct week from public.event_winners
          where now() >= public.ppx_event_draw_at(week)
          order by week desc limit 20) w
  ) r
$$;
revoke all on function public.ppx_event_rounds() from public, anon, authenticated;
grant execute on function public.ppx_event_rounds() to anon, authenticated;

-- 4) 이번 주 현황: 발표일 새 계산, 지난 회차·내 당첨은 발표 시각 이후에만
create or replace function public.ppx_event_status()
returns json
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v uuid := auth.uid();
  w date := greatest(public.ppx_event_week(now()), public.ppx_event_start());
  today date := (now() at time zone 'Asia/Seoul')::date;
  lw date;
begin
  select max(week) into lw from public.event_winners where now() >= public.ppx_event_draw_at(week);
  return json_build_object(
    'start', public.ppx_event_start(),
    'week', w, 'week_end', w + 6, 'draw_date', public.ppx_event_draw_date(w),
    'max_tickets', public.ppx_event_max_tickets(),
    'all_count',    (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e)),
    'member_count', (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
    'winners_all', 2, 'winners_member', 2,
    'last', case when lw is null then null else json_build_object(
      'week', lw,
      'draw_date', public.ppx_event_draw_date(lw),
      'claim_until', public.ppx_event_draw_date(lw) + 7,
      'all_count',    (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e)),
      'member_count', (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
      'winners', (select json_agg(json_build_object('code', left(e.code, 4) || '***', 'pool', x.pool) order by x.pool desc, e.code)
                  from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = lw)
    ) end,
    'mine', case when v is null then '[]'::json else coalesce((
      select json_agg(json_build_object('week', e.week, 'code', e.code,
                      'won', case when now() >= public.ppx_event_draw_at(e.week)
                                  then (select x.pool from public.event_winners x where x.entry_id = e.id) end,
                      'draw_date', public.ppx_event_draw_date(e.week),
                      'claim_until', public.ppx_event_draw_date(e.week) + 7,
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

-- 5) 운영자 수동 추첨: 안내 문구만 바꿈
create or replace function public.admin_event_draw(w date, redraw boolean default false)
returns json
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  if now() < public.ppx_event_draw_at(w) then
    raise exception '추첨은 발표 시각(토요일 17시) 이후에 할 수 있어요. 그때 자동으로 추첨돼요.';
  end if;
  if redraw then delete from public.event_winners where week = w; end if;
  return public.ppx_event_draw_run(w);
end $$;
revoke all on function public.admin_event_draw(date, boolean) from public, anon, authenticated;
grant execute on function public.admin_event_draw(date, boolean) to authenticated;

-- 6) 자동 추첨 시각: 매주 토요일 08:00 UTC = 한국 17:00
--    ppx_auto_draw(이번 주 시작일 - 7일 회차를 추첨)는 그대로 씀. 토요일 17시에 '어제 끝난 주'를 뽑음.
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'ppx-weekly-draw'),
                      schedule := '0 8 * * 6');

-- 확인
select public.ppx_event_draw_at(date '2026-11-14') as r1_draw,   -- 2026-11-23 08:00 UTC (월 17시)
       public.ppx_event_draw_at(date '2026-11-21') as r2_draw,   -- 2026-11-28 08:00 UTC (토 17시)
       (select schedule from cron.job where jobname = 'ppx-weekly-draw') as cron_schedule;
