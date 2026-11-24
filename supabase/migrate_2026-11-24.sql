-- 2026-11-24: 탈퇴 보완 (앱 출시 준비 점검). ppaxse-test에서 시험 18건 통과 후 운영 반영.
-- 시험 기록: D:\AI_Team\reviews\app-2026-11-24\followup-plan.md 'B·C' 절. 되돌리기 rollback_2026-11-24.sql
-- 여러 번 실행해도 안전합니다. 데이터는 탈퇴한 회원의 것만 바뀝니다.
--
-- 1) 탈퇴하면 그 회원의 모든 한마디 닉네임을 '익명 세차러'로 (계정 삭제와 같은 거래 → 한쪽만 되는 일 없음)
-- 2) 세차장 종류 투표를 회원 정보에 연결: 탈퇴하면 투표도 함께 삭제, 탈퇴 후 남은 토큰으로는 투표 불가
-- 3) 제보 사진 올리기: 회원 정보(프로필)가 있는 이용자만 (탈퇴 후 남은 토큰으로 업로드 불가)
--    가입·익명 이용자는 모두 프로필이 있음(가입 트리거가 만듦, 운영 DB 확인: 프로필 없는 계정 0)

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v uuid := auth.uid();
begin
  if v is null then raise exception '로그인이 필요해요.'; end if;
  if coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
     or not exists (select 1 from auth.users u where u.id = v and coalesce(u.is_anonymous, false) = false and u.email is not null) then
    raise exception '가입한 계정만 탈퇴할 수 있어요.';
  end if;
  if exists (select 1 from public.profiles where id = v and role = 'admin') then
    raise exception '운영자 계정은 여기서 탈퇴할 수 없어요.';
  end if;
  -- 남는 한마디에 쓴 닉네임도 지움 (탈퇴 안내: '누가 썼는지 알 수 없는 형태로 남아요'). 계정 삭제와 같은 거래라 한쪽만 되는 일 없음
  update public.place_comments set nickname = '익명 세차러' where user_id = v;
  -- 올린 사진 파일의 소유자 표시만 지움 (사진 자체는 운영자가 확인 후 삭제하는 규칙 그대로)
  begin
    execute 'update storage.objects set owner = null where owner = $1' using v;
  exception when others then null;
  end;
  delete from auth.users where id = v;   -- 프로필은 함께 삭제, 제보·한마디는 누가 썼는지 모르게 남음
end $function$;

-- 2) 종류 투표 ↔ 회원 정보 연결 (이미 있으면 건너뜀)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'place_type_votes_user_id_fkey') then
    delete from public.place_type_votes v where not exists (select 1 from public.profiles p where p.id = v.user_id);  -- 주인 없는 투표(운영 DB 확인: 0건)
    alter table public.place_type_votes
      add constraint place_type_votes_user_id_fkey foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;
end $$;

-- 3) 제보 사진 올리기 규칙
drop policy if exists "report-photos: 올리기" on storage.objects;
create policy "report-photos: 올리기" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = (auth.uid())::text
    and exists (select 1 from public.profiles where profiles.id = auth.uid() and not profiles.blocked)
    and public.ppx_photo_count_today() < 20
  );
