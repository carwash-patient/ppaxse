-- 2026-11-12 보안 수정 되돌리기
-- migrate_2026-11-12.sql 을 실행한 뒤 문제가 생겼을 때만 사용합니다.
-- 조사 당시(2026-11-12 18:47) 상태로 되돌립니다:
--   트리거 3개 본문·INVOKER, 함수별 PUBLIC/anon/authenticated 권한, search_path, 새 함수 기본 권한, places 등록 정책.
--   service_role·소유자 권한은 건드리지 않습니다.
-- 끝에서 함수 ACL이 '변경 전'과 완전히 같은지 스스로 확인하고, 다르면 전체 취소합니다.
-- 실행 후 verify_rollback_2026-11-12.sql 로 원래대로 돌아왔는지 한 번 더 확인하세요.

begin;
set local search_path = pg_catalog, public;

create or replace function pg_temp.ppx_acl(acl aclitem[]) returns text language sql stable as $f$
  select case when acl is null then 'NULL(기본값)' else coalesce((
    select string_agg(x, ',' order by x) from (
      select case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
             || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
             || '/' || pg_get_userbyid(a.grantor) as x
      from aclexplode(acl) a) z), '(빈 ACL)') end
$f$;
-- 기대 ACL: postgres·service_role + (PUBLIC/anon/authenticated 중 해당) — 모두 EXECUTE, 부여자 postgres, GRANT OPTION 없음
create or replace function pg_temp.ppx_acl_expect(pub boolean, an boolean, au boolean) returns text language sql immutable as $f$
  select string_agg(x, ',' order by x) from unnest(array['postgres=EXECUTE/postgres', 'service_role=EXECUTE/postgres']
    || case when pub then array['PUBLIC=EXECUTE/postgres'] else '{}'::text[] end
    || case when an  then array['anon=EXECUTE/postgres'] else '{}'::text[] end
    || case when au  then array['authenticated=EXECUTE/postgres'] else '{}'::text[] end) x
$f$;
create or replace function pg_temp.ppx_defacl(r regrole) returns text language sql stable as $f$
  select coalesce(string_agg(x, ' | ' order by x), '(없음)') from (
    select d.defaclobjtype::text || '/' || case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end
           || ' ' || pg_temp.ppx_acl(d.defaclacl) as x
  from pg_default_acl d where d.defaclrole = r) z
$f$;
create or replace function pg_temp.ppx_defacl_f() returns text language sql stable as $f$
  select coalesce(string_agg(x, ' | ' order by x), '(없음)') from (
    select d.defaclobjtype::text || '/' || case when d.defaclnamespace = 0 then '-' else d.defaclnamespace::regnamespace::text end
           || ' ' || pg_temp.ppx_acl(d.defaclacl) as x
  from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclobjtype = 'f') z
$f$;
create or replace function pg_temp.ppx_defacl_expect(t text, s text, a aclitem[]) returns text language sql stable as $f$
  select t || '/' || s || ' ' || pg_temp.ppx_acl(a)
$f$;

