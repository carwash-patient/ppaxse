# 빡세(PPAXSE.COM) 보안 수정 — 3차 보완 결과 보고서

- 작성: 2026-11-12, Claude
- 기준: `PPAXSE 3차 보완 요청서`
- 브랜치: `security/2026-11-12` (로컬 커밋만 있음. GitHub·main 미반영)
- **판정: 조건부 보류.** 운영 적용 후보로 올리기 전에 남은 확인 2건이 있습니다(9장).

> **운영 DB에는 아무것도 쓰지 않았습니다.** 운영 DB에서 실행한 것은 운영자가 직접 Run 한 읽기 전용 조사 SQL 1회(18:47)뿐입니다.
> 모든 쓰기 테스트는 Claude 작업 공간의 **로컬 PostgreSQL 16** 테스트 DB에서 했습니다. 운영은 PostgreSQL 17입니다.

---

## 1. 바뀐 파일

| 파일 | 상태 | 핵심 |
|---|---|---|
| `supabase/migrate_2026-11-12.sql` | 다시 씀 | 시그니처 42개를 기준값으로 둠. 사전 검사 6종, OID 단위 권한 부여, search_path에 `pg_temp`를 맨 뒤에 붙여 통일, 사후 검사 6종, 하나의 트랜잭션 |
| `supabase/rollback_2026-11-12.sql` | 다시 씀 | 시그니처별 원래 ACL과 원래 search_path로 복원. 함수 목록이 다르면 조용히 건너뛰지 않고 중단 |
| `supabase/verify_rollback_2026-11-12.sql` | 새 파일 | 조사 당시 상태와 항목별 PASS/FAIL 비교(45개 항목). SELECT 1개라 읽기 전용 |
| `supabase/inspect_2026-11-12.sql` | 보강 | 시그니처, 이름 겹침, 역할별 실제 권한, ACL 항목, 테이블 RLS·권한, profiles 열 권한, 스키마 권한, 정책 permissive 여부 추가 |
| `supabase/schema.sql` | 끝부분 교체 | 새로 설치할 때도 같은 결과가 나오도록 요약본 반영. 새 DB에서 역할 테스트 72/72 통과 |
| `AGENTS.md` | 한 줄 | 새 함수는 직접 grant하고 `search_path = pg_catalog, public, pg_temp`를 붙이라는 규칙 |
| `docs/security-tests-2026-11-12/` | 새 폴더 | 로컬 테스트 도구(Supabase 흉내 `shim.sql`, 역할 테스트 72건, 사이클 스크립트)와 결과 |

이전 안(2차)은 커밋 `0f288b9`에 그대로 남아 있습니다.

---

## 2. 사실 확인의 근거와 범위

| 구분 | 내용 | 확인 수준 |
|---|---|---|
| 함수 목록·DEFINER·소유자·search_path·ACL | 운영 조사(18:47) 원자료 | **운영 확인** |
| 함수 본문 | 운영 42개 본문과 저장소 정의(main의 schema.sql)를 공백 제거 후 해시 비교 → **42/42 일치** | **운영 확인** |
| 정책, 트리거, 열 기본값, 기본 권한, 확장, 크론 | 운영 조사 원자료 | **운영 확인** |
| 이름 겹침(오버로드) | 운영 함수 이름 42개가 모두 다름(이름 목록으로 확인). 이번 조사 SQL에 `overloads` 항목도 추가 | **운영 확인** |
| 테이블 RLS 켜짐·테이블 권한·profiles 열 권한·스키마 CREATE 권한 | 저장소와 같은 정의로 만든 테스트 DB에서 확인 | **운영 미확인** → 보강한 조사 SQL을 한 번 더 Run 해야 함 |
| 실제 요청 동작(PostgREST, Storage API, Auth) | 테스트 DB는 DB 계층만 흉내 냄 | **미검증** → 적용 후 사이트 테스트로 확인 |

---

## 3. 보완 A — 시그니처 단위 권한

### 3.1 방식
- 기준표 `_ppx_fn`에 **정확한 시그니처 42개**를 넣었습니다. 시그니처는 `set local search_path = pg_catalog, public` 기준으로 표기합니다.
  - 각 시그니처마다 DEFINER 여부, 변경 전 PUBLIC/anon/authenticated 권한, 변경 전 search_path, 변경 후 anon/authenticated 권한을 함께 적었습니다.
