-- 2026-11-09c 방문자 수 세기 (운영자만 볼 수 있음)
-- 여러 번 실행해도 안전합니다.
--
--  · 기기마다 임의 번호(휴대폰에 저장)를 하나 만들어, 날짜·화면별로 한 줄만 남깁니다.
--    같은 날 같은 화면을 여러 번 열면 그 줄의 '본 횟수'만 올라갑니다.
--  · IP 주소, 이메일, 위치 등 개인을 알 수 있는 정보는 저장하지 않습니다.
--  · 날짜는 한국 시간 기준입니다.
--  · 운영자 화면(admin.html)을 연 기기는 세지 않습니다.

create table if not exists public.ppx_visits (
  day      date not null,
  visitor  uuid not null,
  page     text not null check (page in ('home','map','review','login','join','mypage','other')),
  hits     int  not null default 1,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  primary key (day, visitor, page)
);
create index if not exists ppx_visits_visitor_idx on public.ppx_visits (visitor, day);

alter table public.ppx_visits enable row level security;
-- 이용자는 표를 직접 보거나 고칠 수 없고, 아래 함수로만 기록합니다
revoke all on public.ppx_visits from anon, authenticated;

-- 방문 기록 (가입 안 한 사람도 호출 가능). 한 줄당 본 횟수는 하루 200까지만 셈
create or replace function public.ppx_track(v uuid, p text)
returns void language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null then return; end if;
  if p is null or p not in ('home','map','review','login','join','mypage') then p := 'other'; end if;
  insert into public.ppx_visits (day, visitor, page) values (d, v, p)
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
end $$;
revoke all on function public.ppx_track(uuid, text) from public;
grant execute on function public.ppx_track(uuid, text) to anon, authenticated;

-- 운영자: 방문 통계 한 번에 (최근 days일)
create or replace function public.admin_visit_stats(days int default 14)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  n int := greatest(1, least(coalesce(days, 14), 90));
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  return json_build_object(
    'today', today,
    -- 날짜별: 방문자(기기 수), 본 횟수, 처음 온 기기 수
    'days', coalesce((
      select json_agg(x order by x.day desc) from (
        select g.day::date as day,
               count(distinct v.visitor) as visitors,
               coalesce(sum(v.hits), 0) as views,
               count(distinct v.visitor) filter (where f.first_day = g.day::date) as new_visitors
        from generate_series(today - (n - 1), today, interval '1 day') g(day)
        left join public.ppx_visits v on v.day = g.day::date
        left join (select visitor, min(day) as first_day from public.ppx_visits group by visitor) f
               on f.visitor = v.visitor
        group by g.day
      ) x), '[]'::json),
    -- 기간 전체에서 겹치지 않는 방문자 수
    'uniq7',  (select count(distinct visitor) from public.ppx_visits where day > today - 7),
    'uniq30', (select count(distinct visitor) from public.ppx_visits where day > today - 30),
    'total',  (select count(distinct visitor) from public.ppx_visits),
    -- 오늘 화면별
    'pages_today', coalesce((
      select json_agg(y order by y.visitors desc) from (
        select page, count(*) as visitors, sum(hits) as views
        from public.ppx_visits where day = today group by page
      ) y), '[]'::json)
  );
end $$;
revoke all on function public.admin_visit_stats(int) from public, anon;
grant execute on function public.admin_visit_stats(int) to authenticated;
