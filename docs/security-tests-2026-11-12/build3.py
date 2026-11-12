#!/usr/bin/env python3
# 2026-11-12 보안 수정 SQL 생성기 (4차: 트리거 도우미 비공개화 + 완전 ACL 비교)
import hashlib, re
OUT = '/home/claude/ppaxse/supabase/'

sigs = [l.split('|') for l in open('sigs.txt').read().strip().split('\n')]          # name|sig|secdef|config
before_acl = {l.split('|')[0]: l.split('|')[1] for l in open('/tmp/gen/acl.txt').read().strip().split('\n')}
md5_before = dict(l.split('|') for l in open('md5_before.txt').read().strip().split('\n'))
pols = [l.split('|') for l in open('pol_expect.txt').read().strip().split('\n')]

ANON = {'is_admin', 'ppx_stats', 'ppx_event_status', 'ppx_track'}
AUTH = ANON | {'delete_my_account', 'start_claim', 'finish_claim', 'ppx_enter_event', 'ppx_log_block',
               'ppx_precheck', 'ppx_vote_type',
               'admin_abuse_summary', 'admin_block', 'admin_block_commenter', 'admin_channel_stats',
               'admin_event_draw', 'admin_event_entries', 'admin_event_week', 'admin_type_votes', 'admin_visit_stats'}
assert len(AUTH) == 20

# 호출자 권한(INVOKER)으로 돌던 트리거 3개 → 소유자 권한(DEFINER)으로. 앱 요청 판별만 current_user → JWT role 로 바꿈
TRIG3 = ['places_before_insert', 'place_reports_before_insert', 'place_checks_before_insert']
OLD_LINE = "current_user not in ('anon', 'authenticated')"
NEW_LINE = "coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated')"
orig_src, new_src = {}, {}
for f in TRIG3:
    s = open(f'src_{f}.txt').read()[:-1]
    assert hashlib.md5(s.encode()).hexdigest() == md5_before[f]
    assert s.count(OLD_LINE) == 1 and '$fn$' not in s
    orig_src[f] = s
    new_src[f] = s.replace(OLD_LINE, NEW_LINE)
md5_after = dict(md5_before)
for f in TRIG3:
    md5_after[f] = hashlib.md5(new_src[f].encode()).hexdigest()

def q(s): return "'" + s.replace("'", "''") + "'"
def b(x): return 'true' if x else 'false'

rows = []
for name, sig, sd, cfg in sigs:
    fl = before_acl[name]
    d0 = sd == 't'
    d1 = d0 or name in TRIG3
    sp0 = cfg.replace('search_path=', '') if cfg else None
    rows.append(f"({q(sig)}, {b(d0)}, {b(d1)}, {b('P' in fl)}, {b('A' in fl)}, {b('U' in fl)}, "
                f"{q(sp0) if sp0 else 'null'}, {b(name in ANON)}, {b(name in AUTH)}, {q(md5_before[name])}, {q(md5_after[name])})")
FN_VALUES = ",\n  ".join(rows)
FN_COLS = "sig, def_before, def_after, was_public, was_anon, was_auth, sp_before, to_anon, to_auth, md5_before, md5_after"
FN_COMMENT = """--   sig        정확한 시그니처 (search_path = pg_catalog, public 기준 표기)
--   def_*      SECURITY DEFINER 여부 (변경 전 / 변경 후)
--   was_*      변경 전 PUBLIC / anon / authenticated 직접 권한  (모든 함수: postgres·service_role 권한은 항상 있음, 부여자 postgres, GRANT OPTION 없음)
--   sp_before  변경 전 search_path (null = 설정 없음). 변경 후는 모두 'pg_catalog, public, pg_temp'
--   to_*       변경 후 anon / authenticated 권한
--   md5_*      함수 본문 md5 (변경 전 / 변경 후)"""

POL_VALUES = ",\n  ".join(
    f"({q(s)}, {q(t)}, {q(n)}, {q(c)}, {q(p)}, {q(r)}, {q(uq) if uq else 'null'}, {q(wc) if wc else 'null'})"
    for s, t, n, c, p, r, uq, wc in pols)
POL_COLS = "schemaname, tablename, policyname, cmd, permissive, roles, qual_md5, check_md5"

