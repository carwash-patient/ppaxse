-- 되돌리기: migrate_2026-11-23 (토요일 17시 발표) → 11/20까지의 정의(월요일 17시 발표)
-- 주의: 되돌리면 '발표 시각 전에는 당첨 결과를 숨기는' 기능도 사라집니다.
--       미리 뽑아 둔 당첨이 있으면 바로 사이트에 보이게 되니, 발표 시각이 지난 뒤에 되돌리세요.
-- 적용 전 md5: draw_at 743af1f9f8af6a47004cdcb6c91863b5 · rounds bf3fb553f7a309b98254a8dd3fc6c14e
--              status 17ebeb9008d263517633196ea57ae6cd · admin_event_draw ca202ae2948aa993e3eb641ef48654ca

create or replace function public.ppx_event_draw_at(w date)
returns timestamptz
language sql stable set search_path = pg_catalog, public, pg_temp as $$
  select ((w + 9)::timestamp + time '17:00') at time zone 'Asia/Seoul'
$$;

create or replace function public.ppx_event_rounds()
returns json
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(json_agg(r order by r.week desc), '[]'::json) from (
    select w.week, w.week + 6 as week_end, w.week + 9 as draw_date, w.week + 16 as claim_until,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e)) as all_count,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)) as member_count,
      (select json_agg(json_build_object('code', left(e.code, 4) || '***', 'pool', x.pool) order by x.pool desc, e.code)
         from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = w.week) as winners
    from (select distinct week from public.event_winners order by week desc limit 20) w
  ) r
$$;

create or replace function public.ppx_event_status()
returns json
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
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
      'winners', (select json_agg(json_build_object('code', left(e.code, 4) || '***', 'pool', x.pool) order by x.pool desc, e.code)
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

create or replace function public.admin_event_draw(w date, redraw boolean default false)
returns json
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  if now() < public.ppx_event_draw_at(w) then
    raise exception '추첨은 발표 시각(월요일 17시) 이후에 할 수 있어요. 그때 자동으로 추첨돼요.';
  end if;
  if redraw then delete from public.event_winners where week = w; end if;
  return public.ppx_event_draw_run(w);
end $$;

select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'ppx-weekly-draw'),
                      schedule := '0 8 * * 1');

drop function if exists public.ppx_event_draw_date(date);
