-- migrate_2026-11-24.sql 되돌리기 (적용 전 운영 DB 상태로). 여러 번 실행해도 안전합니다.

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
  -- 올린 사진 파일의 소유자 표시만 지움 (사진 자체는 운영자가 확인 후 삭제하는 규칙 그대로)
  begin
    execute 'update storage.objects set owner = null where owner = $1' using v;
  exception when others then null;
  end;
  delete from auth.users where id = v;   -- 프로필은 함께 삭제, 제보·한마디는 누가 썼는지 모르게 남음
end $function$;

alter table public.place_type_votes drop constraint if exists place_type_votes_user_id_fkey;

drop policy if exists "report-photos: 올리기" on storage.objects;
create policy "report-photos: 올리기" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = (auth.uid())::text
    and not exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.blocked)
    and public.ppx_photo_count_today() < 20
  );
