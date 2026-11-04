-- 2026-11-04 세차장 '요금표 자세히' (긴 가격표·메뉴). 짧은 요약은 기존 price(200자)에
-- 한 번만 실행 (여러 번 실행해도 안전)
alter table public.places add column if not exists price_note text;
alter table public.places drop constraint if exists places_price_note_check;
alter table public.places add constraint places_price_note_check check (char_length(price_note) <= 3000);
