-- migrate_2026-11-24b.sql 되돌리기. 여러 번 실행해도 안전합니다.
-- 주의: 웹 화면(js/ppx.js 20261124a)이 새 함수를 부르므로, 되돌리면 화면도 이전 버전으로 함께 되돌려야 합니다.

-- 한마디 조회 규칙 원래대로
drop policy if exists "comments: 조회" on public.place_comments;
create policy "comments: 조회" on public.place_comments for select
  using ((not hidden) or (user_id = auth.uid()) or public.is_admin());

drop function if exists public.hide_author(bigint);
drop function if exists public.unhide_author(bigint);
drop function if exists public.my_hides();
drop function if exists public.ppx_hidden_for_me(uuid, bigint);
drop table if exists public.user_hides;

-- 신고 사유 원래대로 (작성자 신고로 들어온 것은 '기타'로)
update public.place_comment_reports set reason = 'other' where reason = 'author';
alter table public.place_comment_reports drop constraint if exists place_comment_reports_reason_check;
alter table public.place_comment_reports add constraint place_comment_reports_reason_check
  check (reason in ('abuse', 'spam', 'privacy', 'other'));

-- 동의 검사 없는 한마디 쓰기 검사 (동의 기록 칸 ugc_agreed_at 은 남겨 둠: 지워도 되지만 기록 보존)
drop function if exists public.ppx_agree_ugc();
revoke select (ugc_agreed_at) on public.profiles from authenticated;
create or replace function public.place_comments_before_insert()
returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $function$
declare
  v_uid uuid := auth.uid();
  v_request_role text := auth.jwt() ->> 'role';
begin
  if coalesce(v_request_role, '') not in ('anon', 'authenticated') then
    return new;
  end if;
  if v_uid is null then
    raise exception '한마디를 남기려면 먼저 이용자 확인이 필요해요.';
  end if;

  new.user_id := v_uid;
  new.hidden := false;
  new.created_at := now();
  new.body := btrim(new.body);
  new.nickname := nullif(btrim(coalesce(new.nickname, '')), '');

  -- 닉네임: 비우면 무작위 이름, 운영자처럼 보이는 이름은 운영자만
  if new.nickname is null then
    new.nickname := public.ppx_auto_nick(v_uid::text);
  elsif public.ppx_nick_reserved(new.nickname) and not public.is_admin() then
    raise exception '이 닉네임은 쓸 수 없어요. 🎲를 눌러 다른 이름을 골라 주세요.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  perform public.ppx_guard('comment');

  if exists (
    select 1 from public.place_comments c
    where c.user_id = v_uid
      and c.created_at > now() - interval '30 seconds'
  ) then
    raise exception '한마디는 30초에 한 번씩 남길 수 있어요. 잠시 기다려 주세요.';
  end if;

  if exists (
    select 1 from public.place_comments c
    where c.user_id = v_uid
      and c.place_id = new.place_id
      and c.created_at > now() - interval '30 days'
  ) and not public.is_admin() then
    raise exception '이 세차장에는 이미 한마디를 남기셨어요. 같은 곳은 한 달에 한 번 남길 수 있어요.';
  end if;
  return new;
end;
$function$;

-- 탈퇴 함수: migrate_2026-11-24 상태로 (숨김 옮기기 줄만 뺌)
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
  update public.place_comments set nickname = '익명 세차러' where user_id = v;
  begin
    execute 'update storage.objects set owner = null where owner = $1' using v;
  exception when others then null;
  end;
  delete from auth.users where id = v;
end $function$;