create temp table _fn on commit drop as
with fn_expect(sig, def_before, def_after, was_public, was_anon, was_auth, sp_before, to_anon, to_auth, md5_before, md5_after) as (values
  ('admin_abuse_summary()', true, true, false, false, true, 'public', false, true, '28c4b04e49ce3233d837ac56e7078e24', '28c4b04e49ce3233d837ac56e7078e24'),
  ('admin_block(uuid,boolean)', true, true, true, false, true, 'public', false, true, 'faca4dda056cdb69c2a5e0698579324f', 'faca4dda056cdb69c2a5e0698579324f'),
  ('admin_block_commenter(bigint)', true, true, true, false, true, 'public', false, true, '51fd99230035956506ea98047c05b556', '51fd99230035956506ea98047c05b556'),
  ('admin_channel_stats(integer)', true, true, false, false, true, 'public', false, true, 'eab60d257282f3a5a95b1401f9d2c0b4', 'eab60d257282f3a5a95b1401f9d2c0b4'),
  ('admin_event_draw(date,boolean)', true, true, false, false, true, 'public', false, true, '8c44794dd052f7a884b79b9121f2b66c', '8c44794dd052f7a884b79b9121f2b66c'),
  ('admin_event_entries(timestamp with time zone,timestamp with time zone)', true, true, true, false, true, 'public', false, true, '4a44c3366b44ef03d36ba2ab47914bc2', '4a44c3366b44ef03d36ba2ab47914bc2'),
  ('admin_event_week(date)', true, true, false, false, true, 'public', false, true, '6810c94a426351ae8561ffabdcfad369', '6810c94a426351ae8561ffabdcfad369'),
  ('admin_type_votes()', true, true, false, false, true, 'public', false, true, '490a9f8f7ab296aff139ada4512f349c', '490a9f8f7ab296aff139ada4512f349c'),
  ('admin_visit_stats(integer)', true, true, false, false, true, 'public', false, true, '5168b4bd03d20a7d21c1f8e6f5bd4042', '5168b4bd03d20a7d21c1f8e6f5bd4042'),
  ('delete_my_account()', true, true, false, false, true, 'public', false, true, '9bdb043e72e2cf3c56863ef2c30bcd72', '9bdb043e72e2cf3c56863ef2c30bcd72'),
  ('finish_claim(uuid)', true, true, true, false, true, 'public', false, true, '118f3b9136c39d272e18476e27d5cb19', '118f3b9136c39d272e18476e27d5cb19'),
  ('handle_new_user()', true, true, true, true, true, 'public', false, false, 'f4b09971e3d3e7d7d19ce238176cf0b3', 'f4b09971e3d3e7d7d19ce238176cf0b3'),
  ('is_admin()', true, true, true, true, true, 'public', true, true, 'd5808500f03173b4303120b0ddea4332', 'd5808500f03173b4303120b0ddea4332'),
  ('my_pending_count()', true, true, true, true, true, 'public', false, false, '9bcbc3181520bafcc785adbf1f0f92ba', '9bcbc3181520bafcc785adbf1f0f92ba'),
  ('my_pending_reports()', true, true, true, true, true, 'public', false, false, '580a40f8629ae47258286f3719b2c87e', '580a40f8629ae47258286f3719b2c87e'),
  ('place_checks_after_insert()', true, true, true, true, true, 'public', false, false, 'c73057efaa1b1c48721a8a27feae7945', 'c73057efaa1b1c48721a8a27feae7945'),
  ('place_checks_before_insert()', false, true, true, true, true, null, false, false, '78fb038706663939306fae86af3a80f0', 'e5c5bee930aadac68c3d831cffcadf04'),
  ('place_comment_reports_before_insert()', true, true, false, false, false, 'pg_catalog, public', false, false, '7d9eacbbe37c727a6a08b4943806892a', '7d9eacbbe37c727a6a08b4943806892a'),
  ('place_comments_before_insert()', true, true, false, false, false, 'pg_catalog, public', false, false, 'b1e0b24e00755c55b48709908a8932f3', 'b1e0b24e00755c55b48709908a8932f3'),
  ('place_comments_count()', true, true, true, true, true, 'public', false, false, 'c20e5e03ed94fda829dff20fa5d30eec', 'c20e5e03ed94fda829dff20fa5d30eec'),
  ('place_reports_before_insert()', false, true, true, true, true, null, false, false, '55e1a7a64024e77f2ca8d6fadd88ac66', 'c32c958bd059dc299736ec6d02b6a78c'),
  ('place_reports_before_update()', false, false, true, true, true, null, false, false, 'e0536fb90addb9ee57b835578ef21f53', 'e0536fb90addb9ee57b835578ef21f53'),
  ('places_before_insert()', false, true, true, true, true, null, false, false, 'fe163cb59f37f8a38635be3c9e353713', '50f1cb02972a06be3572fa773b91038d'),
  ('places_before_update()', false, false, true, true, true, null, false, false, '6132ae4520ddde55c7275c13621aa399', '6132ae4520ddde55c7275c13621aa399'),
  ('places_fix_types()', false, false, true, true, true, null, false, false, 'bfce81346ba86b6788de80e1ccebc0a0', 'bfce81346ba86b6788de80e1ccebc0a0'),
  ('ppx_auto_draw(timestamp with time zone)', true, true, false, false, false, 'public', false, false, '0b8f6aba7a44ad360212a6cfcd98ae37', '0b8f6aba7a44ad360212a6cfcd98ae37'),
  ('ppx_burst_guard(text,bigint)', true, true, false, false, true, 'public', false, false, '71f7b8b38efaab267af6ab1c8edf8447', '71f7b8b38efaab267af6ab1c8edf8447'),
  ('ppx_enter_event(bigint)', true, true, false, false, true, 'public', false, true, '936e700bba0c8a10fe26d0f9079ca073', '936e700bba0c8a10fe26d0f9079ca073'),
  ('ppx_entry_valid(event_entries)', true, true, false, false, false, 'public', false, false, '08618e2d3a9c70748407222cd0f062b2', '08618e2d3a9c70748407222cd0f062b2'),
  ('ppx_event_draw_at(date)', false, false, true, true, true, null, false, false, 'f7fffc98dacf0af77d9512347aedee7d', 'f7fffc98dacf0af77d9512347aedee7d'),
  ('ppx_event_draw_run(date)', true, true, false, false, false, 'public', false, false, 'c99ed9f41f39e2431f2818a95a8242df', 'c99ed9f41f39e2431f2818a95a8242df'),
  ('ppx_event_start()', false, false, true, true, true, null, false, false, 'd1b2fd2aee83f03c3b5889a2b3db9daf', 'd1b2fd2aee83f03c3b5889a2b3db9daf'),
  ('ppx_event_status()', true, true, false, true, true, 'public', true, true, '5f3b2d34f4635a56c9cc09551caad740', '5f3b2d34f4635a56c9cc09551caad740'),
  ('ppx_event_week(timestamp with time zone)', false, false, true, true, true, null, false, false, '63b61e3d435f2d9796f23c45c74b0c56', '63b61e3d435f2d9796f23c45c74b0c56'),
  ('ppx_guard(text)', true, true, true, true, true, 'public', false, false, '724560cfdbf3d60d6da872f761ddfde7', '724560cfdbf3d60d6da872f761ddfde7'),
  ('ppx_is_member(uuid)', true, true, false, false, false, 'public', false, false, 'c17b6f9270ac5dbb4b79b53dbf24bd8d', 'c17b6f9270ac5dbb4b79b53dbf24bd8d'),
  ('ppx_log_block(text,text)', true, true, false, false, true, 'public', false, true, 'dc9a6b23e23da87a1f2e1184f6a7ce86', 'dc9a6b23e23da87a1f2e1184f6a7ce86'),
  ('ppx_precheck(text,bigint)', true, true, false, false, true, 'public', false, true, '9747c02ea5ba9c2250bfbac879b6db54', '9747c02ea5ba9c2250bfbac879b6db54'),
  ('ppx_stats()', true, true, true, true, true, 'public', true, true, '773f76fdf39d08c06ad7d232ae90831e', '773f76fdf39d08c06ad7d232ae90831e'),
  ('ppx_track(uuid,text,text)', true, true, false, true, true, 'public', true, true, 'e05f12181508e0f5a14918574bab3c30', 'e05f12181508e0f5a14918574bab3c30'),
  ('ppx_vote_type(bigint,text,text[])', true, true, false, false, true, 'public', false, true, '04a4eef7317d157e377b12c967d0fa05', '04a4eef7317d157e377b12c967d0fa05'),
  ('start_claim()', true, true, true, false, true, 'public', false, true, '6b58648198bbe72df928bb69aa486e85', '6b58648198bbe72df928bb69aa486e85')
)
select * from fn_expect;
create or replace temp view _cur as with cur_fn as (
  select p.oid, replace(p.oid::regprocedure::text, 'public.', '') as sig, p.prosecdef as definer,
         pg_get_userbyid(p.proowner) as owner, p.proconfig, p.proacl, md5(p.prosrc) as src_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
) select * from cur_fn;

