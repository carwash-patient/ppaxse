-- 2026-11-09b 도배 방지 보강 · 이상 요청 기록 · 막힌 사람 신고 금지
-- migrate_2026-11-09.sql(한마디 신고) 다음에 실행. 여러 번 실행해도 안전합니다.
--
--  1) 정보 제보: 15초에 한 번, 같은 세차장은 10분에 한 번
--  2) 세차장 추가 요청: 30초에 한 번
--  3) 막힌 사람은 한마디 신고도 못 함
--  4) 이상 요청 기록(ppx_abuse_log): 제한에 걸린 요청을 운영자가 볼 수 있게 남김
--     · IP 주소는 저장하지 않음 (개인정보). IP 제한은 Supabase 로그인 제한·CAPTCHA로 처리

-- ── 1·2) 짧은 시간 연속 요청 막기 ──
create or replace function public.ppx_burst_guard(what text, pid bigint default null)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null or public.is_admin() then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(v::text || ':burst:' || what, 0));
  if what = 'report' then
    if exists (select 1 from public.place_reports
               where reporter = v and created_at > now() - interval '15 seconds') then
      raise exception '제보는 15초에 한 번씩 보낼 수 있어요. 잠시 기다려 주세요.';
    end if;
    if pid is not null and exists (select 1 from public.place_reports
               where reporter = v and place_id = pid and created_at > now() - interval '10 minutes') then
      raise exception '방금 이 세차장 제보를 보내셨어요. 10분 뒤에 다시 보내 주세요.';
    end if;
  elsif what = 'place' then
    if exists (select 1 from public.places
               where submitted_by = v and created_at > now() - interval '30 seconds') then
      raise exception '추가 요청은 30초에 한 번씩 보낼 수 있어요. 잠시 기다려 주세요.';
    end if;
  end if;
end $$;
revoke all on function public.ppx_burst_guard(text, bigint) from public, anon;
grant execute on function public.ppx_burst_guard(text, bigint) to authenticated;

-- 사진을 올리기 전에 미리 검사 (보내지 못할 제보인데 사진만 남는 일을 줄임)
create or replace function public.ppx_precheck(what text, pid bigint default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception '이용자 확인이 필요해요.'; end if;
  if what not in ('report', 'place') then raise exception '알 수 없는 요청이에요.'; end if;
  perform public.ppx_guard(what);
  perform public.ppx_burst_guard(what, pid);
end $$;
revoke all on function public.ppx_precheck(text, bigint) from public, anon;
grant execute on function public.ppx_precheck(text, bigint) to authenticated;

-- 정보 제보 (기존 규칙 그대로 + 연속 제보 막기)
create or replace function public.place_reports_before_insert()
returns trigger language plpgsql as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  new.reporter    := auth.uid();
  new.status      := 'pending';
  new.reviewed_by := null;
  new.reviewed_at := null;
  if new.photo is not null and new.photo not like auth.uid()::text || '/%' then
    raise exception '사진 정보가 올바르지 않아요';
  end if;
  perform public.ppx_guard('report');
  perform public.ppx_burst_guard('report', new.place_id);
  if public.my_pending_reports() >= 10 then
    raise exception '확인을 기다리는 제보가 10개 있어요. 처리된 뒤에 다시 보내 주세요.';
  end if;
  return new;
end $$;

-- 세차장 추가 요청 (기존 규칙 그대로 + 연속 요청 막기)
create or replace function public.places_before_insert()
returns trigger language plpgsql as $$
begin
  if current_user not in ('anon', 'authenticated') or public.is_admin() then
    return new;
  end if;
  new.status        := 'pending';
  new.source        := 'user';
  new.submitted_by  := auth.uid();
  new.source_ref    := null;
  new.owner_id      := null;
  new.reviewed_by   := null;
  new.reviewed_at   := null;
  new.reject_reason := null;
  new.checked_at    := null;
  new.check_count   := 0;
  new.comment_count := 0;
  perform public.ppx_guard('place');
  perform public.ppx_burst_guard('place');
  if public.my_pending_count() >= 5 then
    raise exception '확인을 기다리는 요청이 5개 있어요. 처리된 뒤에 다시 요청해 주세요.';
  end if;
  return new;
end $$;

-- ── 3) 한마디 신고: 막힌 사람은 신고 불가 (나머지는 11-09 규칙 그대로) ──
create or replace function public.place_comment_reports_before_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception '한마디 신고는 이용자 확인 후 할 수 있어요.';
  end if;
  if exists (select 1 from public.profiles where id = v_uid and blocked) then
    raise exception '이 기기에서는 지금 보낼 수 없어요. 문제가 있다면 운영자에게 알려주세요.';
  end if;

  new.reporter := v_uid;
  new.status := 'pending';
  new.created_at := now();

  if exists (
    select 1 from public.place_comments c
    where c.id = new.comment_id and c.user_id = v_uid
  ) then
    raise exception '내가 쓴 한마디는 신고할 수 없어요.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_uid::text || ':comment-report', 0)
  );

  if (
    select count(*) from public.place_comment_reports r
    where r.reporter = v_uid
      and r.created_at > now() - interval '1 day'
  ) >= 10 then
    raise exception '하루 신고는 10회까지 할 수 있어요.';
  end if;
  return new;
