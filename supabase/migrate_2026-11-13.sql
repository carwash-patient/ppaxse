-- 2026-11-13 한마디 닉네임: 무작위 이름 + 운영자처럼 보이는 이름 막기
--
-- 무엇을 바꾸나
--   1) 닉네임 없이 남긴 한마디에는 '익명 세차러' 대신 무작위 이름을 붙임
--      (같은 이용자 = 늘 같은 이름. 한 사람이 여러 사람처럼 보이지 않게)
--   2) 운영자가 아닌 사람은 '빡세·운영자·관리자' 같은 이름을 쓸 수 없음
--      (띄어쓰기·특수문자·전각 글자를 섞어 피하는 것도 막음)
--   3) 지금까지 '익명 세차러'로 보이던 한마디에도 같은 규칙으로 이름을 채움
--
-- 보안
--   - 새 도우미 함수 2개는 아무도 직접 부를 수 없음(트리거 안에서만 씀)
--   - 트리거의 나머지 규칙(30초 제한, 같은 곳 한 달 1번, 도배 방지)은 그대로
--   - 화면이 아니라 DB에서 검사하므로 화면을 우회해도 막힘
--
-- 참고: 이 파일을 실행하면 place_comments_before_insert 본문이 바뀌므로
--       rollback_2026-11-12.sql 은 '본문이 예상 밖'이라며 스스로 멈춤(안전하게 아무것도 안 바꿈).
-- 여러 번 실행해도 안전합니다.

begin;

-- ── 1) 무작위 이름 (앞말 30 × 뒷말 30 = 900가지) ──
-- 같은 seed(이용자 아이디)에는 늘 같은 이름이 나옴
create or replace function public.ppx_auto_nick(seed text)
returns text
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  with a(w) as (select array[
    '폼건 든','고압수 쏘는','버블 가득한','거품 좋아하는','두 버킷 쓰는',
    '휠 닦는','타이어 닦는','매트 빠는','실내 털어내는','타월 접는',
    '물기 닦는','드라잉 중인','물자국 싫어하는','철분제거 중인','클레이 문지르는',
    '왁스 바르는','코팅 올리는','유리막 입힌','광 내는','반짝이는',
    '광택에 진심인','디테일에 집착하는','무광 지키는','셀프세차 장인','세차장 단골',
    '새벽 세차하는','주말마다 세차하는','비 와도 세차하는','동전 챙긴','세차 끝낸']),
  b(w) as (select array[
    '수달','해달','비버','물개','돌고래','펭귄',
    '오리','참새','부엉이','고양이','강아지','여우',
    '북극여우','너구리','다람쥐','청설모','토끼','고슴도치',
    '햄스터','두더지','미어캣','카피바라','알파카','코알라',
    '판다','레서판다','백곰','사슴','거북이','하마']),
  h(n) as (select ((hashtextextended(coalesce(seed, ''), 20261113) % 900) + 900) % 900)
  select a.w[(h.n / 30)::int + 1] || ' ' || b.w[(h.n % 30)::int + 1] from a, b, h
$$;
revoke all on function public.ppx_auto_nick(text) from public, anon, authenticated;

-- ── 2) 운영자처럼 보이는 이름인지 ──
-- 전각 글자를 보통 글자로 바꾸고, 소문자로, 한글·영문·숫자 말고는 모두 지운 뒤 검사
-- 예: '빡 세', '빡.세', 'ＡＤＭＩＮ', '관 리 자' 모두 걸림
create or replace function public.ppx_nick_reserved(n text)
returns boolean
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select regexp_replace(lower(normalize(coalesce(n, ''), NFKC)), '[^0-9a-z가-힣]', '', 'g')
         ~ '(빡세|빡쎄|빡새|빡쌔|ppaxse|ppakse|운영자|운영진|운영팀|관리자|관리인|어드민|admin|공식)'
$$;
revoke all on function public.ppx_nick_reserved(text) from public, anon, authenticated;

-- ── 3) 한마디 저장 전 검사 (11-09d 규칙 + 닉네임 규칙) ──
create or replace function public.place_comments_before_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
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
$$;
revoke all on function public.place_comments_before_insert()
  from public, anon, authenticated;

-- ── 4) 지금까지 닉네임 없이 남긴 한마디에 이름 채우기 ──
-- 같은 사람이 남긴 글은 같은 이름. 작성자 정보가 없는 글은 글 번호로 이름을 정함
update public.place_comments
set nickname = public.ppx_auto_nick(coalesce(user_id::text, 'c' || id::text))
where nickname is null or btrim(nickname) = '';

commit;

-- 확인용 (결과만 보여 줌, 바꾸는 것 없음)
select
  (select count(*) from public.place_comments where nickname is null) as "이름 없는 한마디(0이어야 함)",
  (select count(distinct nickname) from public.place_comments) as "서로 다른 이름 수",
  has_function_privilege('anon', 'public.ppx_auto_nick(text)', 'execute') as "anon 직접 호출(false여야 함)",
  has_function_privilege('authenticated', 'public.ppx_nick_reserved(text)', 'execute') as "로그인 직접 호출(false여야 함)";
