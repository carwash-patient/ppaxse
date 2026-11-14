-- 2026-11-14d 광고성 정보(혜택·이벤트 소식) 이메일 수신 동의 — 선택 항목
-- migrate_2026-11-14c.sql 다음에 실행. 여러 번 실행해도 안전합니다.
-- 운영자가 Supabase SQL Editor에서 '전체'를 한 번에 Run 합니다.
--
-- 무엇을 바꾸나
--  · profiles에 두 칸 추가
--      - marketing_email_at     : 지금 동의한 상태면 동의한 시각, 동의 안 했으면 비어 있음
--      - marketing_email_off_at : 마지막으로 동의를 끈(철회한) 시각
--    시각은 DB가 직접 적음. 이용자가 화면에서 날짜를 마음대로 넣을 수 없음(열 수정 권한을 주지 않음)
--  · 가입할 때 '[선택] 혜택·이벤트 소식 이메일로 받기'에 체크하면 가입 시각이 동의 시각으로 저장됨
--    (handle_new_user에 한 줄 추가. 나머지 내용은 그대로)
--  · ppx_set_marketing(on_off): 회원 본인이 마이페이지에서 켜고 끄는 함수. 이메일 회원만 가능(익명 불가)
--      - 켜기: 동의 시각 = 지금 (이미 켜져 있으면 처음 동의한 시각 그대로)
--      - 끄기: 동의 시각 비움, 철회 시각 = 지금
--
-- 참고: 카카오톡·문자로 보내려면 나중에 그 수단에 대한 동의를 따로 받아야 함. 이 동의는 '이메일'만 해당
-- 참고: handle_new_user 본문이 바뀌므로, rollback_2026-11-12.sql의 본문 비교는 이 함수에서도 '예상 밖'으로 멈춤(아무것도 안 바뀜)

begin;

alter table public.profiles add column if not exists marketing_email_at     timestamptz;
alter table public.profiles add column if not exists marketing_email_off_at timestamptz;

-- 가입: 지금까지와 같고, marketing_email_at 한 칸만 더 채움
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, nickname, skill, cars, avatar_car, avatar_color, car_model, signup_source, signup_note, signup_ref, agreed_at, marketing_email_at)
  values (
    new.id,
    left(coalesce(nullif(trim(m->>'nickname'), ''), split_part(new.email, '@', 1)), 20),
    case when m->>'skill' in ('beginner','mid','pro','maniac') then m->>'skill' end,
    coalesce(array(select x from jsonb_array_elements_text(case when jsonb_typeof(m->'cars') = 'array' then m->'cars' else '[]'::jsonb end) x
                   where x in ('sedan','suv','sports','truck','van','coupe','ev','other') limit 8), '{}'),
    case when m->>'avatar_car' in ('sedan','suv','sports','truck','van','coupe','ev','other') then m->>'avatar_car' end,
    case when lower(m->>'avatar_color') ~ '^#[0-9a-f]{6}$' then lower(m->>'avatar_color') end,
    nullif(left(trim(coalesce(m->>'car_model', '')), 40), ''),
    case when m->>'signup_source' in ('cafe','insta','youtube','search','friend','poster','other') then m->>'signup_source' end,
    case when m->>'signup_source' = 'other' then nullif(left(regexp_replace(trim(coalesce(m->>'signup_note', '')), '[<>]', '', 'g'), 30), '') end,
    case when lower(m->>'ref') ~ '^[a-z0-9_-]{1,30}$' then lower(m->>'ref') end,
    case when (m->>'age14') = 'true' and new.email is not null then now() end,
    case when (m->>'marketing_email') = 'true' and (m->>'age14') = 'true' and new.email is not null then now() end
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- 마이페이지: 본인 동의 켜고 끄기
create or replace function public.ppx_set_marketing(on_off boolean)
returns json language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare
  v uuid := auth.uid();
  r public.profiles;
begin
  if v is null or not public.ppx_is_member(v) then
    raise exception '이메일로 가입한 회원만 바꿀 수 있어요';
  end if;
  if on_off is null then raise exception '켜기/끄기 값이 필요해요'; end if;

  if on_off then
    update public.profiles set marketing_email_at = coalesce(marketing_email_at, now())
     where id = v returning * into r;
  else
    update public.profiles
       set marketing_email_off_at = case when marketing_email_at is not null then now() else marketing_email_off_at end,
           marketing_email_at = null
     where id = v returning * into r;
  end if;
  if r.id is null then raise exception '회원 정보를 찾지 못했어요'; end if;

  return json_build_object('on', r.marketing_email_at is not null,
                           'at', r.marketing_email_at,
                           'off_at', r.marketing_email_off_at);
end $$;
revoke all on function public.ppx_set_marketing(boolean) from public, anon, authenticated;
grant execute on function public.ppx_set_marketing(boolean) to authenticated;

commit;
