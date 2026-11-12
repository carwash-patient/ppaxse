-- 2026-11-12 보안 수정 적용 전 점검 (읽기 전용 — SELECT 한 개, 아무것도 바꾸지 않음)
-- 목적: 이번에 트리거 3개가 쓰게 될 판별식  auth.jwt() ->> 'role'  이 실제 Supabase 요청에서
--       기대대로 동작한다는 '운영 증거'를 확인합니다.
--  · 한마디(place_comments) 등록 트리거는 2026-11-09부터 같은 판별식을 운영에서 쓰고 있습니다.
--    판별이 실패하면 트리거가 일찍 끝나 user_id가 비게 됩니다(이용자는 user_id 열에 직접 쓸 권한이 없음).
--    → 11-09 이후 앱으로 들어온 한마디의 user_id가 모두 채워져 있으면, 실제 요청에서 판별이 동작한 것입니다.
--  · auth.jwt() 가 요청 정보를 어디서 읽는지(정의)와 최근 크론 실행 기록도 함께 봅니다.
select jsonb_pretty(jsonb_build_object(
  'server_version', current_setting('server_version'),
  'comments_since_1109', (
    select jsonb_build_object(
      'total', count(*),
      'user_id_filled', count(*) filter (where user_id is not null),
      'user_id_empty', count(*) filter (where user_id is null),
      'first', min(created_at), 'last', max(created_at))
    from public.place_comments where created_at >= timestamptz '2026-11-09 00:00+09'),
  'comment_trigger_uses_jwt_role', (
    select p.prosrc like '%auth.jwt() ->> ''role''%' and p.prosecdef
    from pg_proc p where p.oid = 'public.place_comments_before_insert()'::regprocedure),
  'auth_jwt_definition', (select pg_get_functiondef('auth.jwt()'::regprocedure)),
  'auth_uid_definition', (select pg_get_functiondef('auth.uid()'::regprocedure)),
  'cron_recent_runs', (
    select jsonb_agg(x) from (
      select j.jobname, d.status, d.return_message, d.start_time
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
      order by d.start_time desc limit 5) x)
)) as report;
