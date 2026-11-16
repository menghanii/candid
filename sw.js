// candid. 서비스 워커 — 푸시 알림 수신/클릭 처리
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'candid.', {
    body: d.body || '새 사진이 도착했어요.',
    icon: 'brand/icon-512.png',
    badge: 'brand/icon-128.png',
    tag: 'candid-inbox',
    renotify: true,
    data: { url: d.url || self.registration.scope },
  }));
});

// 알림을 누르면 그 내용(그룹·대기 피드·사진)으로 바로
// iPhone 홈 화면 앱은 열려 있는 창을 다른 주소로 옮기는 기능(navigate)을 지원하지 않아서
// 열려 있는 앱에는 메시지로 주소를 알려 앱이 직접 이동, 새로 켜지는 앱은 시작할 때 물어보면 알려줌
let PENDING = null;
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = e.notification.data && e.notification.data.url || self.registration.scope;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const w = wins.find(x => x.url.startsWith(self.registration.scope));
    if (w) {
      try { await w.focus(); } catch (_) {}
      w.postMessage({ type: 'candid-open', url });
      return;
    }
    PENDING = { url, at: Date.now() };
    return self.clients.openWindow(url);
  })());
});
self.addEventListener('message', e => {
  if (e.data !== 'candid-pending?') return;
  if (PENDING && Date.now() - PENDING.at < 60000 && e.source) e.source.postMessage({ type: 'candid-open', url: PENDING.url });
  PENDING = null;
});