- 실제 DB의 시그니처 집합과 **양방향으로 정확히 같아야** 진행합니다. `full join` 결과 한쪽이 비면 즉시 중단합니다.
- 권한은 `oid::regprocedure` 단위로 줍니다. 이름 목록 방식은 없앴습니다.
- 사후 검사는 두 가지를 모두 비교합니다.
  - `aclexplode`(직접 부여 항목)
  - `has_function_privilege`(상속·PUBLIC 경로까지 포함한 실제 실행 가능 여부)

### 3.2 두 결과가 다를 수 있는 이유
- **PUBLIC에 준 권한**은 ACL에는 PUBLIC 항목 하나로만 보입니다. 하지만 `has_function_privilege('anon')`는 true가 됩니다.
  - 변경 전 `admin_block` 등이 이 경우였습니다. ACL에는 anon 항목이 없는데 anon이 실행할 수 있었습니다.
- **소유자(postgres)**는 ACL에 항목이 없어도 항상 실행할 수 있습니다.
- **역할 상속**: 운영 DB에서 `anon`과 `authenticated`는 서로 상속하지 않습니다(테스트 DB에서도 noinherit로 재현).
- 이번 사후 검사는 두 기준을 모두 요구하므로 위 경로가 남아 있으면 실패합니다.

### 3.3 함수 권한 매트릭스 (변경 전 → 변경 후)

P=PUBLIC, A=anon, U=authenticated 직접 권한입니다. service_role과 소유자(postgres)는 42개 모두 그대로 유지합니다.

| 시그니처 | DEFINER | 변경 전 | 변경 후 | 분류 / 근거 |
|---|---|---|---|---|
| `is_admin()` | O | P A U | A U | 비로그인+회원. RLS SELECT 정책(역할 public)에서 사용 |
| `ppx_stats()` | O | P A U | A U | 비로그인+회원. 홈 화면 RPC |
| `ppx_event_status()` | O | A U | A U | 비로그인+회원. 이벤트 현황 RPC |
| `ppx_track(uuid,text,text)` | O | A U | A U | 비로그인+회원. 방문 기록 RPC |
| `delete_my_account()` | O | U | U | 회원. 마이페이지 RPC |
| `start_claim()` | O | P U | U | 회원(익명). 가입 전 기록 연결 |
| `finish_claim(uuid)` | O | P U | U | 회원. 가입 후 기록 연결 |
| `ppx_enter_event(bigint)` | O | U | U | 회원. 응모 |
| `ppx_log_block(text,text)` | O | U | U | 회원. 차단 사유 기록 |
| `ppx_precheck(text,bigint)` | O | U | U | 회원. 제보 전 검사 |
| `ppx_vote_type(bigint,text,text[])` | O | U | U | 회원. 종류 투표 |
| `admin_abuse_summary()` | O | U | U | 운영자 화면 |
| `admin_block(uuid,boolean)` | O | P U | U | 운영자 화면 |
| `admin_block_commenter(bigint)` | O | P U | U | 운영자 화면 |
| `admin_channel_stats(integer)` | O | U | U | 운영자 화면 |
| `admin_event_draw(date,boolean)` | O | U | U | 운영자 화면 |
| `admin_event_entries(timestamptz,timestamptz)` | O | P U | U | 운영자 화면(응모자 이메일 반환) |
| `admin_event_week(date)` | O | U | U | 운영자 화면 |
| `admin_type_votes()` | O | U | U | 운영자 화면 |
| `admin_visit_stats(integer)` | O | U | U | 운영자 화면 |
| `ppx_guard(text)` | O | P A U | U | 트리거 도우미. INVOKER 트리거 3개가 호출자 권한으로 부름 |
| `ppx_burst_guard(text,bigint)` | O | U | U | 트리거 도우미. 같은 이유 |
| `my_pending_count()` | O | P A U | U | 트리거 도우미. `places_before_insert`가 부름 |
| `my_pending_reports()` | O | P A U | U | 트리거 도우미. `place_reports_before_insert`가 부름 |
| `handle_new_user()` | O | P A U | 없음 | 트리거(auth.users) |
| `place_checks_after_insert()` | O | P A U | 없음 | 트리거 |
| `place_comments_count()` | O | P A U | 없음 | 트리거 |
| `place_comments_before_insert()` | O | 없음 | 없음 | 트리거(원래 막혀 있음) |
| `place_comment_reports_before_insert()` | O | 없음 | 없음 | 트리거(원래 막혀 있음) |
| `place_checks_before_insert()` | X | P A U | 없음 | 트리거 |
| `place_reports_before_insert()` | X | P A U | 없음 | 트리거 |
| `place_reports_before_update()` | X | P A U | 없음 | 트리거 |
| `places_before_insert()` | X | P A U | 없음 | 트리거 |
| `places_before_update()` | X | P A U | 없음 | 트리거 |
| `places_fix_types()` | X | P A U | 없음 | 트리거 |
| `ppx_event_week(timestamptz)` | X | P A U | 없음 | 내부. DEFINER 함수 안에서만 사용 |
| `ppx_event_start()` | X | P A U | 없음 | 내부. 같은 이유 |
| `ppx_event_draw_at(date)` | X | P A U | 없음 | 내부. 같은 이유 |
| `ppx_event_draw_run(date)` | O | 없음 | 없음 | 내부(추첨 실행) |
| `ppx_auto_draw(timestamptz)` | O | 없음 | 없음 | 내부(크론, postgres로 실행) |
| `ppx_is_member(uuid)` | O | 없음 | 없음 | 내부 |
| `ppx_entry_valid(event_entries)` | O | 없음 | 없음 | 내부 |

