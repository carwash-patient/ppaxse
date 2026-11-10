-- 2026-11-10b 가입 화면 정리 · 유입 경로 · 차종 아이콘 · 회원 탈퇴 · 추첨 제외 표시
-- migrate_2026-11-10.sql(자동 추첨) 다음에 실행. 여러 번 실행해도 안전합니다.
--
--  1) 프로필: 차종 아이콘(대표 차종·색), 제조사·모델(선택), 가입 경로(선택), 유입 꼬리표(?ref=), 만 14세 확인·동의 시각
--  2) 유입 경로: 링크의 ?ref=꼬리표를 기기별로 처음 한 번만 기록 → 운영자 '채널별 통계'
--     · 꼬리표는 'cafe', 'insta' 같은 채널 이름일 뿐 개인정보가 아님
--  3) 회원 탈퇴: 본인 계정·프로필 즉시 삭제 (남긴 제보·한마디는 누가 썼는지 모르게 남음)
--  4) 추첨 현황의 '내 응모번호'에 추첨 제외(숨김·막힘) 여부 표시

-- ── 1) 프로필 칸 추가 ──
alter table public.profiles add column if not exists avatar_car   text;
alter table public.profiles add column if not exists avatar_color text;
alter table public.profiles add column if not exists car_model    text;
alter table public.profiles add column if not exists signup_source text;
alter table public.profiles add column if not exists signup_ref   text;
alter table public.profiles add column if not exists agreed_at    timestamptz;

alter table public.profiles drop constraint if exists profiles_avatar_car_chk;
alter table public.profiles add constraint profiles_avatar_car_chk
  check (avatar_car is null or avatar_car in ('sedan','suv','sports','truck','van','coupe','ev','other'));
alter table public.profiles drop constraint if exists profiles_avatar_color_chk;
alter table public.profiles add constraint profiles_avatar_color_chk
  check (avatar_color is null or avatar_color ~ '^#[0-9a-f]{6}$');
alter table public.profiles drop constraint if exists profiles_car_model_chk;
alter table public.profiles add constraint profiles_car_model_chk
  check (car_model is null or char_length(car_model) between 1 and 40);
alter table public.profiles drop constraint if exists profiles_signup_source_chk;
alter table public.profiles add constraint profiles_signup_source_chk
  check (signup_source is null or signup_source in ('cafe','insta','youtube','search','friend','poster','other'));
alter table public.profiles drop constraint if exists profiles_signup_ref_chk;
alter table public.profiles add constraint profiles_signup_ref_chk
  check (signup_ref is null or signup_ref ~ '^[a-z0-9_-]{1,30}$');

-- 본인이 마이페이지에서 고칠 수 있는 칸 (가입 경로·꼬리표·동의 시각은 고칠 수 없음)
grant update (avatar_car, avatar_color, car_model) on public.profiles to authenticated;

-- 가입(또는 익명 이름표 만들 때) 넘긴 값 저장. 잘못된 값은 버림
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, nickname, skill, cars, avatar_car, avatar_color, car_model, signup_source, signup_ref, agreed_at)
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
    case when lower(m->>'ref') ~ '^[a-z0-9_-]{1,30}$' then lower(m->>'ref') end,
    case when (m->>'age14') = 'true' and new.email is not null then now() end
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- ── 2) 유입 경로 ──
create table if not exists public.ppx_visitor_ref (
  visitor  uuid primary key,
  ref      text not null check (ref ~ '^[a-z0-9_-]{1,30}$'),
  first_at timestamptz not null default now()
);
alter table public.ppx_visitor_ref enable row level security;
revoke all on public.ppx_visitor_ref from anon, authenticated;

-- 방문 기록 (꼬리표가 있으면 그 기기의 첫 유입 경로로 한 번만 저장)
drop function if exists public.ppx_track(uuid, text);
create or replace function public.ppx_track(v uuid, p text, r text default null)
returns void language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Seoul')::date;
begin
  if v is null then return; end if;
  if p is null or p not in ('home','map','review','login','join','mypage') then p := 'other'; end if;
  insert into public.ppx_visits (day, visitor, page) values (d, v, p)
  on conflict (day, visitor, page) do update
    set hits = least(public.ppx_visits.hits + 1, 200), last_at = now();
  if r is not null and lower(r) ~ '^[a-z0-9_-]{1,30}$' then
    insert into public.ppx_visitor_ref (visitor, ref) values (v, lower(r)) on conflict (visitor) do nothing;
  end if;
