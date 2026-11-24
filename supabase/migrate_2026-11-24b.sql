-- 2026-11-24 (b): 앱 출시 준비 — 한마디 이용자 숨기기 · 작성자 신고 · 운영정책 동의 (Google Play UGC 정책)
-- migrate_2026-11-24.sql 다음에 실행. 여러 번 실행해도 안전합니다. 기존 데이터는 바꾸지 않습니다.
-- ppaxse-test에서 먼저 시험. 되돌리기: rollback_2026-11-24b.sql
--
-- 1) 이용자 숨기기 (user_hides): 이용자가 '이 사람 글 숨기기'를 누르면 그 작성자의 한마디가 나에게만 안 보임
--    · 한마디 번호만 보내면 서버가 작성자를 찾아 저장 → 작성자 번호는 화면에 나가지 않음
--    · 표는 직접 읽기·쓰기 불가, 함수로만: hide_author(cid) / unhide_author(hid) / my_hides()
--    · 한마디 목록은 서버 규칙(RLS)이 내가 숨긴 작성자를 빼고 줌 → 화면의 한마디 불러오기 코드는 그대로
--    · 작성자가 탈퇴하면 작성자 칸이 비므로, 탈퇴 직전에 '작성자 숨김'을 '그 한마디들 숨김'으로 바꿔 둠
--    · 운영자 제재(admin_block_commenter: 글쓰기 막기)와는 별개. 숨기기는 나에게만 적용
-- 2) 작성자 신고: 한마디 신고 사유에 'author'(이 작성자 신고 — 반복·악성) 추가. 운영자는 그 한마디로 작성자를 확인해 제재
-- 3) 운영정책 동의: profiles.ugc_agreed_at. 동의 기록이 없으면 한마디를 쓸 수 없음 (운영자 제외)
--    화면은 처음 한마디 때 동의 체크 → ppx_agree_ugc() → 한마디 저장

-- ── 1) 이용자 숨기기 ──
create table if not exists public.user_hides (
  id         bigint generated always as identity primary key,
  owner      uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  author     uuid references public.profiles(id) on delete cascade,
  comment_id bigint references public.place_comments(id) on delete cascade,
  label      text check (label is null or char_length(label) <= 20),
  created_at timestamptz not null default now(),
  constraint user_hides_one_target check ((author is null) <> (comment_id is null))
);
create unique index if not exists user_hides_owner_author  on public.user_hides (owner, author)     where author is not null;
create unique index if not exists user_hides_owner_comment on public.user_hides (owner, comment_id) where comment_id is not null;
create index if not exists user_hides_author on public.user_hides (author) where author is not null;
alter table public.user_hides enable row level security;
revoke all on public.user_hides from public, anon, authenticated;

-- 이 한마디가 나에게 숨겨진 것인지 (내 숨김 목록만 봄)
create or replace function public.ppx_hidden_for_me(a uuid, cid bigint)
returns boolean
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select auth.uid() is not null and exists (
    select 1 from public.user_hides h
    where h.owner = auth.uid() and (h.author = a or h.comment_id = cid))
$$;
revoke all on function public.ppx_hidden_for_me(uuid, bigint) from public, anon, authenticated;
grant execute on function public.ppx_hidden_for_me(uuid, bigint) to anon, authenticated;

create or replace function public.hide_author(cid bigint)
returns json
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v uuid := auth.uid(); a uuid; nk text;
begin
  if v is null or not exists (select 1 from public.profiles where id = v) then
    raise exception '이용자 확인이 필요해요.';
  end if;
  select c.user_id, c.nickname into a, nk from public.place_comments c where c.id = cid and not c.hidden;
  if not found then raise exception '한마디를 찾지 못했어요.'; end if;
  if a = v then raise exception '내가 쓴 한마디는 숨길 수 없어요.'; end if;
  if (select count(*) from public.user_hides where owner = v) >= 300 then
    raise exception '더 숨길 수 없어요. 숨긴 작성자를 조금 정리해 주세요.';
  end if;
  if a is null then   -- 탈퇴한 작성자: 그 한마디만
    insert into public.user_hides (owner, comment_id, label) values (v, cid, left(nk, 20)) on conflict do nothing;
  else
    insert into public.user_hides (owner, author, label) values (v, a, left(nk, 20)) on conflict do nothing;
  end if;
  return json_build_object('ok', true, 'scope', case when a is null then 'comment' else 'author' end);
