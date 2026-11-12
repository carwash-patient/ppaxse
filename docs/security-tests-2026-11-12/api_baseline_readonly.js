// 빡세 보안 수정 — 실제 요청 경로 기준선 (읽기 전용)
// · GET 요청만 보냅니다. PostgREST는 GET 요청을 '읽기 전용 트랜잭션'으로 실행하므로 DB가 쓰기를 막습니다.
// · 본문에 INSERT/UPDATE/DELETE·잠금이 있는 함수(start_claim, finish_claim, ppx_burst_guard, ppx_track 등)와
//   테이블 쓰기(POST/PATCH/DELETE)는 넣지 않았습니다.
// · 공개 키만 씁니다. 적용 '전'과 '후'에 똑같이 실행해 비교합니다.
// 어디서: 브라우저 개발자 도구 콘솔(어느 사이트든 가능) 또는 Claude가 브라우저에서 실행
(async () => {
  const URL = 'https://zylyncnevdxpimyqrifp.supabase.co';
  const KEY = 'sb_publishable_i5ZeUzflI5otoD9GqwQpew_2x3y_RPA';   // 공개돼도 되는 키 (js/config.js 와 같음)
  const uuid = '00000000-0000-4000-8000-000000000001';
  const get = async path => {
    try {
      const r = await fetch(URL + path, { method: 'GET', headers: { apikey: KEY, Authorization: 'Bearer ' + KEY } });
      let j = null; try { j = await r.json(); } catch (e) {}
      return { status: r.status, code: j && j.code, text: r.status + (j && j.code ? ' ' + j.code : '') + (Array.isArray(j) ? ' rows=' + j.length : '') };
    } catch (e) { return { status: 0, text: '요청 실패: ' + e.message }; }
  };
  // [이름, 주소, 적용 후 기대, 적용 후 판정 함수]
  const ok200 = r => r.status === 200, denied = r => r.code === '42501';
  const list = [
    ['ppx_stats (홈 숫자)',            '/rest/v1/rpc/ppx_stats', '200', ok200],
    ['ppx_event_status (이벤트 현황)', '/rest/v1/rpc/ppx_event_status', '200', ok200],
    ['is_admin',                       '/rest/v1/rpc/is_admin', '200', ok200],
    ['지도 데이터 조회',               '/rest/v1/places?select=id&status=eq.approved&limit=1', '200 rows=1', ok200],
    ['ppx_guard',                      '/rest/v1/rpc/ppx_guard?what=place', '42501', denied],
    ['my_pending_count',               '/rest/v1/rpc/my_pending_count', '42501', denied],
    ['my_pending_reports',             '/rest/v1/rpc/my_pending_reports', '42501', denied],
    ['ppx_event_week',                 '/rest/v1/rpc/ppx_event_week', '42501', denied],
    ['ppx_event_start',                '/rest/v1/rpc/ppx_event_start', '42501', denied],
    ['ppx_event_draw_at',              '/rest/v1/rpc/ppx_event_draw_at?w=2026-11-14', '42501', denied],
    ['ppx_is_member',                  '/rest/v1/rpc/ppx_is_member?u=' + uuid, '42501', denied],
    ['admin_visit_stats',              '/rest/v1/rpc/admin_visit_stats?days=1', '42501', denied],
    ['admin_type_votes',               '/rest/v1/rpc/admin_type_votes', '42501', denied],
    ['admin_event_entries',            '/rest/v1/rpc/admin_event_entries?p_from=2026-11-01T00:00:00Z&p_to=2026-11-02T00:00:00Z', '42501', denied],
  ];
  const out = [];
  for (const [name, path, expect, judge] of list) {
    const r = await get(path);
    out.push({ 시험: '비로그인 ' + name, 결과: r.text, '적용 후 기대': expect, '적용 후 기준': judge(r) ? '일치' : '다름' });
  }
  console.table(out);
  return out;
})();
