#!/bin/bash
# 새 테스트 DB를 '운영 DB 조사 당시' 상태로 만듦 (로컬 테스트 전용 PostgreSQL, 운영 DB 아님)
# 사용: ./mkdb.sh <db이름> [포트]   (5544 = PostgreSQL 16, 5545 = PostgreSQL 17)
# schema_main.sql = 보안 수정 전 main 브랜치의 supabase/schema.sql (pg_cron 확장 줄만 주석 처리)
#   git show 72d64da:supabase/schema.sql | sed 's/^create extension if not exists pg_cron;/-- skip/' > schema_main.sql
db=$1; port=${2:-5545}; host=/tmp/pg$([ "$port" = 5544 ] && echo t || echo 17)
S=${S:-/home/claude/ppaxse/supabase}
P="psql -h $host -p $port -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists $db" -c "create database $db" >/dev/null 2>&1
$P -d $db -f shim.sql >/dev/null && $P -d $db -f schema_main.sql 2>&1 | grep -E "ERROR"
# 운영과 같은 ACL·search_path로 맞춤: 마이그레이션 → 되돌리기 (되돌리기가 조사 당시 값을 그대로 씀)
$P -d $db -c "$(cat $S/migrate_2026-11-12.sql)" >/dev/null 2>/tmp/mk_err || cat /tmp/mk_err
$P -d $db -c "$(cat $S/rollback_2026-11-12.sql)" >/dev/null 2>/tmp/mk_err || cat /tmp/mk_err
