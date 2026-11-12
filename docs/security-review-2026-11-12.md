# 빡세(PPAXSE.COM) 보안 수정 — 4차 보완 결과 보고서

- 작성: 2026-11-12, Claude
- 기준: 4차 검토 의견 4가지 (내부 함수 RPC 노출, 롤백 검증 강화, PostgreSQL 17 검증, 운영 추가 조사)
- 브랜치: `security/2026-11-12` (로컬 커밋만. GitHub·main 미반영)
- **판정: 운영 적용 후보.** 운영 읽기 전용 조사(19:32)까지 모두 PASS. 남은 것은 최종 검토와 운영자 승인입니다.

> **운영 DB에는 아무것도 쓰지 않았습니다.** 운영에서 실행한 것은 운영자가 직접 Run 한 읽기 전용 조사 1회(18:47)뿐입니다.
> 이번에 운영에서 더 읽은 것은 브라우저에 남아 있던 그 조사 결과뿐입니다: ACL 원문, 정책 원문, 기본 권한 원문.
> 모든 쓰기 테스트는 Claude 작업 공간의 **PostgreSQL 17.11** 테스트 DB에서 했습니다(운영과 같은 17 버전).

---

## 1. 바뀐 파일 (3차 대비)

| 파일 | 핵심 변경 |
|---|---|
| `supabase/migrate_2026-11-12.sql` | 트리거 3개를 소유자 권한(DEFINER)으로 바꾸고 도우미 4개를 닫음(로그인 허용 24 → 20개). 사전 검사에 본문 md5, 정책 25개, 함수 ACL 완전 일치를 추가. 사후 검사를 'ACL 완전 일치'로 강화. 건드리지 않는 기본 권한 행 보존 검사 추가 |
| `supabase/rollback_2026-11-12.sql` | 트리거 3개의 원래 본문·INVOKER 복원 추가. 끝에서 ACL·DEFINER·본문·search_path가 원래와 완전히 같은지 스스로 확인하고, 다르면 전체 취소 |
| `supabase/verify_rollback_2026-11-12.sql` | 비교 항목 45 → **73개**. 함수 42개의 ACL 완전 일치·본문·DEFINER, 기본 권한 6행, 정책 25개 |
| `supabase/inspect_2026-11-12.sql` | 테이블·저장소 ACL 원문, 열 단위 권한 전체, storage 테이블 RLS, 버킷 설정, public 스키마 ACL 추가 |
| `supabase/schema.sql` | 끝부분 요약본을 같은 내용으로 갱신. 새로 설치해도 역할 테스트 82/82 통과(PG17) |
| `docs/security-tests-2026-11-12/` | 테스트 도구·결과 갱신. `build3.py`는 위 SQL을 만드는 생성기 |

이전 안은 커밋 `0f288b9`(2차), `7744387`(3차)에 남아 있습니다.

---

## 2. 요청 1 — 내부 도우미 함수의 RPC 노출

### 2.1 문제
`ppx_guard`, `ppx_burst_guard`, `my_pending_count`, `my_pending_reports`가 authenticated에 열려 있던 이유는 하나입니다. 이 함수들을 부르는 **등록 전 검사 트리거 3개가 호출자 권한(INVOKER)으로 돌기** 때문입니다. 트리거 3개는 `places_before_insert`, `place_reports_before_insert`, `place_checks_before_insert`입니다.
- 트리거가 호출자 권한으로 돌면, 그 안에서 부르는 함수도 호출자(authenticated)가 실행 권한을 가져야 합니다.
- 그 권한이 있으면 Supabase API(`/rest/v1/rpc/ppx_guard`)로 직접 부를 수도 있습니다.
- 직접 불렀을 때 생기는 일: 본인 기록 개수가 노출되거나(`my_pending_*`), 본인 기준 제한 검사 메시지를 보게 됩니다. 남의 정보나 쓰기는 없습니다.
- 그래서 실제 위험은 낮지만, **트리거용 권한과 RPC 호출 권한이 분리되지 않은 것**은 맞는 지적입니다.

### 2.2 검토한 두 방법

