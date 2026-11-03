-- 2026-11-03(2) 세차장마다 한마디 개수 (지도 마커에 💬 표시용)
-- 한 번만 실행 (여러 번 실행해도 안전)
alter table public.places add column if not exists comment_count int not null default 0;

-- 한마디가 생기거나 숨겨지거나 지워지면 그 세차장의 개수를 다시 셈 (일반 사용자는 places를 못 고치므로 security definer)
create or replace function public.place_comments_count()
returns trigger language plpgsql security definer set search_path = public as $$
declare pid bigint := coalesce(new.place_id, old.place_id);
begin
  update public.places set comment_count =
    (select count(*) from public.place_comments where place_id = pid and not hidden)
  where id = pid;
  return null;
end $$;
drop trigger if exists place_comments_count on public.place_comments;
create trigger place_comments_count after insert or update of hidden or delete on public.place_comments
  for each row execute function public.place_comments_count();

-- 지금까지 쌓인 한마디로 한 번 맞춤
update public.places p set comment_count = c.n
from (select place_id, count(*) n from public.place_comments where not hidden group by place_id) c
where p.id = c.place_id and p.comment_count is distinct from c.n;

-- 앱에서 추가 요청할 때 개수를 마음대로 넣지 못하게
create or replace function public.places_before_insert()
returns trigger language plpgsql as $$
begin
  if current_user not in ('anon', 'authenticated') or public.is_admin() then
    return new;
  end if;
  new.status        := 'pending';
  new.source        := 'user';
  new.submitted_by  := auth.uid();
  new.source_ref    := null;
  new.owner_id      := null;
  new.reviewed_by   := null;
  new.reviewed_at   := null;
  new.reject_reason := null;
  new.checked_at    := null;
  new.check_count   := 0;
  new.comment_count := 0;
  perform public.ppx_guard('place');
  if public.my_pending_count() >= 5 then
    raise exception '확인을 기다리는 요청이 5개 있어요. 처리된 뒤에 다시 요청해 주세요.';
  end if;
  return new;
end $$;
