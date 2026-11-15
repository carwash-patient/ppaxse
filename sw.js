// 빡세 서비스 워커: '앱처럼 설치'가 되게 해주는 최소한의 파일.
// 페이지는 항상 인터넷에서 새로 받아오고(저장 안 함), 인터넷이 끊겼을 때만 안내 화면을 보여줌.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

const OFFLINE = '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
  + '<title>빡세</title><body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;'
  + 'background:#04111e;color:#e2e8f0;font-family:sans-serif;text-align:center;line-height:1.7">'
  + '<div>📡<br><b>인터넷 연결이 끊겼어요</b><br>연결되면 다시 열어 주세요</div></body>';

self.addEventListener('fetch', e => {
  if(e.request.mode !== 'navigate') return;   // 이미지·데이터 요청은 건드리지 않음
  e.respondWith(fetch(e.request).catch(() =>
    new Response(OFFLINE, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
});
