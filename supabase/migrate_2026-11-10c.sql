-- 2026-11-10c 가입 경로 '기타'를 고르면 직접 쓴 내용(30자)도 저장
-- migrate_2026-11-10b.sql 다음에 실행. 여러 번 실행해도 안전합니다.

alter table public.profiles add column if not exists signup_note text;
alter table public.profiles drop constraint if exists profiles_signup_note_chk;
alter table public.profiles add constraint profiles_signup_note_chk
  check (signup_note is null or char_length(signup_note) between 1 and 30);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, nickname, skill, cars, avatar_car, avatar_color, car_model, signup_source, signup_note, signup_ref, agreed_at)
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
    case when (m->>'age14') = 'true' and new.email is not null then now() end
  )
  on conflict (id) do nothing;
  return new;
end $$;


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
    'by_source', coalesce((select json_agg(json_build_object('source', s.src, 'members', s.n, 'notes', s.notes) order by s.n desc) from (
      select coalesce(p.signup_source, '(답 안 함)') as src, count(*) as n,
             array_remove(array_agg(distinct p.signup_note), null) as notes
      from public.profiles p where p.created_at >= since and public.ppx_is_member(p.id)
      group by 1) s), '[]'::json)
  );
end $$;
revoke all on function public.admin_channel_stats(int) from public, anon;
grant execute on function public.admin_channel_stats(int) to authenticated;