**합계**: 변경 후 anon 4개, authenticated 24개, PUBLIC 0개. service_role은 42개 모두 그대로입니다.

**변경 전 비로그인(anon)이 실제로 실행할 수 있던 함수 중 이번에 닫히는 것** (테스트에서 확인):
- `start_claim`, `finish_claim`, `ppx_guard`, `my_pending_count`, `my_pending_reports`, `ppx_event_week`, `ppx_event_start`, `ppx_event_draw_at`, 트리거 함수들
- `admin_*` 3개(`admin_block`, `admin_block_commenter`, `admin_event_entries`)도 PUBLIC 경로로 열려 있었습니다. 다만 본문 `is_admin()` 검사에서 거절되고 있었습니다.

---

## 4. 보완 B — SECURITY DEFINER 전수 점검 (31개)

- 31개 모두 소유자는 `postgres`입니다.
- 변경 전 search_path는 29개가 `public`, 2개가 `pg_catalog, public`입니다. 변경 후에는 모두 `pg_catalog, public, pg_temp`입니다.
- 함수 본문은 운영과 해시로 일치함을 확인한 뒤 전부 읽었습니다.
- 공통 확인 사항:
  - 31개 모두 본문의 테이블과 함수를 `public.` / `auth.` / `storage.`로 스키마를 적어 부릅니다(이름만으로 부르는 사용자 객체 0건).
  - 확장 함수를 이름만으로 부르는 곳은 0건입니다.
  - 동적 SQL은 1건입니다(`delete_my_account`, 값은 `using $1`로 전달, 식별자 조립 없음).