-- 사전 검사: 함수 목록이 같고, 각 함수가 '변경 전' 또는 '적용 후' 상태 중 하나여야 함 (조용히 건너뛰지 않음)
do $$
declare bad text;
begin
  select string_agg(coalesce(e.sig || ' (없어짐)', '조사 때 없던 함수: ' || c.sig), ', ') into bad
  from _fn e full join _cur c on c.sig = e.sig where e.sig is null or c.sig is null;
  if bad is not null then
    raise exception '[되돌리기 중단] 함수 목록이 조사 때와 달라요: %  → 수동 대응 필요(검토 문서 5장)', bad;
  end if;
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where c.owner <> 'postgres'
     or not ((c.definer = e.def_before and c.src_md5 = e.md5_before) or (c.definer = e.def_after and c.src_md5 = e.md5_after));
  if bad is not null then
    raise exception '[되돌리기 중단] 소유자·DEFINER·본문이 예상 밖이에요: %  → 수동 대응 필요', bad;
  end if;
end $$;

-- 1) 트리거 3개를 원래 본문·호출자 권한(INVOKER)으로
create or replace function public.places_before_insert()
returns trigger language plpgsql as $fn$
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
  perform public.ppx_burst_guard('place');
  if public.my_pending_count() >= 5 then
    raise exception '확인을 기다리는 요청이 5개 있어요. 처리된 뒤에 다시 요청해 주세요.';
  end if;
  return new;
