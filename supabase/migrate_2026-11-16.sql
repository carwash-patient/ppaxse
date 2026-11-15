-- 2026-11-16: 바탕화면 아이콘(앱처럼 설치)으로 연 방문을 따로 세기
-- 방문 기록 함수 ppx_track이 화면 이름 'app'도 받게 함 (원래 화면 기록은 그대로, 앱으로 연 날은 'app' 한 줄이 더 생김)
-- 여러 번 실행해도 안전함. 권한(anon, authenticated 실행 가능)은 그대로 유지됨.
-- 1) 방문 기록 표의 '화면 이름' 허용 목록에 'app' 추가
alter table public.ppx_visits drop constraint if exists ppx_visits_page_check;
alter table public.ppx_visits add constraint ppx_visits_page_check
  check (page in ('home','map','review','login','join','mypage','other','app'));

-- 2) 방문 기록 함수
create or replace function public.ppx_track(v uuid, p text, r text default null)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null then return; end if;
  if p is null or p not in ('home','map','review','login','join','mypage','app') then p := 'other'; end if;
  insert into public.ppx_visits (day, visitor, page) values (d, v, p)
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
  if r is not null and lower(r) ~ '^[a-z0-9_-]{1,30}$' then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, lower(r)) on conflict (visitor) do nothing;
  end if;
end $$;
revoke all on function public.ppx_track(uuid, text, text) from public;
grant execute on function public.ppx_track(uuid, text, text) to anon, authenticated;

-- 3) 운영자 방문 통계: '본 횟수'에서 app 줄은 빼고(이중으로 세지 않게), 바탕화면 아이콘으로 연 사람 수를 따로 보여줌
create or replace function public.admin_visit_stats(days int default 14)
returns json language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  n int := greatest(1, least(coalesce(days, 14), 90));
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  return json_build_object(
    'today', today,
    -- 날짜별: 방문자(기기 수), 본 횟수, 처음 온 기기 수, 바탕화면 아이콘으로 연 기기 수
    'days', coalesce((
      select json_agg(x order by x.day desc) from (
        select g.day::date as day,
               count(distinct v.visitor) as visitors,
               coalesce(sum(v.hits) filter (where v.page <> 'app'), 0) as views,
               count(distinct v.visitor) filter (where f.first_day = g.day::date) as new_visitors,
               count(distinct v.visitor) filter (where v.page = 'app') as app_visitors
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
    'app7',   (select count(distinct visitor) from public.ppx_visits where page = 'app' and day > today - 7),
    'app_total', (select count(distinct visitor) from public.ppx_visits where page = 'app'),
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
