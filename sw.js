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
//  · 알림 링크는 새 주소(candid-feed.com)로 오지만, 홈 화면 앱이 예전 주소로 설치돼 있을 수 있음 → 이 앱의 주소로 바꿔서 연다
//    (다른 주소로 열면 앱이 아니라 Safari 에서, 로그인 안 된 채로 열림)
//  · iPhone 은 열려 있는 창을 다른 주소로 옮기는 기능(navigate)이 없음 → 앱에 메시지로 알려 앱이 직접 이동
//  · 앱이 꺼져 있었거나 잠들어 메시지를 못 받을 수 있음 → '갈 곳'을 저장소(Cache)에 남겨 두고, 앱이 켜지거나 돌아올 때 확인
const PENDING_KEY = 'candid-pending-open';
self.addEventListener('notificationclick', e => {
  e.notification.close();
  let url = e.notification.data && e.notification.data.url || self.registration.scope;
  try { const u = new URL(url, self.registration.scope); url = new URL(u.search || '', self.registration.scope).href; } catch (_) { url = self.registration.scope; }
  e.waitUntil((async () => {
    try { const c = await caches.open('candid-push'); await c.put(PENDING_KEY, new Response(JSON.stringify({ url, at: Date.now() }))); } catch (_) {}
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const w = wins.find(x => x.url.startsWith(self.registration.scope));
    if (w) {
      try { await w.focus(); } catch (_) {}
      w.postMessage({ type: 'candid-open', url });
      return;
    }
    return self.clients.openWindow(url);
  })());
});
