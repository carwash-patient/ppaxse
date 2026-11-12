-- 2026-11-12 보안 수정 되돌리기
-- migrate_2026-11-12.sql 을 실행한 뒤 문제가 생겼을 때만 사용합니다.
-- 조사 당시(2026-11-12 18:47) 상태로 되돌립니다: 함수별 PUBLIC/anon/authenticated 권한, search_path,
-- 새 함수 기본 권한, places 등록 정책.  service_role·소유자 권한은 건드리지 않습니다.
-- 실행 후 verify_rollback_2026-11-12.sql 로 원래대로 돌아왔는지 확인하세요.
-- 전체를 한 번에 Run 합니다.

begin;
set local search_path = pg_catalog, public;

create temp table _ppx_fn (
  sig text primary key,      -- 정확한 함수 시그니처 (search_path = pg_catalog, public 기준 표기)
  definer boolean,           -- SECURITY DEFINER 여부 (조사 결과)
  was_public boolean,        -- 변경 전 ACL: PUBLIC 직접 허용
  was_anon boolean,          -- 변경 전 ACL: anon 직접 허용
  was_auth boolean,          -- 변경 전 ACL: authenticated 직접 허용
  was_sp text,               -- 변경 전 search_path (null = 설정 없음)
  to_anon boolean,           -- 변경 후 anon 허용
  to_auth boolean            -- 변경 후 authenticated 허용
) on commit drop;
insert into _ppx_fn values
    ('admin_abuse_summary()'                                                    , true , false, false, true, 'public', false, true),
    ('admin_block(uuid,boolean)'                                                , true , true, false, true, 'public', false, true),
    ('admin_block_commenter(bigint)'                                            , true , true, false, true, 'public', false, true),
    ('admin_channel_stats(integer)'                                             , true , false, false, true, 'public', false, true),
    ('admin_event_draw(date,boolean)'                                           , true , false, false, true, 'public', false, true),
    ('admin_event_entries(timestamp with time zone,timestamp with time zone)'   , true , true, false, true, 'public', false, true),
    ('admin_event_week(date)'                                                   , true , false, false, true, 'public', false, true),
    ('admin_type_votes()'                                                       , true , false, false, true, 'public', false, true),
    ('admin_visit_stats(integer)'                                               , true , false, false, true, 'public', false, true),
    ('delete_my_account()'                                                      , true , false, false, true, 'public', false, true),
    ('finish_claim(uuid)'                                                       , true , true, false, true, 'public', false, true),
    ('handle_new_user()'                                                        , true , true, true, true, 'public', false, false),
    ('is_admin()'                                                               , true , true, true, true, 'public', true, true),
    ('my_pending_count()'                                                       , true , true, true, true, 'public', false, true),
    ('my_pending_reports()'                                                     , true , true, true, true, 'public', false, true),
    ('place_checks_after_insert()'                                              , true , true, true, true, 'public', false, false),
    ('place_checks_before_insert()'                                             , false, true, true, true, null, false, false),
    ('place_comment_reports_before_insert()'                                    , true , false, false, false, 'pg_catalog, public', false, false),
    ('place_comments_before_insert()'                                           , true , false, false, false, 'pg_catalog, public', false, false),
    ('place_comments_count()'                                                   , true , true, true, true, 'public', false, false),
    ('place_reports_before_insert()'                                            , false, true, true, true, null, false, false),
    ('place_reports_before_update()'                                            , false, true, true, true, null, false, false),
    ('places_before_insert()'                                                   , false, true, true, true, null, false, false),
    ('places_before_update()'                                                   , false, true, true, true, null, false, false),
    ('places_fix_types()'                                                       , false, true, true, true, null, false, false),
    ('ppx_auto_draw(timestamp with time zone)'                                  , true , false, false, false, 'public', false, false),
    ('ppx_burst_guard(text,bigint)'                                             , true , false, false, true, 'public', false, true),
    ('ppx_enter_event(bigint)'                                                  , true , false, false, true, 'public', false, true),
    ('ppx_entry_valid(event_entries)'                                           , true , false, false, false, 'public', false, false),
    ('ppx_event_draw_at(date)'                                                  , false, true, true, true, null, false, false),
    ('ppx_event_draw_run(date)'                                                 , true , false, false, false, 'public', false, false),
    ('ppx_event_start()'                                                        , false, true, true, true, null, false, false),
    ('ppx_event_status()'                                                       , true , false, true, true, 'public', true, true),
    ('ppx_event_week(timestamp with time zone)'                                 , false, true, true, true, null, false, false),
    ('ppx_guard(text)'                                                          , true , true, true, true, 'public', false, true),
    ('ppx_is_member(uuid)'                                                      , true , false, false, false, 'public', false, false),
    ('ppx_log_block(text,text)'                                                 , true , false, false, true, 'public', false, true),
    ('ppx_precheck(text,bigint)'                                                , true , false, false, true, 'public', false, true),
    ('ppx_stats()'                                                              , true , true, true, true, 'public', true, true),
    ('ppx_track(uuid,text,text)'                                                , true , false, true, true, 'public', true, true),
    ('ppx_vote_type(bigint,text,text[])'                                        , true , false, false, true, 'public', false, true),
    ('start_claim()'                                                            , true , true, false, true, 'public', false, true);
create or replace temp view _ppx_cur as
  select p.oid, p.oid::regprocedure::text as sig, p.prosecdef as definer, pg_get_userbyid(p.proowner) as owner, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
-- 사전 검사: 함수 목록이 조사 때와 같아야 되돌릴 수 있음 (조용히 건너뛰지 않음)
do $$
declare bad text;
begin
  select string_agg(coalesce(e.sig, c.sig), ', ') into bad
  from _ppx_fn e full join _ppx_cur c on c.sig = e.sig
  where e.sig is null or c.sig is null;
  if bad is not null then
    raise exception '[되돌리기 중단] 함수 목록이 조사 때와 달라요: %  → 수동 대응 필요(검토 문서 참고)', bad;
  end if;
end $$;
-- 1) 함수 권한을 조사 때와 똑같이 (PUBLIC/anon/authenticated만)
do $$
declare f record;
begin
  for f in select c.oid, e.* from _ppx_fn e join _ppx_cur c using (sig) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.oid::regprocedure);
    if f.was_public then execute format('grant execute on function %s to public', f.oid::regprocedure); end if;
    if f.was_anon   then execute format('grant execute on function %s to anon', f.oid::regprocedure); end if;
    if f.was_auth   then execute format('grant execute on function %s to authenticated', f.oid::regprocedure); end if;
  end loop;
end $$;

-- 2) search_path를 함수별 원래 값으로 (없던 것은 reset)
do $$
declare f record;
begin
  for f in select c.oid, e.was_sp from _ppx_fn e join _ppx_cur c using (sig) loop
    if f.was_sp is null then
      execute format('alter function %s reset search_path', f.oid::regprocedure);
    else
      execute format('alter function %s set search_path = %s', f.oid::regprocedure, f.was_sp);
    end if;
  end loop;
end $$;

-- 3) 새 함수 기본 권한을 원래대로
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated;
alter default privileges for role postgres grant execute on functions to public;

-- 4) places 등록 정책을 원래대로
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (true);

commit;
