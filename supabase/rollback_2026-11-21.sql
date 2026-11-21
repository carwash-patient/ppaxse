-- 2026-11-21 되돌리기: migrate_2026-11-21.sql 이전 상태로 (문제가 생겼을 때만 실행)
drop policy "report-photos: 보기" on storage.objects;
create policy "report-photos: 보기" on storage.objects for select to authenticated
  using (bucket_id = 'report-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

grant usage on sequence public.events_id_seq to anon;
grant insert, update on public.events to authenticated;

alter table public.events drop constraint events_btn_url_check;
alter table public.events add constraint events_btn_url_check check (
  btn_url is null or (char_length(btn_url) <= 500 and (
       btn_url ~ '^https://[^/]'
    or btn_url ~ '^[a-z0-9_.?=&#-][a-z0-9_./?=&#-]*$')));

drop function if exists public.admin_orphan_photos();
