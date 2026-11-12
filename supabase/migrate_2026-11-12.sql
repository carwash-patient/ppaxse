-- 2026-11-12 보안 수정 (4차 검토 반영본)
--
-- 무엇을 바꾸나
--  1) 함수 실행 권한: 정확한 시그니처 단위로 필요한 역할에만 (비로그인 4개 / 로그인 20개 / 나머지 없음)
--  2) 트리거 3개(places·place_reports·place_checks 등록 전 검사)를 소유자 권한(SECURITY DEFINER)으로 바꿔
--     안에서 쓰는 도우미 4개(ppx_guard, ppx_burst_guard, my_pending_count, my_pending_reports)를
--     이용자가 직접 부를 수 없게 닫음. 본문은 '앱 요청인지' 판별하는 한 줄만 바뀜:
--       current_user not in ('anon', 'authenticated')
--     → coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated')
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

create or replace function pg_temp.ppx_acl(acl aclitem[]) returns text language sql stable as $f$
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

create temp table _fn on commit drop as
with fn_expect(sig, def_before, def_after, was_public, was_anon, was_auth, sp_before, to_anon, to_auth, md5_before, md5_after) as (values
  ('admin_abuse_summary()', true, true, false, false, true, 'public', false, true, '28c4b04e49ce3233d837ac56e7078e24', '28c4b04e49ce3233d837ac56e7078e24'),
  ('admin_block(uuid,boolean)', true, true, true, false, true, 'public', false, true, 'faca4dda056cdb69c2a5e0698579324f', 'faca4dda056cdb69c2a5e0698579324f'),
  ('admin_block_commenter(bigint)', true, true, true, false, true, 'public', false, true, '51fd99230035956506ea98047c05b556', '51fd99230035956506ea98047c05b556'),
  ('admin_channel_stats(integer)', true, true, false, false, true, 'public', false, true, 'eab60d257282f3a5a95b1401f9d2c0b4', 'eab60d257282f3a5a95b1401f9d2c0b4'),
  ('admin_event_draw(date,boolean)', true, true, false, false, true, 'public', false, true, '8c44794dd052f7a884b79b9121f2b66c', '8c44794dd052f7a884b79b9121f2b66c'),
  ('admin_event_entries(timestamp with time zone,timestamp with time zone)', true, true, true, false, true, 'public', false, true, '4a44c3366b44ef03d36ba2ab47914bc2', '4a44c3366b44ef03d36ba2ab47914bc2'),
  ('admin_event_week(date)', true, true, false, false, true, 'public', false, true, '6810c94a426351ae8561ffabdcfad369', '6810c94a426351ae8561ffabdcfad369'),
  ('admin_type_votes()', true, true, false, false, true, 'public', false, true, '490a9f8f7ab296aff139ada4512f349c', '490a9f8f7ab296aff139ada4512f349c'),
  ('admin_visit_stats(integer)', true, true, false, false, true, 'public', false, true, '5168b4bd03d20a7d21c1f8e6f5bd4042', '5168b4bd03d20a7d21c1f8e6f5bd4042'),
  ('delete_my_account()', true, true, false, false, true, 'public', false, true, '9bdb043e72e2cf3c56863ef2c30bcd72', '9bdb043e72e2cf3c56863ef2c30bcd72'),
  ('finish_claim(uuid)', true, true, true, false, true, 'public', false, true, '118f3b9136c39d272e18476e27d5cb19', '118f3b9136c39d272e18476e27d5cb19'),
  ('handle_new_user()', true, true, true, true, true, 'public', false, false, 'f4b09971e3d3e7d7d19ce238176cf0b3', 'f4b09971e3d3e7d7d19ce238176cf0b3'),
  ('is_admin()', true, true, true, true, true, 'public', true, true, 'd5808500f03173b4303120b0ddea4332', 'd5808500f03173b4303120b0ddea4332'),
  ('my_pending_count()', true, true, true, true, true, 'public', false, false, '9bcbc3181520bafcc785adbf1f0f92ba', '9bcbc3181520bafcc785adbf1f0f92ba'),
  ('my_pending_reports()', true, true, true, true, true, 'public', false, false, '580a40f8629ae47258286f3719b2c87e', '580a40f8629ae47258286f3719b2c87e'),
  ('place_checks_after_insert()', true, true, true, true, true, 'public', false, false, 'c73057efaa1b1c48721a8a27feae7945', 'c73057efaa1b1c48721a8a27feae7945'),
  ('place_checks_before_insert()', false, true, true, true, true, null, false, false, '78fb038706663939306fae86af3a80f0', 'e5c5bee930aadac68c3d831cffcadf04'),
  ('place_comment_reports_before_insert()', true, true, false, false, false, 'pg_catalog, public', false, false, '7d9eacbbe37c727a6a08b4943806892a', '7d9eacbbe37c727a6a08b4943806892a'),
  ('place_comments_before_insert()', true, true, false, false, false, 'pg_catalog, public', false, false, 'b1e0b24e00755c55b48709908a8932f3', 'b1e0b24e00755c55b48709908a8932f3'),
  ('place_comments_count()', true, true, true, true, true, 'public', false, false, 'c20e5e03ed94fda829dff20fa5d30eec', 'c20e5e03ed94fda829dff20fa5d30eec'),
  ('place_reports_before_insert()', false, true, true, true, true, null, false, false, '55e1a7a64024e77f2ca8d6fadd88ac66', 'c32c958bd059dc299736ec6d02b6a78c'),
  ('place_reports_before_update()', false, false, true, true, true, null, false, false, 'e0536fb90addb9ee57b835578ef21f53', 'e0536fb90addb9ee57b835578ef21f53'),
  ('places_before_insert()', false, true, true, true, true, null, false, false, 'fe163cb59f37f8a38635be3c9e353713', '50f1cb02972a06be3572fa773b91038d'),
  ('places_before_update()', false, false, true, true, true, null, false, false, '6132ae4520ddde55c7275c13621aa399', '6132ae4520ddde55c7275c13621aa399'),
  ('places_fix_types()', false, false, true, true, true, null, false, false, 'bfce81346ba86b6788de80e1ccebc0a0', 'bfce81346ba86b6788de80e1ccebc0a0'),
  ('ppx_auto_draw(timestamp with time zone)', true, true, false, false, false, 'public', false, false, '0b8f6aba7a44ad360212a6cfcd98ae37', '0b8f6aba7a44ad360212a6cfcd98ae37'),
  ('ppx_burst_guard(text,bigint)', true, true, false, false, true, 'public', false, false, '71f7b8b38efaab267af6ab1c8edf8447', '71f7b8b38efaab267af6ab1c8edf8447'),
  ('ppx_enter_event(bigint)', true, true, false, false, true, 'public', false, true, '936e700bba0c8a10fe26d0f9079ca073', '936e700bba0c8a10fe26d0f9079ca073'),
  ('ppx_entry_valid(event_entries)', true, true, false, false, false, 'public', false, false, '08618e2d3a9c70748407222cd0f062b2', '08618e2d3a9c70748407222cd0f062b2'),
  ('ppx_event_draw_at(date)', false, false, true, true, true, null, false, false, 'f7fffc98dacf0af77d9512347aedee7d', 'f7fffc98dacf0af77d9512347aedee7d'),
  ('ppx_event_draw_run(date)', true, true, false, false, false, 'public', false, false, 'c99ed9f41f39e2431f2818a95a8242df', 'c99ed9f41f39e2431f2818a95a8242df'),
  ('ppx_event_start()', false, false, true, true, true, null, false, false, 'd1b2fd2aee83f03c3b5889a2b3db9daf', 'd1b2fd2aee83f03c3b5889a2b3db9daf'),
  ('ppx_event_status()', true, true, false, true, true, 'public', true, true, '5f3b2d34f4635a56c9cc09551caad740', '5f3b2d34f4635a56c9cc09551caad740'),
  ('ppx_event_week(timestamp with time zone)', false, false, true, true, true, null, false, false, '63b61e3d435f2d9796f23c45c74b0c56', '63b61e3d435f2d9796f23c45c74b0c56'),
  ('ppx_guard(text)', true, true, true, true, true, 'public', false, false, '724560cfdbf3d60d6da872f761ddfde7', '724560cfdbf3d60d6da872f761ddfde7'),
  ('ppx_is_member(uuid)', true, true, false, false, false, 'public', false, false, 'c17b6f9270ac5dbb4b79b53dbf24bd8d', 'c17b6f9270ac5dbb4b79b53dbf24bd8d'),
  ('ppx_log_block(text,text)', true, true, false, false, true, 'public', false, true, 'dc9a6b23e23da87a1f2e1184f6a7ce86', 'dc9a6b23e23da87a1f2e1184f6a7ce86'),
  ('ppx_precheck(text,bigint)', true, true, false, false, true, 'public', false, true, '9747c02ea5ba9c2250bfbac879b6db54', '9747c02ea5ba9c2250bfbac879b6db54'),
  ('ppx_stats()', true, true, true, true, true, 'public', true, true, '773f76fdf39d08c06ad7d232ae90831e', '773f76fdf39d08c06ad7d232ae90831e'),
  ('ppx_track(uuid,text,text)', true, true, false, true, true, 'public', true, true, 'e05f12181508e0f5a14918574bab3c30', 'e05f12181508e0f5a14918574bab3c30'),
  ('ppx_vote_type(bigint,text,text[])', true, true, false, false, true, 'public', false, true, '04a4eef7317d157e377b12c967d0fa05', '04a4eef7317d157e377b12c967d0fa05'),
  ('start_claim()', true, true, true, false, true, 'public', false, true, '6b58648198bbe72df928bb69aa486e85', '6b58648198bbe72df928bb69aa486e85')
)
select * from fn_expect;
create temp table _pol on commit drop as
with pol_expect(schemaname, tablename, policyname, cmd, permissive, roles, qual_md5, check_md5) as (values
  ('public', 'event_entries', 'entries: 본인·운영자 조회', 'SELECT', 'PERMISSIVE', 'authenticated', '31e4db3484f0ebfcd462f95fd8166243', null),
  ('public', 'event_winners', 'winners: 운영자 조회', 'SELECT', 'PERMISSIVE', 'authenticated', 'f5a6f165dae5375977a3ceadb54f3eb6', null),
  ('public', 'place_checks', 'checks: 조회', 'SELECT', 'PERMISSIVE', 'public', '6af153ac401c7672c3dd0388fce6cd4a', null),
  ('public', 'place_checks', 'checks: 확인', 'INSERT', 'PERMISSIVE', 'authenticated', null, 'b5f6fa4952f86b5add7940789070c602'),
  ('public', 'place_comment_reports', 'comment reports: 신고 추가', 'INSERT', 'PERMISSIVE', 'authenticated', null, 'b326b5062b2f0e69046810717534cb09'),
  ('public', 'place_comment_reports', 'comment reports: 운영자 조회', 'SELECT', 'PERMISSIVE', 'authenticated', 'f5a6f165dae5375977a3ceadb54f3eb6', null),
  ('public', 'place_comment_reports', 'comment reports: 운영자 처리', 'UPDATE', 'PERMISSIVE', 'authenticated', 'f5a6f165dae5375977a3ceadb54f3eb6', 'f5a6f165dae5375977a3ceadb54f3eb6'),
  ('public', 'place_comments', 'comments: 쓰기', 'INSERT', 'PERMISSIVE', 'authenticated', null, 'a72a3d76eabe6ec4ae16fd1a98417cca'),
  ('public', 'place_comments', 'comments: 운영자 삭제', 'DELETE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', null),
  ('public', 'place_comments', 'comments: 운영자 숨기기', 'UPDATE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', '5533b5b0c6cb6bc41c771c2f6a2c8f37'),
  ('public', 'place_comments', 'comments: 조회', 'SELECT', 'PERMISSIVE', 'public', '9bdb40625fcbbea8f297833f71adb187', null),
  ('public', 'place_reports', 'reports: 운영자 삭제', 'DELETE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', null),
  ('public', 'place_reports', 'reports: 운영자 처리', 'UPDATE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', '5533b5b0c6cb6bc41c771c2f6a2c8f37'),
  ('public', 'place_reports', 'reports: 제보', 'INSERT', 'PERMISSIVE', 'authenticated', null, '92e873c407396e13a3663fa12c1184d9'),
  ('public', 'place_reports', 'reports: 조회', 'SELECT', 'PERMISSIVE', 'public', '24cd17447b8f642ebd3796e687625ef1', null),
  ('public', 'places', 'places: 운영자 삭제', 'DELETE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', null),
  ('public', 'places', 'places: 운영자 수정', 'UPDATE', 'PERMISSIVE', 'public', '5533b5b0c6cb6bc41c771c2f6a2c8f37', '5533b5b0c6cb6bc41c771c2f6a2c8f37'),
  ('public', 'places', 'places: 조회', 'SELECT', 'PERMISSIVE', 'public', '2009cd9a39b36a969631a65608a95a8e', null),
  ('public', 'places', 'places: 추가 요청', 'INSERT', 'PERMISSIVE', 'authenticated', null, 'b326b5062b2f0e69046810717534cb09'),
  ('public', 'ppx_abuse_log', 'abuse log: 운영자 조회', 'SELECT', 'PERMISSIVE', 'authenticated', 'f5a6f165dae5375977a3ceadb54f3eb6', null),
  ('public', 'profiles', 'profiles: 본인 수정', 'UPDATE', 'PERMISSIVE', 'public', 'ea1f5df45681e1946eaa85c22966d773', 'ea1f5df45681e1946eaa85c22966d773'),
  ('public', 'profiles', 'profiles: 본인 조회', 'SELECT', 'PERMISSIVE', 'public', '16ec0c4333f3021fd7cd74f94a6f4b68', null),
  ('storage', 'objects', 'report-photos: 보기', 'SELECT', 'PERMISSIVE', 'authenticated', 'a15f041e254c30d74f6f0d918fba97ef', null),
  ('storage', 'objects', 'report-photos: 올리기', 'INSERT', 'PERMISSIVE', 'authenticated', null, '5be1cda29cf41dfb2a0814cd43de4d29'),
  ('storage', 'objects', 'report-photos: 지우기', 'DELETE', 'PERMISSIVE', 'authenticated', 'afd8696eb6e7d857a8cdddfc2efb6baa', null)
)
select * from pol_expect;
create temp table _defacl_before (t text, s text, a aclitem[]) on commit drop;
insert into _defacl_before values
  ('r', 'public', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('f', 'public', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('S', 'public', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[]),
  ('r', 'storage', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('f', 'storage', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('S', 'storage', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[]);
create temp table _defacl_after (t text, s text, a aclitem[]) on commit drop;
insert into _defacl_after values
  ('r', 'public', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('S', 'public', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[]),
  ('r', 'storage', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('f', 'storage', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('S', 'storage', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[]),
  ('f', 'public', '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('f', '-', '{postgres=X/postgres}'::aclitem[]);
create or replace temp view _cur as with cur_fn as (
  select p.oid, replace(p.oid::regprocedure::text, 'public.', '') as sig, p.prosecdef as definer,
         pg_get_userbyid(p.proowner) as owner, p.proconfig, p.proacl, md5(p.prosrc) as src_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
) select * from cur_fn;
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
create or replace function public.places_before_insert()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fn$
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated') or public.is_admin() then
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
end $fn$;
create or replace function public.place_reports_before_insert()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fn$
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated') then
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
end $fn$;
create or replace function public.place_checks_before_insert()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fn$
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated') then return new; end if;
  new.user_id := auth.uid();
  new.created_on := current_date;
  new.created_at := now();
  perform public.ppx_guard('check');
  return new;
end $fn$;

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
