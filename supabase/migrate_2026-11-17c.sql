-- 2026-11-17c: 검색용 페이지(세차 가이드 글·지역별 세차장)별 조회수 세기
-- 여러 번 실행해도 안전합니다.
--
--  · 가이드 글·지역 페이지를 열면 '어느 페이지를, 어느 기기가, 어디서 와서(구글·네이버 등)' 봤는지 하루 한 줄씩 남깁니다.
--    같은 날 같은 기기가 같은 페이지를 다시 열면 '본 횟수'만 올라갑니다 (하루 200회까지만 셈).
--  · 기기 번호는 기존 방문자 세기와 같은 임의 번호입니다. IP·이메일 등 개인정보는 저장하지 않습니다.
--  · 전체 방문자 수(📊 방문자 탭)에도 '검색용 페이지'로 함께 셉니다.
--  · 검색엔진에서 처음 들어온 기기는 채널별 성과에 google / naver 등으로 남습니다.
--  · 숫자는 운영자만 봅니다 (admin_page_stats).

-- 1) 기존 방문 기록에 'seo'(검색용 페이지) 화면 종류 추가
alter table public.ppx_visits drop constraint if exists ppx_visits_page_check;
alter table public.ppx_visits add constraint ppx_visits_page_check
  check (page in ('home','map','review','login','join','mypage','other','app','seo'));

-- 2) 페이지별 조회 기록
create table if not exists public.ppx_page_views (
  day      date not null,
  path     text not null check (path ~ '^/(guide|wash)/' and char_length(path) <= 200),
  visitor  uuid not null,
  src      text not null default 'direct' check (src in ('google','naver','daum','bing','ppaxse','direct','other')),
  hits     int  not null default 1,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  primary key (day, path, visitor)
);
create index if not exists ppx_page_views_path_idx on public.ppx_page_views (path, day);
alter table public.ppx_page_views enable row level security;
revoke all on public.ppx_page_views from anon, authenticated;

-- 페이지 제목 (운영자 화면에 주소 대신 제목으로 보여주기 위함)
create table if not exists public.ppx_pages (
  path    text primary key check (path ~ '^/(guide|wash)/' and char_length(path) <= 200),
  title   text check (char_length(title) <= 120),
  seen_at timestamptz not null default now()
);
alter table public.ppx_pages enable row level security;
revoke all on public.ppx_pages from anon, authenticated;

-- 3) 기록 함수 (가입 안 한 사람도 호출 가능)
create or replace function public.ppx_track_page(v uuid, pth text, s text default null, t text default null)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null or pth is null or pth !~ '^/(guide|wash)/' or char_length(pth) > 200 then return; end if;
  if s is null or s not in ('google','naver','daum','bing','ppaxse','direct','other') then s := 'other'; end if;

  insert into public.ppx_page_views (day, path, visitor, src) values (d, pth, v, s)
  on conflict (day, path, visitor) do update
    set hits = least(public.ppx_page_views.hits + 1, 200), last_at = now();

  if t is not null then
    insert into public.ppx_pages (path, title) values (pth, left(t, 120))
    on conflict (path) do update set title = excluded.title;
  end if;

  -- 전체 방문자 수에도 '검색용 페이지'로 셈
  insert into public.ppx_visits (day, visitor, page) values (d, v, 'seo')
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();

  -- 검색엔진에서 처음 온 기기는 채널(꼬리표)로 한 번만 남김
  if s in ('google','naver','daum','bing') then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, s) on conflict (visitor) do nothing;
  end if;
end $$;
revoke all on function public.ppx_track_page(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track_page(uuid, text, text, text) to anon, authenticated;

-- 4) 운영자: 페이지별 조회수 (최근 days일)
create or replace function public.admin_page_stats(days int default 30)
returns json language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  n int := greatest(1, least(coalesce(days, 30), 365));
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  return json_build_object(
    'today', today,
    'pages', coalesce((
      select json_agg(x order by x.visitors desc, x.views desc) from (
        select v.path,
               max(pg.title) as title,
               count(distinct v.visitor) as visitors,
               sum(v.hits) as views,
               count(distinct v.visitor) filter (where v.day = today) as today_visitors,
               count(distinct v.visitor) filter (where v.day > today - 7) as week_visitors,
               count(distinct v.visitor) filter (where v.src = 'google') as google,
               count(distinct v.visitor) filter (where v.src = 'naver') as naver,
               count(distinct v.visitor) filter (where v.src not in ('google','naver')) as etc
        from public.ppx_page_views v
        left join public.ppx_pages pg on pg.path = v.path
        where v.day > today - n
        group by v.path
        limit 300
      ) x), '[]'::json),
    'by_src', coalesce((
      select json_object_agg(src, c) from (
        select src, count(distinct visitor) as c from public.ppx_page_views
        where day > today - n group by src) y), '{}'::json),
    'total_visitors', (select count(distinct visitor) from public.ppx_page_views where day > today - n),
    'total_views', (select coalesce(sum(hits), 0) from public.ppx_page_views where day > today - n)
  );
end $$;
revoke all on function public.admin_page_stats(int) from public, anon;
grant execute on function public.admin_page_stats(int) to authenticated;
