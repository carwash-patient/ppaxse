-- 2026-11-12 보안 수정 전 현황 조사 (읽기 전용 — 아무것도 바꾸지 않음)
-- 결과 한 칸(JSON)이 그대로 '변경 전 백업' 자료가 됩니다.
select jsonb_pretty(jsonb_build_object(
  'run_as', current_user,
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
      'cmd', cmd, 'roles', roles, 'using', qual, 'check', with_check
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
