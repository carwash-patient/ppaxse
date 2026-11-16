-- 2026-11-16b 되돌리기: 운영자는 다시 추첨 응모를 못 하게 (원래대로)
-- migrate_2026-11-16b.sql에서 바꾼 네 군데를 원래 글자로 돌려놓음. 이미 원래대로면 그냥 넘어감.
-- 시험 기간에 운영자가 받은 응모(event_entries/event_tickets)는 지우지 않음 — 원래대로 돌리면 응모권 0장(추첨 제외)으로 보임.
do $rb$
declare
  r record; d text; n int;
begin
  for r in select * from (values
    ('public.ppx_enter_event(bigint)',
     $n$where id = v and blocked$n$,
     $o$where id = v and (blocked or role = 'admin')$o$),
    ('public.ppx_entry_weight(public.event_entries)',
     $n$p.id = e.user_id and p.blocked$n$,
     $o$p.id = e.user_id and (p.blocked or p.role = 'admin')$o$),
    ('public.ppx_entry_valid(public.event_entries)',
     $n$select public.ppx_entry_weight(e) > 0 and not exists (select 1 from public.profiles p where p.id = e.user_id and p.role = 'admin')$n$,
     $o$select public.ppx_entry_weight(e) > 0$o$),
    ('public.ppx_event_status()',
     $n$'valid', public.ppx_entry_weight(e) > 0,$n$,
     $o$'valid', public.ppx_entry_valid(e),$o$)
  ) t(fn, cur, orig) loop
    d := pg_get_functiondef(r.fn::regprocedure);
    n := (length(d) - length(replace(d, r.cur, ''))) / length(r.cur);
    if n = 0 then continue; end if;                                 -- 이미 원래대로
    if n <> 1 then raise exception '% 본문이 예상과 달라요 (찾은 개수 %). 아무것도 바꾸지 않았어요.', r.fn, n; end if;
    execute replace(d, r.cur, r.orig);
  end loop;
end $rb$;
