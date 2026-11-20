-- 2026-11-20: 보안 점검 후속 (운영자가 Supabase SQL Editor에서 한 번 실행)
-- 여러 번 실행해도 안전합니다. 세차장·한마디·응모 데이터는 지우거나 바꾸지 않습니다.
-- (방문 통계의 400일 지난 기록만 매일 정리 — 5번 참고. 지금은 400일 지난 기록이 없음)
-- 되돌리기: supabase/rollback_2026-11-20.sql
--
-- 1) 세차장 표(places)의 내부 칸을 공개 조회에서 숨김
--    · 숨기는 칸: memo(제보자가 운영자에게 남긴 메모), submitted_by(제보자), reviewed_by(처리한 운영자),
--                owner_id(사장님 계정), source_ref(공공데이터 원본 번호)
--    · 지도·검색·지역 페이지가 쓰는 칸은 그대로 보임
--    · 대신 필요한 사람에게는 서버 함수로 줌
--        - my_place_requests() : 내가 요청한 세차장 목록 (내 정보 화면, 승인 알림)
--        - admin_places(상태)  : 운영자 '대기·처리됨' 목록 (메모·제보자 포함, 운영자만)
-- 2) 회원 추첨은 '메일 인증을 마친 회원'만 회원으로 셈 (ppx_is_member)
-- 3) 당첨번호 공개할 때 뒤 세 자리를 가림 (예: A7K-***). 응모번호는 더 안전한 난수로 만듦
-- 4) 제보 사진은 한 기기(계정)당 하루 20장까지
-- 5) 방문 통계가 DB 용량을 채우지 못하게 (가짜 방문 기록을 프로그램으로 대량으로 보내는 경우 대비)
--    · 하루에 새로 생기는 기록 수에 상한: 방문 2,000 / 검색 페이지 조회 2,000 / 버튼 클릭 500 / 유입 경로 500
--      (2026-11-20 기준 실제는 하루 최대 방문 272, 조회 31 — 상한은 그보다 7배 이상 넉넉함. 손님이 늘면 숫자만 올리면 됨)
--    · 상한에 닿은 날에는 '처음 보는 방문자'만 더 세지 않음 (이미 센 방문자의 조회 횟수는 그대로 올라감)
--    · ppx_pages(페이지 제목 표)에는 더 쓰지 않음 — 운영자 화면은 제목을 사이트에서 직접 만들어서 필요 없음
--    · 400일 지난 방문 기록은 매일 새벽 4시 10분(한국)에 정리 (ppx-stats-cleanup)
--    · 최악의 경우(1년 내내 상한까지 가짜 기록)에도 약 250MB 안쪽 → 무료 용량 500MB를 넘지 않음

-- ── 1) 세차장 내부 칸 숨기기 ──
revoke select on public.places from anon, authenticated;
grant select (id, name, addr, region, type, types, lat, lng, tel, hours, price, price_note,
              h24, foam, under, indoor, myitem, reserve, info,
              status, source, reject_reason, created_at, updated_at, reviewed_at,
              checked_at, check_count, comment_count)
  on public.places to anon, authenticated;

create or replace function public.my_place_requests()
returns table (id bigint, name text, addr text, status text, reject_reason text,
               memo text, created_at timestamptz, reviewed_at timestamptz)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select p.id, p.name, p.addr, p.status, p.reject_reason, p.memo, p.created_at, p.reviewed_at
  from public.places p
  where auth.uid() is not null and p.submitted_by = auth.uid() and p.source <> 'public_data'
  order by p.created_at desc
  limit 50
$$;
revoke all on function public.my_place_requests() from public, anon, authenticated;
grant execute on function public.my_place_requests() to authenticated;