end $fn$;
create or replace function public.place_reports_before_insert()
returns trigger language plpgsql as $fn$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  new.reporter    := auth.uid();
  new.status      := 'pending';
  new.reviewed_by := null;
  new.reviewed_at := null;
  if new.photo is not null and new.photo not like auth.uid()::text || '/%' then
    raise exception '사진 정보가 올바르지 않아요';
  end if;
  perform public.ppx_guard('report');
  perform public.ppx_burst_guard('report', new.place_id);
  if public.my_pending_reports() >= 10 then
    raise exception '확인을 기다리는 제보가 10개 있어요. 처리된 뒤에 다시 보내 주세요.';
  end if;
  return new;
end $fn$;
create or replace function public.place_checks_before_insert()
returns trigger language plpgsql as $fn$
begin
  if current_user not in ('anon', 'authenticated') then return new; end if;
  new.user_id := auth.uid();
  new.created_on := current_date;
  new.created_at := now();
  perform public.ppx_guard('check');
  return new;
end $fn$;

-- 2) 함수 권한을 조사 때와 똑같이 (PUBLIC/anon/authenticated만 다시 줌)
do $$
declare f record;
begin
  for f in select c.oid, e.* from _fn e join _cur c using (sig) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.oid::regprocedure);
    if f.was_public then execute format('grant execute on function %s to public', f.oid::regprocedure); end if;
    if f.was_anon   then execute format('grant execute on function %s to anon', f.oid::regprocedure); end if;
    if f.was_auth   then execute format('grant execute on function %s to authenticated', f.oid::regprocedure); end if;
  end loop;
end $$;

-- 3) search_path를 함수별 원래 값으로 (없던 것은 reset)
do $$
declare f record;
begin
  for f in select c.oid, e.sp_before from _fn e join _cur c using (sig) loop
    if f.sp_before is null then
      execute format('alter function %s reset search_path', f.oid::regprocedure);
    else
      execute format('alter function %s set search_path = %s', f.oid::regprocedure, f.sp_before);
    end if;
  end loop;
end $$;

-- 4) 새 함수 기본 권한을 원래대로
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated;
alter default privileges for role postgres grant execute on functions to public;

-- 5) places 등록 정책을 원래대로
drop policy if exists "places: 추가 요청" on public.places;
create policy "places: 추가 요청" on public.places
  for insert to authenticated
  with check (true);

-- 6) 스스로 확인: 함수 ACL·DEFINER·본문·search_path가 '변경 전'과 완전히 같은가
do $$
declare bad text;
begin
  select string_agg(c.sig, ', ') into bad from _fn e join _cur c using (sig)
  where pg_temp.ppx_acl(c.proacl) <> pg_temp.ppx_acl_expect(e.was_public, e.was_anon, e.was_auth)
     or c.definer <> e.def_before or c.src_md5 <> e.md5_before
     or c.proconfig is distinct from (case when e.sp_before is null then null else array['search_path=' || e.sp_before] end);
  if bad is not null then raise exception '[되돌리기 확인 실패] 원래와 다른 함수: %  → 전체 취소됨', bad; end if;
end $$;

commit;
