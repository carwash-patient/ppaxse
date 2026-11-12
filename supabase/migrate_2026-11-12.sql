-- 2026-11-12 보안 수정 (3차 검토 반영본)
--
-- 무엇을 바꾸나
--  1) 함수 실행 권한: 정확한 시그니처(OID) 단위로, 필요한 역할에만 (비로그인 4개 / 로그인 24개 / 나머지 없음)
--  2) 앞으로 postgres가 만드는 함수는 기본으로 아무에게도 안 열림
--  3) public 함수 42개의 search_path를 'pg_catalog, public, pg_temp' 로 통일
--  4) 세차장 등록 정책: '아무거나 통과(true)' → '대기 상태 + 본인' 또는 운영자
--
-- 안전장치
--  · 시작 전 사전 검사 6가지(함수 목록·소유자·DEFINER·트리거·정책 호출 관계·기본값·기존 정책). 다르면 즉시 중단
--  · 끝나기 전 사후 검사 6가지(ACL·실제 권한·service_role/소유자 보존·search_path·기본 권한·정책). 다르면 전체 취소
--  · 전체가 하나의 트랜잭션(begin~commit). 중간 오류 = 아무것도 안 바뀜
--  · 이미 적용된 DB에 다시 실행해도 결과가 같음
--  · 되돌리기: rollback_2026-11-12.sql → 확인: verify_rollback_2026-11-12.sql
--
-- 근거: 2026-11-12 18:47 운영 DB 읽기 전용 조사. public 함수 42개 = 저장소 정의와 본문까지 일치(해시 비교).
-- 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다. (일부만 선택해서 실행하지 마세요)

begin;
set local search_path = pg_catalog, public;   -- 시그니처 표기를 고정하기 위해

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
create temp table _ppx_trg (tbl text, fn text) on commit drop;
insert into _ppx_trg values
  ('auth.users','handle_new_user()'),
  ('public.place_checks','place_checks_after_insert()'),
  ('public.place_checks','place_checks_before_insert()'),
  ('public.place_comment_reports','place_comment_reports_before_insert()'),
  ('public.place_comments','place_comments_before_insert()'),
  ('public.place_comments','place_comments_count()'),
  ('public.place_reports','place_reports_before_insert()'),
  ('public.place_reports','place_reports_before_update()'),
  ('public.places','places_before_insert()'),
  ('public.places','places_before_update()'),
  ('public.places','places_fix_types()');
create or replace temp view _ppx_cur as
  select p.oid, p.oid::regprocedure::text as sig, p.prosecdef as definer, pg_get_userbyid(p.proowner) as owner, p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
create or replace function pg_temp.acl_has(acl aclitem[], who text) returns boolean language sql stable as $$
  select exists (select 1 from aclexplode(coalesce(acl, '{}'::aclitem[])) a
                 where a.privilege_type = 'EXECUTE'
                   and a.grantee = case when who = 'PUBLIC' then 0::oid else (select oid from pg_roles where rolname = who) end)