end;
$$;
revoke all on function public.place_comment_reports_before_insert()
  from public, anon, authenticated;

-- ── 4) 이상 요청 기록 ──
-- 제한에 걸리면 DB가 요청 자체를 되돌리기 때문에, 화면(js/ppx.js)이 따로 기록을 보냄.
-- 화면을 거치지 않는 공격은 기록되지 않을 수 있음 → 그 경우는 CAPTCHA·Supabase 로그인 제한이 막음
create table if not exists public.ppx_abuse_log (
  id         bigint generated by default as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('report', 'place', 'comment', 'check', 'comment_report')),
  message    text check (char_length(message) <= 200),
  created_at timestamptz not null default now()
);
create index if not exists ppx_abuse_log_time_idx on public.ppx_abuse_log (created_at desc);
create index if not exists ppx_abuse_log_user_idx on public.ppx_abuse_log (user_id, created_at desc);

alter table public.ppx_abuse_log enable row level security;
drop policy if exists "abuse log: 운영자 조회" on public.ppx_abuse_log;
create policy "abuse log: 운영자 조회" on public.ppx_abuse_log
  for select to authenticated using ((select public.is_admin()));
revoke all on public.ppx_abuse_log from anon, authenticated;
grant select on public.ppx_abuse_log to authenticated;

-- 기록 남기기: 한 사람당 1시간에 30개까지만 (기록 자체로 도배하지 못하게)
create or replace function public.ppx_log_block(k text, m text)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null then return; end if;
  if k not in ('report', 'place', 'comment', 'check', 'comment_report') then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(v::text || ':abuse-log', 0));
  if (select count(*) from public.ppx_abuse_log
      where user_id = v and created_at > now() - interval '1 hour') >= 30 then
    return;
  end if;
  insert into public.ppx_abuse_log (user_id, kind, message) values (v, k, left(m, 200));
end $$;
revoke all on function public.ppx_log_block(text, text) from public, anon;
grant execute on function public.ppx_log_block(text, text) to authenticated;

-- 운영자: 막힌 상태인지 같이 보기 위한 목록 (최근 7일, 사람별로 묶음)
create or replace function public.admin_abuse_summary()
returns table (user_id uuid, cnt bigint, kinds text[], last_message text, last_at timestamptz, blocked boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  return query
    select l.user_id, count(*), array_agg(distinct l.kind),
           (array_agg(l.message order by l.created_at desc))[1], max(l.created_at),
           coalesce(bool_or(p.blocked), false)
    from public.ppx_abuse_log l left join public.profiles p on p.id = l.user_id
    where l.created_at > now() - interval '7 days'
    group by l.user_id
    order by count(*) desc, max(l.created_at) desc
    limit 100;
end $$;
revoke all on function public.admin_abuse_summary() from public, anon;
grant execute on function public.admin_abuse_summary() to authenticated;
