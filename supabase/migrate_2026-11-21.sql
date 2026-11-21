-- 2026-11-21: 보안 수정 계획서(3단계) 중 운영자 승인 없이 적용한 것 — 운영 DB에 이미 적용됨 (Claude가 Supabase 도구로 실행)
-- 되돌리기: supabase/rollback_2026-11-21.sql
-- 추첨 관련 함수는 건드리지 않음 (11/23 첫 자동 추첨과 무관)

-- A-1: 제보 사진은 운영자만 볼 수 있게 (이용자 화면은 사진을 보지 않음. 올리기·하루 20장 조건 그대로)
drop policy "report-photos: 보기" on storage.objects;
create policy "report-photos: 보기" on storage.objects for select to authenticated
  using (bucket_id = 'report-photos' and public.is_admin());

-- B: 이벤트 표 권한 좁히기 (운영자 화면이 쓰는 14칸만. id·created_at·updated_at 은 기본값·트리거가 채움)
revoke usage on sequence public.events_id_seq from anon;
revoke insert, update on public.events from authenticated;
grant insert (title, kind, status, icon, start_date, end_date, draw_date, winners, target,
              body, btn_label, btn_url, pinned, hidden) on public.events to authenticated;
grant update (title, kind, status, icon, start_date, end_date, draw_date, winners, target,
              body, btn_label, btn_url, pinned, hidden) on public.events to authenticated;

-- D: 이벤트 버튼 링크 검사 강화 (https 주소 안 따옴표·빈칸·줄바꿈·역슬래시 막기). mailto 는 운영자 결정 전이라 안 넣음
--    admin.html 저장 검사, events.html 표시 검사와 같은 규칙
alter table public.events drop constraint events_btn_url_check;
alter table public.events add constraint events_btn_url_check check (
  btn_url is null or (char_length(btn_url) <= 500 and (
       btn_url ~ '^https://[^/\[:space:]"''<>]+[^[:space:]"''<>\]*$'
    or btn_url ~ '^[a-z0-9_.?=&#-][a-z0-9_./?=&#-]*$')));

-- A-3: 처리 대기 제보에 붙어 있지 않고 올라온 지 1시간 넘은 사진 목록 (운영자만). 지우기는 운영자 화면이 Storage API로 함
--      (Storage 파일은 SQL로 지울 수 없음 — storage.protect_delete)
create or replace function public.admin_orphan_photos()
returns table (name text, created_at timestamptz)
language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if not public.is_admin() then raise exception '운영자만 볼 수 있어요.'; end if;
  return query
    select o.name, o.created_at from storage.objects o
    where o.bucket_id = 'report-photos'
      and o.created_at < now() - interval '1 hour'
      and not exists (select 1 from public.place_reports r where r.photo = o.name and r.status = 'pending')
    order by o.created_at
    limit 200;
end $$;
revoke all on function public.admin_orphan_photos() from public, anon, authenticated;
grant execute on function public.admin_orphan_photos() to authenticated;
