-- 2026-11-12 보안 점검 테스트 데이터 정리 ② 삭제 (① 미리 보기에서 '진행 가능'을 확인한 뒤에만 실행)
-- ①과 똑같은 매개변수 세 줄을 넣습니다. 대상은 '테스트 계정 UUID + 레코드 ID'로만 정합니다.
-- 지우기 전에 ①과 같은 검사를 다시 하고, 하나라도 예상과 다르면 아무것도 지우지 않고 멈춥니다(전체가 하나의 트랜잭션).
-- 지운 건수가 예상(ID 개수)과 다르면 전체 취소합니다. 다시 실행하면 '계정 없음'으로 멈추며 아무것도 지우지 않습니다.
begin;

create temp table _p on commit drop as select
  '00000000-0000-0000-0000-000000000000'::uuid as test_user,   -- ← 테스트 계정 UUID
  array[]::bigint[] as place_ids,                              -- ← 만들어진 세차장 제보 ID들
  array[]::bigint[] as report_ids;                             -- ← 만들어진 정보 제보 ID들

create temp table if not exists _sectest_result (순서 int, 항목 text, 건수 int, 내용 text);
truncate _sectest_result;

do $$
declare p record; r record; n int; bad text := ''; del int;
begin
  select * into p from _p;

  -- (1) 계정: 익명·이메일 없음·가입 꼬리표 sectest·일반 역할
  if not exists (select 1 from auth.users u join public.profiles f on f.id = u.id
                 where u.id = p.test_user and coalesce(u.is_anonymous, false) and u.email is null
                   and f.signup_ref = 'sectest' and f.role = 'user') then
    raise exception '[정리 중단] % 는 익명 테스트 계정이 아니거나 없습니다', p.test_user;
  end if;

  -- (2) 지울 행이 모두 있고, 테스트 계정이 만든 테스트 제보인가
  select count(*) into n from public.places x where x.id = any(p.place_ids) and x.submitted_by = p.test_user
    and x.source = 'user' and x.status in ('pending', 'rejected') and x.name like '[보안점검 %';
  if n <> cardinality(p.place_ids) then
    raise exception '[정리 중단] 세차장 제보 %건 중 %건만 조건(테스트 계정·이용자 제보·대기/거절·꼬리표)에 맞습니다', cardinality(p.place_ids), n;
  end if;
  select count(*) into n from public.place_reports x where x.id = any(p.report_ids) and x.reporter = p.test_user and x.memo like '[보안점검 %';
  if n <> cardinality(p.report_ids) then
    raise exception '[정리 중단] 정보 제보 %건 중 %건만 조건(테스트 계정·꼬리표)에 맞습니다', cardinality(p.report_ids), n;
  end if;

  -- (3) 테스트 계정 ID가 들어 있는 모든 칸을 확인: auth.users·profiles 를 가리키는 외래키 칸 전부 + public·storage 의 uuid 칸 전부
  for r in
    select n2.nspname as sch, c.relname as tbl, a.attname as col, bool_or(k.oid is not null) as is_fk
    from pg_class c join pg_namespace n2 on n2.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    left join pg_constraint k on k.contype = 'f' and k.conrelid = c.oid and k.conkey = array[a.attnum]
          and k.confrelid in ('auth.users'::regclass, 'public.profiles'::regclass)
    where c.relkind in ('r', 'p')
      and (k.oid is not null or (n2.nspname in ('public', 'storage') and a.atttypid = 'uuid'::regtype))
    group by 1, 2, 3
  loop
    begin
      execute format('select count(*) from %I.%I where %I = $1', r.sch, r.tbl, r.col) into n using p.test_user;
    exception when insufficient_privilege then
      if r.sch = 'auth' then continue; end if;      -- 로그인 내부 표: 계정을 지우면 Auth 가 함께 정리
      raise;
    end;
    continue when n = 0 or r.sch = 'auth';
    continue when (r.sch, r.tbl, r.col) = ('public', 'profiles', 'id') and n = 1;
    continue when (r.sch, r.tbl, r.col) = ('public', 'places', 'submitted_by') and n = cardinality(p.place_ids);
    continue when (r.sch, r.tbl, r.col) = ('public', 'place_reports', 'reporter') and n = cardinality(p.report_ids);
    bad := bad || format(' %s.%s.%s=%s건', r.sch, r.tbl, r.col, n);
  end loop;
  if bad <> '' then raise exception '[정리 중단] 테스트 계정에 예상하지 못한 데이터가 있습니다:%', bad; end if;

  -- (4) 지울 세차장 제보에 다른 데이터(남의 제보·한마디·확인·투표)가 붙어 있지 않은가
  for r in
    select n2.nspname as sch, c.relname as tbl, a.attname as col
    from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n2 on n2.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
    where k.contype = 'f' and k.confrelid = 'public.places'::regclass and array_length(k.conkey, 1) = 1
  loop
    execute format('select count(*) from %I.%I where %I = any($1)', r.sch, r.tbl, r.col) into n using p.place_ids;
    if (r.sch, r.tbl) = ('public', 'place_reports') then
      n := n - (select count(*) from public.place_reports x where x.id = any(p.report_ids) and x.place_id = any(p.place_ids));
    end if;
    if n <> 0 then bad := bad || format(' %s.%s.%s=%s건', r.sch, r.tbl, r.col, n); end if;
  end loop;
  if bad <> '' then raise exception '[정리 중단] 테스트 세차장 제보에 다른 데이터가 붙어 있습니다:%', bad; end if;

  -- (5) 삭제 — ID와 소유자를 함께 조건으로
  delete from public.place_reports x where x.id = any(p.report_ids) and x.reporter = p.test_user;
  get diagnostics del = row_count;
  if del <> cardinality(p.report_ids) then raise exception '[정리 취소] 정보 제보 삭제 건수 % ≠ 예상 %', del, cardinality(p.report_ids); end if;
  insert into _sectest_result values (1, '정보 제보 삭제', del, array_to_string(p.report_ids, ', '));

  delete from public.places x where x.id = any(p.place_ids) and x.submitted_by = p.test_user and x.source = 'user' and x.status in ('pending', 'rejected');
  get diagnostics del = row_count;
  if del <> cardinality(p.place_ids) then raise exception '[정리 취소] 세차장 제보 삭제 건수 % ≠ 예상 %', del, cardinality(p.place_ids); end if;
  insert into _sectest_result values (2, '세차장 제보 삭제', del, array_to_string(p.place_ids, ', '));

  delete from auth.users u where u.id = p.test_user and coalesce(u.is_anonymous, false) and u.email is null;
  get diagnostics del = row_count;
  if del <> 1 then raise exception '[정리 취소] 계정 삭제 건수 % ≠ 1', del; end if;
  insert into _sectest_result values (3, '익명 테스트 계정 삭제', del, p.test_user::text);

  -- (6) 지운 뒤 확인: 계정·프로필·대상 행이 남아 있지 않은가
  select (select count(*) from auth.users where id = p.test_user) + (select count(*) from public.profiles where id = p.test_user)
       + (select count(*) from public.places where id = any(p.place_ids)) + (select count(*) from public.place_reports where id = any(p.report_ids)) into n;
  if n <> 0 then raise exception '[정리 취소] 지운 뒤에도 대상이 %건 남아 있습니다', n; end if;
  insert into _sectest_result values (4, '지운 뒤 남은 대상', 0, '없음');
end $$;

commit;

select 항목, 건수, 내용 from _sectest_result order by 순서;
