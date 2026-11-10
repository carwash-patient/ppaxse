-- 2026-11-10 한마디 기프티콘 추첨을 매주 월요일 17시(한국 시간)에 자동으로
-- migrate_2026-11-09d.sql 다음에 실행. 여러 번 실행해도 안전합니다.
--
--  · Supabase 예약 기능(pg_cron)이 매주 월요일 08:00 UTC = 17:00 한국 시간에 지난주(토~금) 추첨을 실행
--  · 추첨 방법은 그대로: 회원 추첨 2명 먼저 → 남은 사람 중 누구나 추첨 2명, 숨긴 한마디·막힌 사람 제외
--  · 결과가 저장되면 후기 페이지에 당첨 응모번호가 바로 공개됨
--  · 운영자 화면의 '추첨하기'는 예비용: 월요일 17시가 지났는데 자동 추첨이 안 됐을 때만 동작
--    (17시 전에 뽑아서 미리 공개되는 일을 막음)

create extension if not exists pg_cron;

-- 추첨 발표 시각: 응모 주(토요일) + 9일 = 다음 주 월요일 17:00 한국 시간
create or replace function public.ppx_event_draw_at(w date)
returns timestamptz language sql stable as $$
  select ((w + 9)::timestamp + time '17:00') at time zone 'Asia/Seoul'
$$;

-- 실제 추첨 (내부용: 화면에서 직접 부를 수 없음)
create or replace function public.ppx_event_draw_run(w date)
returns json language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('event-draw:' || w::text, 0));
  if not exists (select 1 from public.event_winners where week = w) then
    insert into public.event_winners (week, entry_id, pool)
      select w, e.id, 'member' from public.event_entries e
      where e.week = w and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)
      order by random() limit 2;
    insert into public.event_winners (week, entry_id, pool)
      select w, e.id, 'all' from public.event_entries e
      where e.week = w and public.ppx_entry_valid(e)
        and not exists (select 1 from public.event_winners x where x.week = w and x.entry_id = e.id)
      order by random() limit 2;
  end if;
  return (select coalesce(json_agg(json_build_object('code', e.code, 'pool', x.pool) order by x.pool desc), '[]'::json)
          from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = w);
end $$;
revoke all on function public.ppx_event_draw_run(date) from public, anon, authenticated;

-- 예약 작업이 부르는 함수: 발표 시각이 지난 지난주 회차를 추첨 (이미 뽑았으면 아무것도 안 함)
create or replace function public.ppx_auto_draw(at_time timestamptz default now())
returns json language plpgsql security definer set search_path = public as $$
declare w date := public.ppx_event_week(at_time) - 7;
begin
  if w < public.ppx_event_start() then return null; end if;
  if at_time < public.ppx_event_draw_at(w) then return null; end if;
  return public.ppx_event_draw_run(w);
end $$;
revoke all on function public.ppx_auto_draw(timestamptz) from public, anon, authenticated;

-- 운영자 '추첨하기'(예비용): 발표 시각 이후에만, 다시 뽑기는 그대로 가능
create or replace function public.admin_event_draw(w date, redraw boolean default false)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  if now() < public.ppx_event_draw_at(w) then
    raise exception '추첨은 발표 시각(월요일 17시) 이후에 할 수 있어요. 그때 자동으로 추첨돼요.';
  end if;
  if redraw then delete from public.event_winners where week = w; end if;
  return public.ppx_event_draw_run(w);
end $$;
revoke all on function public.admin_event_draw(date, boolean) from public, anon;
grant execute on function public.admin_event_draw(date, boolean) to authenticated;

-- 매주 월요일 08:00 UTC (= 17:00 한국 시간) 실행. 같은 이름이 있으면 지우고 다시 등록
select cron.unschedule(jobid) from cron.job where jobname = 'ppx-weekly-draw';
select cron.schedule('ppx-weekly-draw', '0 8 * * 1', $$select public.ppx_auto_draw()$$);