| | A. private 스키마로 이동 | **B. 트리거 3개를 소유자 권한으로 (채택)** |
|---|---|---|
| 방법 | 도우미 4개를 API에 노출되지 않는 `private` 스키마로 옮김 | 트리거 3개를 `SECURITY DEFINER`로 바꿈. 그 안에서 부르는 도우미는 소유자(postgres) 권한으로 실행됨 |
| authenticated 실행 권한 | **여전히 필요**(트리거가 호출자 권한이라서). API에서만 안 보이게 됨 | **필요 없음** → 4개 모두 회수 |
| 고쳐야 할 함수 본문 | 6개(`public.ppx_guard(...)`를 부르는 곳 전부) + 스키마 생성·USAGE 권한 | 3개, 각 **한 줄**: 앱 요청인지 판별하는 조건 |
| 다른 설정 의존 | 대시보드 'Exposed schemas'에 private이 없어야 안전 | 없음 |
| 운영 선례 | 없음 | 같은 판별 방식을 `place_comments_before_insert`(DEFINER 트리거)가 **이미 운영에서 사용 중** |

**B를 고른 이유**: 권한을 '숨기는' 대신 아예 없앨 수 있고, 바꾸는 본문이 더 적습니다.

### 2.3 바뀌는 한 줄과 그 이유
```
변경 전: if current_user not in ('anon', 'authenticated') ...
변경 후: if coalesce(auth.jwt() ->> 'role', '') not in ('anon', 'authenticated') ...
```
- 이 조건은 '앱에서 온 요청이면 값을 대기·본인으로 고정하고, 관리 도구(SQL 편집기·service_role)면 그대로 둔다'를 판별합니다.
- 소유자 권한으로 돌면 `current_user`가 항상 postgres가 되므로 판별 기준을 JWT role로 바꿨습니다.
  - 앱 요청은 Supabase API가 JWT role을 `anon`/`authenticated`로 넣습니다.
  - SQL 편집기는 JWT가 없어서 빈 값입니다.
  - service_role은 `service_role`입니다.
- **결과는 바뀌기 전과 같습니다.** 테스트로 확인했습니다(5장 표의 '관리 도구 경로'와 '제한').
- 소유자 권한이 되어도 INSERT 문 자체의 RLS 정책은 그대로 호출자 기준으로 검사됩니다. 트리거는 값을 고정하고 기록을 읽기만 합니다.

### 2.4 트리거 동작 확인 (PG17 테스트)
- 정상 동작 확인:
  - 세차장 제보·정보 제보·다녀왔어요가 대기·본인으로 저장됩니다(조작 시도 포함).
  - 30초·15초 연속 제한이 작동합니다.
  - 차단 사용자의 제보·확인이 거부됩니다.
- 도우미 4개를 익명 로그인 사용자가 직접 부르면 **4개 모두 `permission denied`**입니다(변경 전에는 3개 실행됨, 1개는 제한 오류).
- 관리 도구 경로: SQL 편집기(postgres)와 service_role로 '승인 상태'로 넣으면 그대로 승인 상태로 저장됩니다(공공데이터 넣기 유지).

### 2.5 갱신된 권한 매트릭스 요약
- **anon 4개**: `is_admin`, `ppx_stats`, `ppx_event_status`, `ppx_track`
- **authenticated 20개**: 위 4개, 회원 기능 7개(`delete_my_account`, `start_claim`, `finish_claim`, `ppx_enter_event`, `ppx_log_block`, `ppx_precheck`, `ppx_vote_type`), 운영자 기능 9개(`admin_*`)
- **없음 22개**: 트리거 11개, 도우미 4개(`ppx_guard`, `ppx_burst_guard`, `my_pending_count`, `my_pending_reports`), 내부 7개(`ppx_event_week`, `ppx_event_start`, `ppx_event_draw_at`, `ppx_event_draw_run`, `ppx_auto_draw`, `ppx_is_member`, `ppx_entry_valid`)
- service_role과 postgres는 42개 모두 그대로입니다.
- SECURITY DEFINER 함수는 31개에서 **34개**가 됩니다(트리거 3개 추가).
  - 추가된 3개도 소유자 postgres, search_path `pg_catalog, public, pg_temp`, 본문의 모든 참조에 스키마 명시, 동적 SQL 없음입니다.
  - 직접 실행 권한은 아무에게도 없습니다(트리거 전용).
  - 나머지 31개의 점검 결과는 3차 보고서와 같고, 본문은 바뀌지 않았습니다.

---

## 3. 요청 2 — 롤백 검증 강화

### 3.1 '완전 일치'의 기준
- 운영 조사 원문에서 확인한 사실: 함수 42개의 ACL 항목은 다음 다섯 종류뿐입니다.
  - `postgres=X/postgres`, `service_role=X/postgres`, `=X/postgres`(PUBLIC), `anon=X/postgres`, `authenticated=X/postgres`
  - **부여자는 모두 postgres, GRANT OPTION(`*`)은 하나도 없음**, 42개 모두 postgres·service_role 항목이 있음
