// 흐름 A: 쓰기 테스트 스크립트 + 정리 SQL 전체 검증 (테스트 DB + 요청 흉내 서버)
// 사용: node run_flow_a.js   (PG17 테스트 서버가 떠 있어야 함)
const fs = require('fs'), cp = require('child_process');
const { Client } = require('/tmp/stack/node_modules/pg');
const REPO = '/home/claude/ppaxse';
const SCRIPT = fs.readFileSync(REPO + '/docs/security-tests-2026-11-12/api_postapply_write_test.js', 'utf8');
const PREVIEW = fs.readFileSync(REPO + '/supabase/cleanup_sectest_preview_2026-11-12.sql', 'utf8');
const DELETE = fs.readFileSync(REPO + '/supabase/cleanup_sectest_delete_2026-11-12.sql', 'utf8');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const out = [];
const rec = (no, name, expect, got, pass) => { out.push({ no, name, expect, got: String(got), verdict: pass ? 'PASS' : 'FAIL' }); };
const store = {}; globalThis.localStorage = { getItem: k => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; } };
const quiet = async f => { const t = console.table, l = console.log; console.table = () => {}; console.log = () => {}; try { return await f(); } finally { console.table = t; console.log = l; } };
const runScript = confirm => quiet(() => eval(SCRIPT.replace(/\)\('아직'\);.*$/s, ")('" + confirm + "')")));
const params = ids => PARAM_RE => null;
const fill = (sql, ids) => sql
  .replace("'00000000-0000-0000-0000-000000000000'::uuid as test_user", "'" + ids.test_user + "'::uuid as test_user")
  .replace('array[]::bigint[] as place_ids', 'array[' + ids.place_ids.join(',') + ']::bigint[] as place_ids')
  .replace('array[]::bigint[] as report_ids', 'array[' + ids.report_ids.join(',') + ']::bigint[] as report_ids');

async function withDb(db, apply, f) {
  cp.execSync(`./mkdb_e.sh ${db} ${apply ? 'apply' : 'noapply'}`, { cwd: __dirname, stdio: 'ignore' });
  const port = 3900 + Math.floor(Math.random() * 90);
  const emu = cp.spawn('node', [__dirname + '/pgrst_emu.js', db, port], { stdio: 'ignore' });
  await sleep(700);
  globalThis.PPX_TEST_TARGET = { url: 'http://127.0.0.1:' + port, key: 'sb_publishable_TEST' };
  for (const k of Object.keys(store)) delete store[k];
  const c = new Client({ host: '/tmp/pg17', port: 5545, user: 'postgres', database: db }); await c.connect();
  const TABLES = ['auth.users', 'public.profiles', 'public.places', 'public.place_reports', 'public.place_comments', 'public.place_checks',
    'public.place_comment_reports', 'public.place_type_votes', 'public.event_entries', 'public.event_winners', 'public.anon_claims',
    'public.ppx_abuse_log', 'public.ppx_visits', 'public.ppx_visitor_ref', 'storage.objects'];
  const snap = async () => { const o = {}; for (const t of TABLES) { const r = await c.query(`select count(*)::int n, md5(coalesce(string_agg(x::text, '|' order by x::text), '')) h from ${t} x`); o[t] = r.rows[0].n + ':' + r.rows[0].h; } return o; };
  const diff = (a, b) => TABLES.filter(t => a[t] !== b[t]).map(t => `${t} ${a[t].split(':')[0]}→${b[t].split(':')[0]}`).join(', ') || '차이 없음';
  const sql = async text => { try { const r = await c.query(text); const last = Array.isArray(r) ? r[r.length - 1] : r; return { ok: true, rows: last.rows || [] }; }
    catch (e) { try { await c.query('rollback'); } catch (x) {} return { ok: false, err: e.message }; } };
  const api = async (method, path, body) => (await fetch(globalThis.PPX_TEST_TARGET.url + path, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined })).json();
  try { return await f({ c, snap, diff, sql, api }); } finally { await c.end(); emu.kill(); await sleep(200); }
}
const passAll = r => r.기록.every(x => x.판정 === 'PASS');
const rows = (r, name) => r.기록.find(x => x.시험.includes(name));

