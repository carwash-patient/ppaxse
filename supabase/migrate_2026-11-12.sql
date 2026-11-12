-- 2026-11-12 보안 점검 반영 (2차 검토 반영본)
--  1) 함수 실행 권한: '한꺼번에 열기' 대신 함수 이름 목록으로 필요한 사람에게만 열기
--  2) 앞으로 새로 만드는 함수는 기본으로 아무에게도 안 열림 (마이그레이션에서 직접 grant)
--  3) search_path가 없던 함수 9개 고정
--  4) 세차장 등록 정책: '아무거나 통과(true)' → '대기 상태 + 본인' 또는 운영자
--  5) 끝에서 결과를 스스로 검사 — 하나라도 예상과 다르면 전체가 취소되고 아무것도 안 바뀜
-- 근거: 2026-11-12 18:47 실제 DB 조사(inspect_2026-11-12.sql). public 함수 42개, 저장소와 이름 일치.
-- 문제가 생기면 rollback_2026-11-12.sql 로 조사 때 상태로 되돌림.
-- 운영자가 Supabase SQL Editor에서 직접 Run 합니다. 여러 번 실행해도 결과가 같습니다.

begin;

-- ── 1) 함수 실행 권한 ─────────────────────────────────────────────
do $$
declare
  f record;
  n int := 0;
  -- 비로그인(anon)도 필요한 것
  anon_list text[] := array[
    'is_admin',          -- 지도·한마디·확인 기록 '조회' 정책 안에서 쓰임 (비로그인 지도 보기에 필요)
    'ppx_stats',         -- 홈 화면 세차장 수 등
    'ppx_event_status',  -- 이벤트 현황 표시
    'ppx_track'          -- 방문 기록
  ];
  -- 로그인(authenticated, 익명 로그인 포함)이 필요한 것
  auth_list text[] := array[
    'is_admin', 'ppx_stats', 'ppx_event_status', 'ppx_track',
    -- 화면에서 직접 부르는 회원 기능
    'delete_my_account', 'start_claim', 'finish_claim', 'ppx_enter_event',
    'ppx_log_block', 'ppx_precheck', 'ppx_vote_type',
    -- 운영자 화면 (함수 첫 줄에서 is_admin() 아니면 거절)
    'admin_abuse_summary', 'admin_block', 'admin_block_commenter', 'admin_channel_stats',
    'admin_event_draw', 'admin_event_entries', 'admin_event_week', 'admin_type_votes', 'admin_visit_stats',
    -- 트리거(호출자 권한으로 도는 것)가 안에서 부르는 도우미
    'ppx_guard', 'ppx_burst_guard', 'my_pending_count', 'my_pending_reports'
  ];
  -- 나머지(트리거 함수, 내부 전용 함수)는 아무도 직접 실행 못 함
begin
  for f in
    select p.proname, p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    n := n + 1;
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any(auth_list) then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
    if f.proname = any(anon_list) then
      execute format('grant execute on function %s to anon', f.sig);
    end if;
  end loop;
  if n <> 42 then
    raise exception '함수 개수가 조사 때(42개)와 달라요(지금 %개). 아무것도 바꾸지 않고 멈춥니다.', n;
  end if;
end $$;

-- ── 2) 앞으로 만드는 함수의 기본 권한 (postgres가 만드는 함수 기준) ──
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
alter default privileges for role postgres revoke execute on functions from public;

-- ── 3) search_path 고정 (조사 때 설정이 없던 9개, 모두 일반 함수·트리거, 확장 함수 호출 없음) ──
alter function public.place_checks_before_insert()  set search_path = pg_catalog, public;
alter function public.place_reports_before_insert() set search_path = pg_catalog, public;
alter function public.place_reports_before_update() set search_path = pg_catalog, public;
alter function public.places_before_insert()        set search_path = pg_catalog, public;
alter function public.places_before_update()        set search_path = pg_catalog, public;
alter function public.places_fix_types()            set search_path = pg_catalog, public;
alter function public.ppx_event_draw_at(date)       set search_path = pg_catalog, public;
alter function public.ppx_event_start()             set search_path = pg_catalog, public;
alter function public.ppx_event_week(timestamptz)   set search_path = pg_catalog, public;

-- ── 4) 세차장 등록 정책 ──
--  BEFORE INSERT 트리거가 일반 사용자 값을 pending/본인으로 먼저 고정하고, 그 다음 이 검사가 돌아감
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (
    (status = 'pending' and submitted_by = (select auth.uid()))
    or (select public.is_admin())
  );

-- ── 5) 스스로 검사 (예상과 다르면 전체 취소) ──
do $$
declare bad text;
begin
  select string_agg(p.proname, ', ') into bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and has_function_privilege('anon', p.oid, 'execute')
    and p.proname not in ('is_admin', 'ppx_stats', 'ppx_event_status', 'ppx_track');
  if bad is not null then raise exception '비로그인에게 열리면 안 되는 함수가 열려 있어요: %', bad; end if;

  select string_agg(p.proname, ', ') into bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0);
  if bad is not null then raise exception '모든 역할(PUBLIC)에 열린 함수가 남아 있어요: %', bad; end if;

  select string_agg(p.proname, ', ') into bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f' and p.prorettype = 'trigger'::regtype
    and has_function_privilege('authenticated', p.oid, 'execute');
  if bad is not null then raise exception '트리거 함수가 직접 실행 가능해요: %', bad; end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f'
        and has_function_privilege('authenticated', p.oid, 'execute')) <> 24 then
    raise exception '로그인 사용자에게 열린 함수 수가 예상(24개)과 달라요.';
  end if;

  select string_agg(p.proname, ', ') into bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  if bad is not null then raise exception 'search_path가 없는 함수가 남아 있어요: %', bad; end if;
end $$;

commit;

-- ── 결과 표 (확인용) ──
select p.proname as 함수,
       case when p.prorettype = 'trigger'::regtype then '트리거' else '' end as 종류,
       has_function_privilege('anon', p.oid, 'execute') as 비로그인,
       has_function_privilege('authenticated', p.oid, 'execute') as 로그인
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prokind = 'f'
order by 3 desc, 4 desc, 1;