| 함수 | 호출자 검증 | 입력값 검증 | 위험도 | 조치 |
|---|---|---|---|---|
| admin_abuse_summary() | 첫 줄 `is_admin()` | 입력 없음 | 낮음 | 권한 U만 |
| admin_block(uuid,boolean) | 첫 줄 `is_admin()` | 대상이 admin이면 바뀌지 않음 | 낮음 | PUBLIC 경로 닫음 |
| admin_block_commenter(bigint) | 첫 줄 `is_admin()` | 대상이 admin이면 바뀌지 않음 | 낮음 | PUBLIC 경로 닫음 |
| admin_channel_stats(integer) | 첫 줄 `is_admin()` | 기간 1~365일로 제한 | 낮음 | — |
| admin_event_draw(date,boolean) | 첫 줄 `is_admin()` | 발표 시각 전에는 거절 | 낮음 | — |
| admin_event_entries(timestamptz,timestamptz) | 첫 줄 `is_admin()` | 기간 값만 받음. **이메일 반환** | 중간(노출되면 개인정보) → 검사 있어 실제 위험 낮음 | PUBLIC 경로 닫음. 익명·회원 호출 시 거절 테스트 통과 |
| admin_event_week(date) | 첫 줄 `is_admin()` | 회원만 이메일 반환 | 낮음 | — |
| admin_type_votes() | 첫 줄 `is_admin()` | 입력 없음 | 낮음 | — |
| admin_visit_stats(integer) | 첫 줄 `is_admin()` | 1~90일로 제한 | 낮음 | — |
| delete_my_account() | uid 없음·익명·이메일 없음·운영자면 거절 | 입력 없음. 동적 SQL은 using 바인딩 | 낮음 | 탈퇴 후 같은 토큰으로 쓰기·운영자 RPC 거절 테스트 통과 |
| finish_claim(uuid) | uid 없음·익명이면 0 반환 | 일회용 토큰(uuid). 쓰면 지움 | **낮음(잠재)**: 토큰이 새면 다른 회원이 그 익명 기록을 가져갈 수 있음 | 이번 범위 밖. 토큰은 기기 안에서만 쓰임 |
| start_claim() | 익명만 허용 | 입력 없음. 30일 지난 토큰 정리 | 낮음 | anon 경로 닫음 |
| handle_new_user() | 트리거 전용 | 메타데이터 허용 목록·길이·형식 검사 | 낮음 | 직접 실행 막음 |
| is_admin() | `auth.uid()` 기준. 없으면 false | 입력 없음 | 낮음 | `role` 열은 사용자가 못 바꿈(테스트 통과) |
| my_pending_count() / my_pending_reports() | 본인 것만 셈 | 입력 없음 | 낮음 | anon 경로 닫음 |
| place_checks_after_insert() | 트리거 전용 | — | 낮음 | 직접 실행 막음 |
| place_comment_reports_before_insert() | uid 없으면 거절, 차단 사용자 거절 | 신고자를 본인으로 고정, 하루 10회 | 낮음 | 그대로 |
| place_comments_before_insert() | JWT role이 anon/authenticated일 때만 검사 | 작성자 고정, 숨김 false 고정, 30초·한 달 제한 | 낮음 | 그대로 |
| place_comments_count() | 트리거 전용 | — | 낮음 | 직접 실행 막음 |
| ppx_auto_draw(timestamptz) | 실행 권한 없음(크론 전용) | 시작일·발표 시각 검사 | 낮음 | 그대로 |
| ppx_burst_guard(text,bigint) | uid 없으면 통과(트리거 단계에서 이미 걸러짐) | 본인 기록만 조회. 잠금 키도 본인 uid | 낮음 | anon 경로 없음 |
| ppx_enter_event(bigint) | uid 필수, 차단·운영자 거절 | 본인 한마디만, 주 1회 | 낮음 | — |
| ppx_entry_valid(event_entries) | 실행 권한 없음 | — | 낮음 | 그대로 |
| ppx_event_draw_run(date) | 실행 권한 없음 | 주별 잠금 | 낮음 | 그대로 |
| ppx_event_status() | 비로그인 허용(공개 정보) | 본인 응모만 'mine'에 표시 | 낮음 | — |
| ppx_guard(text) | 본인 기록만 셈 | 종류 4가지 외에는 확인 기록으로 셈 | 낮음 | anon 경로 닫음 |
| ppx_is_member(uuid) | 실행 권한 없음 | — | 낮음 | 그대로 |
| ppx_log_block(text,text) | uid 필수 | 종류 허용 목록, 200자, 1시간 30건. 운영자 화면에서 `esc()`로 출력 | 낮음 | — |
| ppx_precheck(text,bigint) | uid 필수 | 종류 2가지만 | 낮음 | — |
| ppx_stats() | 공개 숫자만 | 입력 없음 | 낮음 | — |
| ppx_track(uuid,text,text) | 비로그인 허용 | 페이지·꼬리표 허용 목록, 하루·기기·페이지 200회 | **중간(통계 무결성)**: 방문 수를 부풀릴 수 있음 | 구조상 남는 위험(9장) |
| ppx_vote_type(bigint,text,text[]) | uid 필수 | 승인된 세차장만, 값 허용 목록 | 낮음 | — |