- 그래서 함수별 '변경 전 ACL'을 다음 모양으로 정확히 재현할 수 있습니다: `postgres + service_role + (PUBLIC/anon/authenticated 중 해당)`.

### 3.2 비교 방식
- ACL을 `aclexplode`로 풀어 **(받는 역할 = 권한 [GRANT OPTION이면 *] / 준 역할)** 문자열로 만들고, 정렬해 이어 붙인 뒤 **문자열 전체가 같은지** 비교합니다.
  - 그래서 service_role 권한, GRANT OPTION, 부여자, 그 밖의 어떤 역할(예: supabase_auth_admin)에 생긴 권한까지 모두 차이로 잡힙니다.
- ACL이 NULL(기본값)인 경우는 'NULL(기본값)'으로 따로 표시합니다. 그래서 명시적 ACL과 혼동하지 않습니다.
- 함수마다 더 비교하는 것: 소유자, DEFINER, **본문 md5**, search_path, anon·authenticated·service_role의 실제 실행 가능 여부.
- **기본 권한**: postgres 역할의 모든 행(테이블·함수·시퀀스 × public·storage, 그리고 전역)을 행 단위로 비교합니다. 빠진 행, 늘어난 행, ACL 차이를 모두 잡습니다.
  - 마이그레이션은 여기에 더해 **다른 모든 역할의 기본 권한 행**이 시작 때와 같은지도 사후 검사합니다.
- **정책**: public·storage의 25개 전체를 비교합니다(이름, 명령, PERMISSIVE, 역할, USING md5, WITH CHECK md5).
  - 기준값은 운영 원문과 대조했습니다(25개 일치).

### 3.3 검증된 것 (PG17)

| 시험 | 결과 |
|---|---|
| 변경 전 상태 = 운영 조사 스냅샷 | **73/73 PASS** |
| 적용 후 비교 | 45개 FAIL(바뀐 것이므로 정상), 정책 24개·기본 권한 5행 PASS(안 바뀐 것) |
| 되돌린 뒤 | **73/73 PASS**, 다시 되돌려도 73/73 |
| 되돌린 DB의 역할 테스트 | 변경 전과 **82개 항목 판정이 모두 같음** |
| [C] service_role에 GRANT OPTION을 일부러 붙이고 적용 | 사전 검사에서 중단: `service_role=EXECUTE*/postgres` 표시 |
| [F] 적용 후 다른 역할(supabase_auth_admin)에 권한이 생긴 채 되돌리기 | 되돌리기 자체 확인에서 **전체 취소** |
| [H] 그 상태를 비교 SQL로 보면 | 72 PASS / **1 FAIL**: `ppx_stats()` ACL 다름(지금 값과 원래 값 함께 표시) |

---

## 4. 요청 3 — PostgreSQL 17 검증

- **환경**: PostgreSQL **17.11**입니다(npm `@embedded-postgres` 공식 빌드 바이너리, 작업 공간에서 실행).
  - Supabase 흉내 `shim.sql`: 역할 4개, `auth.uid/jwt`, `auth.users`, `storage`, `cron`, 운영과 같은 postgres 기본 권한 6행.
  - 운영 정확한 마이너 버전은 이번 조사 SQL의 `server_version`으로 확인할 예정입니다.
- **PG17 전체 사이클 결과** (`cycle_result_pg17.txt`)

| 단계 | 결과 |
|---|---|
| [1] 변경 전 = 운영 스냅샷 | 73/73 PASS |
| [2] 변경 전 역할 테스트 | 66 PASS / 16 FAIL. FAIL 16개는 **변경 전에 열려 있던 것**(비로그인 실행 가능 11, 익명의 도우미 직접 실행 4, 트리거 직접 호출 1) = 이번 수정 대상 |
| [3][4] 적용 1·2회차 | 성공, 성공 |
| [6] 적용 후 역할 테스트 | **82 PASS / 0 FAIL** |
| [7][8][9] 되돌리기 1·2회차 | 성공, 73/73 PASS, 73/73 PASS |
| [10] 적용→되돌리기 2번 한 새 DB | 변경 전 [2]와 82개 판정 모두 같음 |
| [A] 조사 때 없던 함수 | 사전 검사 중단, DB 그대로(73/73) |
| [B] 트리거 꺼짐 | 사전 검사 중단 |
| [C] 예상 밖 GRANT OPTION | 사전 검사 중단 |
| [D] 조사 때 없던 정책 | 사전 검사 중단 |
| [E] 적용 도중 예상 밖 권한 | 사후 검사 실패, **전부 취소돼 DB 그대로(73/73)** |
| [F] 다른 역할 권한이 생긴 채 되돌리기 | 되돌리기 확인 실패, 전체 취소 |
| [G] 함수 이름이 바뀐 채 되돌리기 | 되돌리기 중단(조용히 건너뛰지 않음) |
| 편집기 방식(파일 전체를 한 문자열로, psycopg2) | 적용 42행(비로그인 4, 로그인 20), 고장 낸 적용은 취소, 되돌리기 후 73/73, 조사 SQL 정상 |
| schema.sql로 새로 설치 | 역할 테스트 82/82 |

