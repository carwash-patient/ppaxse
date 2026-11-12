-- 2026-11-12 보안 수정 되돌리기 (migrate_2026-11-12.sql 을 실행한 뒤 문제가 생겼을 때만 사용)
-- 바꾸기 전 상태(2026-11-12 18:47 조사 결과)로 그대로 돌립니다.
--   P = 모든 역할(PUBLIC), A = 비로그인(anon), U = 로그인(authenticated). service_role·postgres 권한은 건드리지 않음.
begin;

-- 1) 함수 실행 권한을 조사 때와 똑같이
do $$
declare f record; flags text;
begin
  for f in
    select p.proname, p.oid::regprocedure::text as sig, b.flags
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    join (values
    ('admin_abuse_summary','U'),
    ('admin_block','PU'),
    ('admin_block_commenter','PU'),
    ('admin_channel_stats','U'),
    ('admin_event_draw','U'),
    ('admin_event_entries','PU'),
    ('admin_event_week','U'),
    ('admin_type_votes','U'),
    ('admin_visit_stats','U'),
    ('delete_my_account','U'),
    ('finish_claim','PU'),
    ('handle_new_user','PAU'),
    ('is_admin','PAU'),
    ('my_pending_count','PAU'),
    ('my_pending_reports','PAU'),
    ('place_checks_after_insert','PAU'),
    ('place_checks_before_insert','PAU'),
    ('place_comment_reports_before_insert',''),
    ('place_comments_before_insert',''),
    ('place_comments_count','PAU'),
    ('place_reports_before_insert','PAU'),
    ('place_reports_before_update','PAU'),
    ('places_before_insert','PAU'),
    ('places_before_update','PAU'),
    ('places_fix_types','PAU'),
    ('ppx_auto_draw',''),
    ('ppx_burst_guard','U'),
    ('ppx_enter_event','U'),
    ('ppx_entry_valid',''),
    ('ppx_event_draw_at','PAU'),
    ('ppx_event_draw_run',''),
    ('ppx_event_start','PAU'),
    ('ppx_event_status','AU'),
    ('ppx_event_week','PAU'),
    ('ppx_guard','PAU'),
    ('ppx_is_member',''),
    ('ppx_log_block','U'),
    ('ppx_precheck','U'),
    ('ppx_stats','PAU'),
    ('ppx_track','AU'),
    ('ppx_vote_type','U'),
    ('start_claim','PU')
    ) as b(name, flags) on b.name = p.proname
    where n.nspname = 'public' and p.prokind = 'f'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if position('P' in f.flags) > 0 then execute format('grant execute on function %s to public', f.sig); end if;
    if position('A' in f.flags) > 0 then execute format('grant execute on function %s to anon', f.sig); end if;
    if position('U' in f.flags) > 0 then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;

-- 2) 새 함수 기본 권한을 예전대로
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated;
alter default privileges for role postgres grant execute on functions to public;

-- 3) search_path 설정을 원래대로(설정 없음) — 조사 때 설정이 없던 9개
alter function public.place_checks_before_insert()  reset search_path;
alter function public.place_reports_before_insert() reset search_path;
alter function public.place_reports_before_update() reset search_path;
alter function public.places_before_insert()        reset search_path;
alter function public.places_before_update()        reset search_path;
alter function public.places_fix_types()            reset search_path;
alter function public.ppx_event_draw_at(date)       reset search_path;
alter function public.ppx_event_start()             reset search_path;
alter function public.ppx_event_week(timestamptz)   reset search_path;

-- 4) 세차장 등록 정책을 예전대로
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (true);

commit;
