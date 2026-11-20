-- 2026-11-20 되돌리기: migrate_2026-11-20.sql 이전 상태로 (문제가 생겼을 때만 실행)
-- 새로 만든 함수(my_place_requests, admin_places, ppx_photo_count_today)는 지우지 않고 남겨 둡니다.
-- (새 화면 코드가 이 함수들을 부르므로, 지우면 내 정보·운영자 목록이 멈춤. 남겨 둬도 해가 없음)

-- 1) 세차장 표: 모든 칸 다시 공개 조회 가능 (예전과 같음, 여전히 RLS로 '승인된 곳'만 보임)
grant select on public.places to anon, authenticated;

-- 2) 회원 판정: 메일 인증 조건 빼기
create or replace function public.ppx_is_member(u uuid)
returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from auth.users x
                 where x.id = u and coalesce(x.is_anonymous, false) = false and x.email is not null)
$$;
revoke all on function public.ppx_is_member(uuid) from public, anon, authenticated;

-- 3) 당첨번호 가리기: 뒤 두 자리로 (ppx_event_status / ppx_event_rounds 안의 글자만 다름)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.ppx_event_rounds'::regproc);
  execute replace(d, 'left(e.code, 4) || ''***''', 'left(e.code, 5) || ''**''');
  d := pg_get_functiondef('public.ppx_event_status'::regproc);
  execute replace(d, 'left(e.code, 4) || ''***''', 'left(e.code, 5) || ''**''');
end $$;
-- (응모번호 만드는 난수는 더 안전한 쪽이라 되돌리지 않음)

-- 4) 사진 하루 20장 제한 풀기
alter policy "report-photos: 올리기" on storage.objects
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.blocked)
  );

create or replace function public.ppx_precheck(what text, pid bigint default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '이용자 확인이 필요해요.'; end if;
  if what not in ('report', 'place') then raise exception '알 수 없는 요청이에요.'; end if;
  perform public.ppx_guard(what);
  perform public.ppx_burst_guard(what, pid);
end $$;
revoke all on function public.ppx_precheck(text, bigint) from public, anon, authenticated;
grant execute on function public.ppx_precheck(text, bigint) to authenticated;

-- 5) 방문 통계 상한 풀기: 예전 함수로 (상한 검사만 빠짐), 정리 작업 끄기
create or replace function public.ppx_track(v uuid, p text, r text default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
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

create or replace function public.ppx_track_page(v uuid, pth text, s text default null, t text default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
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
  insert into public.ppx_visits (day, visitor, page) values (d, v, 'seo')
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
  if s in ('google','naver','daum','bing') then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, s) on conflict (visitor) do nothing;
  end if;
end $$;

create or replace function public.ppx_track_click(v uuid, pth text, b text)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null or pth is null or pth !~ '^/(guide|wash)/' or char_length(pth) > 200 then return; end if;
  if b is null or b not in ('cta_map','cta_review','card_map','card_review') then return; end if;
  insert into public.ppx_page_clicks (day, path, visitor, btn) values (d, pth, v, b)
  on conflict (day, path, visitor, btn) do update
    set hits = least(public.ppx_page_clicks.hits + 1, 200), last_at = now();
end $$;
-- (권한은 create or replace로 그대로 유지됨: anon, authenticated 실행 가능)

select cron.unschedule('ppx-stats-cleanup') where exists (select 1 from cron.job where jobname = 'ppx-stats-cleanup');