**실제 취약점(재현 가능한 권한 우회)은 발견하지 못했습니다.**
- 잠재 위험은 3건입니다: `finish_claim` 토큰 유출 시, `ppx_track` 통계 부풀리기, `admin_event_entries` 이메일 반환(검사가 있어 실제 위험은 낮음).
- `ppx_burst_guard`가 uid 없으면 그냥 통과하는 점은 우회가 아닙니다. 이 함수를 부르는 트리거들이 앞 단계에서 이미 비로그인을 막습니다(정책 `to authenticated`, `ppx_precheck`의 uid 필수 검사).

### 4.1 search_path 재검토
- 요청서 지적대로 `pg_temp` 위치를 정했습니다.
  - search_path에 `pg_temp`가 없으면 PostgreSQL은 임시 스키마를 **맨 앞**에서 테이블 이름을 찾습니다.
  - 그래서 `pg_temp`를 **맨 뒤**에 명시하는 것이 PostgreSQL 문서의 권장 방식입니다.
- 실제 위험은 낮습니다.
  - 모든 본문이 스키마를 적어 객체를 부릅니다.
  - PostgREST를 통해서는 사용자가 임시 테이블을 만들 수 없습니다.
- 그래도 42개 모두 `pg_catalog, public, pg_temp`로 통일했습니다.
- 스키마 CREATE 권한: anon과 authenticated 모두 public 스키마 CREATE 권한이 없습니다. 테스트 DB에서 확인했고, **운영은 보강 조사로 확인 필요**합니다.
- 변경 후 역할 테스트 72건이 모두 통과했으므로, 경로를 고정해서 깨진 함수는 없습니다.

---

## 5. 보완 C — 롤백의 완전성과 재현성

- `rollback_2026-11-12.sql`
  - 시작할 때 시그니처 집합을 비교합니다. 다르면 **[되돌리기 중단]**으로 멈춥니다(조용히 건너뛰지 않음).
  - PUBLIC/anon/authenticated만 원래대로 다시 줍니다. service_role과 소유자는 건드리지 않습니다.
  - search_path는 함수별 원래 값으로 되돌립니다. 원래 없던 9개는 `reset`합니다.
  - 기본 권한(스키마 단위, 전역)과 places 등록 정책을 원래 정의 그대로 다시 만듭니다.
- `verify_rollback_2026-11-12.sql`: 45개 항목을 비교하고 첫 줄에 요약을 보여 줍니다.
  - 함수 42개: 소유자, DEFINER, ACL이 NULL로 바뀌었는지, PUBLIC·anon·authenticated 직접 권한, anon·authenticated 실제 권한, service_role 권한, search_path
  - 기본 권한 2개: postgres의 public 스키마 단위, postgres 전역
  - 정책 1개: 이름, 명령, permissive, 역할, USING, WITH CHECK 전체
- `proacl`이 NULL인 경우와 명시적 ACL을 구분합니다. 조사 당시 42개 모두 명시적 ACL이었으므로, NULL로 바뀌면 FAIL입니다.

**불일치가 났을 때 수동 대응**
1. verify 결과의 FAIL 줄(함수와 항목)을 저장합니다.
2. 권한 문제면 해당 시그니처에 대해 `revoke all ... from public, anon, authenticated` 후, 매트릭스의 '변경 전' 값대로 다시 grant합니다.
3. search_path 문제면 `alter function … set search_path = <원래값>`을 쓰고, 원래 값이 없던 함수는 `reset`합니다.
4. 함수 목록 자체가 다르면(이름 변경·추가·삭제) 롤백이 멈춥니다. 무엇이 바뀌었는지 먼저 확인한 뒤 Claude에게 결과를 주세요. 기준표를 갱신해 다시 만듭니다.

---

## 6. 보완 D — 사전 조건과 안전장치

