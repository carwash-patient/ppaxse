-- 2026-11-17b: 이벤트 글 버튼 링크 검사 강화
-- 17에서 빡세 안 주소(r/, map.html 등)를 허용하는 규칙이 '//다른사이트.com'처럼 슬래시 두 개로 시작하는 주소도 통과시켰음
-- (브라우저는 이걸 다른 사이트 주소로 읽음). 첫 글자는 슬래시가 아니도록 바꿈. 여러 번 실행해도 안전함.
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid = 'public.events'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%btn_url%' loop
    execute format('alter table public.events drop constraint %I', c);
  end loop;
end $$;
alter table public.events add constraint events_btn_url_check check (
  btn_url is null or (char_length(btn_url) <= 500 and (btn_url ~ '^https://[^/]' or btn_url ~ '^[a-z0-9_.?=&#-][a-z0-9_./?=&#-]*$'))
);
