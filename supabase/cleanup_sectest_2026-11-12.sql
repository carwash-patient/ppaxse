-- 2026-11-12 보안 점검 테스트 데이터 정리 (적용 '후' 실제 경로 쓰기 테스트를 한 다음에만 사용)
-- 지우는 것 — 아래 꼬리표가 붙은 것만:
--   · 정보 제보(place_reports): 메모가 '[보안점검 ' 로 시작
--   · 세차장 제보(places): 이름이 '[보안점검 ' 로 시작하고, 이용자 제보(source = user)이며 대기·거절 상태인 것만
--   · 익명 테스트 계정(auth.users): 위 테스트 제보를 보냈거나 가입 꼬리표가 'sectest' 인 '익명' 계정 중,
--     테스트 데이터 말고는 아무 기록(제보·한마디·확인·투표·응모)도 없는 계정만
-- 안전장치: 지울 대상이 예상(각 10건)보다 많으면 아무것도 지우지 않고 멈춥니다. 전체가 하나의 트랜잭션입니다.
-- 승인 상태로 남은 테스트 세차장이 있으면 지우지 않고 결과 표에 '확인 필요'로 보여 줍니다(운영자 화면에서 직접 처리).
-- 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다. 다시 실행해도 안전합니다(지울 것이 없으면 0건).

begin;

create temp table if not exists _sectest_result (항목 text, 건수 int, 내용 text);
truncate _sectest_result;

create temp table _sectest_users on commit drop as
  select u.id from auth.users u
  where coalesce(u.is_anonymous, false)
    and (u.id in (select submitted_by from public.places where name like '[보안점검 %')
      or u.id in (select reporter from public.place_reports where memo like '[보안점검 %')
      or u.id in (select id from public.profiles where signup_ref = 'sectest'));

do $$
declare n int;
begin
  select count(*) into n from public.place_reports where memo like '[보안점검 %';
  if n > 10 then raise exception '[정리 중단] 테스트 정보 제보가 %건 — 예상보다 많아요', n; end if;
  select count(*) into n from public.places where name like '[보안점검 %';
  if n > 10 then raise exception '[정리 중단] 테스트 세차장 제보가 %건 — 예상보다 많아요', n; end if;
  select count(*) into n from _sectest_users;
  if n > 10 then raise exception '[정리 중단] 테스트 계정이 %개 — 예상보다 많아요', n; end if;
end $$;

with d as (delete from public.place_reports where memo like '[보안점검 %' returning id, place_id)
insert into _sectest_result select '정보 제보 삭제', count(*), coalesce(string_agg(id::text, ', '), '') from d;

with d as (delete from public.places
           where name like '[보안점검 %' and source = 'user' and status in ('pending', 'rejected') returning id, name)
insert into _sectest_result select '세차장 제보 삭제', count(*), coalesce(string_agg(id::text || ' ' || name, ', '), '') from d;

with d as (delete from auth.users u
           where u.id in (select id from _sectest_users) and coalesce(u.is_anonymous, false)
             and not exists (select 1 from public.places x where x.submitted_by = u.id)
             and not exists (select 1 from public.place_reports x where x.reporter = u.id)
             and not exists (select 1 from public.place_comments x where x.user_id = u.id)
             and not exists (select 1 from public.place_checks x where x.user_id = u.id)
             and not exists (select 1 from public.place_type_votes x where x.user_id = u.id)
             and not exists (select 1 from public.event_entries x where x.user_id = u.id)
           returning u.id)
insert into _sectest_result select '익명 테스트 계정 삭제', count(*), coalesce(string_agg(id::text, ', '), '') from d;

insert into _sectest_result
select '확인 필요: 남아 있는 테스트 세차장', count(*), coalesce(string_agg(id::text || ' ' || status || ' ' || name, ', '), '없음')
from public.places where name like '[보안점검 %';
insert into _sectest_result
select '확인 필요: 남아 있는 테스트 계정', count(*), coalesce(string_agg(id::text, ', '), '없음')
from auth.users where id in (select id from _sectest_users);

commit;

select * from _sectest_result;