end $$;
revoke all on function public.ppx_track(uuid, text, text) from public;
grant execute on function public.ppx_track(uuid, text, text) to anon, authenticated;

-- 운영자: 채널별 새 방문자 → 응모 → 가입 (최근 days일)
create or replace function public.admin_channel_stats(days int default 30)
returns json language plpgsql stable security definer set search_path = public as $$
declare since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(days, 30), 365)));
        since_day date := (since at time zone 'Asia/Seoul')::date;
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요'; end if;
  return json_build_object(
    'by_ref', coalesce((select json_agg(t order by t.visitors desc, t.ref) from (
      select u.ref, sum(u.visitors)::int as visitors, sum(u.entries)::int as entries, sum(u.members)::int as members
      from (
        -- 꼬리표 달고 처음 들어온 기기
        select r.ref, count(*) as visitors, 0 as entries, 0 as members
        from public.ppx_visitor_ref r where r.first_at >= since group by r.ref
        union all
        -- 꼬리표 없이 처음 들어온 기기 (이 기간에 처음 방문)
        select '(꼬리표 없음)', count(*), 0, 0 from (
          select v.visitor from public.ppx_visits v group by v.visitor
          having min(v.day) >= since_day) f
        where not exists (select 1 from public.ppx_visitor_ref r where r.visitor = f.visitor)
        union all
        -- 응모한 사람 (기기·계정 기준)
        select coalesce(p.signup_ref, '(꼬리표 없음)'), 0, count(distinct e.user_id), 0
        from public.event_entries e join public.profiles p on p.id = e.user_id
        where e.created_at >= since group by 1
        union all
        -- 가입한 회원
        select coalesce(p.signup_ref, '(꼬리표 없음)'), 0, 0, count(*)
        from public.profiles p where p.created_at >= since and public.ppx_is_member(p.id) group by 1
      ) u
      group by u.ref
      having sum(u.visitors) + sum(u.entries) + sum(u.members) > 0) t), '[]'::json),
    'by_source', coalesce((select json_agg(json_build_object('source', s.src, 'members', s.n) order by s.n desc) from (
      select coalesce(p.signup_source, '(답 안 함)') as src, count(*) as n
      from public.profiles p where p.created_at >= since and public.ppx_is_member(p.id)
      group by 1) s), '[]'::json)
  );
end $$;
revoke all on function public.admin_channel_stats(int) from public, anon;
grant execute on function public.admin_channel_stats(int) to authenticated;

-- ── 3) 회원 탈퇴 ──
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
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
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ── 4) 추첨 현황: 내 응모번호에 추첨 제외 여부 ──
create or replace function public.ppx_event_status()
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v uuid := auth.uid();
  w date := greatest(public.ppx_event_week(now()), public.ppx_event_start());
  lw date;
begin
  select max(week) into lw from public.event_winners;
  return json_build_object(
    'start', public.ppx_event_start(),
    'week', w, 'week_end', w + 6, 'draw_date', w + 9,
    'all_count',    (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e)),
    'member_count', (select count(*) from public.event_entries e where e.week = w and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
    'winners_all', 2, 'winners_member', 2,
    'last', case when lw is null then null else json_build_object(
      'week', lw,
      'all_count',    (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e)),
      'member_count', (select count(*) from public.event_entries e where e.week = lw and public.ppx_entry_valid(e) and public.ppx_is_member(e.user_id)),
      'winners', (select json_agg(json_build_object('code', e.code, 'pool', x.pool) order by x.pool desc, e.code)
                  from public.event_winners x join public.event_entries e on e.id = x.entry_id where x.week = lw)
    ) end,
    'mine', case when v is null then '[]'::json else coalesce((
      select json_agg(json_build_object('week', e.week, 'code', e.code,
                      'won', (select x.pool from public.event_winners x where x.entry_id = e.id),
                      'valid', public.ppx_entry_valid(e)) order by e.week desc)
      from (select * from public.event_entries where user_id = v order by week desc limit 6) e), '[]'::json) end,
    'member', case when v is null then false else public.ppx_is_member(v) end
  );
end $$;
revoke all on function public.ppx_event_status() from public;
grant execute on function public.ppx_event_status() to anon, authenticated;