사전 검사 6종입니다. 하나라도 다르면 `[사전검사]` 오류를 내고 아무것도 바꾸지 않습니다.
1. 시그니처 집합이 42개와 정확히 일치하는가(추가·삭제·인자 변경·이름 겹침)
2. 소유자가 postgres이고 DEFINER 여부가 같은가
3. 트리거 11개(테이블+함수)가 존재하고 켜져 있는가. public 함수를 쓰는 트리거 수가 정확히 11개인가
4. RLS 정책(public, storage)에서 쓰는 public 함수가 `is_admin` 하나뿐인가(호출 관계 전제)
5. 열 기본값이 public 함수를 쓰지 않는가(`pg_depend`로 확인)
6. places 등록 정책이 '변경 전' 또는 '이미 적용된' 모양이고, places의 INSERT 정책이 1개뿐인가

사후 검사 6종입니다. 하나라도 다르면 `[사후검사]` 오류를 내고 **트랜잭션 전체가 취소**됩니다.
- ACL 직접 항목
- 실제 권한
- service_role·소유자 권한 보존(변경 전 기록과 집합 비교)
- search_path
- 기본 권한
- places 정책

**트랜잭션**
- 스크립트 전체가 `begin … commit` 한 덩어리입니다.
- SQL 편집기처럼 파일 전체를 한 문자열로 보내는 방식(psycopg2, simple query)으로 테스트했습니다. 사후 검사 실패 시 DB가 조사 당시 그대로임을 확인했습니다(7장 [C]).
- 단, **Supabase SQL 편집기 자체에서는 아직 시험하지 않았습니다**(운영 DB이기 때문).
- `commit` 뒤의 결과 표 SELECT가 실패해도, 이미 커밋된 변경은 되돌아가지 않습니다. 그때는 롤백 SQL을 씁니다.
- 실패 메시지가 나오면 편집기에서 `rollback;`을 한 번 실행해도 해가 없습니다.

**적용 전 백업**
- 권한·설정 메타데이터는 조사 원자료(18:47)와 롤백 SQL에 들어 있는 스냅샷으로 복원할 수 있습니다. 함수 본문과 데이터는 이번에 바꾸지 않습니다.
- Supabase 무료 요금제의 자동 백업과 복원 범위는 **확인하지 못했습니다(미검증).**
  - 대시보드 Database → Backups 화면에서 운영자가 확인하는 것을 권합니다.
  - 데이터를 바꾸는 작업이 아니므로, 복원 지점이 없어도 롤백 SQL로 원상 복구할 수 있습니다.

---

## 7. 테스트 환경과 결과

**환경**
- 작업 공간의 PostgreSQL 16.15입니다.
- Supabase 흉내(`shim.sql`): anon·authenticated·service_role 역할, `auth.uid()`·`auth.jwt()`, `auth.users`, `storage.objects`·`foldername`, `cron.job`, 운영과 같은 기본 권한 행.
- DB는 main 브랜치 `schema.sql`로 만들었습니다(본문은 운영과 해시 일치).
- 권한과 search_path는 운영 조사 스냅샷과 같게 맞췄고, verify 결과 **45/45 PASS**로 운영 조사 당시와 같은 상태임을 확인했습니다.

**구문 검사**: 다섯 SQL 파일이 모두 오류 없이 실행됩니다(migrate, rollback, verify, inspect, schema.sql 새 설치).

**사이클 결과** (`cycle.sh`)

| 단계 | 결과 |
|---|---|
| [1] 변경 전 상태 = 조사 스냅샷 | PASS 45 / FAIL 0 |
| [2] 변경 전 역할 테스트 | 64 PASS / 8 FAIL. FAIL 8개는 **변경 전에 비로그인이 실행할 수 있던 함수들**로, 수정 대상을 확인한 것 |
| [3] 마이그레이션 1회차 | 성공 |
| [4] 마이그레이션 2회차(재실행) | 성공(결과 같음) |
| [5] 적용 후 스냅샷 비교 | 45개 모두 달라짐(정상) |
| [6] 적용 후 역할 테스트 | **72 PASS / 0 FAIL** |
| [7] 되돌리기 | 성공 |
| [8] 되돌린 뒤 스냅샷 비교 | **PASS 45 / FAIL 0** |
| [9] 되돌리기 재실행 | 성공, PASS 45 / FAIL 0 |

