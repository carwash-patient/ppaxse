// 빡세 보안 수정 — 실제 Supabase 요청 경로(PostgREST) 점검 스크립트
// 어디서: https://ppaxse.com 아무 화면 → 개발자 도구 콘솔에 붙여넣기 (또는 Claude가 브라우저에서 실행)
// 무엇을: 공개 키(publishable key)만 씁니다. service_role 키·비밀번호는 절대 쓰지 않습니다.
//
//  WRITE = false (기본): 비로그인 요청만, 읽기 전용. 적용 '전'과 '후'에 모두 실행해 비교합니다.
//  WRITE = true : 적용 '후'에만. 익명 로그인 계정을 하나 새로 만들고(사이트가 제보 때 하는 것과 같은 방식),
//                 조작한 제보를 보내 트리거가 값을 고정하는지 봅니다.
//                 남는 것: 익명 계정 1개, '[보안 점검 테스트]' 대기 제보 1건 + 정보 제보 1건 → 운영자 화면에서 거절/삭제.
(async (WRITE) => {
  const URL = 'https://zylyncnevdxpimyqrifp.supabase.co';
  const KEY = 'sb_publishable_i5ZeUzflI5otoD9GqwQpew_2x3y_RPA';   // 공개돼도 되는 키 (js/config.js 와 같음)
  const uuid = '00000000-0000-4000-8000-000000000001';
  const out = [];
  const call = async (path, body, token, method = 'POST', extra = {}) => {
    const r = await fetch(URL + path, {
      method, headers: { apikey: KEY, Authorization: 'Bearer ' + (token || KEY), 'Content-Type': 'application/json', ...extra },
      body: body === undefined ? undefined : JSON.stringify(body) });
    let j = null; try { j = await r.json(); } catch (e) {}
    return { status: r.status, code: j && j.code, msg: j && j.message, data: j };
  };
  const row = (who, name, expectAfter, r, ok) =>
    out.push({ 누구: who, 시험: name, '적용 후 기대': expectAfter, 결과: r.status + (r.code ? ' ' + r.code : '') + (r.msg ? ' ' + String(r.msg).slice(0, 40) : ''), '적용 후 기준 판정': ok ? 'PASS' : 'FAIL' });
  const denied = r => r.code === '42501';          // permission denied for function …

  // ── 1) 비로그인(anon) — 읽기 전용 ──
  for (const [fn, args] of [['ppx_stats', {}], ['ppx_event_status', {}], ['is_admin', {}]]) {
    const r = await call('/rest/v1/rpc/' + fn, args); row('비로그인', fn, '200 정상', r, r.status === 200);
  }
  { const r = await call('/rest/v1/places?select=id&status=eq.approved&limit=1', undefined, null, 'GET');
    row('비로그인', '지도 데이터 조회', '200, 1건', r, r.status === 200 && Array.isArray(r.data) && r.data.length === 1); }
  for (const [fn, args] of [
    ['ppx_guard', { what: 'place' }], ['ppx_burst_guard', { what: 'place' }], ['my_pending_count', {}], ['my_pending_reports', {}],
    ['start_claim', {}], ['finish_claim', { t: uuid }], ['ppx_event_week', {}], ['ppx_event_start', {}],
    ['ppx_event_draw_at', { w: '2026-11-14' }], ['ppx_is_member', { u: uuid }],
    ['admin_visit_stats', { days: 1 }], ['admin_type_votes', {}],
    ['admin_event_entries', { p_from: '2026-11-01T00:00:00Z', p_to: '2026-11-02T00:00:00Z' }]]) {
    const r = await call('/rest/v1/rpc/' + fn, args); row('비로그인', '거부: ' + fn, '42501 권한 없음', r, denied(r));
  }
  { const r = await call('/rest/v1/places', { name: '[보안 점검 테스트] 비로그인', type: 'self', lat: 37.3857, lng: 126.6444 });
    row('비로그인', '거부: 세차장 직접 등록', '거부(401/403)', r, r.status === 401 || r.status === 403); }

  // ── 2) 익명 로그인(authenticated) — 적용 후에만 ──
  if (WRITE) {
    const s = await call('/auth/v1/signup', {});
    const token = s.data && s.data.access_token;
    if (!token) { out.push({ 누구: '익명 로그인', 시험: '익명 로그인', 결과: s.status + ' ' + (s.msg || ''), '적용 후 기준 판정': 'FAIL' }); }
    else {
      const claims = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      const me = claims.sub;
      out.push({ 누구: '익명 로그인', 시험: 'JWT role / is_anonymous', '적용 후 기대': 'authenticated / true', 결과: claims.role + ' / ' + claims.is_anonymous, '적용 후 기준 판정': claims.role === 'authenticated' && claims.is_anonymous === true ? 'PASS' : 'FAIL' });
      for (const [fn, args] of [['ppx_guard', { what: 'place' }], ['ppx_burst_guard', { what: 'place' }], ['my_pending_count', {}], ['my_pending_reports', {}], ['ppx_event_week', {}]]) {
        const r = await call('/rest/v1/rpc/' + fn, args, token); row('익명 로그인', '거부: ' + fn + ' 직접 실행', '42501 권한 없음', r, denied(r));
      }
      { const r = await call('/rest/v1/rpc/admin_visit_stats', { days: 1 }, token); row('익명 로그인', '거부: 운영자 통계', 'P0001 운영자만', r, r.code === 'P0001'); }
      const rep = { Prefer: 'return=representation' };
      const place = { name: '[보안 점검 테스트] 삭제해 주세요', type: 'self', region: '테스트', lat: 37.3857, lng: 126.6444,
                      status: 'approved', source: 'public_data', submitted_by: uuid, check_count: 99 };   // 일부러 조작
      { const r = await call('/rest/v1/places', place, token, 'POST', rep); const p = (r.data || [])[0] || {};
        row('익명 로그인', '조작한 세차장 제보 → 대기·본인으로 고정', '201, pending / user / 본인 / 0', { status: r.status, code: r.code, msg: [p.status, p.source, p.submitted_by === me ? '본인' : '남', p.check_count].join(' / ') },
            r.status === 201 && p.status === 'pending' && p.source === 'user' && p.submitted_by === me && p.check_count === 0); }
      { const r = await call('/rest/v1/places', place, token, 'POST', rep); row('익명 로그인', '제한: 30초 안에 두 번째 제보', 'P0001 거절', r, r.code === 'P0001'); }
      const ap = await call('/rest/v1/places?select=id&status=eq.approved&limit=1', undefined, token, 'GET');
      const pid = ap.data && ap.data[0] && ap.data[0].id;
      const report = { place_id: pid, memo: '[보안 점검 테스트] 무시해 주세요', status: 'applied', reporter: uuid };   // 일부러 조작
      { const r = await call('/rest/v1/place_reports', report, token, 'POST', rep); const p = (r.data || [])[0] || {};
        row('익명 로그인', '조작한 정보 제보 → 대기·본인으로 고정', '201, pending / 본인', { status: r.status, code: r.code, msg: [p.status, p.reporter === me ? '본인' : '남'].join(' / ') },
            r.status === 201 && p.status === 'pending' && p.reporter === me); }
      { const r = await call('/rest/v1/place_reports', report, token, 'POST', rep); row('익명 로그인', '제한: 15초 안에 두 번째 정보 제보', 'P0001 거절', r, r.code === 'P0001'); }
      { const r = await call('/rest/v1/profiles?id=eq.' + me, { role: 'admin' }, token, 'PATCH', rep); row('익명 로그인', '거부: 내 역할을 admin으로', '42501 권한 없음', r, denied(r)); }
      { const r = await call('/rest/v1/places?id=eq.' + pid, { name: '해킹' }, token, 'PATCH', rep);
        row('익명 로그인', '거부: 승인된 세차장 수정', '0건 수정', { status: r.status, code: r.code, msg: Array.isArray(r.data) ? r.data.length + '건' : '' }, Array.isArray(r.data) && r.data.length === 0); }
    }
  }
  console.table(out);
  return out;
})(false);
