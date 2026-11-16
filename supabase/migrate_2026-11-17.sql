-- 2026-11-17: 이벤트 게시판
-- 1) events 표: 운영자가 쓰는 이벤트 글 (빡세·협찬·광고 세차장). 누구나 읽기(숨긴 글 제외), 쓰기는 운영자만.
-- 2) ppx_event_rounds(): 지난 기프티콘 추첨 회차 목록 (당첨번호 뒤 두 자리 가림, 참여 수). 누구나 실행.
-- 매주 기프티콘 이벤트 글은 표에 쓰지 않고 화면이 ppx_event_status / ppx_event_rounds로 자동으로 만듦.
-- 여러 번 실행해도 안전함.

create table if not exists public.events (
  id          bigserial primary key,
  title       text not null check (char_length(title) between 1 and 80),
  kind        text not null default 'ppaxse' check (kind in ('ppaxse','sponsor','ad')),   -- 빡세 / 협찬 / 광고 세차장
  status      text not null default 'on' check (status in ('on','win','end')),          -- 진행 중 / 당첨자 발표 / 마감
  icon        text check (icon is null or char_length(icon) <= 8),
  start_date  date,
  end_date    date,
  draw_date   date,
  winners     int check (winners is null or winners between 0 and 1000),
  target      text check (target is null or char_length(target) <= 80),                  -- 예) 첫 방문 손님 누구나 (추첨 없음)
  body        text not null default '' check (char_length(body) <= 4000),
  btn_label   text check (btn_label is null or char_length(btn_label) <= 30),
  btn_url     text check (btn_url is null or (char_length(btn_url) <= 500 and (btn_url ~ '^https://' or btn_url ~ '^[a-z0-9_./?=&#-]+$'))),
  pinned      boolean not null default false,
  hidden      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists events_list_idx on public.events (hidden, pinned desc, created_at desc);

alter table public.events enable row level security;
drop policy if exists events_read on public.events;
create policy events_read on public.events for select to anon, authenticated using (not hidden or public.is_admin());
drop policy if exists events_admin_ins on public.events;
create policy events_admin_ins on public.events for insert to authenticated with check (public.is_admin());
drop policy if exists events_admin_upd on public.events;
create policy events_admin_upd on public.events for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists events_admin_del on public.events;
create policy events_admin_del on public.events for delete to authenticated using (public.is_admin());

revoke all on public.events from public, anon, authenticated;
grant select on public.events to anon, authenticated;
grant insert, update, delete on public.events to authenticated;
grant usage, select on sequence public.events_id_seq to authenticated;

-- 고친 시각 자동 기록
create or replace function public.ppx_events_touch()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function public.ppx_events_touch() from public, anon, authenticated;
drop trigger if exists events_touch on public.events;
create trigger events_touch before update on public.events for each row execute function public.ppx_events_touch();

-- 지난 추첨 회차 (최근 20회): 당첨번호 뒤 두 자리 가림
create or replace function public.ppx_event_rounds()
returns json language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(json_agg(r order by r.week desc), '[]'::json) from (
    select w.week, w.week + 6 as week_end, w.week + 9 as draw_date, w.week + 16 as claim_until,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e)) as all_count,
      (select count(*) from public.event_entries e where e.week = w.week and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)) as member_count,
      (select json_agg(json_build_object('code', left(e.code, 5) || '**', 'pool', x.pool) order by x.pool desc, e.code)
         from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = w.week) as winners
    from (select distinct week from public.event_winners order by week desc limit 20) w
  ) r
$$;
revoke all on function public.ppx_event_rounds() from public, anon, authenticated;
grant execute on function public.ppx_event_rounds() to anon, authenticated;