$$;
-- ── 0) 사전 조건: 하나라도 다르면 아무것도 바꾸지 않고 멈춤 ──
do $$
declare bad text; n int;
begin
  -- (1) 함수 시그니처 집합이 조사 때와 정확히 같은가 (추가·삭제·인자 변경·이름 겹침 모두 잡음)
  select string_agg(coalesce(e.sig, '없어야 할 함수: ' || c.sig) || coalesce(case when c.sig is null then ' (없어짐)' end, ''), ', ')
    into bad
  from _ppx_fn e full join _ppx_cur c on c.sig = e.sig
  where e.sig is null or c.sig is null;
  if bad is not null then raise exception '[사전검사] 함수 목록이 조사 때와 달라요: %', bad; end if;

  -- (2) 소유자·SECURITY DEFINER 여부
  select string_agg(c.sig, ', ') into bad
  from _ppx_fn e join _ppx_cur c using (sig)
  where c.owner <> 'postgres' or c.definer <> e.definer;
  if bad is not null then raise exception '[사전검사] 소유자나 DEFINER 여부가 달라요: %', bad; end if;

  -- (3) 트리거 11개가 그대로 있고 켜져 있는가
  select string_agg(t.tbl || ':' || t.fn, ', ') into bad
  from _ppx_trg t
  where not exists (
    select 1 from pg_trigger g join pg_class k on k.oid = g.tgrelid
    where not g.tgisinternal and g.tgenabled = 'O'
      and k.relnamespace::regnamespace::text || '.' || k.relname = t.tbl
      and g.tgfoid::regprocedure::text = t.fn);
  if bad is not null then raise exception '[사전검사] 트리거가 없거나 꺼져 있어요: %', bad; end if;
  select count(*) into n from pg_trigger g join pg_proc p on p.oid = g.tgfoid
  where not g.tgisinternal and p.pronamespace = 'public'::regnamespace;
  if n <> 11 then raise exception '[사전검사] public 함수를 쓰는 트리거 수가 11개가 아니에요(%개)', n; end if;

  -- (4) RLS 정책에서 쓰는 public 함수가 여전히 is_admin() 하나뿐인가 (호출 관계 전제)
  select string_agg(distinct f.name, ', ') into bad
  from pg_policies pol
  cross join lateral (select p.proname as name from pg_proc p
                      where p.pronamespace = 'public'::regnamespace
                        and (coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, '')) ~ ('\m' || p.proname || '\(')) f
  where pol.schemaname in ('public', 'storage') and f.name <> 'is_admin';
  if bad is not null then raise exception '[사전검사] 정책에서 is_admin 외 함수를 써요: %', bad; end if;

  -- (5) 열 기본값에서 public 함수를 부르지 않는가
  select string_agg(c.relname || '.' || a.attname, ', ') into bad
  from pg_attrdef ad join pg_class c on c.oid = ad.adrelid
  join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
  join pg_depend d on d.classid = 'pg_attrdef'::regclass and d.objid = ad.oid and d.refclassid = 'pg_proc'::regclass
  join pg_proc p on p.oid = d.refobjid and p.pronamespace = 'public'::regnamespace;
  if bad is not null then raise exception '[사전검사] 열 기본값에서 public 함수를 써요: %', bad; end if;

  -- (6) places 등록 정책이 '변경 전' 또는 '이미 적용된' 모양인가
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'places' and policyname = 'places: 추가 요청'
      and cmd = 'INSERT' and permissive = 'PERMISSIVE' and roles = '{authenticated}' and qual is null
      and (with_check = 'true' or with_check like '%status = ''pending''%submitted_by%is_admin%'))
  then raise exception '[사전검사] places 등록 정책이 예상한 모양이 아니에요'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'places' and cmd in ('INSERT', 'ALL')) <> 1 then
    raise exception '[사전검사] places에 등록(INSERT) 정책이 1개가 아니에요';
  end if;
end $$;
-- 바꾸지 않을 권한(service_role, postgres 등)을 미리 기록해 두고 끝에서 비교
create temp table _ppx_keep on commit drop as
  select c.sig, a.grantor, a.grantee, a.privilege_type, a.is_grantable
  from _ppx_cur c join pg_proc p on p.oid = c.oid
  cross join lateral aclexplode(p.proacl) a
  where a.grantee not in (0, 'anon'::regrole, 'authenticated'::regrole);
-- ── 1) 함수 실행 권한: 정확한 시그니처(OID) 단위 ──
do $$
declare f record;
begin
  for f in select c.oid, e.to_anon, e.to_auth from _ppx_fn e join _ppx_cur c using (sig) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.oid::regprocedure);
    if f.to_auth then execute format('grant execute on function %s to authenticated', f.oid::regprocedure); end if;
    if f.to_anon then execute format('grant execute on function %s to anon', f.oid::regprocedure); end if;
  end loop;
end $$;

-- ── 2) 앞으로 postgres가 만드는 함수의 기본 권한: 아무에게도 안 열림 ──
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
alter default privileges for role postgres revoke execute on functions from public;

-- ── 3) search_path: 42개 모두 'pg_catalog, public, pg_temp' 로 통일 ──
--  · pg_catalog 먼저: 기본 함수(now, count 등)를 가로챌 수 없게
--  · pg_temp 마지막: 임시 테이블로 이름을 가로챌 수 없게 (PostgreSQL 문서 권장 방식)
--  · 모든 본문이 테이블·함수를 public. / auth. / storage. 로 적고 있어 동작은 같음
do $$
declare f record;
begin
  for f in select c.oid from _ppx_cur c loop
    execute format('alter function %s set search_path = pg_catalog, public, pg_temp', f.oid::regprocedure);
  end loop;
end $$;