end $$;
revoke all on function public.hide_author(bigint) from public, anon, authenticated;
grant execute on function public.hide_author(bigint) to authenticated;

create or replace function public.unhide_author(hid bigint)
returns boolean
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '이용자 확인이 필요해요.'; end if;
  delete from public.user_hides where id = hid and owner = auth.uid();
  return found;
end $$;
revoke all on function public.unhide_author(bigint) from public, anon, authenticated;
grant execute on function public.unhide_author(bigint) to authenticated;

-- 내가 숨긴 목록 (작성자 번호는 주지 않음: 숨길 때 보인 닉네임만)
create or replace function public.my_hides()
returns table (id bigint, label text, scope text, created_at timestamptz)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select h.id, coalesce(h.label, '익명 세차러'), case when h.author is null then 'comment' else 'author' end, h.created_at
  from public.user_hides h where h.owner = auth.uid()
  order by h.created_at desc limit 300
$$;
revoke all on function public.my_hides() from public, anon, authenticated;
grant execute on function public.my_hides() to authenticated;

-- 한마디 조회 규칙: 기존 조건 + 내가 숨긴 작성자·한마디는 빼고 (운영자는 다 보임)
drop policy if exists "comments: 조회" on public.place_comments;
create policy "comments: 조회" on public.place_comments for select
  using (
    ((not hidden) or (user_id = auth.uid()) or public.is_admin())
    and (public.is_admin() or not public.ppx_hidden_for_me(user_id, id))
  );

-- ── 2) 작성자 신고 사유 ──
alter table public.place_comment_reports drop constraint if exists place_comment_reports_reason_check;
alter table public.place_comment_reports add constraint place_comment_reports_reason_check
  check (reason in ('abuse', 'spam', 'privacy', 'other', 'author'));

-- ── 3) 운영정책 동의 ──
alter table public.profiles add column if not exists ugc_agreed_at timestamptz;
grant select (ugc_agreed_at) on public.profiles to authenticated;

create or replace function public.ppx_agree_ugc()
returns void
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '이용자 확인이 필요해요.'; end if;
  update public.profiles set ugc_agreed_at = coalesce(ugc_agreed_at, now()) where id = auth.uid();
end $$;
revoke all on function public.ppx_agree_ugc() from public, anon, authenticated;
grant execute on function public.ppx_agree_ugc() to authenticated;

-- 한마디 쓰기 검사: 기존 그대로 + 동의 확인 한 덩어리 추가
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

  -- 커뮤니티 운영정책 동의 (2026-11-24b)
  if not exists (select 1 from public.profiles where id = v_uid and ugc_agreed_at is not null) and not public.is_admin() then
    raise exception '한마디를 남기려면 커뮤니티 운영정책에 동의해 주세요.';
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

-- ── 탈퇴: 기존(migrate_2026-11-24) + 나를 숨긴 사람들의 '작성자 숨김'을 내 한마디 단위로 바꿔 둠 ──
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
  -- 나를 숨긴 이용자에게는 탈퇴 뒤에도 내 한마디가 계속 숨겨지도록 (작성자 칸이 비기 전에 한마디 단위로 옮김)
  insert into public.user_hides (owner, comment_id, label)
    select h.owner, c.id, h.label from public.user_hides h join public.place_comments c on c.user_id = h.author
    where h.author = v
  on conflict do nothing;
  -- 남는 한마디에 쓴 닉네임도 지움 (탈퇴 안내: '누가 썼는지 알 수 없는 형태로 남아요'). 계정 삭제와 같은 거래라 한쪽만 되는 일 없음
  update public.place_comments set nickname = '익명 세차러' where user_id = v;
  -- 올린 사진 파일의 소유자 표시만 지움 (사진 자체는 운영자가 확인 후 삭제하는 규칙 그대로)
  begin
    execute 'update storage.objects set owner = null where owner = $1' using v;
  exception when others then null;
  end;
  delete from auth.users where id = v;   -- 프로필은 함께 삭제, 제보·한마디는 누가 썼는지 모르게 남음
end $function$;
