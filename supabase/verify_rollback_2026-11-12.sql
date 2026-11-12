-- 2026-11-12 되돌리기 확인 (읽기 전용 — 아무것도 바꾸지 않는 SELECT 한 개)
-- 지금 DB가 조사 당시(2026-11-12 18:47, 보안 수정 '전') 상태와 완전히 같은지 항목별 PASS / FAIL.
-- 첫 줄 '요약'이 PASS면 원래대로 돌아온 것입니다.
-- 비교 항목
--   함수 42개: 목록, 소유자, DEFINER, 본문(md5), search_path,
--              ACL 완전 일치(받는 역할·준 역할·권한·GRANT OPTION — service_role·postgres·그 밖의 모든 역할 포함),
--              anon·authenticated·service_role 실제 실행 가능 여부
--   기본 권한: postgres 역할의 모든 행 (스키마별 + 전역)
--   정책 25개: 목록, 명령, PERMISSIVE, 대상 역할, USING, WITH CHECK
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
),
pol_expect(schemaname, tablename, policyname, cmd, permissive, roles, qual_md5, check_md5) as (values
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
),
defacl_before(t, s, a) as (values
  ('r', 'public', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('f', 'public', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('S', 'public', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[]),
  ('r', 'storage', '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[]),
  ('f', 'storage', '{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[]),
  ('S', 'storage', '{postgres=rwU/postgres,anon=rwU/postgres,authenticated=rwU/postgres,service_role=rwU/postgres}'::aclitem[])
),
cur_fn as (
  select p.oid, replace(p.oid::regprocedure::text, 'public.', '') as sig, p.prosecdef as definer,
         pg_get_userbyid(p.proowner) as owner, p.proconfig, p.proacl, md5(p.prosrc) as src_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
),
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
  cross join lateral (select (select case when c.proacl is null then 'NULL(기본값)' else coalesce((
      select string_agg(x, ',' order by x collate "C") from (
        select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
               || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
               || '/' || pg_get_userbyid(a.grantor) as x
        from aclexplode(c.proacl) a) z), '(빈 ACL)') end) as acl_now,
                             (select string_agg(x, ',' order by x collate "C") from unnest(array['postgres=EXECUTE/postgres', 'service_role=EXECUTE/postgres']
      || case when e.was_public then array['PUBLIC=EXECUTE/postgres'] else '{}'::text[] end
      || case when e.was_anon  then array['anon=EXECUTE/postgres'] else '{}'::text[] end
      || case when e.was_auth  then array['authenticated=EXECUTE/postgres'] else '{}'::text[] end) x) as acl_exp) a
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
  from (select t, s, (select case when a is null then 'NULL(기본값)' else coalesce((
      select string_agg(x, ',' order by x collate "C") from (
        select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
               || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
               || '/' || pg_get_userbyid(a.grantor) as x
        from aclexplode(a) a) z), '(빈 ACL)') end) as acl from defacl_before) b
  full join (select d.defaclobjtype::text as t,
                    case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end as s,
                    (select case when d.defaclacl is null then 'NULL(기본값)' else coalesce((
      select string_agg(x, ',' order by x collate "C") from (
        select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
               || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
               || '/' || pg_get_userbyid(a.grantor) as x
        from aclexplode(d.defaclacl) a) z), '(빈 ACL)') end) as acl
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
