// ── 앱 테스터 피드백 버튼 ('💬 피드백') ── 모든 화면에서 이 파일 하나로 동작
// 사용법: 페이지 맨 아래에 <script src="js/feedback.js?v=..." defer></script> (지역·가이드 페이지는 tools/build_seo.py 가 넣음)
// - 앱으로 열었을 때만 화면 오른쪽 아래에 보임: Play 앱(com.ppaxse.app) 또는 바탕화면에 추가한 빡세(주소창 없는 화면).
//   브라우저로 ppaxse.com을 보는 일반 방문자에게는 안 보임.
// - Play 앱은 처음 열 때만 '앱에서 열림' 표시(referrer)가 옴 → 한 번 본 기기는 기억(twa).
//   (Play 앱과 휴대폰 크롬은 저장 공간을 같이 써서, 앱을 연 적 있는 휴대폰은 크롬으로 볼 때도 버튼이 보일 수 있음 — 테스트 기간이라 괜찮음)
// - 운영자 미리보기: 주소 끝에 ?fb=1 (끄기 ?fb=0). 운영자 화면(admin)에서는 안 보임.
// - 보내면 ppx_feedback(글, 지금 화면 주소, 휴대폰 기종 요약)으로 저장 → 운영자 화면 '💬 앱 피드백'
// - js/ppx.js 가 없는 화면(가이드·지역 페이지 등)은 '보내기'를 누를 때만 config.js·supabase·ppx.js 를 불러옴
//   (이때 ppx.js 의 방문자 세기는 끔: PPX_NO_TRACK). ppx.js 버전을 올리면 아래 PPX_SRC 도 같이 올릴 것
(function () {
  const PPX_SRC = 'ppx.js?v=20261126d';
  const CFG_SRC = 'config.js?v=20261117';
  const SUPA_SRC = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.119.0/dist/umd/supabase.js';
  const me = document.currentScript;
  const base = me && me.src ? me.src.replace(/[^/]*(\?.*)?$/, '') : '/js/';
  try {
    const APP_KEY = 'ppxApp';
    const q = new URLSearchParams(location.search);
    if (/^android-app:\/\//.test(document.referrer || '')) { localStorage.setItem(APP_KEY, 'twa'); sessionStorage.setItem(APP_KEY, '1'); }
    if (q.get('fb') === '1') localStorage.setItem(APP_KEY, 'preview');
    if (q.get('fb') === '0') localStorage.setItem(APP_KEY, 'off');
    const flag = localStorage.getItem(APP_KEY);
    const standalone = matchMedia('(display-mode: standalone)').matches || matchMedia('(display-mode: fullscreen)').matches || navigator.standalone === true;
    const inApp = flag !== 'off' && (flag === 'preview' || flag === 'twa' || sessionStorage.getItem(APP_KEY) === '1' || standalone);
    if (!inApp || /admin/.test(location.pathname) || document.querySelector('.fb-btn')) return;

    // ppx.js 가 없으면 불러오기 (보내기 누를 때 한 번만)
    const loadJs = src => new Promise((ok, no) => {
      const s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = () => no(new Error('load ' + src));
      document.head.appendChild(s);
    });
    let loading = null;
    const getPPX = () => {
      if (window.PPX && window.PPX.db) return Promise.resolve(window.PPX);
      if (!loading) loading = (async () => {
        window.PPX_NO_TRACK = true;
        if (!window.PPX_CONFIG) await loadJs(base + CFG_SRC);
        if (!window.supabase || !window.supabase.createClient) await loadJs(SUPA_SRC);
        if (!window.PPX) await loadJs(base + PPX_SRC);
        if (!window.PPX || !window.PPX.db) throw new Error('not ready');
        return window.PPX;
      })().catch(e => { loading = null; throw e; });
      return loading;
    };
    const say = async (msg) => {
      try { const P = await getPPX(); return P.ask(msg, { cancel: false }); } catch (e) { alert(msg); }
    };

    const deviceInfo = async () => {
      const ua = navigator.userAgent;
      let os = '', model = '';
      const a = ua.match(/Android ([\d.]+)(?:; ([^;)]+))?/);
      if (a) { os = 'Android ' + a[1]; model = a[2] && a[2] !== 'K' ? a[2].trim() : ''; }
      else if (/iPhone|iPad/.test(ua)) { const i = ua.match(/OS (\d+)[_\d]*/); os = (/iPad/.test(ua) ? 'iPad' : 'iPhone') + (i ? ' iOS ' + i[1] : ''); }
      else os = /Windows/.test(ua) ? 'PC(Windows)' : /Mac/.test(ua) ? 'PC(Mac)' : 'PC';
      try {
        if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
          const h = await navigator.userAgentData.getHighEntropyValues(['model', 'platformVersion']);
          if (h.model) model = h.model;
          if (h.platformVersion && /^Android/.test(os)) os = 'Android ' + String(h.platformVersion).split('.')[0];
        }
      } catch (e) {}
      return [os, model, screen.width + '×' + screen.height].filter(Boolean).join(' · ').slice(0, 120);
    };

    const css = document.createElement('style');
    css.textContent = `
.fb-btn{position:fixed;right:12px;bottom:calc(14px + env(safe-area-inset-bottom));z-index:9000;display:flex;align-items:center;gap:5px;
  border:1px solid rgba(150,170,60,.55);border-radius:999px;padding:8px 13px;font-family:'Noto Sans KR',sans-serif;font-size:13px;font-weight:800;color:#F2F1EC;
  background:#262B33;box-shadow:0 6px 18px rgba(38,43,51,.203);cursor:pointer;-webkit-tap-highlight-color:transparent;line-height:1.2}
.fb-ov{position:fixed;inset:0;z-index:9998;background:rgba(0,0,0,.55)}
.fb-sheet{position:fixed;left:0;right:0;bottom:0;z-index:9999;max-width:520px;margin:0 auto;background:#FFFFFF;color:#262B33;text-align:left;
  border-radius:24px 24px 0 0;border-top:1px solid rgba(150,170,60,.3);padding:20px 20px calc(22px + env(safe-area-inset-bottom));
  font-family:'Noto Sans KR',sans-serif;box-sizing:border-box}
.fb-sheet b.t{display:block;font-size:17px;font-weight:900}
.fb-sheet p{margin:6px 0 12px;color:#6B7078;font-size:13px;line-height:1.55}
.fb-sheet textarea{width:100%;box-sizing:border-box;min-height:120px;padding:12px;border-radius:14px;border:1px solid rgba(38,43,51,.16);
  background:#FFFFFF;color:#262B33;font:inherit;font-size:16px;line-height:1.5;resize:vertical}
.fb-sheet .n{text-align:right;color:#6B7078;font-size:12px;margin-top:4px}
.fb-sheet .row{display:flex;gap:8px;margin-top:12px}
.fb-sheet .row button{flex:1;min-height:46px;border-radius:12px;font:inherit;font-size:15px;font-weight:800;cursor:pointer}
.fb-sheet .no{border:1px solid rgba(38,43,51,.16);background:transparent;color:rgba(38,43,51,.8)}
.fb-sheet .go{border:none;color:#F2F1EC;background:#262B33}
.fb-sheet .go:disabled{opacity:.45}`;
    document.head.appendChild(css);

    const btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'fb-btn'; btn.setAttribute('aria-label', '피드백 보내기');
    btn.textContent = '💬 피드백';
    btn.onclick = () => {
      getPPX().catch(() => {});   // 입력하는 동안 미리 불러 둠
      const ov = document.createElement('div'); ov.className = 'fb-ov';
      const sh = document.createElement('div'); sh.className = 'fb-sheet';
      sh.setAttribute('role', 'dialog'); sh.setAttribute('aria-modal', 'true');
      sh.innerHTML = `<b class="t">💬 피드백 보내기</b>
<p>테스트 중인 앱이에요. 어느 화면에서 무엇이 불편했는지, 있었으면 하는 기능을 편하게 적어 주세요. 운영자만 봐요.</p>
<textarea maxlength="1000" placeholder="예) 지도에서 내 위치 버튼을 눌러도 반응이 없어요"></textarea>
<div class="n">0 / 1000</div>
<p style="margin:8px 0 0;font-size:12px">지금 보고 있던 화면 주소와 휴대폰 기종이 함께 전달돼요. 이름·연락처는 적지 않아도 돼요.</p>
<div class="row"><button type="button" class="no">닫기</button><button type="button" class="go" disabled>보내기</button></div>`;
      document.body.appendChild(ov); document.body.appendChild(sh);
      const ta = sh.querySelector('textarea'), go = sh.querySelector('.go'), n = sh.querySelector('.n');
      const close = () => { ov.remove(); sh.remove(); btn.focus(); };
      ta.oninput = () => { n.textContent = ta.value.length + ' / 1000'; go.disabled = ta.value.trim().length < 2; };
      ov.onclick = close; sh.querySelector('.no').onclick = close;
      go.onclick = async () => {
        go.disabled = true; go.textContent = '보내는 중…';
        try {
          const P = await getPPX();
          await P.ensureUser();
          const { error } = await P.db.rpc('ppx_feedback', {
            msg: ta.value.trim(),
            pg: (() => { const u = location.pathname + location.search; try { return decodeURI(u); } catch (x) { return u; } })().replace(/[?&]fb=[01]/, '').slice(0, 200),
            dev: await deviceInfo() });
          if (error) throw error;
          close();
          await say('고마워요! 잘 받았어요 🙌\n보내 주신 내용은 운영자가 확인하고 고쳐 나갈게요.');
        } catch (e) {
          go.disabled = false; go.textContent = '보내기';
          let m = '보내지 못했어요. 인터넷 연결을 확인하고 다시 눌러 주세요.';
          try { if (window.PPX && window.PPX.koError && !/^load |not ready/.test(e && e.message || '')) m = window.PPX.koError(e); } catch (x) {}
          await say(m);
        }
      };
      setTimeout(() => ta.focus(), 50);
    };

    // 화면 아래에 고정된 메뉴 막대가 있으면 그 위로 올림 (지도·홈의 아래 메뉴를 가리지 않게)
    const lift = () => {
      let bar = 0;
      btn.style.visibility = 'hidden';
      for (const x of [window.innerWidth - 40, window.innerWidth / 2]) {
        for (const el of document.elementsFromPoint(x, window.innerHeight - 6)) {
          if (el === btn || el === document.body || el === document.documentElement) continue;
          for (let p = el; p && p !== document.body; p = p.parentElement) {
            const cs = getComputedStyle(p);
            if (cs.position === 'fixed' || cs.position === 'sticky') {
              const r = p.getBoundingClientRect();
              if (r.height < window.innerHeight / 3) bar = Math.max(bar, window.innerHeight - r.top);
              break;
            }
          }
        }
      }
      btn.style.visibility = '';
      btn.style.bottom = bar ? (bar + 10) + 'px' : '';
    };
    const put = () => { document.body.appendChild(btn); lift(); setTimeout(lift, 800); window.addEventListener('resize', lift); };
    if (document.body) put(); else document.addEventListener('DOMContentLoaded', put);
  } catch (e) { /* 저장소를 못 쓰는 환경이면 버튼 없이 */ }
})();
