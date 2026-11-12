// 흐름 B(다녀왔어요 트리거)·C(이벤트 응모) 검증 — 테스트 DB + 요청 흉내 서버. 운영 DB와 무관.
// 같은 시험을 '변경 전' DB와 '적용 후' DB에서 모두 돌려 결과를 비교합니다.
// 사용: node run_flow_bc.js
const cp = require('child_process');
const { Client } = require('/tmp/stack/node_modules/pg');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const KEY = 'sb_publishable_TEST';
const ADMIN = '00000000-0000-0000-0000-00000000000a', MEM = '00000000-0000-0000-0000-00000000000b', MEM2 = '00000000-0000-0000-0000-00000000000d';

async function run(db, apply) {
  cp.execSync(`./mkdb_e.sh ${db} ${apply ? 'apply' : 'noapply'}`, { cwd: __dirname, stdio: 'ignore' });
  const port = 3800 + Math.floor(Math.random() * 90);
  const emu = cp.spawn('node', [__dirname + '/pgrst_emu.js', db, port], { stdio: 'ignore' }); await sleep(700);
  const base = 'http://127.0.0.1:' + port;
  const c = new Client({ host: '/tmp/pg17', port: 5545, user: 'postgres', database: db }); await c.connect();
  const q = async (t, v) => (await c.query(t, v)).rows;
  const one = async (t, v) => Object.values((await q(t, v))[0])[0];
  const req = async (method, path, body, token, extra = {}) => {
    const r = await fetch(base + path, { method, headers: { apikey: KEY, Authorization: 'Bearer ' + (token || KEY), 'Content-Type': 'application/json', ...extra }, body: body === undefined ? undefined : JSON.stringify(body) });
    let j = null; try { j = await r.json(); } catch (e) {}
    return { status: r.status, code: j && j.code, msg: j && j.message, data: j, t: r.status + (j && j.code ? ' ' + j.code : '') };
  };
  const anonUser = async () => { const r = await req('POST', '/auth/v1/signup', {}); return { token: r.data.access_token, id: r.data.user.id }; };
  const tokenOf = async (id) => (await req('POST', '/__token', { id })).data.access_token;
  const out = [];
  const rec = (no, name, expect, got, pass) => out.push({ no, name, expect, got: String(got), verdict: pass ? 'PASS' : 'FAIL' });
  try {
    // ════ B. 다녀왔어요(place_checks) — 전용 세차장 900003 ════
    const P = 900003; const cnt = () => one('select check_count from public.places where id = $1', [P]);
    const rowsN = () => one('select count(*)::int from public.place_checks where place_id = $1', [P]);
    { const r = await req('POST', '/rest/v1/place_checks', { place_id: P });
      rec('B1', '비로그인(anon) 요청', '거부(401), 행 0·횟수 0', `${r.t} / 행 ${await rowsN()} / 횟수 ${await cnt()}`, r.status === 401 && (await rowsN()) === 0 && (await cnt()) === 0); }
    const u1 = await anonUser(), u2 = await anonUser();
    let id1;
    { const r = await req('POST', '/rest/v1/place_checks', { place_id: P }, u1.token, { Prefer: 'return=representation' }); const x = (r.data || [])[0] || {}; id1 = x.id;
      const chk = (await q('select checked_at is not null as ok, check_count from public.places where id = $1', [P]))[0];
      rec('B2', '익명 로그인 사용자의 정상 확인', '201, 본인 기록, 횟수 0→1, 최근 확인 시각 기록', `${r.t} / 본인 ${x.user_id === u1.id} / 횟수 ${chk.check_count} / 시각 ${chk.ok}`, r.status === 201 && x.user_id === u1.id && chk.check_count === 1 && chk.ok); }
    { const r = await req('POST', '/rest/v1/place_checks', { place_id: P, user_id: MEM, created_on: '2020-01-01', created_at: '2020-01-01T00:00:00Z' }, u2.token, { Prefer: 'return=representation' }); const x = (r.data || [])[0] || {};
      const today = await one("select current_date::text");
      rec('B3', '조작된 user_id·날짜 (남의 ID, 2020년)', '201, 본인·오늘 날짜로 고정, 횟수 1→2', `${r.t} / 본인 ${x.user_id === u2.id} / 날짜 ${x.created_on} / 횟수 ${await cnt()}`, r.status === 201 && x.user_id === u2.id && String(x.created_on).startsWith(today) === true && (await cnt()) === 2);
      rec('B3b', '남의 ID로 기록이 생기지 않음', '회원 ID 기록 0건', `${await one('select count(*)::int from public.place_checks where user_id = $1', [MEM])}건`, (await one('select count(*)::int from public.place_checks where user_id = $1', [MEM])) === 0); }
    { const r = await req('PATCH', '/rest/v1/places?id=eq.' + P, { check_count: 999 }, u1.token, { Prefer: 'return=representation' });
      rec('B4', '조작된 확인 횟수 (세차장 횟수를 직접 999로)', '0건 수정, 횟수 그대로 2', `${r.t} / ${Array.isArray(r.data) ? r.data.length : '?'}건 / 횟수 ${await cnt()}`, Array.isArray(r.data) && r.data.length === 0 && (await cnt()) === 2); }
    { const r = await req('POST', '/rest/v1/rpc/place_checks_after_insert', {}, u1.token);
      rec('B4b', '횟수 올리는 트리거 함수를 직접 호출', apply ? '42501 권한 없음' : '실행 안 됨(오류)', r.t, apply ? r.code === '42501' : r.status >= 400); }
    { const r = await req('POST', '/rest/v1/place_checks', { place_id: P }, u1.token);
      rec('B5', '중복 확인 (같은 사람·같은 날·같은 세차장)', '409 중복 거부, 횟수 그대로 2', `${r.t} / 횟수 ${await cnt()} / 행 ${await rowsN()}`, r.status === 409 && r.code === '23505' && (await cnt()) === 2 && (await rowsN()) === 2); }
    { const r1 = await req('PATCH', '/rest/v1/place_checks?id=eq.' + id1, { user_id: MEM, created_on: '2020-01-01' }, u1.token, { Prefer: 'return=representation' });
      const r2 = await req('DELETE', '/rest/v1/place_checks?id=eq.' + id1, undefined, u1.token, { Prefer: 'return=representation' });
      const still = (await q('select user_id, created_on::text from public.place_checks where id = $1', [id1]))[0];
      rec('B6', '비정상 수정·삭제 시도 (내 확인 기록)', '수정 0건·삭제 0건, 기록 그대로', `수정 ${r1.t}/${Array.isArray(r1.data) ? r1.data.length : '?'}건 · 삭제 ${r2.t}/${Array.isArray(r2.data) ? r2.data.length : '?'}건 · 본인 ${still && still.user_id === u1.id}`,
          Array.isArray(r1.data) && r1.data.length === 0 && Array.isArray(r2.data) && r2.data.length === 0 && still && still.user_id === u1.id); }
    { await c.query("insert into public.places (id, name, type, status, source, region, lat, lng) values (900010, '[전용] 대기 세차장', 'self', 'pending', 'user', '테스트', 37.6, 127.1)");
      const r = await req('POST', '/rest/v1/place_checks', { place_id: 900010 }, u1.token);
      rec('B7', '승인되지 않은 세차장에 확인', '거부(403 RLS)', r.t, r.status === 403 && r.code === '42501'); }
    { const u3 = await anonUser(); await c.query('update public.profiles set blocked = true where id = $1', [u3.id]);
      const r = await req('POST', '/rest/v1/place_checks', { place_id: P }, u3.token);
      rec('B8', '차단된 사용자의 확인', 'P0001 거절, 횟수 그대로 2', `${r.t} ${String(r.msg).slice(0, 20)} / 횟수 ${await cnt()}`, r.code === 'P0001' && (await cnt()) === 2); }
    { const u4 = await anonUser();
      await c.query("insert into public.places (id, name, type, status, source, region, lat, lng) select 910000 + g, '[전용] 한도 ' || g, 'self', 'approved', 'public_data', '테스트', 37.7, 127.2 from generate_series(1, 100) g");
      await c.query('alter table public.place_checks disable trigger user');
      await c.query('insert into public.place_checks (place_id, user_id) select 910000 + g, $1 from generate_series(1, 100) g', [u4.id]);
      await c.query('alter table public.place_checks enable trigger user');
      const r = await req('POST', '/rest/v1/place_checks', { place_id: P }, u4.token);
      rec('B9', '하루 100회 한도를 채운 사용자의 101번째 확인', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 22)}`, r.code === 'P0001' && /오늘은 더/.test(r.msg || '')); }
    { const x = (await q("insert into public.place_checks (place_id, user_id, created_on) values ($1, $2, '2026-01-01') returning user_id, created_on::text", [P, MEM2]))[0];
      rec('B10', '관리 도구(postgres) 입력은 값을 그대로 둠', '지정한 회원·날짜 그대로', `${x.user_id === MEM2} / ${x.created_on}`, x.user_id === MEM2 && x.created_on === '2026-01-01'); }
    { const mt = await tokenOf(MEM);
      const r = await req('POST', '/rest/v1/place_checks', { place_id: P }, mt, { Prefer: 'return=representation' }); const x = (r.data || [])[0] || {};
      rec('B11', '일반 회원의 정상 확인', '201, 본인 기록', `${r.t} / 본인 ${x.user_id === MEM}`, r.status === 201 && x.user_id === MEM); }

    // ════ C. 이벤트 응모 — 전용 세차장 900004. 날짜 조정은 이 테스트 DB 안에서만 ════
    const E = 900004;
    const dbToday = await one("select (now() at time zone 'Asia/Seoul')::date::text");
    const realStart = await one('select public.ppx_event_start()::text');
    const comment = async (tok, body, place = E) => { const r = await req('POST', '/rest/v1/place_comments?select=id', { place_id: place, nickname: '테스트', body }, tok, { Prefer: 'return=representation' }); return r.data && r.data[0] && r.data[0].id; };
    const check = (tok, place = E) => req('POST', '/rest/v1/place_checks', { place_id: place }, tok);
    const enter = (tok, cid) => req('POST', '/rest/v1/rpc/ppx_enter_event', { cid }, tok);
    const entries = () => one('select count(*)::int from public.event_entries');
    const a1 = await anonUser(); const a1c = await comment(a1.token, '폼건 압력이 좋고 자리가 넓어요'); await check(a1.token);
    { const r = await enter(a1.token, a1c);
      rec('C1', `이벤트 시작 전 응모 (테스트 DB 오늘 ${dbToday}, 시작일 ${realStart})`, 'P0001 "11월 14일부터", 응모 0건', `${r.t} ${String(r.msg).slice(0, 30)} / 응모 ${await entries()}건`, r.code === 'P0001' && /11월 14일/.test(r.msg || '') && (await entries()) === 0); }
    // ▼ 테스트 DB에서만 시작일을 이번 주 시작(토요일)으로 당김. 권한(ACL)은 create or replace 가 그대로 유지함
    const weekStart = await one('select public.ppx_event_week(now())::text');
    const aclBefore = await one("select coalesce(proacl::text, 'NULL') from pg_proc where oid = 'public.ppx_event_start()'::regprocedure");
    await c.query(`create or replace function public.ppx_event_start() returns date language sql immutable ${apply ? 'set search_path = pg_catalog, public, pg_temp ' : ''}as $$ select date '${weekStart}' $$`);
    const aclAfter = await one("select coalesce(proacl::text, 'NULL') from pg_proc where oid = 'public.ppx_event_start()'::regprocedure");
    rec('C2', `[테스트 DB 한정] 시작일을 ${weekStart}로 조정 — 권한은 그대로`, '함수 권한(ACL) 변화 없음', aclBefore === aclAfter ? '변화 없음 ' + aclAfter : aclBefore + ' → ' + aclAfter, aclBefore === aclAfter);
    let code1;
    { const r = await enter(a1.token, a1c); code1 = r.data && r.data.code;
      rec('C3', '익명 사용자 응모 (한마디 10자 이상 + 다녀왔어요)', '200, 응모번호 XXX-XXX, already=false, 응모 1건', `${r.t} / ${code1} / already=${r.data && r.data.already} / 주 ${r.data && r.data.week} / 응모 ${await entries()}건`,
          r.status === 200 && /^[A-Z2-9]{3}-[A-Z2-9]{3}$/.test(code1 || '') && r.data.already === false && (await entries()) === 1); }
    const mt = await tokenOf(MEM2); const mc = await comment(mt, '손세차 꼼꼼하고 대기실이 쾌적해요'); await check(mt);
    { const r = await enter(mt, mc);
      rec('C4', '회원 응모', '200, 응모번호, already=false, 응모 2건', `${r.t} / ${r.data && r.data.code} / already=${r.data && r.data.already} / 응모 ${await entries()}건`, r.status === 200 && r.data.already === false && (await entries()) === 2); }
    { const r = await enter(a1.token, a1c);
      rec('C5', '중복 응모 (같은 주 두 번째)', '같은 번호, already=true, 응모 그대로 2건', `${r.t} / ${r.data && r.data.code} / already=${r.data && r.data.already} / 응모 ${await entries()}건`, r.status === 200 && r.data.code === code1 && r.data.already === true && (await entries()) === 2); }
    { const b1 = await anonUser(); const bc = await comment(b1.token, '한마디만 쓰고 다른 정보는 없음'); const r = await enter(b1.token, bc);
      rec('C6', '조건 미달: 한마디만 있고 확인·제보·투표 없음', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const b2 = await anonUser(); const bc = await comment(b2.token, '짧아요'); await check(b2.token); const r = await enter(b2.token, bc);
      rec('C7', '조건 미달: 한마디 10자 미만', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const b3 = await anonUser(); await check(b3.token); const r = await enter(b3.token, a1c);
      rec('C8', '남이 쓴 한마디로 응모', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const b4 = await anonUser(); const bc = await comment(b4.token, '세 시간 전에 쓴 한마디라고 가정'); await check(b4.token);
      await c.query("update public.place_comments set created_at = now() - interval '3 hours' where id = $1", [bc]);
      const r = await enter(b4.token, bc);
      rec('C9', '응모 가능 시간(2시간)이 지난 한마디', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const b5 = await anonUser(); const bc = await comment(b5.token, '지난주에 쓴 한마디라고 가정함'); await check(b5.token);
      await c.query("update public.place_comments set created_at = now() - interval '8 days' where id = $1", [bc]);
      const r = await enter(b5.token, bc);
      rec('C10', '지난 주(이미 끝난 회차)의 한마디로 응모', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const b6 = await anonUser(); const bc = await comment(b6.token, '차단될 사용자의 한마디입니다'); await check(b6.token);
      await c.query('update public.profiles set blocked = true where id = $1', [b6.id]);
      const r = await enter(b6.token, bc);
      rec('C11', '차단된 사용자의 응모', 'P0001 거절', `${r.t} ${String(r.msg).slice(0, 26)}`, r.code === 'P0001' && (await entries()) === 2); }
    { const r = await req('POST', '/rest/v1/rpc/ppx_enter_event', { cid: a1c });
      rec('C12', '비로그인 응모', '401 권한 없음', r.t, r.status === 401 && r.code === '42501'); }
    { const rs = []; for (const [fn, qs] of [['ppx_event_week', ''], ['ppx_event_start', ''], ['ppx_event_draw_at', '?w=' + weekStart]]) {
        const ra = await req('GET', '/rest/v1/rpc/' + fn + qs); const ru = await req('GET', '/rest/v1/rpc/' + fn + qs, undefined, a1.token); rs.push(fn + ' 비로그인 ' + ra.t + ' · 로그인 ' + ru.t); var allDenied = (allDenied === undefined ? true : allDenied) && ra.code === '42501' && ru.code === '42501'; }
      rec('C13', 'ppx_event_week·start·draw_at 직접 호출', apply ? '모두 42501 (권한 회수됨)' : '모두 200 (변경 전: 열려 있음)', rs.join(' / '), apply ? allDenied : !allDenied); }
    { const ra = await req('GET', '/rest/v1/rpc/ppx_event_status'); const ru = await req('GET', '/rest/v1/rpc/ppx_event_status', undefined, a1.token);
      rec('C14', '이벤트 현황 표시 (비로그인·응모자)', '200, 전체 2건·회원 1건, 응모자에게 내 번호', `비로그인 ${ra.t} 전체 ${ra.data && ra.data.all_count}·회원 ${ra.data && ra.data.member_count} / 응모자 ${ru.t} 내 번호 ${ru.data && ru.data.mine && ru.data.mine[0] && ru.data.mine[0].code}`,
          ra.status === 200 && ra.data.all_count === 2 && ra.data.member_count === 1 && ru.data.mine[0].code === code1 && Array.isArray(ra.data.mine) && ra.data.mine.length === 0); }
    { const w = await one(`select public.ppx_auto_draw((date '${weekStart}' + 9 + time '17:00') at time zone 'Asia/Seoul')::text`);
      const winners = await one('select count(*)::int from public.event_winners');
      const st = await req('GET', '/rest/v1/rpc/ppx_event_status');
      rec('C15', '자동 추첨(크론과 같은 postgres 호출, 발표 시각을 인자로 줌)', '당첨 2건(응모 2건 모두), 현황에 당첨 번호 표시', `${String(w).slice(0, 70)} / 당첨 ${winners}건 / 현황 last.winners ${st.data && st.data.last && st.data.last.winners && st.data.last.winners.length}건`,
          winners === 2 && st.data.last && st.data.last.winners.length === 2); }
    { const adm = await tokenOf(ADMIN); const r = await req('POST', '/rest/v1/rpc/admin_event_week', { w: weekStart }, adm); const r2 = await req('POST', '/rest/v1/rpc/admin_event_week', { w: weekStart }, a1.token);
      rec('C16', '운영자 화면 응모 목록 (운영자 / 일반 사용자)', '운영자 200 · 일반 P0001', `운영자 ${r.t} · 일반 ${r2.t}`, r.status === 200 && r2.code === 'P0001'); }
  } catch (e) { rec('ERR', '테스트 실행 오류', '-', e.message, false); }
  finally { await c.end(); emu.kill(); await sleep(200); }
  return out;
}

(async () => {
  const before = await run('fbc0', false), after = await run('fbc1', true);
  const line = o => `${o.no.padEnd(5)}| ${o.verdict} | ${o.name}\n       기대: ${o.expect}\n       결과: ${o.got}`;
  console.log('════ 적용 후 DB ════\n' + after.map(line).join('\n'));
  console.log(`\n합계(적용 후): PASS ${after.filter(o => o.verdict === 'PASS').length} / FAIL ${after.filter(o => o.verdict === 'FAIL').length}`);
  console.log('\n════ 변경 전 DB (같은 시험) ════');
  console.log(`합계(변경 전): PASS ${before.filter(o => o.verdict === 'PASS').length} / FAIL ${before.filter(o => o.verdict === 'FAIL').length}`);
  const differ = after.filter(a => { const b = before.find(x => x.no === a.no); return !b || b.verdict !== a.verdict; });
  console.log('변경 전과 판정이 다른 항목: ' + (differ.map(d => d.no).join(', ') || '없음'));
  for (const b of before.filter(o => o.verdict === 'FAIL' || ['B1', 'B4b', 'C13'].includes(o.no))) console.log('  [변경 전] ' + line(b).replace(/\n/g, '\n  '));
})().catch(e => { console.error('RUNNER ERROR', e); process.exit(1); });
