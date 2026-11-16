-- 2026-11-16b: (며칠간 시험용) 운영자 계정도 한마디로 추첨 응모권을 받아 보게 함 — 단, 운영자 응모는 추첨·참여 수에서 항상 빠짐
-- 왜: 운영자가 직접 다녀온 세차장을 쓰면서, 응모권이 언제 나오고 어떻게 보이는지 이용자와 똑같이 확인하려고
-- 바꾸는 것 (함수 본문의 한 군데씩만 바꿈, 새 함수 없음, 실행 권한 그대로):
--   1) ppx_enter_event   : 운영자도 응모 가능 (차단된 이용자는 그대로 막음)
--   2) ppx_entry_weight  : 운영자 응모권도 장수로 셈 (화면에 '응모권 1/3장'처럼 똑같이 보이게)
--   3) ppx_entry_valid   : 운영자 응모는 '추첨 대상 아님' → 자동 추첨·참여 수·운영자 응모 목록에서 제외
--   4) ppx_event_status  : 내 응모 표시(mine.valid)는 응모권 기준으로 → 운영자 화면에 '숨겨져 제외'로 잘못 안 보이게
--                          (일반 이용자는 전과 똑같이 보임)
-- 되돌리기: rollback_2026-11-16b.sql
-- 바꿀 부분이 예상과 다르면 아무것도 바꾸지 않고 멈춤.
do $mig$
declare
  r record; d text; n int;
begin
  for r in select * from (values
    ('public.ppx_enter_event(bigint)',
     $o$where id = v and (blocked or role = 'admin')$o$,
     $n$where id = v and blocked$n$),
    ('public.ppx_entry_weight(public.event_entries)',
     $o$p.id = e.user_id and (p.blocked or p.role = 'admin')$o$,
     $n$p.id = e.user_id and p.blocked$n$),
    ('public.ppx_entry_valid(public.event_entries)',
     $o$select public.ppx_entry_weight(e) > 0$o$,
     $n$select public.ppx_entry_weight(e) > 0 and not exists (select 1 from public.profiles p where p.id = e.user_id and p.role = 'admin')$n$),
    ('public.ppx_event_status()',
     $o$'valid', public.ppx_entry_valid(e),$o$,
     $n$'valid', public.ppx_entry_weight(e) > 0,$n$)
  ) t(fn, old, new) loop
    d := pg_get_functiondef(r.fn::regprocedure);
    if position(r.new in d) > 0 then continue; end if;           -- 이미 바뀌어 있음 (두 번 실행해도 안전)
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception '% 본문이 예상과 달라요 (찾은 개수 %). 아무것도 바꾸지 않았어요.', r.fn, n; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $mig$;
