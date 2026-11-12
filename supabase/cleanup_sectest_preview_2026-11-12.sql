-- 2026-11-12 보안 점검 테스트 데이터 정리 ① 미리 보기 (읽기 전용 — SELECT 한 개, 아무것도 지우지 않음)
-- 쓰기 테스트 스크립트(api_postapply_write_test.js)가 돌려준 '정리_매개변수'를 아래 세 줄에 그대로 넣습니다.
-- 꼬리표 문자열이 아니라 '테스트 계정 UUID + 만들어진 레코드 ID'로만 대상을 정합니다.
-- 결과 표에서 판정이 모두 '삭제 대상' / '함께 지워짐(정상)' / '없음(정상)' 이면 ② 삭제 SQL로 넘어갑니다.
-- '★ 중단' 이 한 줄이라도 있으면 지우지 말고 원인을 먼저 확인합니다.
with p as (select
  '00000000-0000-0000-0000-000000000000'::uuid as test_user,   -- ← 테스트 계정 UUID
  array[]::bigint[] as place_ids,                              -- ← 만들어진 세차장 제보 ID들
  array[]::bigint[] as report_ids                              -- ← 만들어진 정보 제보 ID들
),
-- 테스트 계정 ID가 들어 있을 수 있는 모든 칸: (1) auth.users 또는 profiles 를 가리키는 외래키 칸 전부(pg_constraint)
--                                           (2) public·storage 스키마의 uuid 칸 전부 (외래키가 없는 칸까지)
ref_cols as (
  select distinct n.nspname as sch, c.relname as tbl, a.attname as col, c.oid as reloid,
         bool_or(k.oid is not null) as is_fk, max(k.confdeltype::text) as on_delete
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_constraint k on k.contype = 'f' and k.conrelid = c.oid and k.conkey = array[a.attnum]
        and k.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
  where c.relkind in ('r', 'p')
    and (k.oid is not null or (n.nspname in ('public', 'storage') and a.atttypid = 'uuid'::regtype))
  group by 1, 2, 3, 4
),
ref_counts as (
  select r.*, case when has_table_privilege(r.reloid, 'select')
    then (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I where %I = %L', r.sch, r.tbl, r.col, (select test_user from p)), false, true, '')))[1]::text::int
    end as n
  from ref_cols r
),
-- 지울 세차장 제보를 가리키는 다른 표의 행 (세차장을 지우면 함께 지워지는 것들)
place_refs as (
  select n.nspname as sch, c.relname as tbl, a.attname as col,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I where %I = any(%L::bigint[])', n.nspname, c.relname, a.attname, (select place_ids from p)), false, true, '')))[1]::text::int as n
  from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
  where k.contype = 'f' and k.confrelid = 'public.places'::regclass and array_length(k.conkey, 1) = 1
),
res(순서, 종류, 대상, 내용, 판정) as (
  select 1, '테스트 계정', p.test_user::text,
         coalesce((select 'is_anonymous=' || coalesce(u.is_anonymous, false) || ', email=' || coalesce(u.email, '(없음)')
                          || ', 가입 꼬리표=' || coalesce((select signup_ref from public.profiles where id = u.id), '(없음)')
                   from auth.users u where u.id = p.test_user), '계정 없음'),
         case when exists (select 1 from auth.users u join public.profiles f on f.id = u.id
                           where u.id = p.test_user and coalesce(u.is_anonymous, false) and u.email is null
                             and f.signup_ref = 'sectest' and f.role = 'user')
              then '삭제 대상' else '★ 중단: 익명 테스트 계정이 아님' end
  from p
  union all
  select 2, '세차장 제보', i::text,
         coalesce((select x.name || ' / ' || x.status || ' / ' || x.source || ' / 제출자 ' || coalesce(x.submitted_by::text, '(없음)')
                   from public.places x where x.id = i), '행 없음'),
         case when exists (select 1 from public.places x where x.id = i and x.submitted_by = p.test_user and x.source = 'user'
                           and x.status in ('pending', 'rejected') and x.name like '[보안점검 %')
              then '삭제 대상' else '★ 중단: 테스트 계정이 만든 대기 제보가 아님' end
  from p, unnest(p.place_ids) i
  union all
  select 3, '정보 제보', i::text,
         coalesce((select left(x.memo, 40) || ' / ' || x.status || ' / 세차장 ' || x.place_id || ' / 제보자 ' || coalesce(x.reporter::text, '(없음)')
                   from public.place_reports x where x.id = i), '행 없음'),
         case when exists (select 1 from public.place_reports x where x.id = i and x.reporter = p.test_user and x.memo like '[보안점검 %')
              then '삭제 대상' else '★ 중단: 테스트 계정이 만든 제보가 아님' end
  from p, unnest(p.report_ids) i
  union all
  select 4, '계정이 남긴 데이터', r.sch || '.' || r.tbl || '.' || r.col,
         coalesce(r.n::text, '(조회 권한 없음)') || '건' || case when r.is_fk then ' · 외래키(on delete ' || r.on_delete || ')' else '' end,
         case when r.n is null then '확인 불가'
              when r.n = 0 then '없음(정상)'
              when r.sch = 'auth' then '함께 지워짐(정상)'
              when (r.sch, r.tbl, r.col) = ('public', 'profiles', 'id') and r.n = 1 then '함께 지워짐(정상)'
              when (r.sch, r.tbl, r.col) = ('public', 'places', 'submitted_by') and r.n = (select cardinality(place_ids) from p) then '삭제 대상과 같음'
              when (r.sch, r.tbl, r.col) = ('public', 'place_reports', 'reporter') and r.n = (select cardinality(report_ids) from p) then '삭제 대상과 같음'
              else '★ 중단: 예상하지 못한 데이터' end
  from ref_counts r
  union all
  select 5, '세차장 제보에 붙은 데이터', r.sch || '.' || r.tbl || '.' || r.col, r.n || '건',
         case when r.n = 0 then '없음(정상)'
              when (r.sch, r.tbl) = ('public', 'place_reports')
                   and r.n = (select count(*) from public.place_reports x, p where x.id = any(p.report_ids) and x.place_id = any(p.place_ids)) then '삭제 대상과 같음'
              else '★ 중단: 테스트 세차장에 다른 데이터가 붙어 있음' end
  from place_refs r
)
select 종류, 대상, 내용, 판정 from (
  select 0 as 순서, '요약' as 종류, '전체' as 대상,
         count(*) filter (where 판정 like '★%') || '건 중단 사유 / 삭제 대상: 계정 ' || count(*) filter (where 순서 = 1 and 판정 = '삭제 대상')
           || ', 세차장 제보 ' || count(*) filter (where 순서 = 2 and 판정 = '삭제 대상') || ', 정보 제보 ' || count(*) filter (where 순서 = 3 and 판정 = '삭제 대상') as 내용,
         case when count(*) filter (where 판정 like '★%') = 0 then '진행 가능' else '★ 중단' end as 판정
  from res
  union all select * from res
) t order by 순서, (판정 like '★%') desc, (판정 in ('없음(정상)')) , 대상;