create or replace function public.admin_places(p_status text)
returns json
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 볼 수 있어요.'; end if;
  if p_status = 'pending' then
    return coalesce((select json_agg(row_to_json(x) order by x.created_at) from (
      select p.id, p.name, p.addr, p.region, p.type, p.types, p.lat, p.lng, p.tel, p.memo, p.status,
             p.reject_reason, p.created_at, p.reviewed_at, p.submitted_by,
             case when pr.id is null then null
                  else json_build_object('nickname', pr.nickname, 'blocked', pr.blocked) end as submitter
      from public.places p left join public.profiles pr on pr.id = p.submitted_by
      where p.status = 'pending'
      order by p.created_at asc
    ) x), '[]'::json);
  end if;
  return coalesce((select json_agg(row_to_json(x) order by x.reviewed_at desc nulls last) from (
    select p.id, p.name, p.addr, p.region, p.type, p.types, p.lat, p.lng, p.tel, p.memo, p.status,
           p.reject_reason, p.created_at, p.reviewed_at, p.submitted_by,
           case when pr.id is null then null
                else json_build_object('nickname', pr.nickname, 'blocked', pr.blocked) end as submitter
    from public.places p left join public.profiles pr on pr.id = p.submitted_by
    where p.status in ('approved', 'rejected') and p.source = 'user'
    order by p.reviewed_at desc nulls last
    limit 50
  ) x), '[]'::json);
end $$;
revoke all on function public.admin_places(text) from public, anon, authenticated;
grant execute on function public.admin_places(text) to authenticated;

-- ── 2) 회원 추첨: 메일 인증까지 마친 회원만 ──
create or replace function public.ppx_is_member(u uuid)
returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select exists (select 1 from auth.users x
                 where x.id = u and coalesce(x.is_anonymous, false) = false
                   and x.email is not null and x.email_confirmed_at is not null)
$$;
revoke all on function public.ppx_is_member(uuid) from public, anon, authenticated;

-- ── 3) 당첨번호: 뒤 세 자리 가리기 ──
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
revoke all on function public.ppx_event_rounds() from public, anon, authenticated;
grant execute on function public.ppx_event_rounds() to anon, authenticated;

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
revoke all on function public.ppx_event_status() from public, anon, authenticated;
grant execute on function public.ppx_event_status() to anon, authenticated;

-- 응모번호: random() 대신 암호용 난수(gen_random_bytes)로 만듦. 나머지는 그대로
create or replace function public.ppx_enter_event(cid bigint)
returns json
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v uuid := auth.uid();
  w date := public.ppx_event_week(now());
  today date := (now() at time zone 'Asia/Seoul')::date;
  mx int := public.ppx_event_max_tickets();
  c public.place_comments;
  e public.event_entries;
  n int := 0;
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  k text; i int;
begin
  if v is null then raise exception '이용자 확인이 필요해요.'; end if;
  if today < public.ppx_event_start() then
    raise exception '기프티콘 추첨은 11월 14일(토)부터 응모할 수 있어요.';
  end if;
  if exists (select 1 from public.profiles where id = v and (blocked or role = 'admin')) then
    raise exception '이 계정은 추첨에 응모할 수 없어요.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v::text || ':event', 0));

  select * into c from public.place_comments where id = cid and user_id = v and not hidden;
  if not found then raise exception '응모할 한마디를 찾지 못했어요.'; end if;

  -- 이번 주 응모가 있으면: 오늘 이미 / 이번 주 다 씀 / 같은 세차장이면 번호만 돌려줌
  select * into e from public.event_entries where week = w and user_id = v;
  if found then
    select count(*) into n from public.event_tickets where entry_id = e.id;
    if n >= mx then
      return json_build_object('code', e.code, 'week', w, 'already', true, 'reason', 'max', 'tickets', n, 'max', mx);
    end if;
    if exists (select 1 from public.event_tickets where entry_id = e.id and day = today) then
      return json_build_object('code', e.code, 'week', w, 'already', true, 'reason', 'today', 'tickets', n, 'max', mx);
    end if;
    if exists (select 1 from public.event_tickets where entry_id = e.id and place_id = c.place_id) then
      return json_build_object('code', e.code, 'week', w, 'already', true, 'reason', 'place', 'tickets', n, 'max', mx);
    end if;
  end if;

  -- 응모 조건 (그대로)
  if c.created_at < now() - interval '2 hours' or public.ppx_event_week(c.created_at) <> w then
    raise exception '이번 주에 남긴 한마디로만 응모할 수 있어요.';
  end if;
  if char_length(c.body) < 10 then
    raise exception '응모하려면 한마디를 10자 이상 써 주세요.';
  end if;
  if not exists (select 1 from public.place_reports r
                 where r.reporter = v and r.place_id = c.place_id and r.created_at > c.created_at - interval '2 hours')
     and not exists (select 1 from public.place_checks k2
                 where k2.user_id = v and k2.place_id = c.place_id and k2.created_at > c.created_at - interval '2 hours')
     and not exists (select 1 from public.place_type_votes tv
                 where tv.user_id = v and tv.place_id = c.place_id and tv.created_at > c.created_at - interval '2 hours') then
    raise exception '응모하려면 다녀온 시기나 세차장 정보를 하나 이상 함께 알려 주세요.';
  end if;

  -- 이번 주 첫 응모면 응모번호를 새로 만듦 (32글자 중 하나씩, 256 = 32×8 이라 고르게 뽑힘)
  if e.id is null then
    for i in 1..20 loop
      k := '';
      for j in 1..6 loop
        k := k || substr(chars, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % 32), 1);
      end loop;
      k := substr(k, 1, 3) || '-' || substr(k, 4, 3);
      exit when not exists (select 1 from public.event_entries where code = k);
    end loop;
    insert into public.event_entries (week, user_id, comment_id, code) values (w, v, c.id, k) returning * into e;
  end if;

  insert into public.event_tickets (entry_id, day, comment_id, place_id) values (e.id, today, c.id, c.place_id);
  select count(*) into n from public.event_tickets where entry_id = e.id;
  return json_build_object('code', e.code, 'week', w, 'already', false, 'tickets', n, 'max', mx);