-- ── 4) 세차장 등록 정책 ──
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (
    (status = 'pending' and submitted_by = (select auth.uid()))
    or (select public.is_admin())
  );
-- ── 5) 사후 검사: 예상과 한 건이라도 다르면 전체 취소 ──
do $$
declare bad text;
begin
  -- (1) ACL 직접 항목: PUBLIC 없음, anon·authenticated는 예상과 정확히 같음
  select string_agg(c.sig, ', ') into bad
  from _ppx_fn e join _ppx_cur c using (sig) join pg_proc p on p.oid = c.oid
  where pg_temp.acl_has(p.proacl, 'PUBLIC')
     or pg_temp.acl_has(p.proacl, 'anon') <> e.to_anon
     or pg_temp.acl_has(p.proacl, 'authenticated') <> e.to_auth;
  if bad is not null then raise exception '[사후검사] ACL이 예상과 달라요: %', bad; end if;

  -- (2) 실제 실행 가능 여부(has_function_privilege)도 예상과 같음 (상속·PUBLIC 경로까지 포함)
  select string_agg(c.sig, ', ') into bad
  from _ppx_fn e join _ppx_cur c using (sig)
  where has_function_privilege('anon', c.oid, 'execute') <> e.to_anon
     or has_function_privilege('authenticated', c.oid, 'execute') <> e.to_auth;
  if bad is not null then raise exception '[사후검사] 실제 실행 권한이 예상과 달라요: %', bad; end if;

  -- (3) service_role·postgres 등 다른 역할의 권한은 그대로
  select string_agg(distinct sig, ', ') into bad from (
    (select * from _ppx_keep
     except
     select c.sig, a.grantor, a.grantee, a.privilege_type, a.is_grantable
     from _ppx_cur c join pg_proc p on p.oid = c.oid cross join lateral aclexplode(p.proacl) a
     where a.grantee not in (0, 'anon'::regrole, 'authenticated'::regrole))
    union all
    (select c.sig, a.grantor, a.grantee, a.privilege_type, a.is_grantable
     from _ppx_cur c join pg_proc p on p.oid = c.oid cross join lateral aclexplode(p.proacl) a
     where a.grantee not in (0, 'anon'::regrole, 'authenticated'::regrole)
     except
     select * from _ppx_keep)) x;
  if bad is not null then raise exception '[사후검사] service_role·소유자 권한이 바뀌었어요: %', bad; end if;
  if exists (select 1 from _ppx_cur c where not has_function_privilege('service_role', c.oid, 'execute')) then
    raise exception '[사후검사] service_role이 실행할 수 없는 함수가 생겼어요';
  end if;

  -- (4) search_path
  select string_agg(c.sig, ', ') into bad from _ppx_cur c
  where c.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp'];
  if bad is not null then raise exception '[사후검사] search_path가 예상과 달라요: %', bad; end if;

  -- (5) 기본 권한: postgres가 public에 만드는 함수 → service_role만, 전역 PUBLIC 회수
  if exists (select 1 from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
             where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f'
               and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole))
  then raise exception '[사후검사] 새 함수 기본 권한이 아직 열려 있어요'; end if;
  if not exists (select 1 from pg_default_acl d where d.defaclrole = 'postgres'::regrole
                 and d.defaclobjtype = 'f' and d.defaclnamespace = 0)
  then raise exception '[사후검사] 전역 기본 권한(PUBLIC 회수)이 적용되지 않았어요'; end if;

  -- (6) places 등록 정책
  if not exists (
    select 1 from pg_policies where schemaname = 'public' and tablename = 'places' and policyname = 'places: 추가 요청'
      and cmd = 'INSERT' and permissive = 'PERMISSIVE' and roles = '{authenticated}' and qual is null
      and with_check like '%status = ''pending''%submitted_by%auth.uid()%is_admin()%')
  then raise exception '[사후검사] places 등록 정책이 예상과 달라요'; end if;
end $$;

commit;

-- ── 결과 표 (확인용, 커밋 후 출력) ──
select p.oid::regprocedure::text as 함수,
       p.prosecdef as definer,
       has_function_privilege('anon', p.oid, 'execute') as 비로그인,
       has_function_privilege('authenticated', p.oid, 'execute') as 로그인,
       has_function_privilege('service_role', p.oid, 'execute') as service_role,
       p.proacl::text as acl,
       array_to_string(p.proconfig, ';') as 설정
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
order by 3 desc, 4 desc, 1;
