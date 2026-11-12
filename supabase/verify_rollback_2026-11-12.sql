-- 2026-11-12 되돌리기 확인 (읽기 전용 — 아무것도 바꾸지 않는 SELECT 한 개)
-- 지금 DB가 조사 당시(2026-11-12 18:47, 보안 수정 '전') 상태와 같은지 항목별로 PASS / FAIL 을 보여줍니다.
-- rollback_2026-11-12.sql 실행 뒤에 Run 하세요. 첫 줄 '요약'이 PASS면 원래대로 돌아온 것입니다.
-- (시그니처 표기는 search_path에 따라 달라질 수 있어 'public.' 을 떼고 비교합니다)

with e(sig, definer, was_public, was_anon, was_auth, was_sp, to_anon, to_auth) as (values
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
    ('start_claim()'                                                            , true , true, false, true, 'public', false, true)
),
c as (
  select p.oid, replace(p.oid::regprocedure::text, 'public.', '') as sig, p.prosecdef as definer,
         pg_get_userbyid(p.proowner) as owner, p.proconfig, p.proacl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
),
acl as (
  select c.oid,
    bool_or(a.grantee = 0) as has_public,
    bool_or(a.grantee = 'anon'::regrole) as has_anon,
    bool_or(a.grantee = 'authenticated'::regrole) as has_auth,
    bool_or(a.grantee = 'service_role'::regrole) as has_service
  from c left join lateral aclexplode(coalesce(c.proacl, '{}'::aclitem[])) a on a.privilege_type = 'EXECUTE'
  group by c.oid
),
res(구분, 대상, 결과, 내용) as (
  -- 함수 목록 (빠지거나 늘어난 것)
  select '함수 목록', coalesce(e.sig, c.sig), 'FAIL',
         case when c.sig is null then '조사 때 있던 함수가 없음' else '조사 때 없던 함수가 있음' end
  from e full join c on c.sig = e.sig
  where e.sig is null or c.sig is null
  union all
  -- 함수별 비교
  select '함수', e.sig, case when x.p = '' then 'PASS' else 'FAIL' end, x.p
  from e join c on c.sig = e.sig join acl on acl.oid = c.oid
  cross join lateral (select concat_ws(' / ',
      case when c.owner <> 'postgres' then '소유자=' || c.owner end,
      case when c.definer <> e.definer then 'DEFINER 다름' end,
      case when c.proacl is null then 'ACL이 NULL(기본값)으로 바뀜' end,
      case when coalesce(acl.has_public, false) <> e.was_public then 'PUBLIC 권한 다름' end,
      case when coalesce(acl.has_anon, false) <> e.was_anon then 'anon 직접권한 다름' end,
      case when coalesce(acl.has_auth, false) <> e.was_auth then 'authenticated 직접권한 다름' end,
      case when has_function_privilege('anon', c.oid, 'execute') <> (e.was_public or e.was_anon) then 'anon 실제권한 다름' end,
      case when has_function_privilege('authenticated', c.oid, 'execute') <> (e.was_public or e.was_auth) then 'authenticated 실제권한 다름' end,
      case when not coalesce(acl.has_service, false) then 'service_role 권한 없음' end,
      case when c.proconfig is distinct from (case when e.was_sp is null then null else array['search_path=' || e.was_sp] end)
           then 'search_path=' || coalesce(array_to_string(c.proconfig, ';'), '(없음)') || ' (원래 ' || coalesce(e.was_sp, '없음') || ')' end
    ) as p) x
  union all
  -- 기본 권한: postgres / public 스키마 / 함수 = anon, authenticated, postgres, service_role
  select '기본 권한', 'postgres / public 스키마 / 함수',
    case when (select array_agg(r.rolname::text order by r.rolname)
               from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a join pg_roles r on r.oid = a.grantee
               where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f'
                 and d.defaclnamespace = 'public'::regnamespace and a.privilege_type = 'EXECUTE')
              = array['anon','authenticated','postgres','service_role'] then 'PASS' else 'FAIL' end,
    coalesce((select d.defaclacl::text from pg_default_acl d where d.defaclrole = 'postgres'::regrole
              and d.defaclobjtype = 'f' and d.defaclnamespace = 'public'::regnamespace), '(행 없음)')
  union all
  -- 기본 권한: postgres / 전역 — 조사 때는 행이 없었음(= PUBLIC 기본 허용)
  select '기본 권한', 'postgres / 전역 / 함수',
    case when n = 0 then 'PASS' else 'FAIL' end,
    case when n = 0 then '행 없음 (원래와 같음)' else '전역 기본 권한 행이 남아 있음: ' || acl end
  from (select count(*) n, string_agg(d.defaclacl::text, ' ') acl from pg_default_acl d
        where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f' and d.defaclnamespace = 0) s
  union all
  -- places 등록 정책 (이름·명령·종류·역할·USING·WITH CHECK 전체)
  select '정책', 'places: 추가 요청',
    case when exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'places'
           and policyname = 'places: 추가 요청' and cmd = 'INSERT' and permissive = 'PERMISSIVE'
           and roles = '{authenticated}' and qual is null and with_check = 'true') then 'PASS' else 'FAIL' end,
    coalesce((select cmd || ' / ' || permissive || ' / ' || roles::text || ' / USING ' || coalesce(qual, '(없음)')
                     || ' / CHECK ' || coalesce(with_check, '(없음)')
              from pg_policies where schemaname = 'public' and tablename = 'places' and policyname = 'places: 추가 요청'), '정책 없음')
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
