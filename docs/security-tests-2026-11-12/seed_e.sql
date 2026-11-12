-- 흉내 API 테스트용 기본 데이터 (테스트 DB 전용)
insert into auth.users (id, email, is_anonymous) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test', false),
  ('00000000-0000-0000-0000-00000000000b', 'member@test', false),
  ('00000000-0000-0000-0000-00000000000d', 'member2@test', false);
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
insert into public.places (id, name, type, status, source, region, lat, lng) values
  (900001, '운영 세차장 A', 'self', 'approved', 'public_data', '테스트', 37.50, 127.00),
  (900002, '운영 세차장 B', 'hand', 'approved', 'public_data', '테스트', 37.51, 127.01),
  (900003, '[전용] 확인 테스트 세차장', 'self', 'approved', 'public_data', '테스트', 37.52, 127.02),
  (900004, '[전용] 이벤트 테스트 세차장', 'self', 'approved', 'public_data', '테스트', 37.53, 127.03);
insert into public.place_reports (place_id, reporter, memo) values (900001, '00000000-0000-0000-0000-00000000000b', '실제 이용자 제보');
insert into public.place_comments (place_id, user_id, nickname, body) values (900001, '00000000-0000-0000-0000-00000000000b', '회원', '실제 이용자 한마디입니다');
