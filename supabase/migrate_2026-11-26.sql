-- 2026-11-26: 앱 테스터 피드백 받기 (app_feedback)
-- migrate_2026-11-24b.sql 다음에 실행. 여러 번 실행해도 안전합니다. 기존 데이터는 바꾸지 않습니다.
-- ppaxse-test에서 먼저 시험. 되돌리기: rollback_2026-11-26.sql
--
-- · 앱 화면 구석의 '불편한 점 알려주기' 버튼으로 보낸 글을 저장
-- · 표는 이용자가 직접 읽기·쓰기 불가. 보내기는 함수 ppx_feedback(msg, pg, dev)로만
--   (글 2~1000자, 30초에 한 번, 하루 20개까지, 막힌 이용자는 못 보냄)
-- · 운영자만 조회하고 '처리함' 표시(status)를 바꿀 수 있음
-- · 보낸 사람이 탈퇴하면 보낸 사람 칸만 비우고 글은 남김 (개선 기록용)
-- · 같이 남기는 것: 눌렀던 화면 주소, 휴대폰 기종 요약(예: Android 14 · SM-S918N). 위치·연락처는 안 남김

create table if not exists public.app_feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid default auth.uid() references public.profiles(id) on delete set null,
  message    text not null check (char_length(btrim(message)) between 2 and 1000),
  page       text check (page is null or char_length(page) <= 200),
  device     text check (device is null or char_length(device) <= 120),
  status     text not null default 'new' check (status in ('new', 'done')),
  created_at timestamptz not null default now()
);
create index if not exists app_feedback_time_idx on public.app_feedback (created_at desc);
create index if not exists app_feedback_user_idx on public.app_feedback (user_id, created_at desc);

alter table public.app_feedback enable row level security;
revoke all on public.app_feedback from public, anon, authenticated;
grant select, update (status) on public.app_feedback to authenticated;

drop policy if exists "feedback: 운영자 조회" on public.app_feedback;
create policy "feedback: 운영자 조회" on public.app_feedback
  for select to authenticated using ((select public.is_admin()));
drop policy if exists "feedback: 운영자 처리" on public.app_feedback;
create policy "feedback: 운영자 처리" on public.app_feedback
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- 보내기 (가입 없이 쓰는 이용자도 가능: 화면이 먼저 익명 이름표를 만듦)
create or replace function public.ppx_feedback(msg text, pg text, dev text)
returns bigint
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v uuid := auth.uid(); m text := btrim(coalesce(msg, '')); nid bigint;
begin
  if v is null then raise exception '로그인 정보가 없어요. 화면을 새로 고친 뒤 다시 보내 주세요.'; end if;
  if exists (select 1 from public.profiles where id = v and blocked) then
    raise exception '이 기기에서는 지금 보낼 수 없어요. 문제가 있다면 운영자에게 알려주세요.';
  end if;
  if char_length(m) < 2 then raise exception '내용을 2자 이상 적어 주세요.'; end if;
  if char_length(m) > 1000 then raise exception '1000자까지 보낼 수 있어요.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v::text || ':feedback', 0));
  if exists (select 1 from public.app_feedback where user_id = v and created_at > now() - interval '30 seconds') then
    raise exception '피드백은 30초에 한 번씩 보낼 수 있어요. 잠시 기다려 주세요.';
  end if;
  if (select count(*) from public.app_feedback where user_id = v and created_at > now() - interval '1 day') >= 20 then
    raise exception '오늘은 더 보낼 수 없어요. 내일 다시 부탁드려요.';
  end if;
  insert into public.app_feedback (user_id, message, page, device)
  values (v, m, left(nullif(btrim(pg), ''), 200), left(nullif(btrim(dev), ''), 120))
  returning id into nid;
  return nid;
end $$;
revoke all on function public.ppx_feedback(text, text, text) from public, anon, authenticated;
grant execute on function public.ppx_feedback(text, text, text) to authenticated;