**PostgreSQL 16에서는 실행되지 않습니다(의도된 결과)**
- 운영 기본 권한 원문의 `m`(MAINTAIN, PG17에서 생긴 권한)을 그대로 기준값으로 쓰기 때문에, PG16에서는 `invalid mode character` 오류로 시작 단계에서 멈춥니다(`cycle_result_pg16.txt`).
- 운영이 PG17이므로 문제는 아닙니다. 오히려 다른 버전에서 잘못 실행되는 것을 막습니다.
- 3차의 PG16 결과는 이전 SQL 기준이라 이번 판정에는 쓰지 않았습니다.

**아직 확인하지 못한 것(PASS로 표시하지 않음)**
- Supabase SQL 편집기 자체의 트랜잭션 처리(운영 DB라 시험하지 않음)
- 실제 PostgREST·Storage·Auth 요청 경로

---

## 5. 역할 테스트 82건 (PG17, 적용 후)

| 누구 | 정상 동작 확인 | 거절 확인 |
|---|---|---|
| 비로그인(32) | 지도 조회, ppx_stats, ppx_event_status, ppx_track, is_admin | 함수 26개 직접 호출 → 모두 `permission denied` / places 직접 등록 → RLS 거부 |
| 익명 로그인(20) | 세차장 제보(대기·본인·source=user로 고정), 정보 제보(대기·본인), 다녀왔어요, 한마디, 종류 투표, start_claim | 운영자 RPC 2, 승인 세차장 수정(0행), 내부·트리거·**도우미 4개 직접 실행**(permission denied), role을 admin으로, 프로필 직접 생성, 남의 제보 보기(0행), 30초·15초 연속 제출 |
| 일반 회원(12) | 제보, 제보 전 검사, 닉네임 수정, ppx_log_block, finish_claim, 탈퇴 | 운영자 통계, 남의 프로필(0행), 남의 대기 세차장(0행), 차단 풀기, 탈퇴 후 같은 토큰으로 제보·운영자 RPC |
| 차단 사용자(2) | — | 세차장 제보, 다녀왔어요 |
| 운영자(13) | 승인 상태 직접 등록, 승인, 차단·해제, 통계 3종, 응모 목록 2종, 투표 보기, 한마디 숨김, 제보 처리, 전체 프로필 | — |
| 관리 도구(2) | SQL 편집기(postgres)·service_role로 승인 상태 등록 → 값 유지 | — |
| 크론(1) | ppx_auto_draw (postgres) | — |

---

## 6. 요청 4 — 운영 추가 조사 SQL (읽기 전용)

`supabase/inspect_2026-11-12.sql`은 **SELECT 한 개**입니다(쓰기 없음). PG17 테스트 DB에서 정상 실행을 확인했습니다. 확인할 항목:

| 항목 | 조사 키 |
|---|---|
| 테이블별 RLS 켜짐·FORCE RLS (public) | `tables[].rls`, `tables[].force_rls` |
| storage 테이블 RLS | `storage_tables` |
| 테이블 권한(anon·authenticated의 S/I/U/D 실제 권한) | `tables[].anon`, `tables[].authenticated` |
| 테이블 ACL 원문 (public·storage) | `table_acl` |
| 열 단위 권한 원문 (public 전체) | `column_grants` |
| profiles에서 이용자가 고칠 수 있는 열 | `profiles_update_columns` |
| public 스키마 CREATE 권한·ACL 원문, 임시 테이블 권한 | `schema_privs` |
| 정책 permissive 여부 | `policies[].permissive` |
| 함수 이름 겹침, 역할별 실행 권한, ACL 항목 | `overloads`, `function_privs` |
| 저장소 버킷 설정 | `storage_buckets` |
| 서버 버전 | `server_version` |

