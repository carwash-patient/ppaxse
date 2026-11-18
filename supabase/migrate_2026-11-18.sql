-- 2026-11-18: 검색용 페이지 조회수 기록을 '실제 페이지 주소'만 받게 좁힘 (보안 점검 후속)
-- migrate_2026-11-17d.sql 다음에 실행. 여러 번 실행해도 안전합니다.
--
-- 왜: 지금은 가입 안 한 누구나 ppx_track_page를 직접 불러
--      ① 운영자 화면에 보이는 페이지 제목을 아무 글자로 바꾸고
--      ② /guide/·/wash/로 시작하는 '없는 주소'를 기록에 마구 넣을 수 있음
--      (운영자 화면은 글자를 안전하게 바꿔 보여 줘서 해킹 코드가 실행되지는 않음)
-- 바꾸는 것:
--  1) ppx_track_page, ppx_track_click : 실제 페이지 주소 모양만 받음
--       /guide/ , /guide/글주소/ , /wash/ , /wash/시도/ , /wash/시도/시군구/  (끝의 index.html은 떼고 셈)
--  2) ppx_track_page : 화면이 보내는 제목(t)은 더 이상 저장하지 않음
--       → 운영자 화면이 제목을 사이트의 가이드 목록·주소에서 직접 만듦 (admin.html 같이 수정)
--       (t 입력칸은 이미 배포된 페이지가 계속 보내므로 남겨 두고 무시함)
--  · 표·이미 쌓인 기록은 지우지 않음. 실행 권한도 그대로.

-- 실제 페이지 주소인지 (내부용)
create or replace function public.ppx_seo_path(pth text)
returns text language sql immutable set search_path = pg_catalog, public, pg_temp as $$
  select case
    when p collate "C" ~ '^/guide/([a-z0-9-]{1,80}/)?$' then p
    when p collate "C" ~ '^/wash/([가-힣]{1,20}/){0,2}$' then p
  end
  from (select regexp_replace(coalesce(pth, ''), 'index\.html$', '') as p) s
  where char_length(coalesce(pth, '')) <= 200
$$;
revoke all on function public.ppx_seo_path(text) from public, anon, authenticated;

create or replace function public.ppx_track_page(v uuid, pth text, s text default null, t text default null)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  pth := public.ppx_seo_path(pth);
  if v is null or pth is null then return; end if;
  if s is null or s not in ('google','naver','daum','bing','ppaxse','direct','other') then s := 'other'; end if;
  -- t(제목)는 받기만 하고 저장하지 않음

  insert into public.ppx_page_views (day, path, visitor, src) values (d, pth, v, s)
  on conflict (day, path, visitor) do update
    set hits = least(public.ppx_page_views.hits + 1, 200), last_at = now();

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

create or replace function public.ppx_track_click(v uuid, pth text, b text)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  pth := public.ppx_seo_path(pth);
  if v is null or pth is null then return; end if;
  if b is null or b not in ('cta_map','cta_review','card_map','card_review') then return; end if;
  insert into public.ppx_page_clicks (day, path, visitor, btn) values (d, pth, v, b)
  on conflict (day, path, visitor, btn) do update
    set hits = least(public.ppx_page_clicks.hits + 1, 200), last_at = now();
end $$;
revoke all on function public.ppx_track_click(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track_click(uuid, text, text) to anon, authenticated;

-- 확인용 (읽기만 함, 실행 결과 표가 나오면 정상):
--   select public.ppx_seo_path('/guide/winter-self-wash/') as 정상1,      -- /guide/winter-self-wash/
--          public.ppx_seo_path('/wash/경기/수원시/index.html') as 정상2,   -- /wash/경기/수원시/
--          public.ppx_seo_path('/guide/<b>x</b>/') as 막힘;               -- 빈칸(null)
-- 이미 들어간 '없는 주소' 기록이 있는지 보기 (읽기만 함):
--   select path, count(*) from public.ppx_page_views where public.ppx_seo_path(path) is null group by path;