(async () => {
  // ── A0. CONFIRM 을 바꾸지 않으면 아무 요청도 보내지 않는다 / 적용 전 DB에서는 첫 단계에서 멈춘다 ──
  await withDb('fa0', false, async ({ snap, diff, api }) => {
    const s0 = await snap();
    const r1 = await runScript('아직');
    rec('A0-1', "CONFIRM='아직' → 요청 0건", '요청 0건, 기록 0줄', (await api('GET', '/__count')).n + '건, 기록 ' + r1.기록.length + '줄', (await api('GET', '/__count')).n === 0 && r1.기록.length === 0);
    const r2 = await runScript('적용 완료');
    rec('A0-2', '적용 전 DB에서 실행 → 첫 단계에서 중단', '중단, 만든 데이터 없음', r2.중단사유 + ' / 데이터 ' + diff(s0, await snap()), /적용되지 않은/.test(r2.중단사유) && diff(s0, await snap()) === '차이 없음');
  });

  // ── A1~A8. 정상 흐름 → 재실행 → 정리 → 정리 후 재실행 ──
  await withDb('fa1', true, async ({ c, snap, diff, sql }) => {
    const s0 = await snap();
    const r1 = await runScript('적용 완료');
    const s1 = await snap();
    rec('A1', '1회차: 모든 단계 PASS', '전부 PASS', r1.기록.filter(x => x.판정 !== 'PASS').map(x => x.시험).join(',') || `PASS ${r1.기록.length}단계`, passAll(r1));
    rec('A1-계정', '① 익명 테스트 계정 생성', 'role=authenticated, is_anonymous=true', rows(r1, 'JWT').결과, rows(r1, 'JWT').판정 === 'PASS');
    rec('A1-세차장', '② 조작한 세차장 제보 → 대기·본인 고정', '201 / pending / user / 본인 / 0', rows(r1, '조작한 세차장').결과, rows(r1, '조작한 세차장').판정 === 'PASS');
    rec('A1-제보', '③ 조작한 정보 제보 → 대기·본인 고정', '201 / pending / 본인', rows(r1, '조작한 정보').결과, rows(r1, '조작한 정보').판정 === 'PASS');
    rec('A1-제한', '④ 중복 제출 제한 (30초·15초)', 'P0001 두 건', rows(r1, '30초').결과.slice(0, 9) + ' · ' + rows(r1, '15초').결과.slice(0, 9), rows(r1, '30초').판정 === 'PASS' && rows(r1, '15초').판정 === 'PASS');
    rec('A1-권한', '⑤ 자기 권한 상승 차단', '42501', rows(r1, 'admin으로').결과, rows(r1, 'admin으로').판정 === 'PASS');
    rec('A1-수정', '⑥ 승인된 세차장 수정 차단', '0건', rows(r1, '승인된 세차장 수정').결과, rows(r1, '승인된 세차장 수정').판정 === 'PASS');
    // 스크립트가 보고한 '만든 데이터' = DB에 실제로 늘어난 데이터
    const real = await c.query(`select (select array_agg(id order by id) from public.places where submitted_by = $1) p, (select array_agg(id order by id) from public.place_reports where reporter = $1) r,
       (select count(*)::int from auth.users where id = $1) u`, [r1.정리_매개변수.test_user]);
    const same = JSON.stringify(real.rows[0].p.map(Number)) === JSON.stringify(r1.정리_매개변수.place_ids) && JSON.stringify(real.rows[0].r.map(Number)) === JSON.stringify(r1.정리_매개변수.report_ids);
    rec('A1-기록', '보고된 ID = DB에 실제 생긴 행', '계정 1, 세차장 1, 제보 1 (ID 일치)', `계정 ${real.rows[0].u}, 세차장 [${real.rows[0].p}], 제보 [${real.rows[0].r}] / DB 변화: ${diff(s0, s1)}`,
        same && real.rows[0].u === 1 && diff(s0, s1) === 'auth.users 3→4, public.profiles 3→4, public.places 4→5, public.place_reports 1→2');

    // 정리 전 재실행: 같은 계정 재사용, 새로 만들지 않음
    const r2 = await runScript('적용 완료');
    rec('A2', '정리 전 재실행: 계정 재사용·중복 생성 없음', 'DB 변화 없음, 같은 계정, 같은 ID', `${diff(s1, await snap())} / 같은 계정 ${r2.정리_매개변수.test_user === r1.정리_매개변수.test_user} / ${JSON.stringify(r2.정리_매개변수.place_ids)} ${JSON.stringify(r2.정리_매개변수.report_ids)}`,
        diff(s1, await snap()) === '차이 없음' && JSON.stringify(r2.정리_매개변수) === JSON.stringify(r1.정리_매개변수) && r2.만들어진_데이터.length === 0);

    // ⑦ 정리: 미리 보기 → 삭제
    const pv = await sql(fill(PREVIEW, r1.정리_매개변수));
    rec('A3', '⑦-1 미리 보기(읽기 전용)', "요약 '진행 가능', DB 변화 없음", (pv.ok ? pv.rows[0].판정 + ' / ' + pv.rows[0].내용 : pv.err) + ' / ' + diff(s1, await snap()), pv.ok && pv.rows[0].판정 === '진행 가능' && diff(s1, await snap()) === '차이 없음');
    const dl = await sql(fill(DELETE, r1.정리_매개변수));
    const s2 = await snap();
    rec('A4', '⑦-2 삭제', '제보 1·세차장 1·계정 1 삭제', dl.ok ? dl.rows.map(x => x.항목 + '=' + x.건수).join(', ') : dl.err, dl.ok && dl.rows[0].건수 === 1 && dl.rows[1].건수 === 1 && dl.rows[2].건수 === 1);
    rec('A5', '정리 후 DB = 테스트 전 DB (모든 표의 행 내용 비교)', '차이 없음', diff(s0, s2), diff(s0, s2) === '차이 없음');
    const dl2 = await sql(fill(DELETE, r1.정리_매개변수));
    rec('A6', '삭제 SQL 다시 실행', '중단(계정 없음), DB 변화 없음', (dl2.ok ? '실행됨' : dl2.err.slice(0, 60)) + ' / ' + diff(s2, await snap()), !dl2.ok && /정리 중단/.test(dl2.err) && diff(s2, await snap()) === '차이 없음');

    // ⑧ 정리 후 재실행: 새 계정으로 처음부터 (30초 제한은 계정별이라 영향 없음)
    const r3 = await runScript('적용 완료');
    rec('A7', '⑧ 정리 후 재실행: 새 계정으로 전 단계 PASS', '전부 PASS, 새 계정', `${passAll(r3) ? 'PASS ' + r3.기록.length + '단계' : 'FAIL'} / 새 계정 ${r3.정리_매개변수.test_user !== r1.정리_매개변수.test_user}`, passAll(r3) && r3.정리_매개변수.test_user !== r1.정리_매개변수.test_user);
    const dl3 = await sql(fill(DELETE, r3.정리_매개변수));
    rec('A8', '재실행분 정리 후 DB = 테스트 전 DB', '차이 없음', dl3.ok ? diff(s0, await snap()) : dl3.err, dl3.ok && diff(s0, await snap()) === '차이 없음');
  });

  // ── B. 중간 실패: 남는 데이터가 보고와 일치하고 정리되는가 ──
  for (const [no, title, fault, expectDiff] of [
    ['B1', '익명 로그인 단계에서 서버 오류', { method: 'POST', pathIncludes: '/auth/v1/signup', times: 1, kind: '500' }, '차이 없음'],
    ['B2', '정보 제보 등록에서 서버 오류 (세차장 제보는 이미 생김)', { method: 'POST', pathIncludes: '/rest/v1/place_reports', times: 1, kind: '500' }, 'auth.users 3→4, public.profiles 3→4, public.places 4→5'],
    ['B3', '두 번째 세차장 제보에서 연결 끊김', { method: 'POST', pathIncludes: '/rest/v1/places', times: 0, kind: 'drop', second: true }, 'auth.users 3→4, public.profiles 3→4, public.places 4→5'],
  ]) {
    await withDb('fb' + no.toLowerCase(), true, async ({ c, snap, diff, sql, api }) => {
      const s0 = await snap();
      if (fault.second) {       // 첫 등록은 통과시키고 두 번째에서 끊기도록: 첫 요청 뒤에 고장을 켬
        const orig = globalThis.fetch; let n = 0;
        globalThis.fetch = async (u, o) => { if (o && o.method === 'POST' && String(u).endsWith('/rest/v1/places') && ++n === 2) await api('POST', '/__fault', { ...fault, times: 1 }); return orig(u, o); };
        var restore = () => { globalThis.fetch = orig; };
      } else await api('POST', '/__fault', fault);
      const r = await runScript('적용 완료'); if (restore) restore();
      const s1 = await snap();
      const ids = r.정리_매개변수;
      const real = ids.test_user ? (await c.query(`select coalesce((select array_agg(id order by id) from public.places where submitted_by = $1), '{}') p, coalesce((select array_agg(id order by id) from public.place_reports where reporter = $1), '{}') r`, [ids.test_user])).rows[0] : { p: [], r: [] };
      const match = JSON.stringify(real.p.map(Number)) === JSON.stringify(ids.place_ids) && JSON.stringify(real.r.map(Number)) === JSON.stringify(ids.report_ids);
      rec(no + '-1', title + ' → 기록', '실패가 기록되고, 보고된 ID = 실제 남은 행', `FAIL 단계: ${r.기록.filter(x => x.판정 === 'FAIL').map(x => x.시험).join(' / ') || '없음'} · 중단사유: ${r.중단사유 || '-'} · 남은 것: ${diff(s0, s1)} · ID 일치 ${match}`,
          r.기록.some(x => x.판정 === 'FAIL') && match && diff(s0, s1) === expectDiff);
      if (ids.test_user) {
        const pv = await sql(fill(PREVIEW, ids)); const dl = pv.ok && pv.rows[0].판정 === '진행 가능' ? await sql(fill(DELETE, ids)) : { ok: false, err: '미리 보기 중단: ' + (pv.err || pv.rows[0].내용) };
        rec(no + '-2', title + ' → 정리', '정리 후 DB = 테스트 전 DB', dl.ok ? diff(s0, await snap()) : dl.err, dl.ok && diff(s0, await snap()) === '차이 없음');
      } else rec(no + '-2', title + ' → 정리', '정리할 것 없음', r.정리, /정리할 것 없음/.test(r.정리));
    });
  }

  // ── C. 정리 SQL이 잘못된 대상을 거부하는가 ──
  await withDb('fc1', true, async ({ c, snap, diff, sql, api }) => {
    const r = await runScript('적용 완료'); const ids = r.정리_매개변수; const s1 = await snap();
    const tryBoth = async (no, title, bad, mutate, undo) => {
      if (mutate) await c.query(mutate);
      const sA = await snap();
      const pv = await sql(fill(PREVIEW, bad)); const dl = await sql(fill(DELETE, bad));
      const stars = pv.ok ? pv.rows.filter(x => String(x.판정).startsWith('★') && x.종류 !== '요약').map(x => x.종류 + ':' + x.대상).join(' | ') : pv.err;
      rec(no, title, "미리 보기 '★ 중단', 삭제 SQL 중단, DB 변화 없음", `미리 보기: ${pv.ok ? pv.rows[0].판정 : '오류'} (${stars.slice(0, 110)}) · 삭제: ${dl.ok ? '실행됨!' : dl.err.slice(0, 70)} · ${diff(sA, await snap())}`,
          pv.ok && pv.rows[0].판정 === '★ 중단' && !dl.ok && diff(sA, await snap()) === '차이 없음');
      if (undo) await c.query(undo);
    };
    await tryBoth('C1', '운영 세차장 ID(900001)를 섞어 넣음', { ...ids, place_ids: [...ids.place_ids, 900001] });
    await tryBoth('C2', '남의 정보 제보 ID(실제 이용자 제보)를 섞어 넣음', { ...ids, report_ids: [...ids.report_ids, 1] });
    await tryBoth('C3', '테스트 계정 대신 실제 회원 UUID', { ...ids, test_user: '00000000-0000-0000-0000-00000000000b' });
    await tryBoth('C4', '만든 ID 일부를 빼고 넣음(계정에 데이터가 더 남음)', { ...ids, place_ids: [] });
    await tryBoth('C5', '테스트 계정에 다녀왔어요 기록이 있음', ids, `insert into public.place_checks (place_id, user_id) values (900002, '${ids.test_user}')`, `delete from public.place_checks where user_id = '${ids.test_user}'; update public.places set check_count = 0, checked_at = null where id = 900002`);
    await tryBoth('C6', '테스트 계정에 한마디 신고(place_comment_reports) 기록이 있음', ids, `alter table public.place_comment_reports disable trigger user; insert into public.place_comment_reports (comment_id, reporter, reason) select id, '${ids.test_user}', 'other' from public.place_comments limit 1; alter table public.place_comment_reports enable trigger user`, `delete from public.place_comment_reports where reporter = '${ids.test_user}'`);
    await tryBoth('C7', '테스트 계정에 종류 투표(외래키 없는 칸) 기록이 있음', ids, `insert into public.place_type_votes (place_id, user_id, main) values (900002, '${ids.test_user}', 'self')`, `delete from public.place_type_votes where user_id = '${ids.test_user}'`);
    await tryBoth('C8', '테스트 세차장 제보에 남이 쓴 한마디가 붙어 있음', ids, `alter table public.place_comments disable trigger user; insert into public.place_comments (place_id, user_id, nickname, body) values (${ids.place_ids[0]}, '00000000-0000-0000-0000-00000000000b', 'x', '남이 쓴 한마디입니다요'); alter table public.place_comments enable trigger user`, `delete from public.place_comments where place_id = ${ids.place_ids[0]}`);
    await tryBoth('C9', '테스트 세차장 제보가 승인 상태로 바뀌어 있음', ids, `update public.places set status = 'approved' where id = ${ids.place_ids[0]}`, `update public.places set status = 'pending', reviewed_by = null, reviewed_at = null where id = ${ids.place_ids[0]}`);
    const pv = await sql(fill(PREVIEW, ids));
    const dl = await sql(fill(DELETE, ids));
    rec('C10', '위 상황을 되돌린 뒤 올바른 매개변수로 정리', '진행 가능 → 삭제 성공', (pv.ok ? pv.rows[0].판정 : pv.err) + ' → ' + (dl.ok ? dl.rows.map(x => x.항목 + '=' + x.건수).join(', ') : dl.err), pv.ok && pv.rows[0].판정 === '진행 가능' && dl.ok);
  });

  const w = out.map(o => `${o.no.padEnd(8)}| ${o.verdict} | ${o.name}\n          기대: ${o.expect}\n          결과: ${o.got}`).join('\n');
  console.log(w + `\n\n합계: PASS ${out.filter(o => o.verdict === 'PASS').length} / FAIL ${out.filter(o => o.verdict === 'FAIL').length}`);
})().catch(e => { console.log(out.map(o => o.no + ' ' + o.verdict + ' ' + o.name + ' :: ' + o.got).join('\n')); console.error('RUNNER ERROR', e.message); process.exit(1); });
