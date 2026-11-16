-- 2026-11-17d: 가이드 글·지역 페이지에서 어떤 버튼을 눌렀는지 세기
-- 여러 번 실행해도 안전합니다. (migrate_2026-11-17c 다음에 실행)
--
--  · 버튼 종류: cta_map(안내 상자 '세차장 지도 열기'), cta_review(안내 상자 '자주 가는 세차장에 한마디 남기기'),
--              card_map(세차장마다 '지도에서 보기'), card_review(세차장마다 '이 세차장에 한마디 남기기')
--  · 같은 날 같은 기기가 같은 페이지에서 같은 버튼을 여러 번 누르면 '누른 횟수'만 올라갑니다 (하루 200회까지).
--  · 숫자는 운영자만 봅니다 (admin_page_stats 결과에 함께 나옴).

create table if not exists public.ppx_page_clicks (
  day      date not null,
  path     text not null check (path ~ '^/(guide|wash)/' and char_length(path) <= 200),
  visitor  uuid not null,
  btn      text not null check (btn in ('cta_map','cta_review','card_map','card_review')),
  hits     int  not null default 1,
  first_at timestamptz not null default now(),
  last_at  timestamptz not null default now(),
  primary key (day, path, visitor, btn)
);
create index if not exists ppx_page_clicks_path_idx on public.ppx_page_clicks (path, day);
alter table public.ppx_page_clicks enable row level security;
revoke all on public.ppx_page_clicks from anon, authenticated;

create or replace function public.ppx_track_click(v uuid, pth text, b text)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null or pth is null or pth !~ '^/(guide|wash)/' or char_length(pth) > 200 then return; end if;
  if b is null or b not in ('cta_map','cta_review','card_map','card_review') then return; end if;
  insert into public.ppx_page_clicks (day, path, visitor, btn) values (d, pth, v, b)
  on conflict (day, path, visitor, btn) do update
    set hits = least(public.ppx_page_clicks.hits + 1, 200), last_at = now();
end $$;
revoke all on function public.ppx_track_click(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track_click(uuid, text, text) to anon, authenticated;

-- 운영자: 페이지별 조회수 + 버튼 누른 사람 수 (최근 days일)
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
               count(distinct v.visitor) filter (where v.src not in ('google','naver')) as etc,
               (select count(distinct c.visitor) from public.ppx_page_clicks c
                 where c.path = v.path and c.day > today - n and c.btn in ('cta_map','card_map')) as map_clicks,
               (select count(distinct c.visitor) from public.ppx_page_clicks c
                 where c.path = v.path and c.day > today - n and c.btn in ('cta_review','card_review')) as review_clicks
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
    -- 버튼별 누른 사람 수 (가이드 글 / 지역 페이지 따로)
    'clicks', coalesce((
      select json_object_agg(k, c) from (
        select (case when path like '/guide/%' then 'guide_' else 'wash_' end) || btn as k,
               count(distinct visitor) as c
        from public.ppx_page_clicks where day > today - n group by 1) z), '{}'::json),
    'total_visitors', (select count(distinct visitor) from public.ppx_page_views where day > today - n),
    'total_views', (select coalesce(sum(hits), 0) from public.ppx_page_views where day > today - n)
  );
end $$;
revoke all on function public.admin_page_stats(int) from public, anon;
grant execute on function public.admin_page_stats(int) to authenticated;