**안전장치 시험**

| 시험 | 결과 |
|---|---|
| [A] 조사 때 없던 함수가 있을 때 | `[사전검사] 함수 목록이 조사 때와 달라요: 없어야 할 함수: zz_extra()`. DB 변화 없음(PASS 45) |
| [B] 트리거 하나를 꺼 두었을 때 | `[사전검사] 트리거가 없거나 꺼져 있어요: public.places:places_before_insert()` |
| [C] 적용 도중 예상 밖 권한이 생겼을 때 | `[사후검사] ACL이 예상과 달라요: ppx_event_week(...)`. **DB 변화 없음(PASS 45) = 전체 취소 확인** |
| [D] 적용 후 함수 이름이 바뀐 상태에서 되돌리기 | `[되돌리기 중단] 함수 목록이 조사 때와 달라요: ppx_stats_old(), ppx_stats()` |
| [E] 한 문자열로 보내기(편집기 방식) | 적용 성공·결과 표 42행. 고장 낸 적용은 오류 후 취소. 되돌리기 후 PASS |
| 새 설치(schema.sql만으로) | 역할 테스트 72/72 PASS |

**역할 테스트 72건 요약** (`result_after.txt`)
- 비로그인 32건
  - 지도 조회, ppx_stats, ppx_event_status, ppx_track, is_admin은 정상입니다.
  - 그 밖의 함수 26개 호출은 모두 `permission denied`입니다.
  - places 직접 등록도 거부됩니다.
- 익명 로그인 15건
  - 정상: 세차장 제보가 `pending`·본인·`source=user`로 저장됩니다(`approved`·남의 UID·`source=public`로 조작 시도). 정보 제보도 `pending`·본인으로 저장됩니다(`applied`·남의 UID로 조작 시도). '다녀왔어요', 한마디, 종류 투표, start_claim도 정상입니다.
  - 거절: 운영자 RPC 2건(본문 검사), 승인된 세차장 수정(0행), 내부·트리거 함수 직접 실행, `role`을 admin으로 바꾸기, 프로필 직접 생성, 남의 제보 보기(0행).
- 일반 회원 12건
  - 정상: 제보, 제보 전 검사, 닉네임 수정, ppx_log_block, finish_claim, 탈퇴.
  - 거절: 운영자 통계, 남의 프로필 보기(0행), 남의 대기 세차장 보기(0행), 차단 풀기.
  - 탈퇴 후 같은 토큰으로 제보하면 외래키 오류로 거절, 운영자 RPC도 거절됩니다.
- 운영자 13건
  - 승인 상태로 직접 등록, 승인, 차단·해제, 통계 3종, 응모 목록 2종, 투표 보기, 한마디 숨김, 제보 처리, 전체 프로필 보기가 모두 정상입니다.
- 크론 1건: `ppx_auto_draw`가 postgres로 정상 실행됩니다.

---

## 8. 기존 사이트에 영향을 줄 수 있는 변경점

| 변경 | 영향 가능성 | 근거와 대비 |
|---|---|---|
| 비로그인에게서 `ppx_guard`, `my_pending_*`, `ppx_event_*`, `start_claim`, `finish_claim` 회수 | 화면이 로그인 전에 이 함수들을 직접 부르면 오류 | 화면 코드의 RPC 호출을 전수 확인: 로그인 전 호출은 ppx_stats, ppx_event_status, ppx_track뿐 |
| 트리거 함수 실행 권한 회수 | 없음 | 운영에서 이미 막혀 있던 트리거 2개가 정상 동작 중이고, 테스트에서도 모든 트리거가 정상 실행 |
| search_path 통일 | 없음 | 본문이 모두 스키마를 적어 부름. 테스트 72건 통과 |
| places 등록 정책 | 없음 | 트리거가 먼저 값을 고정. 운영자의 승인 상태 직접 등록도 통과 |
| 새 함수 기본 권한 닫힘 | **앞으로 새 함수를 만들 때 grant를 빼먹으면 그 기능이 '권한 없음'으로 실패**(보안 쪽으로 안전하게 실패) | AGENTS.md에 규칙 추가 |

