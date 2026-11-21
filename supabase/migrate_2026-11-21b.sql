-- 2026-11-21 (b): 사장님(via=owner) 제보를 운영자가 전화로 확인한 기록 — 운영자 결정. 운영 DB에 이미 적용됨
-- 운영자 화면에서 '☎️ 전화로 확인했어요'를 체크하고 반영하면 admin_owner_checked() 가 누가·언제를 남김
-- (같은 날 운영자 결정으로 운영자 시험 응모 1건(event_entries id 12, 추첨 제외 상태)을 지움 — 데이터 정리라 SQL 파일엔 없음)
alter table public.place_reports add column if not exists owner_checked_at timestamptz;
alter table public.place_reports add column if not exists owner_checked_by uuid;

-- 제보하는 사람이 이 칸을 미리 채워 보낼 수 없게 (나머지는 기존과 같음)
create or replace function public.place_reports_before_insert()
returns trigger
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated') then
    return new;
  end if;
  new.reporter    := auth.uid();
  new.status      := 'pending';
  new.reviewed_by := null;
  new.reviewed_at := null;
  new.owner_checked_at := null;
  new.owner_checked_by := null;
  if new.photo is not null and new.photo not like auth.uid()::text || '/%' then
    raise exception '사진 정보가 올바르지 않아요';
  end if;
  perform public.ppx_guard('report');
  perform public.ppx_burst_guard('report', new.place_id);
  if public.my_pending_reports() >= 10 then
    raise exception '확인을 기다리는 제보가 10개 있어요. 처리된 뒤에 다시 보내 주세요.';
  end if;
  return new;
end $$;

create or replace function public.admin_owner_checked(rid bigint)
returns timestamptz
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare t timestamptz;
begin
  if not public.is_admin() then raise exception '운영자만 할 수 있어요.'; end if;
  update public.place_reports
     set owner_checked_at = now(), owner_checked_by = auth.uid()
   where id = rid and via = 'owner' and status = 'pending'
  returning owner_checked_at into t;
  if t is null then raise exception '확인할 사장님 제보를 찾지 못했어요.'; end if;
  return t;
end $$;
revoke all on function public.admin_owner_checked(bigint) from public, anon, authenticated;
grant execute on function public.admin_owner_checked(bigint) to authenticated;
