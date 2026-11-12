-- 역할별 권한 우회 테스트 (테스트 DB 전용 — 운영 DB에서 실행하지 말 것)
-- 비로그인(anon) / 익명 로그인 / 일반 회원 / 운영자 로 각각 요청을 흉내 내고 기대 결과와 비교
set client_min_messages = warning;

-- 테스트 사용자
insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test', false),
  ('00000000-0000-0000-0000-00000000000b', 'member@test', false),
  ('00000000-0000-0000-0000-00000000000c', null, true),
  ('00000000-0000-0000-0000-00000000000d', 'other@test', false)
on conflict do nothing;
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
insert into public.places (id, name, type, status, region, lat, lng)
  values (900001, '테스트 세차장', 'self', 'approved', '테스트', 37.5, 127.0) on conflict do nothing;

create or replace function pg_temp.run(r text, uid uuid, is_anon boolean, q text) returns text
language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', r, 'is_anonymous', is_anon)::text, true);
  begin
    execute format('set local role %I', r);
    execute q into v;
    reset role;
    return 'OK ' || coalesce(v, '');
  exception when others then
    return 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
end $$;

create temp table t (no serial, 누구 text, 시험 text, 기대 text, 결과 text);
create or replace function pg_temp.chk(who text, name text, expect text, r text, uid uuid, is_anon boolean, q text) returns void
language plpgsql as $$
declare res text := pg_temp.run(r, uid, is_anon, q);
begin
  insert into t (누구, 시험, 기대, 결과) values (who, name, expect, res);
end $$;

-- 약칭
-- A = 비로그인, N = 익명 로그인, M = 회원, X = 운영자
do $$
declare
  adm uuid := '00000000-0000-0000-0000-00000000000a';
  mem uuid := '00000000-0000-0000-0000-00000000000b';
  ano uuid := '00000000-0000-0000-0000-00000000000c';
  oth uuid := '00000000-0000-0000-0000-00000000000d';
  f text;