---

## 9. 남은 위험과 운영자 수동 작업

**운영 적용 후보로 올리기 전 남은 확인 (조건부 보류 사유)**
1. **보강한 `inspect_2026-11-12.sql`을 운영에서 한 번 더 Run(읽기 전용).** 다음 항목을 운영에서 직접 확인해야 합니다.
   - 테이블 RLS가 전부 켜져 있는지
   - 테이블·열 권한
   - public 스키마 CREATE 권한
   - 정책 permissive 여부
   - 함수 이름 겹침
2. **이번 3차 결과에 대한 최종 검토(GPT).**

**적용 절차 (승인 후)**
1. 대시보드 Database → Backups에서 백업 여부를 확인합니다(선택).
2. `migrate_2026-11-12.sql`을 **전체** 붙여넣고 Run합니다.
   - `[사전검사]` 오류가 나면 아무것도 바뀌지 않은 것입니다. 메시지를 Claude에게 전달합니다.
3. 결과 표에서 비로그인 4개, 로그인 24개를 확인합니다.
4. 사이트 기능 확인(휴대폰): 비로그인 지도·홈 숫자·이벤트 현황 → 익명 제보·한마디·확인·투표·응모 → 가입·로그인·탈퇴 → 운영자 화면 전 기능.
5. 공개 키로 운영자·내부 RPC를 호출해 `permission denied`가 나는지 확인합니다(Claude가 브라우저에서 진행).
6. 문제가 있으면 `rollback_2026-11-12.sql`을 Run한 뒤 `verify_rollback_2026-11-12.sql`로 요약 PASS를 확인합니다.
7. 이상이 없으면 브랜치를 main에 합칩니다(운영자 승인 후).

**이번 범위에서 남는 위험**

| 항목 | 상태 |
|---|---|
| G. CAPTCHA | 꺼져 있음. 운영자가 Turnstile 키를 발급하고 Supabase Auth에 등록해야 함. 그 전까지 DB 쪽 횟수 제한 유지 |
| H. 유출 비밀번호 보호 | Supabase 공식 문서상 Pro 요금제 이상 기능. 현재 Free |
| I. ppx_track 통계 부풀리기 | 구조상 남음(비로그인 신원 없음). 영향은 운영자용 통계뿐 |
| finish_claim 토큰 | 토큰이 새면 기록 이전 가능(잠재). 토큰을 기기 밖으로 보내지 않는 현재 방식 유지 |
| 운영자 함수 구조 | authenticated + 본문 `is_admin()` 검사. 장기적으로 Edge Function 이전 검토 |
| supabase_admin 기본 권한 | 이 역할이 만드는 함수는 여전히 anon에 열림(Supabase 내부 역할이라 그대로 둠). 마이그레이션은 항상 postgres로 실행 |
| 실제 요청 경로 | PostgREST·Storage·Auth는 흉내 내지 않았음 → 적용 후 사이트 테스트로 확인 |
| 처음 보고서 3장 이후 | 아직 받지 못해 검토하지 못함 |

---

## 10. 완료 판정 기준 대조

| 기준 | 상태 |
|---|---|
| 시그니처 단위로 권한 검증 | 충족 (사후 검사 + 테스트) |
| 예상 함수 목록 = 실제 목록 | 충족 (운영 조사 기준 42개, 사전 검사로 재확인) |
| anon / authenticated / PUBLIC 권한 기대값 일치 | 충족 (테스트 DB) |
| service_role·소유자 권한 보존 | 충족 (사후 검사 (3) + verify) |
| SECURITY DEFINER 전수 검토 | 충족 (31개, 4장) |
| search_path·동적 SQL 위험 검토 | 충족 (4.1장) |
| 사전 조건 검사 작동 | 충족 ([A][B]) |
| 롤백 후 비교 PASS | 충족 (테스트 DB 45/45) |
| 역할별 기능 테스트 | DB 계층 충족(72건) / **실제 사이트는 적용 후 확인 필요** |
| 운영 DB 미적용 유지 | 충족 |
| 운영의 테이블 RLS·열 권한 등 | **미충족** → 보강 조사 SQL 1회 Run 필요 |
