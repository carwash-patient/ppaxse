-- migrate_2026-11-26.sql 되돌리기. 여러 번 실행해도 안전합니다.
-- 주의: 받은 테스터 피드백이 모두 지워집니다. 필요하면 먼저 운영자 화면에서 내용을 옮겨 두세요.
-- 화면(js/ppx.js)이 ppx_feedback을 부르므로, 되돌리면 화면도 이전 버전으로 함께 되돌려야 합니다.
drop function if exists public.ppx_feedback(text, text, text);
drop table if exists public.app_feedback;
