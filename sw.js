// 되돌리기용: 예전에 설치된 서비스 워커를 스스로 지움 (설치 기능을 뺄 때 사용)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(
  self.registration.unregister().then(() => self.clients.matchAll()).then(cs => cs.forEach(c => c.navigate(c.url)))
));
