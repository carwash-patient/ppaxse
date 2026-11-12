// PostgREST·Auth 요청 '흉내' 서버 (테스트 전용 — 실제 PostgREST/GoTrue 가 아님)
// 이 작업 공간에서는 실제 PostgREST 바이너리를 받을 수 없어(외부 저장소 차단) 요청 처리 순서만 같게 만든 것입니다.
//   · 요청마다 트랜잭션을 열고  set local role anon|authenticated,  request.jwt.claims / request.jwt.claim.sub 설정
//   · GET 은 읽기 전용 트랜잭션으로 실행 (PostgREST 와 같음)
//   · 오류 코드 → HTTP 상태: 42501 → 401(비로그인)/403(로그인), P0001 → 400, 23505/23503 → 409
// DB 쪽(RLS·트리거·함수 권한)은 흉내가 아니라 실제 PostgreSQL 17 이 그대로 처리합니다.
// 사용: node pgrst_emu.js <db이름> <포트>
const http = require('http'), crypto = require('crypto');
const { Client, types } = require('/tmp/stack/node_modules/pg');
types.setTypeParser(20, v => Number(v));   // bigint 를 숫자로 (PostgREST 의 JSON 출력과 같게)
types.setTypeParser(1082, v => v);          // date 는 문자열 그대로
const DB = process.argv[2], PORT = +process.argv[3] || 3999;
const KEY = 'sb_publishable_TEST', SECRET = 'test-secret';
const refresh = new Map();           // refresh_token → user id
let FAULT = null, REQS = 0;                    // 테스트용 고장 주입: { method, pathIncludes, times }
const b64 = o => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
const sign = claims => { const h = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64(claims);
  return h + '.' + crypto.createHmac('sha256', SECRET).update(h).digest('base64url'); };
const verify = t => { const [a, b, c] = t.split('.'); if (!c) return null;
  if (crypto.createHmac('sha256', SECRET).update(a + '.' + b).digest('base64url') !== c) return null;
  return JSON.parse(Buffer.from(b, 'base64url').toString()); };
const pg = async () => { const c = new Client({ host: '/tmp/pg17', port: 5545, user: 'postgres', database: DB }); await c.connect(); return c; };
const ident = s => { if (!/^[a-z_][a-z0-9_]*$/.test(s)) throw new Error('bad identifier ' + s); return '"' + s + '"'; };
const issue = id => { const rt = crypto.randomBytes(12).toString('hex'); refresh.set(rt, id);
  const now = Math.floor(Date.now() / 1000);
  return { access_token: sign({ sub: id, role: 'authenticated', aud: 'authenticated', is_anonymous: true, iat: now, exp: now + 3600 }),
           refresh_token: rt, user: { id, is_anonymous: true } }; };

async function asRole(req, readOnly, fn) {
  const auth = (req.headers.authorization || '').replace(/^Bearer /, '');
  let claims = { role: 'anon' };
  if (auth && auth !== KEY) { const v = verify(auth); if (!v) return { status: 401, body: { code: 'PGRST301', message: 'JWT invalid' } }; claims = v; }
  if (req.headers.apikey !== KEY) return { status: 401, body: { message: 'Invalid API key' } };
  const c = await pg();
  try {
    await c.query(readOnly ? 'begin read only' : 'begin');
    await c.query(`select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true)`, [JSON.stringify(claims), claims.sub || '']);
    await c.query('set local role ' + ident(claims.role));
    const out = await fn(c);
    await c.query('commit');
    return out;
  } catch (e) {
    try { await c.query('rollback'); } catch (x) {}
    const code = e.code || 'XX000';
    const status = code === '42501' ? (claims.role === 'anon' ? 401 : 403) : (code === '23505' || code === '23503') ? 409 : code === '25006' ? 405 : 400;
    return { status, body: { code, message: e.message, details: e.detail || null, hint: e.hint || null } };
  } finally { await c.end(); }
}
function filters(q, startAt) {     // col=eq.x / like.x  → where 절
  const w = [], v = [];
  for (const [k, val] of q) {
    if (['select', 'order', 'limit'].includes(k)) continue;
    const m = /^(eq|like|neq)\.(.*)$/s.exec(val); if (!m) throw new Error('unsupported filter ' + k + '=' + val);
    v.push(m[1] === 'like' ? m[2].replace(/\*/g, '%') : m[2]);
    w.push(`${ident(k)}::text ${m[1] === 'eq' ? '=' : m[1] === 'neq' ? '<>' : 'like'} $${startAt + v.length}`);
  }
  return { where: w.length ? ' where ' + w.join(' and ') : '', values: v };
}
const cols = q => (q.get('select') || '*').split(',').map(s => s === '*' ? '*' : ident(s)).join(', ');

