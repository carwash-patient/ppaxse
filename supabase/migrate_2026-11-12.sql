-- 2026-11-12 보안 점검 반영
-- 1) 함수 실행 권한 정리  2) 함수 search_path 고정  3) 세차장 등록 정책 좁히기
-- 운영자가 Supabase SQL Editor에서 직접 Run 합니다.

-- ── 1) 함수 실행 권한 ─────────────────────────────────────────────
--  · 로그인 안 한 방문자(anon)는 꼭 필요한 4개만: is_admin(공개 조회 정책에서 씀), ppx_stats, ppx_event_status, ppx_track
--  · 로그인 사용자(authenticated, 익명 로그인 포함)는 일반 함수 실행 가능 (운영자 함수는 안에서 is_admin() 검사)
--  · 트리거 전용 함수, 내부 도우미(ppx_is_member, ppx_entry_valid)는 아무도 직접 실행 못 함
do $$
declare
  f record;
  anon_ok  text[] := array['is_admin','ppx_stats','ppx_event_status','ppx_track'];
  internal text[] := array['ppx_is_member','ppx_entry_valid'];
begin
  for f in
    select p.proname, p.oid::regprocedure::text as sig,
           p.prorettype = 'trigger'::regtype as is_trigger
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    continue when f.is_trigger or f.proname = any(internal);
    execute format('grant execute on function %s to authenticated', f.sig);
    if f.proname = any(anon_ok) then
      execute format('grant execute on function %s to anon', f.sig);
    end if;
  end loop;
end $$;

-- 앞으로 새로 만드는 함수도 기본으로는 아무에게도 열리지 않게 (필요하면 마이그레이션에서 grant)
alter default privileges in schema public revoke execute on functions from public, anon;

-- ── 2) search_path 고정 (설정이 없는 함수만) ─────────────────────
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = pg_catalog, public', f.sig);
  end loop;
end $$;

-- ── 3) 세차장 등록 정책: '아무거나 통과(true)' → '대기 상태 + 본인 이름' 또는 운영자 ──
--  (트리거가 먼저 status=pending, submitted_by=본인으로 고정하므로 일반 제보는 그대로 통과)
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (
    (status = 'pending' and submitted_by = (select auth.uid()))
    or (select public.is_admin())
  );

-- ── 확인: 결과 표에 나오는 함수별 권한 ──
select p.proname as 함수,
       has_function_privilege('anon', p.oid, 'execute') as 비로그인_가능,
       has_function_privilege('authenticated', p.oid, 'execute') as 로그인_가능,
       exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%') as search_path_고정
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f'
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
order by 2 desc, 3 desc, 1;