# 운영 조사(18:47) 그대로의 postgres 기본 권한 6행
DEFACL_BEFORE = [
    ('r', 'public', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
    ('f', 'public', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('S', 'public', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'),
    ('r', 'storage', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'),
    ('f', 'storage', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
    ('S', 'storage', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'),
]
DEFACL_AFTER = [x for x in DEFACL_BEFORE if not (x[0] == 'f' and x[1] == 'public')] + [
    ('f', 'public', '{postgres=X/postgres,service_role=X/postgres}'),
    ('f', '-', '{postgres=X/postgres}'),   # 전역(스키마 무관): PUBLIC 회수
]
def defacl_values(lst): return ",\n  ".join(f"({q(t)}, {q(s)}, {q(a)}::aclitem[])" for t, s, a in lst)

# ── 공통 조각 ──────────────────────────────────────────────
FN_CTE = f"""fn_expect({FN_COLS}) as (values
  {FN_VALUES}
)"""
POL_CTE = f"""pol_expect({POL_COLS}) as (values
  {POL_VALUES}
)"""

# 현재 함수 상태 (시그니처는 'public.' 을 떼고 비교 → 세션 search_path와 무관)
CUR_FN = """cur_fn as (
  select p.oid, replace(p.oid::regprocedure::text, 'public.', '') as sig, p.prosecdef as definer,
         pg_get_userbyid(p.proowner) as owner, p.proconfig, p.proacl, md5(p.prosrc) as src_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
)"""
# ACL을 (받는 역할, 준 역할, 권한, GRANT OPTION) 문자열 집합으로 풀어 정렬 — NULL ACL은 그대로 'NULL'
ACL_NORM = """create or replace function pg_temp.ppx_acl(acl aclitem[]) returns text language sql stable as $f$
  select case when acl is null then 'NULL(기본값)' else coalesce((
    select string_agg(x, ',' order by x collate "C") from (
      select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
             || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
             || '/' || pg_get_userbyid(a.grantor) as x
      from aclexplode(acl) a) z), '(빈 ACL)') end
$f$;
-- 기대 ACL: postgres·service_role + (PUBLIC/anon/authenticated 중 해당) — 모두 EXECUTE, 부여자 postgres, GRANT OPTION 없음
create or replace function pg_temp.ppx_acl_expect(pub boolean, an boolean, au boolean) returns text language sql immutable as $f$
  select string_agg(x, ',' order by x collate "C") from unnest(array['postgres=EXECUTE/postgres', 'service_role=EXECUTE/postgres']
    || case when pub then array['PUBLIC=EXECUTE/postgres'] else '{}'::text[] end
    || case when an  then array['anon=EXECUTE/postgres'] else '{}'::text[] end
    || case when au  then array['authenticated=EXECUTE/postgres'] else '{}'::text[] end) x
$f$;
create or replace function pg_temp.ppx_defacl(r regrole) returns text language sql stable as $f$
  select coalesce(string_agg(x, ' | ' order by x collate "C"), '(없음)') from (
    select d.defaclobjtype::text || '/' || case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end
           || ' ' || pg_temp.ppx_acl(d.defaclacl) as x
  from pg_default_acl d where d.defaclrole = r) z
$f$;
create or replace function pg_temp.ppx_defacl_f() returns text language sql stable as $f$
  select coalesce(string_agg(x, ' | ' order by x collate "C"), '(없음)') from (
    select d.defaclobjtype::text || '/' || case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end
           || ' ' || pg_temp.ppx_acl(d.defaclacl) as x
  from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f') z
$f$;
create or replace function pg_temp.ppx_defacl_expect(t text, s text, a aclitem[]) returns text language sql stable as $f$
  select t || '/' || s || ' ' || pg_temp.ppx_acl(a)
$f$;
"""

def trig_def(f, src, definer):
    if definer:
        head = f"create or replace function public.{f}()\nreturns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fn$"
    else:
        head = f"create or replace function public.{f}()\nreturns trigger language plpgsql as $fn$"
    return f"{head}{src}$fn$;\n"

# ── 마이그레이션 ─────────────────────────────────────────────
MIG = f"""-- 2026-11-12 보안 수정 (4차 검토 반영본)
--
-- 무엇을 바꾸나
--  1) 함수 실행 권한: 정확한 시그니처 단위로 필요한 역할에만 (비로그인 4개 / 로그인 20개 / 나머지 없음)
--  2) 트리거 3개(places·place_reports·place_checks 등록 전 검사)를 소유자 권한(SECURITY DEFINER)으로 바꿔
--     안에서 쓰는 도우미 4개(ppx_guard, ppx_burst_guard, my_pending_count, my_pending_reports)를
--     이용자가 직접 부를 수 없게 닫음. 본문은 '앱 요청인지' 판별하는 한 줄만 바뀜:
--       {OLD_LINE}
--     → {NEW_LINE}
--     (같은 방식을 place_comments_before_insert 트리거가 이미 운영에서 쓰고 있음)
--  3) 앞으로 postgres가 만드는 함수는 기본으로 아무에게도 안 열림
--  4) public 함수 42개의 search_path를 'pg_catalog, public, pg_temp' 로 통일
--  5) 세차장 등록 정책: '아무거나 통과(true)' → '대기 상태 + 본인' 또는 운영자
--
-- 안전장치
--  · 사전 검사 7가지: 함수 목록·소유자·DEFINER·본문(md5)·트리거·정책 호출 관계·열 기본값·정책 25개·기본 권한
--  · 사후 검사: 함수별 ACL '완전 일치'(받는 역할·준 역할·권한·GRANT OPTION), 실제 실행 권한, search_path, 본문,
--               기본 권한 행 전체, 정책 25개 전체 — 하나라도 다르면 전체 취소
--  · 전체가 하나의 트랜잭션. 다시 실행해도 결과가 같음
--  · 되돌리기: rollback_2026-11-12.sql → 확인: verify_rollback_2026-11-12.sql
--
-- 근거: 2026-11-12 18:47 운영 DB 읽기 전용 조사. 함수 42개 본문·정책 25개·ACL·기본 권한이 저장소/테스트 DB와 일치.
-- 테스트: PostgreSQL 16.15 / 17.11 테스트 DB (docs/security-review-2026-11-12.md)
-- 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다.

begin;
set local search_path = pg_catalog, public;

{ACL_NORM}
create temp table _fn on commit drop as
with {FN_CTE}
select * from fn_expect;
create temp table _pol on commit drop as
with {POL_CTE}
select * from pol_expect;
create temp table _defacl_before (t text, s text, a aclitem[]) on commit drop;
insert into _defacl_before values
  {defacl_values(DEFACL_BEFORE)};
create temp table _defacl_after (t text, s text, a aclitem[]) on commit drop;
insert into _defacl_after values
  {defacl_values(DEFACL_AFTER)};
create or replace temp view _cur as with {CUR_FN} select * from cur_fn;
-- 바꾸지 않을 것들의 시작 상태 기록: 모든 역할의 기본 권한 행(postgres 함수 행 제외), 함수 외 다른 객체는 건드리지 않음
create temp table _defacl_keep on commit drop as
  select d.defaclrole::regrole::text as r, d.defaclobjtype::text as t, d.defaclnamespace::regnamespace::text as s,
         pg_temp.ppx_acl(d.defaclacl) as acl
  from pg_default_acl d where not (d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f');

-- ── 0) 사전 검사: 하나라도 다르면 아무것도 바꾸지 않고 멈춤 ──
do $$
declare bad text; n int;
begin
  -- (1) 함수 시그니처 집합이 정확히 같은가 (추가·삭제·인자 변경·이름 겹침)
  select string_agg(coalesce(e.sig || ' (없어짐)', '없어야 할 함수: ' || c.sig), ', ') into bad
  from _fn e full join _cur c on c.sig = e.sig where e.sig is null or c.sig is null;
  if bad is not null then raise exception '[사전검사] 함수 목록이 조사 때와 달라요: %', bad; end if;

  -- (2) 소유자 postgres, DEFINER 여부와 본문(md5)이 '변경 전' 또는 '이미 적용' 상태 중 하나와 정확히 같은가
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where c.owner <> 'postgres'
     or not ((c.definer = e.def_before and c.src_md5 = e.md5_before) or (c.definer = e.def_after and c.src_md5 = e.md5_after));
  if bad is not null then raise exception '[사전검사] 소유자·DEFINER·본문이 예상과 달라요: %', bad; end if;

  -- (3) 트리거 11개가 그대로 있고 켜져 있는가
  select string_agg(t.tbl || ':' || t.fn, ', ') into bad
  from (values ('auth.users','handle_new_user()'), ('public.place_checks','place_checks_after_insert()'),
               ('public.place_checks','place_checks_before_insert()'), ('public.place_comment_reports','place_comment_reports_before_insert()'),
               ('public.place_comments','place_comments_before_insert()'), ('public.place_comments','place_comments_count()'),
               ('public.place_reports','place_reports_before_insert()'), ('public.place_reports','place_reports_before_update()'),
               ('public.places','places_before_insert()'), ('public.places','places_before_update()'),
               ('public.places','places_fix_types()')) t(tbl, fn)
  where not exists (
    select 1 from pg_trigger g join pg_class k on k.oid = g.tgrelid
    where not g.tgisinternal and g.tgenabled = 'O'
      and k.relnamespace::regnamespace::text || '.' || k.relname = t.tbl
      and replace(g.tgfoid::regprocedure::text, 'public.', '') = t.fn);
  if bad is not null then raise exception '[사전검사] 트리거가 없거나 꺼져 있어요: %', bad; end if;
  select count(*) into n from pg_trigger g join pg_proc p on p.oid = g.tgfoid
  where not g.tgisinternal and p.pronamespace = 'public'::regnamespace;
  if n <> 11 then raise exception '[사전검사] public 함수를 쓰는 트리거 수가 11개가 아니에요(%개)', n; end if;

  -- (4) 열 기본값이 public 함수를 쓰지 않는가
  select string_agg(c.relname || '.' || a.attname, ', ') into bad
  from pg_attrdef ad join pg_class c on c.oid = ad.adrelid
  join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
  join pg_depend d on d.classid = 'pg_attrdef'::regclass and d.objid = ad.oid and d.refclassid = 'pg_proc'::regclass
  join pg_proc p on p.oid = d.refobjid and p.pronamespace = 'public'::regnamespace;
  if bad is not null then raise exception '[사전검사] 열 기본값에서 public 함수를 써요: %', bad; end if;

  -- (5) 정책 25개가 조사 때와 같은가 (places 등록 정책만 '이미 적용' 모양도 허용)
  select string_agg(coalesce(e.tablename || ':' || e.policyname, '없어야 할 정책: ' || c.tablename || ':' || c.policyname), ', ') into bad
  from _pol e full join (
    select schemaname::text, tablename::text, policyname::text, cmd::text, permissive::text,
           array_to_string(roles, ',') as roles, md5(qual) as qual_md5, md5(with_check) as check_md5
    from pg_policies where schemaname in ('public', 'storage')) c
    on c.schemaname = e.schemaname and c.tablename = e.tablename and c.policyname = e.policyname
  where e.policyname is null or c.policyname is null
     or (c.cmd, c.permissive, c.roles, c.qual_md5) is distinct from (e.cmd, e.permissive, e.roles, e.qual_md5)
     or (c.check_md5 is distinct from e.check_md5
         and not (c.policyname = 'places: 추가 요청'
                  and (select with_check from pg_policies where schemaname = 'public' and tablename = 'places'
                       and policyname = 'places: 추가 요청') like '%status = ''pending''%submitted_by%is_admin%'));
  if bad is not null then raise exception '[사전검사] 정책이 조사 때와 달라요: %', bad; end if;

  -- (6) postgres의 '함수' 기본 권한 행이 '변경 전' 또는 '이미 적용' 상태와 정확히 같은가
  if pg_temp.ppx_defacl_f() not in (
       (select string_agg(pg_temp.ppx_defacl_expect(t, s, a), ' | ' order by pg_temp.ppx_defacl_expect(t, s, a) collate "C") from _defacl_before where t = 'f'),
       (select string_agg(pg_temp.ppx_defacl_expect(t, s, a), ' | ' order by pg_temp.ppx_defacl_expect(t, s, a) collate "C") from _defacl_after where t = 'f')) then
    raise exception '[사전검사] 함수 기본 권한이 조사 때와 달라요: %', pg_temp.ppx_defacl_f();
  end if;

  -- (7) 함수 ACL이 '변경 전' 또는 '이미 적용' 상태와 정확히 같은가
  select string_agg(c.sig || ' = ' || pg_temp.ppx_acl(c.proacl), ', ') into bad
  from _fn e join _cur c using (sig)
  where pg_temp.ppx_acl(c.proacl) not in (pg_temp.ppx_acl_expect(e.was_public, e.was_anon, e.was_auth),
                                         pg_temp.ppx_acl_expect(false, e.to_anon, e.to_auth));
  if bad is not null then raise exception '[사전검사] 함수 권한이 조사 때와 달라요: %', bad; end if;
end $$;

-- ── 1) 트리거 3개를 소유자 권한으로 (본문은 판별 한 줄만 다름) ──
{''.join(trig_def(f, new_src[f], True) for f in TRIG3)}
-- ── 2) 함수 실행 권한: 정확한 시그니처(OID) 단위 ──
do $$
declare f record;
begin
  for f in select c.oid, e.to_anon, e.to_auth from _fn e join _cur c using (sig) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.oid::regprocedure);
    if f.to_auth then execute format('grant execute on function %s to authenticated', f.oid::regprocedure); end if;
    if f.to_anon then execute format('grant execute on function %s to anon', f.oid::regprocedure); end if;
  end loop;
end $$;

-- ── 3) 앞으로 postgres가 만드는 함수의 기본 권한 ──
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
alter default privileges for role postgres revoke execute on functions from public;

-- ── 4) search_path 통일 (pg_catalog 먼저, pg_temp 마지막 — PostgreSQL 문서 권장) ──
do $$
declare f record;
begin
  for f in select c.oid from _cur c loop
    execute format('alter function %s set search_path = pg_catalog, public, pg_temp', f.oid::regprocedure);
  end loop;
end $$;

-- ── 5) 세차장 등록 정책 ──
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (
    (status = 'pending' and submitted_by = (select auth.uid()))
    or (select public.is_admin())
  );

-- ── 6) 사후 검사: 예상과 한 건이라도 다르면 전체 취소 ──
do $$
declare bad text;
begin
  -- (1) 함수 ACL 완전 일치 (받는 역할·준 역할·권한·GRANT OPTION, 다른 역할 포함)
  select string_agg(c.sig || ' = ' || pg_temp.ppx_acl(c.proacl), ', ') into bad
  from _fn e join _cur c using (sig)
  where pg_temp.ppx_acl(c.proacl) <> pg_temp.ppx_acl_expect(false, e.to_anon, e.to_auth);
  if bad is not null then raise exception '[사후검사] 함수 ACL이 예상과 달라요: %', bad; end if;

  -- (2) 실제 실행 가능 여부 (PUBLIC·상속 경로 포함)
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where has_function_privilege('anon', c.oid, 'execute') <> e.to_anon
     or has_function_privilege('authenticated', c.oid, 'execute') <> e.to_auth
     or not has_function_privilege('service_role', c.oid, 'execute');
  if bad is not null then raise exception '[사후검사] 실제 실행 권한이 예상과 달라요: %', bad; end if;

  -- (3) 소유자·DEFINER·본문·search_path
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where c.owner <> 'postgres' or c.definer <> e.def_after or c.src_md5 <> e.md5_after
     or c.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp'];
  if bad is not null then raise exception '[사후검사] 소유자·DEFINER·본문·search_path가 예상과 달라요: %', bad; end if;

  -- (4) 기본 권한: postgres 함수 행은 예상대로, 나머지 모든 역할·종류의 행은 시작 때와 완전히 같음
  if pg_temp.ppx_defacl_f() <> (select string_agg(pg_temp.ppx_defacl_expect(t, s, a), ' | ' order by pg_temp.ppx_defacl_expect(t, s, a) collate "C") from _defacl_after where t = 'f') then
    raise exception '[사후검사] 함수 기본 권한이 예상과 달라요: %', pg_temp.ppx_defacl_f();
  end if;
  if exists ((select * from _defacl_keep
              except select d.defaclrole::regrole::text, d.defaclobjtype::text, d.defaclnamespace::regnamespace::text, pg_temp.ppx_acl(d.defaclacl)
                     from pg_default_acl d where not (d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f'))
             union all
             (select d.defaclrole::regrole::text, d.defaclobjtype::text, d.defaclnamespace::regnamespace::text, pg_temp.ppx_acl(d.defaclacl)
              from pg_default_acl d where not (d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f')
              except select * from _defacl_keep)) then
    raise exception '[사후검사] 건드리지 않아야 할 기본 권한이 바뀌었어요';
  end if;

  -- (5) 정책 25개 (places 등록 정책만 새 모양)
  select string_agg(coalesce(e.policyname, c.policyname), ', ') into bad
  from _pol e full join (
    select schemaname::text, tablename::text, policyname::text, cmd::text, permissive::text,
           array_to_string(roles, ',') as roles, md5(qual) as qual_md5, md5(with_check) as check_md5
    from pg_policies where schemaname in ('public', 'storage')) c
    on c.schemaname = e.schemaname and c.tablename = e.tablename and c.policyname = e.policyname
  where e.policyname is null or c.policyname is null
     or (c.cmd, c.permissive, c.roles, c.qual_md5) is distinct from (e.cmd, e.permissive, e.roles, e.qual_md5)
     or (c.policyname <> 'places: 추가 요청' and c.check_md5 is distinct from e.check_md5);
  if bad is not null then raise exception '[사후검사] 정책이 예상과 달라요: %', bad; end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'places' and policyname = 'places: 추가 요청'
                 and with_check like '%status = ''pending''%submitted_by%auth.uid()%is_admin()%') then
    raise exception '[사후검사] places 등록 정책 내용이 예상과 달라요';
  end if;
end $$;

commit;

-- ── 결과 표 (커밋 후 확인용) ──
select replace(p.oid::regprocedure::text, 'public.', '') as 함수,
       p.prosecdef as definer,
       has_function_privilege('anon', p.oid, 'execute') as 비로그인,
       has_function_privilege('authenticated', p.oid, 'execute') as 로그인,
       has_function_privilege('service_role', p.oid, 'execute') as service_role,
       p.proacl::text as acl
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
order by 3 desc, 4 desc, 1;
"""
open(OUT + 'migrate_2026-11-12.sql', 'w').write(MIG)

# ── 되돌리기 ─────────────────────────────────────────────
RB = f"""-- 2026-11-12 보안 수정 되돌리기
-- migrate_2026-11-12.sql 을 실행한 뒤 문제가 생겼을 때만 사용합니다.
-- 조사 당시(2026-11-12 18:47) 상태로 되돌립니다:
--   트리거 3개 본문·INVOKER, 함수별 PUBLIC/anon/authenticated 권한, search_path, 새 함수 기본 권한, places 등록 정책.
--   service_role·소유자 권한은 건드리지 않습니다.
-- 끝에서 함수 ACL이 '변경 전'과 완전히 같은지 스스로 확인하고, 다르면 전체 취소합니다.
-- 실행 후 verify_rollback_2026-11-12.sql 로 원래대로 돌아왔는지 한 번 더 확인하세요.

begin;
set local search_path = pg_catalog, public;

{ACL_NORM}
create temp table _fn on commit drop as
with {FN_CTE}
select * from fn_expect;
create or replace temp view _cur as with {CUR_FN} select * from cur_fn;

-- 사전 검사: 함수 목록이 같고, 각 함수가 '변경 전' 또는 '적용 후' 상태 중 하나여야 함 (조용히 건너뛰지 않음)
do $$
declare bad text;
begin
  select string_agg(coalesce(e.sig || ' (없어짐)', '조사 때 없던 함수: ' || c.sig), ', ') into bad
  from _fn e full join _cur c on c.sig = e.sig where e.sig is null or c.sig is null;
  if bad is not null then
    raise exception '[되돌리기 중단] 함수 목록이 조사 때와 달라요: %  → 수동 대응 필요(검토 문서 5장)', bad;
  end if;
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where c.owner <> 'postgres'
     or not ((c.definer = e.def_before and c.src_md5 = e.md5_before) or (c.definer = e.def_after and c.src_md5 = e.md5_after));
  if bad is not null then
    raise exception '[되돌리기 중단] 소유자·DEFINER·본문이 예상 밖이에요: %  → 수동 대응 필요', bad;
  end if;
end $$;

-- 1) 트리거 3개를 원래 본문·호출자 권한(INVOKER)으로
{''.join(trig_def(f, orig_src[f], False) for f in TRIG3)}
-- 2) 함수 권한을 조사 때와 똑같이 (PUBLIC/anon/authenticated만 다시 줌)
do $$
declare f record;
begin
  for f in select c.oid, e.* from _fn e join _cur c using (sig) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.oid::regprocedure);
    if f.was_public then execute format('grant execute on function %s to public', f.oid::regprocedure); end if;
    if f.was_anon   then execute format('grant execute on function %s to anon', f.oid::regprocedure); end if;
    if f.was_auth   then execute format('grant execute on function %s to authenticated', f.oid::regprocedure); end if;
  end loop;
end $$;

-- 3) search_path를 함수별 원래 값으로 (없던 것은 reset)
do $$
declare f record;
begin
  for f in select c.oid, e.sp_before from _fn e join _cur c using (sig) loop
    if f.sp_before is null then
      execute format('alter function %s reset search_path', f.oid::regprocedure);
    else
      execute format('alter function %s set search_path = %s', f.oid::regprocedure, f.sp_before);
    end if;
  end loop;
end $$;

-- 4) 새 함수 기본 권한을 원래대로
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated;
alter default privileges for role postgres grant execute on functions to public;

-- 5) places 등록 정책을 원래대로
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (true);

-- 6) 스스로 확인: 함수 ACL·DEFINER·본문·search_path가 '변경 전'과 완전히 같은가
do $$
declare bad text;
begin
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where pg_temp.ppx_acl(c.proacl) <> pg_temp.ppx_acl_expect(e.was_public, e.was_anon, e.was_auth)
     or c.definer <> e.def_before or c.src_md5 <> e.md5_before
     or c.proconfig is distinct from (case when e.sp_before is null then null else array['search_path=' || e.sp_before] end);
  if bad is not null then raise exception '[되돌리기 확인 실패] 원래와 다른 함수: %  → 전체 취소됨', bad; end if;
end $$;

commit;
"""
open(OUT + 'rollback_2026-11-12.sql', 'w').write(RB)

# ── 되돌리기 확인 (SELECT 하나) ───────────────────────────────
def acl_text_sql(expr):
    return f"""(select case when {expr} is null then 'NULL(기본값)' else coalesce((
      select string_agg(x, ',' order by x collate "C") from (
        select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
               || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
               || '/' || pg_get_userbyid(a.grantor) as x
        from aclexplode({expr}) a) z), '(빈 ACL)') end)"""
def acl_expect_sql(pub, an, au):
    return f"""(select string_agg(x, ',' order by x collate "C") from unnest(array['postgres=EXECUTE/postgres', 'service_role=EXECUTE/postgres']
      || case when {pub} then array['PUBLIC=EXECUTE/postgres'] else '{{}}'::text[] end
      || case when {an}  then array['anon=EXECUTE/postgres'] else '{{}}'::text[] end
      || case when {au}  then array['authenticated=EXECUTE/postgres'] else '{{}}'::text[] end) x)"""

VR = f"""-- 2026-11-12 되돌리기 확인 (읽기 전용 — 아무것도 바꾸지 않는 SELECT 한 개)
-- 지금 DB가 조사 당시(2026-11-12 18:47, 보안 수정 '전') 상태와 완전히 같은지 항목별 PASS / FAIL.
-- 첫 줄 '요약'이 PASS면 원래대로 돌아온 것입니다.
-- 비교 항목
--   함수 42개: 목록, 소유자, DEFINER, 본문(md5), search_path,
--              ACL 완전 일치(받는 역할·준 역할·권한·GRANT OPTION — service_role·postgres·그 밖의 모든 역할 포함),
--              anon·authenticated·service_role 실제 실행 가능 여부
--   기본 권한: postgres 역할의 모든 행 (스키마별 + 전역)
--   정책 25개: 목록, 명령, PERMISSIVE, 대상 역할, USING, WITH CHECK
with {FN_CTE},
{POL_CTE},
defacl_before(t, s, a) as (values
  {defacl_values(DEFACL_BEFORE)}
),
{CUR_FN},
cur_pol as (
  select schemaname::text, tablename::text, policyname::text, cmd::text, permissive::text,
         array_to_string(roles, ',') as roles, md5(qual) as qual_md5, md5(with_check) as check_md5,
         qual, with_check
  from pg_policies where schemaname in ('public', 'storage')
),
res(구분, 대상, 결과, 내용) as (
  select '함수 목록', coalesce(e.sig, c.sig), 'FAIL',
         case when c.sig is null then '조사 때 있던 함수가 없음' else '조사 때 없던 함수가 있음' end
  from fn_expect e full join cur_fn c on c.sig = e.sig
  where e.sig is null or c.sig is null
  union all
  select '함수', e.sig, case when x.p = '' then 'PASS' else 'FAIL' end,
         case when x.p = '' then 'ACL ' || x.acl_now else x.p end
  from fn_expect e join cur_fn c on c.sig = e.sig
  cross join lateral (select {acl_text_sql('c.proacl')} as acl_now,
                             {acl_expect_sql('e.was_public', 'e.was_anon', 'e.was_auth')} as acl_exp) a
  cross join lateral (select a.acl_now, concat_ws(' / ',
      case when c.owner <> 'postgres' then '소유자=' || c.owner end,
      case when c.definer <> e.def_before then 'DEFINER 다름(지금 ' || c.definer || ')' end,
      case when c.src_md5 <> e.md5_before then '본문 다름' end,
      case when a.acl_now <> a.acl_exp then 'ACL 다름: 지금 ' || a.acl_now || ' / 원래 ' || a.acl_exp end,
      case when has_function_privilege('anon', c.oid, 'execute') <> (e.was_public or e.was_anon) then 'anon 실제권한 다름' end,
      case when has_function_privilege('authenticated', c.oid, 'execute') <> (e.was_public or e.was_auth) then 'authenticated 실제권한 다름' end,
      case when not has_function_privilege('service_role', c.oid, 'execute') then 'service_role 실행 불가' end,
      case when c.proconfig is distinct from (case when e.sp_before is null then null else array['search_path=' || e.sp_before] end)
           then 'search_path=' || coalesce(array_to_string(c.proconfig, ';'), '(없음)') || ' (원래 ' || coalesce(e.sp_before, '없음') || ')' end
    ) as p) x
  union all
  -- 기본 권한: postgres 역할의 모든 행을 행 단위로 비교 (빠진 행·늘어난 행·ACL 다름)
  select '기본 권한', coalesce(b.t || '/' || b.s, n.t || '/' || n.s),
         case when b.acl is not distinct from n.acl then 'PASS' else 'FAIL' end,
         case when b.acl is not distinct from n.acl then n.acl
              else '지금 ' || coalesce(n.acl, '(행 없음)') || ' / 원래 ' || coalesce(b.acl, '(행 없음)') end
  from (select t, s, {acl_text_sql('a')} as acl from defacl_before) b
  full join (select d.defaclobjtype::text as t,
                    case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end as s,
                    {acl_text_sql('d.defaclacl')} as acl
             from pg_default_acl d where d.defaclrole = 'postgres'::regrole) n on n.t = b.t and n.s = b.s
  union all
  -- 정책 25개
  select '정책', coalesce(e.tablename || ': ' || e.policyname, c.tablename || ': ' || c.policyname),
         case when e.policyname is not null and c.policyname is not null
               and (c.cmd, c.permissive, c.roles, c.qual_md5, c.check_md5)
                   is not distinct from (e.cmd, e.permissive, e.roles, e.qual_md5, e.check_md5) then 'PASS' else 'FAIL' end,
         case when c.policyname is null then '조사 때 있던 정책이 없음'
              when e.policyname is null then '조사 때 없던 정책이 있음'
              else c.cmd || ' / ' || c.permissive || ' / ' || c.roles || ' / USING ' || coalesce(c.qual, '(없음)')
                   || ' / CHECK ' || coalesce(c.with_check, '(없음)') end
  from pol_expect e full join cur_pol c
    on c.schemaname = e.schemaname and c.tablename = e.tablename and c.policyname = e.policyname
)
select 구분, 대상, 결과, 내용 from (
  select '요약' as 구분, '전체' as 대상,
         case when count(*) filter (where 결과 = 'FAIL') = 0 then 'PASS' else 'FAIL' end as 결과,
         count(*) filter (where 결과 = 'PASS') || '개 PASS, ' || count(*) filter (where 결과 = 'FAIL') || '개 FAIL' as 내용,
         0 as ord
  from res
  union all
  select 구분, 대상, 결과, 내용, case when 결과 = 'FAIL' then 1 else 2 end from res
) t order by ord, 구분, 대상;
"""
open(OUT + 'verify_rollback_2026-11-12.sql', 'w').write(VR)

# 테스트 DB를 '조사 당시' 상태로 맞추는 스크립트 (기본 권한 6행 포함)
SHIM_ACL = "\n".join(
    f"alter default privileges for role postgres in schema {s} grant {'all on tables' if t=='r' else 'all on sequences' if t=='S' else 'execute on functions'} to postgres, anon, authenticated, service_role;"
    for t, s, a in DEFACL_BEFORE)
open('shim_defacl.sql', 'w').write(SHIM_ACL + "\n")
print('ok', len(rows), 'functions,', len(pols), 'policies')