end $$;
revoke all on function public.ppx_enter_event(bigint) from public, anon, authenticated;
grant execute on function public.ppx_enter_event(bigint) to authenticated;

-- ── 4) 제보 사진 하루 20장 ──
create or replace function public.ppx_photo_count_today()
returns int
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select count(*)::int from storage.objects o
  where auth.uid() is not null
    and o.bucket_id = 'report-photos'
    and (storage.foldername(o.name))[1] = auth.uid()::text
    and o.created_at > now() - interval '1 day'
$$;
revoke all on function public.ppx_photo_count_today() from public, anon, authenticated;
grant execute on function public.ppx_photo_count_today() to authenticated;

-- 서버에서 최종으로 막음 (화면을 거치지 않고 올려도 21장째부터 거절)
alter policy "report-photos: 올리기" on storage.objects
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and not exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.blocked)
    and public.ppx_photo_count_today() < 20
  );

-- 화면에서 사진 올리기 전에 미리 확인해 쉬운 말로 안내 (ppx_precheck는 사진 제보 직전에만 불림)
create or replace function public.ppx_precheck(what text, pid bigint default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '이용자 확인이 필요해요.'; end if;
  if what not in ('report', 'place') then raise exception '알 수 없는 요청이에요.'; end if;
  perform public.ppx_guard(what);
  perform public.ppx_burst_guard(what, pid);
  if what = 'report' and not public.is_admin() and public.ppx_photo_count_today() >= 20 then
    raise exception '사진은 하루 20장까지 올릴 수 있어요. 내일 다시 부탁드려요.';
  end if;
end $$;
revoke all on function public.ppx_precheck(text, bigint) from public, anon, authenticated;
grant execute on function public.ppx_precheck(text, bigint) to authenticated;

-- ── 5) 방문 통계 용량 상한 ──
create index if not exists ppx_visitor_ref_first_at_idx on public.ppx_visitor_ref (first_at);

create or replace function public.ppx_track(v uuid, p text, r text default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null then return; end if;
  if p is null or p not in ('home','map','review','login','join','mypage','app') then p := 'other'; end if;
  -- 처음 보는 방문자인데 오늘 상한(2,000)에 닿았으면 세지 않음
  if not exists (select 1 from public.ppx_visits where day = d and visitor = v and page = p)
     and (select count(*) from public.ppx_visits where day = d) >= 2000 then
    return;
  end if;
  insert into public.ppx_visits (day, visitor, page) values (d, v, p)
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
  if r is not null and lower(r) ~ '^[a-z0-9_-]{1,30}$'
     and (select count(*) from public.ppx_visitor_ref where first_at > now() - interval '1 day') < 500 then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, lower(r)) on conflict (visitor) do nothing;
  end if;
