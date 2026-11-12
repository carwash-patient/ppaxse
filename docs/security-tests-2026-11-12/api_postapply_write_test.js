// 빡세 보안 수정 — 적용 '후' 실제 경로 쓰기 테스트 (운영자 승인 후에만 실행)
// 무엇을: 익명 로그인 계정으로 '조작한 제보'를 보내, 트리거 3개 중 2개(세차장 제보·정보 제보)가 값을 고정하는지 확인합니다.
//         (다녀왔어요 트리거는 실제 세차장의 확인 횟수를 올리므로 여기서 하지 않고 화면 체크리스트로 확인)
// 남는 데이터 (모두 '[보안점검 ' 로 시작하는 꼬리표가 붙음):
//   · 익명 테스트 계정 1개 (다시 실행하면 같은 계정을 재사용)
//   · 대기 중 세차장 제보 1건  — 이름: [보안점검 날짜-시각] 삭제해 주세요, 지역: 테스트
//   · 대기 중 정보 제보 1건    — 메모: [보안점검 날짜-시각] 무시해 주세요
//   정리: supabase/cleanup_sectest_2026-11-12.sql (운영자가 Run) 또는 운영자 화면에서 거절·무시
// 안전장치:
//   · CONFIRM 이 정확히 '적용 완료' 가 아니면 아무 요청도 보내지 않음
//   · 적용이 안 된 상태(비로그인 ppx_guard 가 실행됨)면 중단
//   · 테스트 계정이 운영자이면 중단 (운영자는 값 고정 대상이 아니라 승인 상태로 들어가 버림)
//   · 이전 실행의 테스트 데이터가 남아 있으면 새로 만들지 않고 알려 줌 (중복 방지)
//   · 단계마다 결과와 '만들어진 데이터'를 기록. 중간에 멈춰도 그때까지의 기록을 돌려줌
(async (CONFIRM) => {
  const URL = 'https://zylyncnevdxpimyqrifp.supabase.co';
  const KEY = 'sb_publishable_i5ZeUzflI5otoD9GqwQpew_2x3y_RPA';
  const STORE = 'ppxSecTest20261112';
  const TAG = '[보안점검 ';
  const d = new Date(), p2 = n => String(n).padStart(2, '0');
  const RUN = TAG + d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) + '-' + p2(d.getHours()) + p2(d.getMinutes()) + ']';
  const fake = '00000000-0000-4000-8000-000000000001';
  const log = [], created = [];
  const step = (name, expect, got, pass, note) => log.push({ 단계: log.length + 1, 시험: name, 기대: expect, 결과: got, 판정: pass ? 'PASS' : 'FAIL', 비고: note || '' });
  const finish = why => { const r = { 실행표: RUN, 중단사유: why || '', 기록: log, 만들어진_데이터: created,
      정리: created.length ? 'supabase/cleanup_sectest_2026-11-12.sql 을 운영자가 Run (또는 운영자 화면에서 거절·무시)' : '정리할 것 없음' };
    console.table(log); console.log(r); return r; };
  const req = async (method, path, body, token, extra = {}) => {
    const r = await fetch(URL + path, { method, headers: { apikey: KEY, Authorization: 'Bearer ' + (token || KEY), 'Content-Type': 'application/json', ...extra },
      body: body === undefined ? undefined : JSON.stringify(body) });
    let j = null; try { j = await r.json(); } catch (e) {}
    return { status: r.status, code: j && j.code, msg: j && (j.message || j.msg), data: j, text: r.status + (j && j.code ? ' ' + j.code : '') };
  };
  if (CONFIRM !== '적용 완료') return finish("CONFIRM 값이 '적용 완료'가 아니라서 아무 요청도 보내지 않았습니다");
  try {
    // 0) 적용 여부 (읽기 전용 GET)
    const g = await req('GET', '/rest/v1/rpc/ppx_guard?what=place');
    step('적용 여부: 비로그인 ppx_guard', '42501', g.text, g.code === '42501');
    if (g.code !== '42501') return finish('보안 수정이 아직 적용되지 않은 것으로 보여 중단');

    // 1) 테스트 계정 (있으면 재사용)
    let token = null, me = null, reused = false;
    try {
      const saved = JSON.parse(localStorage.getItem(STORE) || 'null');
      if (saved && saved.refresh_token) {
        const r = await req('POST', '/auth/v1/token?grant_type=refresh_token', { refresh_token: saved.refresh_token });
        if (r.data && r.data.access_token) { token = r.data.access_token; me = r.data.user.id; reused = true;
          localStorage.setItem(STORE, JSON.stringify({ refresh_token: r.data.refresh_token, id: me })); }
      }
    } catch (e) {}
    if (!token) {
      const s = await req('POST', '/auth/v1/signup', { data: { ref: 'sectest' } });
      if (!s.data || !s.data.access_token) { step('익명 로그인', '200', s.text + ' ' + (s.msg || ''), false); return finish('익명 로그인 실패'); }
      token = s.data.access_token; me = s.data.user.id;
      try { localStorage.setItem(STORE, JSON.stringify({ refresh_token: s.data.refresh_token, id: me })); } catch (e) {}
      created.push({ 종류: '익명 테스트 계정', id: me });
    }
    const claims = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    step('테스트 계정 JWT', 'role=authenticated, is_anonymous=true', 'role=' + claims.role + ', is_anonymous=' + claims.is_anonymous,
         claims.role === 'authenticated' && claims.is_anonymous === true, (reused ? '기존 테스트 계정 재사용 ' : '새 계정 ') + me);
    const adm = await req('GET', '/rest/v1/rpc/is_admin', undefined, token);
    step('테스트 계정은 운영자가 아님', 'false', String(adm.data), adm.data === false);
    if (adm.data !== false) return finish('테스트 계정이 운영자로 판정되어 중단');

    // 2) 닫혀야 하는 함수 (읽기 전용 GET)
    for (const q of ['ppx_guard?what=place', 'my_pending_count', 'my_pending_reports', 'ppx_event_week']) {
      const r = await req('GET', '/rest/v1/rpc/' + q, undefined, token);
      step('거부: ' + q.split('?')[0] + ' 직접 실행', '42501', r.text, r.code === '42501');
    }
    { const r = await req('GET', '/rest/v1/rpc/admin_visit_stats?days=1', undefined, token);
      step('거부: 운영자 통계', 'P0001 운영자만', r.text, r.code === 'P0001'); }

    // 3) 이전 실행 데이터 확인 (중복 방지)
    const rep = { Prefer: 'return=representation' };
    const oldP = await req('GET', '/rest/v1/places?select=id,name,status&submitted_by=eq.' + me + '&name=like.' + encodeURIComponent(TAG + '*'), undefined, token);
    const oldR = await req('GET', '/rest/v1/place_reports?select=id,memo,status&reporter=eq.' + me + '&memo=like.' + encodeURIComponent(TAG + '*'), undefined, token);
    const hasP = Array.isArray(oldP.data) && oldP.data.length > 0, hasR = Array.isArray(oldR.data) && oldR.data.length > 0;

    // 4) 조작한 세차장 제보
    if (hasP) step('세차장 제보', '(건너뜀)', '이전 테스트 제보가 남아 있음: id ' + oldP.data.map(x => x.id).join(','), true, '정리 후 다시 실행하면 이 단계를 수행');
    else {
      const body = { name: RUN + ' 삭제해 주세요', type: 'self', region: '테스트', lat: 37.3857, lng: 126.6444,
                     status: 'approved', source: 'public_data', submitted_by: fake, check_count: 99 };   // 일부러 조작
      const r = await req('POST', '/rest/v1/places', body, token, rep); const x = (Array.isArray(r.data) ? r.data[0] : null) || {};
      if (x.id) created.push({ 종류: '세차장 제보(places)', id: x.id, 상태: x.status });
      step('조작한 세차장 제보 → 대기·본인으로 고정', '201 / pending / user / 본인 / 0',
           r.text + ' / ' + [x.status, x.source, x.submitted_by === me ? '본인' : x.submitted_by, x.check_count].join(' / '),
           r.status === 201 && x.status === 'pending' && x.source === 'user' && x.submitted_by === me && x.check_count === 0,
           x.status && x.status !== 'pending' ? '★ 대기가 아닌 상태로 저장됨 — 즉시 정리하고 롤백 검토' : '');
      const r2 = await req('POST', '/rest/v1/places', body, token, rep); const y = (Array.isArray(r2.data) ? r2.data[0] : null) || {};
      if (y.id) created.push({ 종류: '세차장 제보(places) — 제한이 안 걸려 생김', id: y.id, 상태: y.status });
      step('제한: 30초 안에 두 번째 세차장 제보', 'P0001 거절', r2.text + ' ' + (r2.msg || ''), r2.code === 'P0001');
    }

    // 5) 조작한 정보 제보 (승인된 세차장 1곳에 대기 제보가 1건 생김)
    if (hasR) step('정보 제보', '(건너뜀)', '이전 테스트 제보가 남아 있음: id ' + oldR.data.map(x => x.id).join(','), true, '정리 후 다시 실행하면 이 단계를 수행');
    else {
      const ap = await req('GET', '/rest/v1/places?select=id,name&status=eq.approved&order=id.desc&limit=1', undefined, token);
      const tgt = Array.isArray(ap.data) && ap.data[0];
      if (!tgt) step('정보 제보 대상 찾기', '승인된 세차장 1건', ap.text, false);
      else {
        const body = { place_id: tgt.id, memo: RUN + ' 무시해 주세요', status: 'applied', reporter: fake };   // 일부러 조작
        const r = await req('POST', '/rest/v1/place_reports', body, token, rep); const x = (Array.isArray(r.data) ? r.data[0] : null) || {};
        if (x.id) created.push({ 종류: '정보 제보(place_reports)', id: x.id, 상태: x.status, 대상_세차장: tgt.id + ' ' + tgt.name });
        step('조작한 정보 제보 → 대기·본인으로 고정', '201 / pending / 본인', r.text + ' / ' + [x.status, x.reporter === me ? '본인' : x.reporter].join(' / '),
             r.status === 201 && x.status === 'pending' && x.reporter === me,
             x.status && x.status !== 'pending' ? '★ 대기가 아닌 상태로 저장됨 — 즉시 정리하고 롤백 검토' : '');
        const r2 = await req('POST', '/rest/v1/place_reports', body, token, rep); const y = (Array.isArray(r2.data) ? r2.data[0] : null) || {};
        if (y.id) created.push({ 종류: '정보 제보(place_reports) — 제한이 안 걸려 생김', id: y.id, 상태: y.status });
        step('제한: 15초 안에 두 번째 정보 제보', 'P0001 거절', r2.text + ' ' + (r2.msg || ''), r2.code === 'P0001');
      }
    }

    // 6) 바뀌면 안 되는 것 (성공하면 안 되는 쓰기 시도)
    { const r = await req('PATCH', '/rest/v1/profiles?id=eq.' + me, { role: 'admin' }, token, rep);
      step('거부: 내 역할을 admin으로', '42501', r.text, r.code === '42501'); }
    { const ap = await req('GET', '/rest/v1/places?select=id,name&status=eq.approved&order=id.desc&limit=1', undefined, token);
      const tgt = Array.isArray(ap.data) && ap.data[0];
      if (tgt) { const r = await req('PATCH', '/rest/v1/places?id=eq.' + tgt.id, { updated_at: new Date().toISOString() }, token, rep);
        const n = Array.isArray(r.data) ? r.data.length : -1;
        step('거부: 승인된 세차장 수정', '0건', r.text + ' / ' + n + '건', n === 0, n > 0 ? '★ 수정됨(시각만 바뀜) — 롤백 검토' : ''); } }
    return finish('');
  } catch (e) {
    step('예상하지 못한 오류', '-', String(e && e.message || e), false);
    return finish('오류로 중단 — 위 기록과 만들어진_데이터를 확인');
  }
})('아직');   // ← 적용 후 실행할 때만 '적용 완료' 로 바꿉니다
