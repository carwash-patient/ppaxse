// '바탕화면에 추가(앱처럼 설치)' 카드
// 사용법: <div id="ppxInstall" hidden data-key="main" data-icon="icons/icon-192.png"
//              data-title="바탕화면에 빡세 추가" data-sub="아이콘 한 번에 세차장 지도"></div>
// - 갤럭시·안드로이드·PC 크롬: 휴대폰/브라우저의 설치 창을 바로 띄움
// - 아이폰: 설치 창을 띄울 수 없어서 '공유 → 홈 화면에 추가' 안내를 보여줌
// - 이미 설치해서 앱으로 연 경우, ✕로 닫은 경우에는 안 보임
(function () {
  if('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});

  const box = document.getElementById('ppxInstall');
  if(!box) return;
  const d = box.dataset, KEY = 'ppxInst_' + (d.key || 'main');
  const ua = navigator.userAgent;
  const isIOS = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const isMobile = isIOS || /Android/.test(ua);
  // 삼성 인터넷은 '앱 설치' 때 옛 안드로이드 기준 설치 파일을 만들어 Play 프로텍트 경고가 뜸 → 설치 창 대신 '홈 화면에 추가' 안내만
  const isSamsung = /SamsungBrowser/.test(ua);
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  let stored = null; try { stored = localStorage.getItem(KEY); } catch(_) {}
  if(standalone || stored) return;

  const css = document.createElement('style');
  css.textContent = `
.pi-card{position:relative;display:flex;align-items:center;gap:12px;padding:14px;border-radius:18px;text-align:left;
  background:linear-gradient(135deg,rgba(14,165,233,.16),rgba(34,211,238,.06));border:1px solid rgba(34,211,238,.35)}
.pi-card img{width:46px;height:46px;border-radius:12px;flex:none}
.pi-t{flex:1;min-width:0}.pi-t b{display:block;color:#fff;font-size:15px;font-weight:900}
.pi-t span{display:block;color:#94a3b8;font-size:12px;margin-top:2px}
.pi-go{flex:none;border:none;border-radius:999px;padding:10px 14px;font:inherit;font-weight:900;font-size:14px;color:#04111e;
  background:linear-gradient(135deg,#38bdf8,#22d3ee);cursor:pointer}
.pi-x{position:absolute;top:2px;right:4px;width:28px;height:28px;border:none;background:none;color:#64748b;font-size:14px;cursor:pointer}
.pi-ov{position:fixed;inset:0;z-index:9998;background:rgba(0,0,0,.55)}
.pi-sheet{position:fixed;left:0;right:0;bottom:0;z-index:9999;background:#0d1e35;border-radius:24px 24px 0 0;
  border-top:1px solid rgba(34,211,238,.3);padding:20px 22px calc(28px + env(safe-area-inset-bottom));color:#fff;text-align:left;
  max-width:520px;margin:0 auto;animation:piUp .25s ease}
@keyframes piUp{from{transform:translateY(100%)}to{transform:none}}
.pi-sheet .h{display:flex;gap:12px;align-items:center;margin-bottom:16px}
.pi-sheet .h img{width:48px;height:48px;border-radius:12px}
.pi-sheet .h b{display:block;font-size:17px;font-weight:900}.pi-sheet .h span{color:#94a3b8;font-size:12px}
.pi-step{background:rgba(255,255,255,.05);border-radius:14px;padding:13px;margin-bottom:10px;font-size:15px;line-height:1.5}
.pi-step em{font-style:normal;font-weight:900;color:#22d3ee}
.pi-share{display:inline-block;border:2px solid #22d3ee;border-radius:5px;padding:0 5px;font-size:12px;line-height:1.3}
.pi-ok{display:block;width:100%;margin-top:6px;min-height:48px;border:none;border-radius:14px;font:inherit;font-weight:900;font-size:15px;
  color:#fff;background:rgba(255,255,255,.08);cursor:pointer}`;
  document.head.appendChild(css);

  let deferred = null;
  const esc = s => String(s || '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  box.innerHTML = `<div class="pi-card"><img src="${esc(d.icon)}" alt=""><div class="pi-t"><b>${esc(d.title)}</b><span>${esc(d.sub)}</span></div>
    <button class="pi-go" type="button">📲 추가</button><button class="pi-x" type="button" aria-label="닫기">✕</button></div>`;

  function show() { if(box.hidden) { box.hidden = false; document.body.classList.add('pi-on'); } }
  function hide(save) {
    box.hidden = true; document.body.classList.remove('pi-on');
    if(save) try { localStorage.setItem(KEY, save); } catch(_) {}
  }

  function guide() {
    const steps = isIOS
      ? ['① 화면 아래(또는 위) <em>공유 버튼 <span class="pi-share">↑</span></em> 누르기',
         '② 아래로 내려서 <em>\'홈 화면에 추가\'</em> 누르기',
         '③ 오른쪽 위 <em>\'추가\'</em> 누르면 끝!']
      : isSamsung
      ? ['① 화면 아래 <em>메뉴(≡)</em> 누르기',
         '② <em>\'현재 페이지 추가\'</em> 누르기',
         '③ <em>\'홈 화면\'</em> 고르고 <em>\'추가\'</em> 누르면 끝!']
      : isMobile
      ? ['① 브라우저 <em>메뉴(⋮ 또는 ≡)</em> 누르기',
         '② <em>\'홈 화면에 추가\'</em> 또는 <em>\'현재 페이지 추가 → 홈 화면\'</em> 누르기',
         '③ <em>\'추가\'</em> 누르면 끝!']
      : ['① 주소창 오른쪽 <em>설치 아이콘(⊕)</em>을 누르거나',
         '② 즐겨찾기로 두려면 <em>Ctrl + D</em> (맥은 ⌘ + D)'];
    const ov = document.createElement('div'); ov.className = 'pi-ov';
    const sh = document.createElement('div'); sh.className = 'pi-sheet';
    sh.innerHTML = `<div class="h"><img src="${esc(d.icon)}" alt=""><div><b>${isIOS ? '아이폰은 이렇게 추가해요' : '이렇게 추가해요'}</b><span>10초면 끝나요</span></div></div>`
      + steps.map(s => `<div class="pi-step">${s}</div>`).join('') + `<button class="pi-ok" type="button">확인</button>`;
    const close = () => { ov.remove(); sh.remove(); };
    ov.onclick = close; sh.querySelector('.pi-ok').onclick = close;
    document.body.append(ov, sh);
  }

  box.querySelector('.pi-x').onclick = () => hide('closed');
  box.querySelector('.pi-go').onclick = async () => {
    if(!deferred) return guide();
    deferred.prompt();
    try { const r = await deferred.userChoice; if(r && r.outcome === 'accepted') hide('installed'); } catch(_) {}
    deferred = null;
  };

  window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); if(isSamsung) return; deferred = e; show(); });
  window.addEventListener('appinstalled', () => hide('installed'));
  // 아이폰은 바로 보여줌. 안드로이드는 설치 창 준비 신호를 잠깐 기다렸다가, 안 오면 안내 방식으로 보여줌. PC는 설치 가능할 때만
  if(isIOS) show();
  else if(isSamsung) show();
  else if(isMobile) setTimeout(show, 2500);
})();
