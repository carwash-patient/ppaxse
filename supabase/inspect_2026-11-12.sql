-- 2026-11-12 보안 수정 전 현황 조사 (읽기 전용 — SELECT 한 개, 아무것도 바꾸지 않음)
-- 결과 한 칸(JSON)이 그대로 '변경 전 백업' 자료가 됩니다.
-- 2차(18:47)에 함수·정책·트리거·기본값·기본 권한·확장·크론을 조사했고,
-- 3차 보완으로 시그니처·역할별 실제 권한·ACL 항목·테이블 RLS/권한·profiles 열 권한·스키마 권한·이름 겹침을 더했습니다.
select jsonb_pretty(jsonb_build_object(
  'run_as', current_user,
  'server_version', current_setting('server_version'),
  'overloads', (
    select coalesce(jsonb_agg(proname), '[]'::jsonb) from (
      select p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      group by p.proname having count(*) > 1) x
  ),
  'function_privs', (
    select jsonb_agg(jsonb_build_object(
      'sig', replace(p.oid::regprocedure::text, 'public.', ''),
      'definer', p.prosecdef,
      'owner', pg_get_userbyid(p.proowner),
      'config', p.proconfig,
      'acl_null', p.proacl is null,
      'acl_entries', (select jsonb_agg(case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
                                       || '<-' || pg_get_userbyid(a.grantor) order by a.grantee)
                      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'),
      'exec_anon', has_function_privilege('anon', p.oid, 'execute'),
      'exec_authenticated', has_function_privilege('authenticated', p.oid, 'execute'),
      'exec_service_role', has_function_privilege('service_role', p.oid, 'execute'),
      'exec_postgres', has_function_privilege('postgres', p.oid, 'execute')
    ) order by p.oid::regprocedure::text)
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
  ),
  'tables', (
    select jsonb_agg(jsonb_build_object(
      'table', c.relname, 'rls', c.relrowsecurity, 'force_rls', c.relforcerowsecurity,
      'anon', concat_ws(',', case when has_table_privilege('anon', c.oid, 'select') then 'S' end,
                             case when has_table_privilege('anon', c.oid, 'insert') then 'I' end,
                             case when has_table_privilege('anon', c.oid, 'update') then 'U' end,
                             case when has_table_privilege('anon', c.oid, 'delete') then 'D' end),
      'authenticated', concat_ws(',', case when has_table_privilege('authenticated', c.oid, 'select') then 'S' end,
                             case when has_table_privilege('authenticated', c.oid, 'insert') then 'I' end,
                             case when has_table_privilege('authenticated', c.oid, 'update') then 'U' end,
                             case when has_table_privilege('authenticated', c.oid, 'delete') then 'D' end)
    ) order by c.relname)
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
  ),
  'profiles_update_columns', (
    select jsonb_agg(a.attname order by a.attnum) from pg_attribute a
    where a.attrelid = 'public.profiles'::regclass and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('authenticated', 'public.profiles'::regclass, a.attnum, 'update')
  ),
  'schema_privs', jsonb_build_object(
    'public_create_anon', has_schema_privilege('anon', 'public', 'create'),
    'public_create_authenticated', has_schema_privilege('authenticated', 'public', 'create'),
    'db_temp_authenticated', has_database_privilege('authenticated', current_database(), 'temp')
  ),
  'functions', (
    select jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'args', pg_get_function_identity_arguments(p.oid),
      'definer', p.prosecdef,
      'owner', pg_get_userbyid(p.proowner),
      'returns', format_type(p.prorettype, null),
      'acl', p.proacl::text,
      'anon', has_function_privilege('anon', p.oid, 'execute'),
      'auth', has_function_privilege('authenticated', p.oid, 'execute'),
      'config', p.proconfig,
      'body', p.prosrc
    ) order by p.proname)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  ),
  'policies', (
    select jsonb_agg(jsonb_build_object(
      'schema', schemaname, 'table', tablename, 'name', policyname,
      'cmd', cmd, 'permissive', permissive, 'roles', roles, 'using', qual, 'check', with_check
    ) order by schemaname, tablename, policyname)
    from pg_policies where schemaname in ('public', 'storage')
  ),
  'triggers', (
    select jsonb_agg(jsonb_build_object(
      'table', c.relnamespace::regnamespace::text || '.' || c.relname,
      'name', t.tgname, 'function', t.tgfoid::regprocedure::text, 'enabled', t.tgenabled
    ) order by 1)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where not t.tgisinternal
      and (c.relnamespace = 'public'::regnamespace or t.tgfoid::regprocedure::text like 'public.%' or t.tgfoid::regprocedure::text not like '%.%')
  ),
  'defaults', (
    select jsonb_agg(jsonb_build_object(
      'table', c.relname, 'column', a.attname, 'default', pg_get_expr(ad.adbin, ad.adrelid)))
    from pg_attrdef ad
    join pg_class c on c.oid = ad.adrelid
    join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
    where c.relnamespace = 'public'::regnamespace
      and pg_get_expr(ad.adbin, ad.adrelid) ~ '\('
      and pg_get_expr(ad.adbin, ad.adrelid) !~ '^(now\(\)|nextval\(|gen_random_uuid\(\)|''\{\}''|ARRAY\[)'
  ),
  'views', (
    select jsonb_agg(c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm')
  ),
  'default_acl', (
    select jsonb_agg(jsonb_build_object(
      'role', pg_get_userbyid(d.defaclrole), 'schema', d.defaclnamespace::regnamespace::text,
      'type', d.defaclobjtype, 'acl', d.defaclacl::text))
    from pg_default_acl d
  ),
  'extensions', (
    select jsonb_agg(jsonb_build_object('name', e.extname, 'schema', e.extnamespace::regnamespace::text))
    from pg_extension e
  ),
  'cron', (
    select jsonb_agg(jsonb_build_object('name', jobname, 'schedule', schedule, 'command', command, 'active', active))
    from cron.job
  )
)) as report;