begin
  -- ── 비로그인(anon) ──
  perform pg_temp.chk('A', '지도 조회(승인된 세차장)', 'OK', 'anon', null, false, 'select count(*)::text from public.places where id = 900001');
  perform pg_temp.chk('A', 'ppx_stats', 'OK', 'anon', null, false, 'select public.ppx_stats()::text');
  perform pg_temp.chk('A', 'ppx_event_status', 'OK', 'anon', null, false, 'select left(public.ppx_event_status()::text, 20)');
  perform pg_temp.chk('A', 'ppx_track', 'OK', 'anon', null, false, $q$select public.ppx_track('11111111-1111-1111-1111-111111111111', 'map', 'test')::text$q$);
  perform pg_temp.chk('A', 'is_admin', 'OK', 'anon', null, false, 'select public.is_admin()::text');
  foreach f in array array[
    'public.admin_block(''00000000-0000-0000-0000-00000000000d'', true)',
    'public.admin_block_commenter(1)', 'public.admin_event_entries(now(), now())', 'public.admin_abuse_summary()',
    'public.admin_channel_stats(30)', 'public.admin_event_draw(current_date, false)', 'public.admin_event_week(current_date)',
    'public.admin_type_votes()', 'public.admin_visit_stats(14)',
    'public.start_claim()', 'public.finish_claim(gen_random_uuid())', 'public.delete_my_account()',
    'public.ppx_enter_event(1)', 'public.ppx_log_block(''place'', ''x'')', 'public.ppx_precheck(''place'')',
    'public.ppx_vote_type(900001, ''self'')',
    'public.ppx_guard(''place'')', 'public.ppx_burst_guard(''place'')', 'public.my_pending_count()', 'public.my_pending_reports()',
    'public.ppx_event_week(now())', 'public.ppx_event_start()', 'public.ppx_event_draw_at(current_date)',
    'public.ppx_event_draw_run(current_date)', 'public.ppx_auto_draw(now())', 'public.ppx_is_member(gen_random_uuid())'] loop
    perform pg_temp.chk('A', '거부: ' || split_part(f, '(', 1), 'NOPERM', 'anon', null, false, 'select (' || f || ')::text');
  end loop;
  perform pg_temp.chk('A', '거부: places 직접 등록', 'DENY', 'anon', null, false,
    $q$insert into public.places (name, type, status, region, lat, lng) values ('x', 'self', 'approved', 'x', 1, 1) returning id::text$q$);

  -- ── 익명 로그인(authenticated, is_anonymous) ──
  perform pg_temp.chk('N', '세차장 제보 → pending·본인', 'OK pending', 'authenticated', ano, true,
    $q$insert into public.places (name, type, status, region, lat, lng, submitted_by, source)
       values ('제보1', 'self', 'approved', '테스트', 37.6, 127.1, '00000000-0000-0000-0000-00000000000d', 'public')
       returning status || case when submitted_by = '00000000-0000-0000-0000-00000000000c' and source = 'user' then '' else ' 조작됨' end$q$);
  perform pg_temp.chk('N', '정보 제보', 'OK', 'authenticated', ano, true,
    $q$insert into public.place_reports (place_id, memo, status, reporter) values (900001, '테스트', 'applied', '00000000-0000-0000-0000-00000000000d')
       returning status || case when reporter = '00000000-0000-0000-0000-00000000000c' then '' else ' 조작됨' end$q$);
  perform pg_temp.chk('N', '다녀왔어요(확인)', 'OK', 'authenticated', ano, true,
    $q$insert into public.place_checks (place_id) values (900001) returning (user_id = '00000000-0000-0000-0000-00000000000c')::text$q$);
  perform pg_temp.chk('N', '한마디 작성', 'OK', 'authenticated', ano, true,
    $q$insert into public.place_comments (place_id, nickname, body) values (900001, '익명', '테스트 한마디입니다 열자이상') returning 'ok'$q$);
  perform pg_temp.chk('N', '종류 투표', 'OK', 'authenticated', ano, true, $q$select public.ppx_vote_type(900001, 'self')::text$q$);
  perform pg_temp.chk('N', 'start_claim', 'OK', 'authenticated', ano, true, 'select (public.start_claim() is not null)::text');
  perform pg_temp.chk('N', '거부: 운영자 차단 RPC', 'DENY', 'authenticated', ano, true,
    $q$select public.admin_block('00000000-0000-0000-0000-00000000000d', true)::text$q$);
  perform pg_temp.chk('N', '거부: 응모자 이메일 목록', 'DENY', 'authenticated', ano, true, 'select count(*)::text from public.admin_event_entries(now() - interval ''1 day'', now())');
  perform pg_temp.chk('N', '거부: 승인된 세차장 수정', 'DENY0', 'authenticated', ano, true,
    $q$with u as (update public.places set name = '해킹' where id = 900001 returning 1) select count(*)::text from u$q$);
  perform pg_temp.chk('N', '거부: 내부 함수 직접 실행', 'NOPERM', 'authenticated', ano, true, 'select public.ppx_event_draw_run(current_date)::text');
  perform pg_temp.chk('N', '거부: 도우미 ppx_guard 직접 실행', 'NOPERM', 'authenticated', ano, true, $q$select public.ppx_guard('place')::text$q$);
  perform pg_temp.chk('N', '거부: 도우미 ppx_burst_guard 직접 실행', 'NOPERM', 'authenticated', ano, true, $q$select public.ppx_burst_guard('place')::text$q$);
  perform pg_temp.chk('N', '거부: 도우미 my_pending_count 직접 실행', 'NOPERM', 'authenticated', ano, true, 'select public.my_pending_count()::text');
  perform pg_temp.chk('N', '거부: 도우미 my_pending_reports 직접 실행', 'NOPERM', 'authenticated', ano, true, 'select public.my_pending_reports()::text');
  perform pg_temp.chk('N', '거부: 트리거 함수 직접 실행', 'NOPERM', 'authenticated', ano, true, 'select public.handle_new_user()::text');
  perform pg_temp.chk('N', '거부: 내 역할을 admin으로', 'DENY', 'authenticated', ano, true,
    $q$update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000c' returning 'x'$q$);
  perform pg_temp.chk('N', '거부: 프로필 직접 생성', 'DENY', 'authenticated', ano, true,
    $q$insert into public.profiles (id, nickname, role) values (gen_random_uuid(), 'x', 'admin') returning 'x'$q$);
  perform pg_temp.chk('N', '거부: 남의 제보 보기', 'DENY0', 'authenticated', ano, true,
    $q$select count(*)::text from public.place_reports where reporter <> '00000000-0000-0000-0000-00000000000c'$q$);

  -- ── 일반 회원 ──
  perform pg_temp.chk('M', '세차장 제보', 'OK pending', 'authenticated', mem, false,
    $q$insert into public.places (name, type, region, lat, lng) values ('제보2', 'self', '테스트', 37.7, 127.2) returning status$q$);
  perform pg_temp.chk('M', '거부: 운영자 통계', 'DENY', 'authenticated', mem, false, 'select public.admin_visit_stats(14)::text');
  perform pg_temp.chk('M', '거부: 남의 프로필 보기', 'DENY0', 'authenticated', mem, false,
    $q$select count(*)::text from public.profiles where id <> '00000000-0000-0000-0000-00000000000b'$q$);
  perform pg_temp.chk('M', '거부: 남의 대기 세차장 보기', 'DENY0', 'authenticated', mem, false,
    $q$select count(*)::text from public.places where status = 'pending' and submitted_by <> '00000000-0000-0000-0000-00000000000b'$q$);
  perform pg_temp.chk('M', '내 닉네임 수정', 'OK', 'authenticated', mem, false,
    $q$update public.profiles set nickname = '회원닉' where id = '00000000-0000-0000-0000-00000000000b' returning nickname$q$);
  perform pg_temp.chk('M', '거부: 내 차단 풀기', 'DENY', 'authenticated', mem, false,
    $q$update public.profiles set blocked = false where id = '00000000-0000-0000-0000-00000000000b' returning 'x'$q$);
  perform pg_temp.chk('M', '제보 전 검사', 'OK', 'authenticated', mem, false, $q$select public.ppx_precheck('report', 900001)::text$q$);
  perform pg_temp.chk('M', 'ppx_log_block', 'OK', 'authenticated', mem, false, $q$select public.ppx_log_block('place', '테스트')::text$q$);
  perform pg_temp.chk('M', 'finish_claim', 'OK', 'authenticated', mem, false, 'select public.finish_claim(gen_random_uuid())::text');

  -- ── 운영자 ──
  perform pg_temp.chk('X', '운영자 직접 등록(승인 상태)', 'OK approved', 'authenticated', adm, false,
    $q$insert into public.places (name, type, status, region, lat, lng, source) values ('운영자등록', 'self', 'approved', '테스트', 37.8, 127.3, 'admin') returning status$q$);
  perform pg_temp.chk('X', '대기 세차장 승인', 'OK', 'authenticated', adm, false,
    $q$with u as (update public.places set status = 'approved' where name = '제보2' returning 1) select count(*)::text from u$q$);
  perform pg_temp.chk('X', '사용자 차단', 'OK', 'authenticated', adm, false, $q$select public.admin_block('00000000-0000-0000-0000-00000000000d', true)::text$q$);
  perform pg_temp.chk('X', '사용자 차단 해제', 'OK', 'authenticated', adm, false, $q$select public.admin_block('00000000-0000-0000-0000-00000000000d', false)::text$q$);
  perform pg_temp.chk('X', '도배 요약', 'OK', 'authenticated', adm, false, 'select count(*)::text from public.admin_abuse_summary()');
  perform pg_temp.chk('X', '채널 통계', 'OK', 'authenticated', adm, false, 'select left(public.admin_channel_stats(30)::text, 10)');
  perform pg_temp.chk('X', '방문 통계', 'OK', 'authenticated', adm, false, 'select left(public.admin_visit_stats(14)::text, 10)');
  perform pg_temp.chk('X', '응모자 목록', 'OK', 'authenticated', adm, false, 'select count(*)::text from public.admin_event_entries(now() - interval ''1 day'', now())');
  perform pg_temp.chk('X', '이번 주 응모', 'OK', 'authenticated', adm, false, 'select count(*)::text from public.admin_event_week(current_date)');
  perform pg_temp.chk('X', '종류 투표 보기', 'OK', 'authenticated', adm, false, 'select left(public.admin_type_votes()::text, 10)');
  perform pg_temp.chk('X', '한마디 숨기기', 'OK', 'authenticated', adm, false,
    $q$with u as (update public.place_comments set hidden = true where place_id = 900001 returning 1) select count(*)::text from u$q$);
  perform pg_temp.chk('X', '제보 처리', 'OK', 'authenticated', adm, false,
    $q$with u as (update public.place_reports set status = 'applied' where place_id = 900001 returning 1) select count(*)::text from u$q$);
  perform pg_temp.chk('X', '전체 프로필 보기', 'OK', 'authenticated', adm, false, 'select count(*)::text from public.profiles');

  -- ── 회원 탈퇴 (마지막) ──
  perform pg_temp.chk('M', '회원 탈퇴', 'OK', 'authenticated', mem, false, 'select public.delete_my_account()::text');
  perform pg_temp.chk('M', '탈퇴 후 같은 토큰: 제보 시도', 'DENY', 'authenticated', mem, false,
    $q$insert into public.places (name, type, region, lat, lng) values ('탈퇴후', 'self', '테스트', 37.9, 127.4) returning status$q$);
  perform pg_temp.chk('M', '탈퇴 후 같은 토큰: 운영자 RPC', 'DENY', 'authenticated', mem, false, 'select public.admin_type_votes()::text');
end $$;

-- 트리거 안의 횟수 제한·차단이 소유자 권한에서도 그대로 작동하는지
do $$
declare
  ano uuid := '00000000-0000-0000-0000-00000000000c';
  oth uuid := '00000000-0000-0000-0000-00000000000d';
begin
  perform pg_temp.chk('N', '제한: 30초 안에 두 번째 세차장 제보', 'DENY', 'authenticated', ano, true,
    $q$insert into public.places (name, type, region, lat, lng) values ('제보3', 'self', '테스트', 37.61, 127.11) returning status$q$);
  perform pg_temp.chk('N', '제한: 15초 안에 두 번째 정보 제보', 'DENY', 'authenticated', ano, true,
    $q$insert into public.place_reports (place_id, memo) values (900001, '두번째') returning status$q$);
  update public.profiles set blocked = true where id = oth;
  perform pg_temp.chk('B', '제한: 차단된 사용자 세차장 제보', 'DENY', 'authenticated', oth, false,
    $q$insert into public.places (name, type, region, lat, lng) values ('차단제보', 'self', '테스트', 37.62, 127.12) returning status$q$);
  perform pg_temp.chk('B', '제한: 차단된 사용자 다녀왔어요', 'DENY', 'authenticated', oth, false,
    $q$insert into public.place_checks (place_id) values (900001) returning 'x'$q$);
  update public.profiles set blocked = false where id = oth;
end $$;
-- 관리 도구(postgres·service_role) 경로는 값을 그대로 둠 (공공데이터 넣기 등)
with x as (insert into public.places (name, type, status, source, region, lat, lng)
           values ('공공데이터', 'self', 'approved', 'public_data', '테스트', 37.63, 127.13) returning status, source)
insert into t (누구, 시험, 기대, 결과)
select 'SQL편집기', 'postgres가 승인 상태로 직접 등록', 'OK approved',
       'OK ' || status || case when source = 'public_data' then '' else ' 바뀜' end from x;
insert into t (누구, 시험, 기대, 결과)
select 'service_role', '승인 상태로 직접 등록', 'OK approved',
       pg_temp.run('service_role', null, false,
         $q$insert into public.places (name, type, status, source, region, lat, lng) values ('서비스', 'self', 'approved', 'admin', '테스트', 37.64, 127.14) returning status$q$);

-- 크론(postgres)으로 자동 추첨이 도는지
insert into t (누구, 시험, 기대, 결과)
select 'cron', 'ppx_auto_draw (postgres)', 'OK', 'OK ' || coalesce(public.ppx_auto_draw(now())::text, 'null');

select no, 누구, 시험, 기대,
  case
    when 기대 like 'OK%' and 결과 like 'OK%' and (기대 = 'OK' or 결과 like 기대 || '%') then 'PASS'
    when 기대 = 'DENY' and 결과 like 'ERR%' then 'PASS'
    when 기대 = 'NOPERM' and 결과 like 'ERR 42501 permission denied for function%' then 'PASS'
    when 기대 = 'DENY0' and (결과 = 'OK 0' or 결과 like 'ERR%') then 'PASS'
    else 'FAIL' end as 판정,
  left(결과, 90) as 결과
from t order by no;