판정 기준(Claude가 결과를 읽고 표로 보고):
- public 테이블 RLS 전부 켜짐
- anon·authenticated에 public 스키마 CREATE 없음
- profiles에서 고칠 수 있는 열이 닉네임·차량·지역 등 7개뿐(`role`·`blocked` 없음)
- 정책 전부 PERMISSIVE(테스트 DB와 같음)
- 이름 겹침 없음
- 함수 권한이 조사 때와 같음

하나라도 다르면 보고하고 SQL을 다시 검토합니다.

### 6.1 운영 조사 결과 (2026-11-12 19:32, 읽기 전용 Run 1회)

| 항목 | 운영 결과 | 판정 |
|---|---|---|
| 서버 버전 | PostgreSQL **17.11** (테스트와 같은 버전) | PASS |
| public 테이블 13개 RLS | **13개 모두 켜짐**, FORCE RLS는 모두 꺼짐(소유자 postgres만 해당, 앱 역할에는 영향 없음) | PASS |
| storage 테이블 8개 RLS | 8개 모두 켜짐 | PASS |
| 테이블 권한 (anon·authenticated 실제 S/I/U/D) | 13개 테이블 모두 **테스트 DB와 같음** | PASS |
| 테이블 ACL 원문 | 13개 모두 테스트 DB와 같음(길이·구성 비교) | PASS |
| 열 단위 권한 | 16개 항목, **테스트 DB와 완전히 같음** | PASS |
| profiles에서 이용자가 고칠 수 있는 열 | nickname, skill, cars, home, avatar_car, avatar_color, car_model (7개, `role`·`blocked` 없음) | PASS |
| public 스키마 CREATE | anon **없음**, authenticated **없음** (USAGE만) | PASS |
| 정책 25개 | **모두 PERMISSIVE**, 개수 25 | PASS |
| 함수 이름 겹침 | 없음 | PASS |
| 함수 42개 권한 | 조사 스냅샷과 **42개 모두 같음**(실행 가능 여부, ACL 항목, 소유자, service_role) — 아직 아무것도 바뀌지 않았음을 확인 | PASS |
| search_path 없는 함수 | 9개(스냅샷과 같음) | PASS |
| 저장소 버킷 | report-photos 1개: 비공개, 3MB, jpeg/png/webp | PASS |

**참고로 남겨 둘 관찰 (조치 불필요)**
- `places`, `place_reports`, `place_checks`, `anon_claims`, `profiles`는 anon에게도 테이블 단위 쓰기 권한이 있습니다(Supabase 기본값).
- 다만 RLS가 켜져 있고 anon용 쓰기 정책이 없어서 실제로는 막힙니다. 테스트의 '비로그인 places 직접 등록 → RLS 거부'로 확인했습니다.
- 이번 범위에서는 바꾸지 않았습니다. 바꾸면 기존 기능 영향 검토가 따로 필요합니다.

---

## 7. 기존 사이트에 영향을 줄 수 있는 변경 (3차 대비 추가분)

| 변경 | 영향 | 근거 |
|---|---|---|
| 트리거 3개 소유자 권한 + 판별 한 줄 | 앱 제보·확인·관리 도구 입력 결과는 같음 | 5장 테스트(정상·조작·제한·차단·관리 도구) 모두 통과 |
| 도우미 4개 회수 | 화면은 이 4개를 직접 부르지 않음 | 화면 코드 RPC 전수 확인(3차): 해당 없음 |

나머지(비로그인 회수, search_path, 등록 정책, 새 함수 기본 권한 닫힘)는 3차와 같습니다. 새 함수를 만들 때는 grant를 직접 써야 하며, 이 규칙은 AGENTS.md에 적혀 있습니다.

---

## 8. 남은 것

**운영 적용 후보로 올리기 전**
1. ~~운영 읽기 전용 조사~~ → 완료(6.1장, 전 항목 PASS)
2. 최종 검토와 운영자 승인.

**적용 절차 (승인 후, 3차와 같음)**
- 백업 확인(선택) → migrate 전체 Run → 결과 표 확인(비로그인 4, 로그인 20) → 휴대폰으로 사이트 기능 확인 → 공개 키로 거부 확인
- 문제가 있으면 rollback → verify 요약 PASS 확인

**남는 위험 (3차와 같음)**
- CAPTCHA 꺼짐(운영자 키 발급 필요)
- 유출 비밀번호 보호(Pro 요금제 기능)
- ppx_track 통계 부풀리기(구조상)
- finish_claim 토큰 유출 시 기록 이전(잠재)
- 운영자 함수의 authenticated + 본문 검사 구조(장기 과제)
- 실제 API 경로는 적용 후 사이트 테스트로 확인
- 처음 보고서 3장 이후 미수령