end $$;
revoke all on function public.ppx_track(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track(uuid, text, text) to anon, authenticated;

create or replace function public.ppx_track_page(v uuid, pth text, s text default null, t text default null)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null or pth is null or pth !~ '^/(guide|wash)/' or char_length(pth) > 200 then return; end if;
  if s is null or s not in ('google','naver','daum','bing','ppaxse','direct','other') then s := 'other'; end if;

  if exists (select 1 from public.ppx_page_views where day = d and path = pth and visitor = v)
     or (select count(*) from public.ppx_page_views where day = d) < 2000 then
    insert into public.ppx_page_views (day, path, visitor, src) values (d, pth, v, s)
    on conflict (day, path, visitor) do update
      set hits = least(public.ppx_page_views.hits + 1, 200), last_at = now();
  end if;

  -- (t: 페이지 제목은 더 저장하지 않음. 운영자 화면이 사이트에서 직접 제목을 만듦)

  if exists (select 1 from public.ppx_visits where day = d and visitor = v and page = 'seo')
     or (select count(*) from public.ppx_visits where day = d) < 2000 then
    insert into public.ppx_visits (day, visitor, page) values (d, v, 'seo')
    on conflict (day, visitor, page) do update
      set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
  end if;

  if s in ('google','naver','daum','bing')
     and (select count(*) from public.ppx_visitor_ref where first_at > now() - interval '1 day') < 500 then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, s) on conflict (visitor) do nothing;
  end if;
end $$;
revoke all on function public.ppx_track_page(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track_page(uuid, text, text, text) to anon, authenticated;

create or replace function public.ppx_track_click(v uuid, pth text, b text)
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null or pth is null or pth !~ '^/(guide|wash)/' or char_length(pth) > 200 then return; end if;
  if b is null or b not in ('cta_map','cta_review','card_map','card_review') then return; end if;
  if not exists (select 1 from public.ppx_page_clicks where day = d and path = pth and visitor = v and btn = b)
     and (select count(*) from public.ppx_page_clicks where day = d) >= 500 then
    return;
  end if;
  insert into public.ppx_page_clicks (day, path, visitor, btn) values (d, pth, v, b)
  on conflict (day, path, visitor, btn) do update
    set hits = least(public.ppx_page_clicks.hits + 1, 200), last_at = now();
end $$;
revoke all on function public.ppx_track_click(uuid, text, text) from public, anon, authenticated;
grant execute on function public.ppx_track_click(uuid, text, text) to anon, authenticated;

-- 400일 지난 방문 기록 정리 (매일 19:10 UTC = 한국 새벽 4:10). 같은 이름이면 덮어씀
select cron.schedule('ppx-stats-cleanup', '10 19 * * *', $job$
  delete from public.ppx_visits      where day < (now() at time zone 'Asia/Seoul')::date - 400;
  delete from public.ppx_page_views  where day < (now() at time zone 'Asia/Seoul')::date - 400;
  delete from public.ppx_page_clicks where day < (now() at time zone 'Asia/Seoul')::date - 400;
$job$);

-- ── 확인 (결과가 모두 true면 성공) ──
select
  not has_column_privilege('anon', 'public.places', 'memo', 'SELECT')          as memo_hidden,
  not has_column_privilege('anon', 'public.places', 'submitted_by', 'SELECT')  as submitter_hidden,
  has_column_privilege('anon', 'public.places', 'name', 'SELECT')              as name_visible,
  has_function_privilege('authenticated', 'public.admin_places(text)', 'EXECUTE') as admin_fn_ok,
  not has_function_privilege('anon', 'public.admin_places(text)', 'EXECUTE')   as admin_fn_closed,
  position('''***''' in pg_get_functiondef('public.ppx_event_status'::regproc)) > 0 as mask3_ok,
  position('>= 2000' in pg_get_functiondef('public.ppx_track'::regproc)) > 0      as stats_cap_ok,
  exists (select 1 from cron.job where jobname = 'ppx-stats-cleanup')             as cleanup_job_ok;
