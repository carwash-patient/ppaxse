// 이벤트 공통: 하단 메뉴 '이벤트'의 빨간 점 + 당첨자에게 한 번 뜨는 축하 창
// ppx.js 다음에 불러옴. 화면마다 따로 고칠 것 없이 이 파일만 넣으면 됨.
(function () {
  const P = window.PPX;
  if(!P || !P.ready || !P.db) return;
  const LS = k => { try { return localStorage.getItem(k); } catch(_) { return null; } };
  const SS = (k, v) => { try { localStorage.setItem(k, v); } catch(_) {} };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const today = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);   // 한국 날짜
  const addDays = (d, n) => { const t = new Date(d + 'T00:00:00Z'); t.setUTCDate(t.getUTCDate() + n); return t.toISOString().slice(0, 10); };
  const md = d => { const [, m, dd] = String(d).split('-'); return `${+m}/${+dd}`; };
  const wk = d => '일월화수목금토'[new Date(d + 'T00:00:00Z').getUTCDay()];
  const isEventsPage = /\/events(\.html)?$/.test(location.pathname);
  const isAdmin = /\/admin(\.html)?$/.test(location.pathname);
  window.PPXEV = { today, addDays, md, wk, esc };

  // ── 빨간 점: 새 이벤트 글이나 새 추첨 발표가 내가 마지막으로 본 뒤에 생겼으면 ──
  async function dot() {
    const el = document.querySelector('.nav-item[data-ev]');
    if(!el) return;
    if(isEventsPage) { SS('ppxEvSeen', new Date().toISOString()); return; }
    let latest = '';
    try {
      const { data } = await P.db.from('events').select('created_at').eq('hidden', false).order('created_at', { ascending: false }).limit(1);
      if(data && data[0]) latest = data[0].created_at;
    } catch(_) {}
    try {
      const { data } = await P.db.rpc('ppx_event_rounds');
      if(data && data[0]) { const t = data[0].draw_date + 'T08:00:00.000Z'; if(t > latest) latest = t; }   // 발표 17시(한국)
    } catch(_) {}
    const seen = LS('ppxEvSeen');
    if(latest && (!seen || latest > seen)) el.classList.add('has-dot');
  }

  // ── 당첨 축하 창: 발표 뒤 연락 기한(발표+7일) 안에, 기기마다 회차별로 한 번 ──
  async function winPopup() {
    if(isAdmin) return;
    let st; try { st = await P.eventStatus(); } catch(_) { return; }
    const t = today();
    const m = (st && st.mine || []).find(x => x.won && t >= addDays(x.week, 9) && t <= addDays(x.week, 16) && !LS('ppxWinSeen_' + x.week));
    if(!m) return;
    const until = addDays(m.week, 16);
    const subj = encodeURIComponent(`[빡세 당첨] 응모번호 ${m.code}`);
    const body = encodeURIComponent(`응모번호: ${m.code}\n한마디를 남긴 세차장 이름: \n`);
    const css = document.createElement('style');
    css.textContent = `.pw-ov{position:fixed;inset:0;z-index:2000;background:rgba(0,0,0,.6);display:flex;align-items:center;justify-content:center;padding:22px}
.pw-box{width:100%;max-width:360px;background:#0d1e35;background-image:linear-gradient(135deg,rgba(245,183,43,.22),rgba(14,165,233,.08));border:1px solid rgba(245,183,43,.6);border-radius:24px;padding:24px 20px 18px;text-align:center;color:#fff;font-family:inherit}
.pw-code{font-size:28px;font-weight:900;letter-spacing:2px;color:#fbbf24;margin:6px 0;user-select:all}
.pw-b{display:flex;gap:8px;margin-top:14px}.pw-b a,.pw-b button{flex:1;min-height:48px;border:none;border-radius:14px;font:inherit;font-weight:900;font-size:14px;cursor:pointer;text-decoration:none;display:flex;align-items:center;justify-content:center}
.pw-copy{background:rgba(255,255,255,.1);color:#fff}.pw-mail{background:linear-gradient(135deg,#fbbf24,#f59e0b);color:#04111e}
.pw-x{margin-top:12px;background:none;border:none;color:#94a3b8;font:inherit;font-size:13px;min-height:40px;cursor:pointer}`;
    document.head.appendChild(css);
    const ov = document.createElement('div');
    ov.className = 'pw-ov';
    ov.innerHTML = `<div class="pw-box" role="dialog" aria-label="당첨 안내">
      <div style="font-size:46px;line-height:1">🎉</div>
      <div style="font-size:21px;font-weight:900;margin-top:8px">기프티콘에 당첨됐어요!</div>
      <div style="font-size:13px;color:#bae6fd;margin-top:4px">${md(m.week)}~${md(addDays(m.week, 6))} 회차 · ${m.won === 'member' ? '회원 추첨' : '누구나 추첨'}</div>
      <div style="font-size:12px;color:#94a3b8;margin-top:14px">내 전체 응모번호 (나만 볼 수 있어요)</div>
      <div class="pw-code">${esc(m.code)}</div>
      <div style="font-size:13px;line-height:1.7;color:#e2e8f0"><b>${md(until)}(${wk(until)})까지</b> 이 번호와 한마디를 남긴 세차장 이름을<br><b>ppaxse@gmail.com</b>으로 보내 주세요</div>
      <div class="pw-b"><button class="pw-copy" type="button">📋 번호 복사</button><a class="pw-mail" href="mailto:ppaxse@gmail.com?subject=${subj}&body=${body}">✉️ 메일 보내기</a></div>
      <button class="pw-x" type="button">닫기 · [내 정보]에서 다시 볼 수 있어요</button></div>`;
    const close = () => { SS('ppxWinSeen_' + m.week, '1'); ov.remove(); };
    ov.querySelector('.pw-x').onclick = close;
    ov.addEventListener('click', e => { if(e.target === ov) close(); });
    ov.querySelector('.pw-copy').onclick = async e => {
      try { await navigator.clipboard.writeText(m.code); e.target.textContent = '✅ 복사했어요'; } catch(_) { e.target.textContent = m.code; }
    };
    ov.querySelector('.pw-mail').addEventListener('click', () => SS('ppxWinSeen_' + m.week, '1'));
    document.body.appendChild(ov);
  }

  const run = () => { dot(); setTimeout(winPopup, 1200); };
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
})();
