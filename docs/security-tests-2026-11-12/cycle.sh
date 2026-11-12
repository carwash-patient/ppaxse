#!/bin/bash
# 전체 검증 사이클: 변경 전 → 적용(2회) → 역할 테스트 → 되돌리기(2회) → 비교 → 안전장치 시험
# 사용: ./cycle.sh [포트]   (5545 = PostgreSQL 17, 5544 = PostgreSQL 16)
port=${1:-5545}; host=/tmp/pg$([ "$port" = 5544 ] && echo t || echo 17)
S=${S:-/home/claude/ppaxse/supabase}; export S
P="psql -h $host -p $port -U postgres -q"
run(){ $P -d $1 -v ON_ERROR_STOP=1 -c "$(cat $2)" >/dev/null 2>/tmp/cy_err && echo 성공 || { echo "실패: $(grep ERROR /tmp/cy_err | head -1)"; }; }
summ(){ $P -d $1 -At -F' | ' -c "$(cat $S/verify_rollback_2026-11-12.sql)" | head -1; }
tests(){ $P -d $1 -f role_tests.sql 2>&1 | grep -E "^ +[0-9]+ \|" > $2; echo "PASS $(grep -c '| PASS |' $2) / FAIL $(grep -c '| FAIL |' $2)"; }
echo "== $($P -d postgres -Atc 'select version()' | cut -d' ' -f1-2) =="
./mkdb.sh c1 $port
echo "[1] 변경 전 = 운영 조사 스냅샷        $(summ c1)"
echo "[2] 변경 전 역할 테스트              $(tests c1 result_before_$port.txt)"
echo "[3] 적용 1회차                       $(run c1 $S/migrate_2026-11-12.sql)"
echo "[4] 적용 2회차(재실행)               $(run c1 $S/migrate_2026-11-12.sql)"
echo "[5] 적용 후 스냅샷 비교(달라야 정상) $(summ c1)"
./mkdb.sh c2 $port; run c2 $S/migrate_2026-11-12.sql >/dev/null
echo "[6] 적용 후 역할 테스트(새 DB)       $(tests c2 result_after_$port.txt)"
echo "[7] 되돌리기 1회차                   $(run c1 $S/rollback_2026-11-12.sql)"
echo "[8] 되돌린 뒤 스냅샷 비교            $(summ c1)"
echo "[9] 되돌리기 2회차                   $(run c1 $S/rollback_2026-11-12.sql) / $(summ c1)"
./mkdb.sh c4 $port; run c4 $S/migrate_2026-11-12.sql >/dev/null; run c4 $S/rollback_2026-11-12.sql >/dev/null; run c4 $S/migrate_2026-11-12.sql >/dev/null; run c4 $S/rollback_2026-11-12.sql >/dev/null
echo "[10] 적용→되돌리기 2번 한 새 DB 역할 테스트 $(tests c4 result_rolledback_$port.txt)"
diff <(cut -d'|' -f2-6 result_before_$port.txt) <(cut -d'|' -f2-6 result_rolledback_$port.txt) >/dev/null && echo "     → 변경 전 [2]와 $(wc -l < result_before_$port.txt)개 항목 판정이 모두 같음" || { echo "     → 변경 전과 다름:"; diff <(cut -d'|' -f2-6 result_before_$port.txt) <(cut -d'|' -f2-6 result_rolledback_$port.txt); }
# 안전장치
./mkdb.sh c3 $port
$P -d c3 -c "create function public.zz_extra() returns int language sql as 'select 1'"
echo "[A] 조사 때 없던 함수               $(run c3 $S/migrate_2026-11-12.sql)"; $P -d c3 -c "drop function public.zz_extra()"
echo "    → DB 그대로?                    $(summ c3)"
$P -d c3 -c "alter table public.places disable trigger places_before_insert"
echo "[B] 트리거 꺼짐                      $(run c3 $S/migrate_2026-11-12.sql)"; $P -d c3 -c "alter table public.places enable trigger places_before_insert"
$P -d c3 -c "grant execute on function public.ppx_stats() to service_role with grant option"
echo "[C] 예상 밖 GRANT OPTION             $(run c3 $S/migrate_2026-11-12.sql)"; $P -d c3 -c "revoke grant option for execute on function public.ppx_stats() from service_role"
$P -d c3 -c "create policy zz on public.places for select using (true)"
echo "[D] 조사 때 없던 정책               $(run c3 $S/migrate_2026-11-12.sql)"; $P -d c3 -c "drop policy zz on public.places"
python3 - <<PY
s=open('$S/migrate_2026-11-12.sql').read()
s=s.replace("-- ── 6) 사후 검사","grant execute on function public.ppx_event_week(timestamptz) to anon;  -- (테스트용 고장)\n-- ── 6) 사후 검사",1)
open('/tmp/bad_mig.sql','w').write(s)
PY
echo "[E] 적용 도중 예상 밖 권한           $(run c3 /tmp/bad_mig.sql)"
echo "    → 전부 취소돼 DB 그대로?        $(summ c3)"
run c3 $S/migrate_2026-11-12.sql >/dev/null; $P -d c3 -c "grant execute on function public.ppx_stats() to supabase_auth_admin"
echo "[F] 적용 후 다른 역할 권한이 생긴 채 되돌리기 $(run c3 $S/rollback_2026-11-12.sql)"
$P -d c3 -c "revoke execute on function public.ppx_stats() from supabase_auth_admin"; run c3 $S/rollback_2026-11-12.sql >/dev/null
$P -d c3 -c "alter function public.ppx_stats() rename to ppx_stats_old"
echo "[G] 함수 이름이 바뀐 채 되돌리기     $(run c3 $S/rollback_2026-11-12.sql)"
$P -d c3 -c "alter function public.ppx_stats_old() rename to ppx_stats"; $P -d c3 -c "grant execute on function public.ppx_stats() to supabase_auth_admin"
echo "[H] 다른 역할 권한이 남은 상태 비교  $(summ c3)"
$P -d c3 -At -F' | ' -c "$(cat $S/verify_rollback_2026-11-12.sql)" | grep FAIL | sed -n 2p | cut -c1-160
