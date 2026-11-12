#!/bin/bash
# 흉내 API 테스트용 DB: 운영 조사 당시 상태 → (선택) 마이그레이션 적용 → 기본 데이터
# 사용: ./mkdb_e.sh <db이름> [apply|noapply]
db=$1; S=${S:-/home/claude/ppaxse/supabase}; P="psql -h /tmp/pg17 -p 5545 -U postgres -v ON_ERROR_STOP=1 -q"
./mkdb.sh $db 5545
[ "$2" = noapply ] || $P -d $db -c "$(cat $S/migrate_2026-11-12.sql)" >/dev/null
$P -d $db -f seed_e.sql >/dev/null