const server = http.createServer(async (req, res) => {
  let raw = ''; for await (const ch of req) raw += ch;
  const body = raw ? JSON.parse(raw) : undefined;
  const u = new URL(req.url, 'http://x'); const q = u.searchParams; const path = u.pathname;
  const send = (status, obj) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(obj === undefined ? '' : JSON.stringify(obj)); };
  try {
    if (path === '/__fault') { FAULT = body; return send(200, { ok: true }); }
    if (FAULT && req.method === FAULT.method && path.includes(FAULT.pathIncludes) && FAULT.times > 0) {
      FAULT.times--; if (FAULT.kind === 'drop') { req.socket.destroy(); return; } return send(500, { code: 'FAULT', message: '주입된 고장' }); }
    if (path === '/__token') {      // 테스트 전용: 이미 있는 회원의 토큰 발급
      const now = Math.floor(Date.now() / 1000);
      return send(200, { access_token: sign({ sub: body.id, role: 'authenticated', aud: 'authenticated', is_anonymous: !!body.anon, iat: now, exp: now + 3600 }) });
    }
    if (path === '/__count') return send(200, { n: REQS });
    REQS++;
    if (path === '/auth/v1/signup') {
      const c = await pg(); const id = crypto.randomUUID();
      await c.query('insert into auth.users (id, email, is_anonymous, raw_user_meta_data) values ($1, null, true, $2)', [id, JSON.stringify((body && body.data) || {})]);
      await c.end(); return send(200, issue(id));
    }
    if (path === '/auth/v1/token') {
      const id = refresh.get(body && body.refresh_token); if (!id) return send(400, { msg: 'Invalid Refresh Token' });
      const c = await pg(); const r = await c.query('select 1 from auth.users where id = $1', [id]); await c.end();
      if (!r.rowCount) return send(400, { msg: 'Invalid Refresh Token: user not found' });
      refresh.delete(body.refresh_token); return send(200, issue(id));
    }
    let m;
    if ((m = /^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(path))) {
      const args = req.method === 'GET' ? Object.fromEntries(q) : (body || {});
      const names = Object.keys(args);
      const r = await asRole(req, req.method === 'GET', async c => {
        const x = await c.query(`select public.${ident(m[1])}(${names.map((n, i) => `${ident(n)} => $${i + 1}`).join(', ')}) as v`, names.map(n => args[n]));
        const v = x.rows.length === 1 ? x.rows[0].v : x.rows.map(r => r.v);
        return v === null || v === '' ? { status: x.fields[0].dataTypeID === 2278 ? 204 : 200, body: v === '' ? undefined : null } : { status: 200, body: v };
      });
      return send(r.status, r.body);
    }
    if ((m = /^\/rest\/v1\/([a-z_]+)$/.exec(path))) {
      const t = 'public.' + ident(m[1]);
      const r = await asRole(req, req.method === 'GET', async c => {
        if (req.method === 'GET') {
          const f = filters(q, 0); const ord = q.get('order');
          const o = ord ? ' order by ' + ord.split(',').map(s => { const [cn, d] = s.split('.'); return ident(cn) + (d === 'desc' ? ' desc' : ''); }).join(', ') : '';
          const x = await c.query(`select ${cols(q)} from ${t}${f.where}${o}${q.get('limit') ? ' limit ' + (+q.get('limit')) : ''}`, f.values);
          return { status: 200, body: x.rows };
        }
        if (req.method === 'POST') {
          const k = Object.keys(body);
          const x = await c.query(`insert into ${t} (${k.map(ident).join(', ')}) values (${k.map((_, i) => '$' + (i + 1)).join(', ')}) returning ${cols(q)}`, k.map(n => body[n]));
          return { status: 201, body: x.rows };
        }
        if (req.method === 'PATCH' || req.method === 'DELETE') {
          const k = req.method === 'PATCH' ? Object.keys(body) : [];
          const f = filters(q, k.length);
          const sql = req.method === 'PATCH'
            ? `update ${t} set ${k.map((n, i) => `${ident(n)} = $${i + 1}`).join(', ')}${f.where} returning ${cols(q)}`
            : `delete from ${t}${f.where} returning ${cols(q)}`;
          const x = await c.query(sql, k.map(n => body[n]).concat(f.values));
          return { status: 200, body: x.rows };
        }
        throw new Error('unsupported method');
      });
      return send(r.status, r.body);
    }
    send(404, { message: 'not found' });
  } catch (e) { send(500, { code: 'EMU', message: String(e.message || e) }); }
});
server.listen(PORT, '127.0.0.1', () => console.log('emu ready', DB, PORT));
