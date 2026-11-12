#!/bin/bash
# 전체 검증 사이클: 변경 전 → 적용(2회) → 역할 테스트 → 되돌리기 → 비교
S=$(cd "$(dirname "$0")/../../supabase" && pwd); P="psql -h /tmp/pgt -p 5544 -U postgres -q"
summ(){ $P -d $1 -Atc "$(cat $S/verify_rollback_2026-11-12.sql)" | head -1; }
./mkdb.sh t3 >/dev/null 2>&1
echo "[1] 변경 전 상태 = 조사 스냅샷?      $(summ t3)"
$P -d t3 -f role_tests.sql 2>&1 | grep -E "^ +[0-9]+ \|" > tests_before.txt
echo "[2] 변경 전 역할 테스트:              PASS $(grep -c '| PASS |' tests_before.txt) / FAIL $(grep -c '| FAIL |' tests_before.txt)"
$P -d t3 -v ON_ERROR_STOP=1 -c "$(cat $S/migrate_2026-11-12.sql)" >/dev/null 2>mig_err.txt && echo "[3] 마이그레이션 1회차:               성공" || { echo "[3] 실패"; cat mig_err.txt; }
$P -d t3 -v ON_ERROR_STOP=1 -c "$(cat $S/migrate_2026-11-12.sql)" >/dev/null 2>mig_err.txt && echo "[4] 마이그레이션 2회차(재실행):       성공" || { echo "[4] 실패"; cat mig_err.txt; }
echo "[5] 적용 후 스냅샷 비교(달라야 정상): $(summ t3)"
./mkdb.sh t5 >/dev/null 2>&1; $P -d t5 -v ON_ERROR_STOP=1 -c "$(cat $S/migrate_2026-11-12.sql)" >/dev/null 2>&1
$P -d t5 -f role_tests.sql 2>&1 | grep -E "^ +[0-9]+ \|" > tests_after.txt
echo "[6] 적용 후 역할 테스트(새 DB):       PASS $(grep -c '| PASS |' tests_after.txt) / FAIL $(grep -c '| FAIL |' tests_after.txt)"
$P -d t3 -v ON_ERROR_STOP=1 -c "$(cat $S/rollback_2026-11-12.sql)" >/dev/null 2>rb_err.txt && echo "[7] 되돌리기:                         성공" || { echo "[7] 실패"; cat rb_err.txt; }
echo "[8] 되돌린 뒤 스냅샷 비교:            $(summ t3)"
$P -d t3 -v ON_ERROR_STOP=1 -c "$(cat $S/rollback_2026-11-12.sql)" >/dev/null 2>rb_err.txt && echo "[9] 되돌리기 2회차:                   성공 / $(summ t3)"
