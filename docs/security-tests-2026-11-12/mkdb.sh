#!/bin/bash
# 새 테스트 DB를 '운영 DB 조사 당시' 상태로 만듦 (로컬 테스트 전용 PostgreSQL, 운영 DB 아님)
# schema_main.sql = 보안 수정 전 main 브랜치의 supabase/schema.sql (pg_cron 확장 줄만 주석 처리)
#   git show 72d64da:supabase/schema.sql | sed 's/^create extension if not exists pg_cron;/-- skip/' > schema_main.sql
S=$(cd "$(dirname "$0")/../../supabase" && pwd)
db=$1; P="psql -h /tmp/pgt -p 5544 -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists $db" -c "create database $db" >/dev/null
$P -d $db -f shim.sql >/dev/null && $P -d $db -f schema_main.sql 2>&1 | grep -E "ERROR" 
# 운영과 같은 ACL로 맞춤 (rollback 스크립트의 권한·search_path 단계 재사용)
$P -d $db -c "$(cat $S/rollback_2026-11-12.sql)" 2>&1 | grep -E "ERROR|NOTICE" 
