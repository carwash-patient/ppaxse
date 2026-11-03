-- 2026-11-03(3) 기프티콘 추첨: 운영자가 기간을 정해 '가입 회원 중 후기를 남긴 사람' 명단을 봄
-- 한 번만 실행 (여러 번 실행해도 안전)
-- 후기 = 정보 제보 · 한마디 · '정보가 맞아요' · 세차장 추가 요청 (가입 전에 이 기기로 남긴 것도 가입하면 옮겨져서 포함)
create or replace function public.admin_event_entries(p_from timestamptz, p_to timestamptz)
returns table (user_id uuid, nickname text, email text, reports int, comments int, checks int, places int, total int, first_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception '운영자만 볼 수 있어요'; end if;
  return query
  with a as (
    select r.reporter as uid, 1 as rp, 0 as cm, 0 as ck, 0 as pl, r.created_at as t from public.place_reports r where r.created_at >= p_from and r.created_at < p_to
    union all select c.user_id, 0, 1, 0, 0, c.created_at from public.place_comments c where not c.hidden and c.created_at >= p_from and c.created_at < p_to
    union all select k.user_id, 0, 0, 1, 0, k.created_at from public.place_checks k where k.created_at >= p_from and k.created_at < p_to
    union all select s.submitted_by, 0, 0, 0, 1, s.created_at from public.places s where s.source = 'user' and s.created_at >= p_from and s.created_at < p_to
  )
  select u.id, pr.nickname, u.email::text, sum(a.rp)::int, sum(a.cm)::int, sum(a.ck)::int, sum(a.pl)::int,
         (sum(a.rp) + sum(a.cm) + sum(a.ck) + sum(a.pl))::int, min(a.t)
  from a
  join auth.users u on u.id = a.uid
  left join public.profiles pr on pr.id = u.id
  where coalesce(u.is_anonymous, false) = false and u.email is not null
    and coalesce(pr.blocked, false) = false and coalesce(pr.role, 'user') <> 'admin'
  group by u.id, pr.nickname, u.email
  order by min(a.t);
end $$;
revoke execute on function public.admin_event_entries(timestamptz, timestamptz) from anon;

-- 가입·로그인하면 가입 전에 이 기기로 남긴 한마디도 계정으로 옮김 (예전엔 제보·요청·확인만 옮겼음)
create or replace function public.finish_claim(t uuid)
returns int language plpgsql security definer set search_path = public as $$
declare a uuid; n int := 0; k int;
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) then return 0; end if;
  delete from public.anon_claims where token = t returning anon_id into a;
  if a is null or a = auth.uid() then return 0; end if;
  update public.places set submitted_by = auth.uid() where submitted_by = a;        get diagnostics k = row_count; n := n + k;
  update public.place_reports set reporter = auth.uid() where reporter = a;         get diagnostics k = row_count; n := n + k;
  update public.place_comments set user_id = auth.uid() where user_id = a;          get diagnostics k = row_count; n := n + k;
  -- 같은 날 같은 세차장을 두 번 확인한 기록은 하나만 남김
  delete from public.place_checks c where c.user_id = a and exists (
    select 1 from public.place_checks d where d.user_id = auth.uid() and d.place_id = c.place_id and d.created_on = c.created_on);
  update public.place_checks set user_id = auth.uid() where user_id = a;            get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke execute on function public.finish_claim(uuid) from anon;
