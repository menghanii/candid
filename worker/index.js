// candid. Cloudflare Worker
//  · 앱 화면(index.html·이미지 등)은 예전처럼 정적 파일로 (env.ASSETS)
//  · /p/<경로> : Supabase 사진 저장소(photos) 중계 + Cloudflare 캐시
//    같은 파일을 두 번째부터는 Cloudflare 가 바로 보내서 Supabase 전송량(egress)이 늘지 않음
//    (캐시는 직접 연결한 도메인 candid-feed.com 에서만 동작. *.workers.dev 에서는 그냥 중계만 함)
const DEFAULT_ORIGIN = 'https://erlrviaqnnlfeehizlxc.supabase.co/storage/v1/object/public/photos/';
const EDGE_TTL = 60 * 60 * 24 * 30;      // Cloudflare 에 30일 보관(지운 사진이 오래 남지 않게)
const BROWSER_TTL = 60 * 60 * 24 * 365;  // 브라우저는 1년(파일 이름이 무작위라 내용이 안 바뀜)
const PATH_OK = /^[0-9a-zA-Z_-]{1,64}\/[0-9a-zA-Z_-]{1,80}\.(webp|jpe?g|png|mp4|webm|mov)$/;

// iPhone 앱 링크(유니버설 링크): candid-feed.com 링크를 누르면 앱이 설치돼 있으면 앱으로 열림
// 사진 중계(/p/), 이미지·번역 파일, 약관 페이지는 제외
const AASA = { applinks: { details: [{ appIDs: ['92KNXMVFG4.com.candidfeed.app'], components: [
  { '/': '/p/*', exclude: true }, { '/': '/brand/*', exclude: true }, { '/': '/i18n/*', exclude: true },
  { '/': '/terms*', exclude: true }, { '/': '/privacy*', exclude: true }, { '/': '/support*', exclude: true }, { '/': '/legal.css', exclude: true }, { '/': '/' }, { '/': '/*' },
] }] } };

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (url.pathname.startsWith('/p/')) return media(req, url, env.MEDIA_ORIGIN || DEFAULT_ORIGIN); // MEDIA_ORIGIN: 로컬 시험용
    if (url.pathname === '/.well-known/apple-app-site-association' || url.pathname === '/apple-app-site-association') return Response.json(AASA, { headers: { 'Cache-Control': 'public, max-age=3600' } });
    const res = await env.ASSETS.fetch(req);
    const og = ogFor(url);
    if (!og || !(res.headers.get('content-type') || '').includes('text/html')) return res;
    // 링크 종류에 맞는 미리보기(카톡·메시지에 뜨는 제목·설명·썸네일)
    const set = v => ({ element(e) { e.setAttribute('content', v); } });
    return new HTMLRewriter()
      .on('meta[property="og:title"]', set(og.title)).on('meta[name="twitter:title"]', set(og.title))
      .on('meta[property="og:description"]', set(og.desc)).on('meta[name="twitter:description"]', set(og.desc))
      .on('meta[property="og:image"]', set(og.image)).on('meta[name="twitter:image"]', set(og.image))
      .on('meta[property="og:image:width"]', set(og.w)).on('meta[property="og:image:height"]', set(og.h))
      .transform(res);
  },
};

// 미리보기: 링크 종류(o) · 보낸 사람 언어(l)
//  o: ask(피드 부탁) · invite(앱 초대) · gi(그룹 초대) · photo(사진 공유) · feed(친구 피드) · group(공개 그룹)
const OG = {
  ko: { ask: ['candid. · 사진 보내기', '링크를 누르면 로그인 없이 바로 사진을 보낼 수 있어요.'], invite: ['candid. · 친구가 채우는 피드', '링크로 가입하면 초대한 친구와 바로 친구가 돼요.'],
        gi: ['candid. · 그룹 초대', '링크를 누르면 바로 그룹에 들어갈 수 있어요.'], photo: ['candid. · 공유된 사진', '링크를 눌러 사진을 열어 보세요.'],
        feed: ['candid. · 친구 피드', '피드를 구경하고, 로그인 없이 사진을 보낼 수 있어요.'], group: ['candid. · 공개 그룹', '누구나 구경하고 참여할 수 있어요.'] },
  en: { ask: ['candid. · Send a photo', 'Tap the link to send a photo — no sign-in needed.'], invite: ['candid. · Your feed, filled by friends', "Sign up with this link and you'll be friends right away."],
        gi: ['candid. · Group invite', 'Tap the link to join the group right away.'], photo: ['candid. · Shared photo', 'Tap the link to open the photo.'],
        feed: ["candid. · A friend's feed", 'Look around, and send a photo without signing in.'], group: ['candid. · Public group', 'Anyone can look around and join.'] },
  ja: { ask: ['candid.・写真を送る', 'リンクを押せば、ログインなしですぐ写真を送れます。'], invite: ['candid.・友だちが埋めるフィード', 'このリンクから登録すると、すぐ友だちになれます。'],
        gi: ['candid.・グループ招待', 'リンクを押せば、すぐグループに参加できます。'], photo: ['candid.・共有された写真', 'リンクを押して写真を開いてください。'],
        feed: ['candid.・友だちのフィード', 'フィードを見て、ログインなしで写真を送れます。'], group: ['candid.・公開グループ', '誰でも見て、参加できます。'] },
};
function ogFor(url) {
  const q = url.searchParams, raw = url.search;
  let o = q.get('o');
  if (!o) { // 예전 링크(꼬리표 없음)
    if (q.has('invite')) o = 'invite'; else if (q.has('gi')) o = 'gi'; else if (q.has('p') && q.has('s')) o = 'photo';
    else if (q.has('g')) o = 'group'; else if ((q.has('u') || raw.startsWith('?@')) && q.has('m')) o = 'ask'; else if (q.has('u') || raw.startsWith('?@')) o = 'feed';
  }
  const l = OG[q.get('l')] ? q.get('l') : 'ko', t = o && OG[l][o]; if (!t) return null;
  // 썸네일은 6종 모두 같은 디자인(블루닷 캐릭터)으로 — 링크 종류·언어별 그림
  return { title: t[0], desc: t[1], image: `${url.origin}/brand/og/${o}-${l}.jpg?v=1`, w: '1200', h: '630' };
}

async function media(req, url, ORIGIN) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return new Response('Method Not Allowed', { status: 405 });
  const path = url.pathname.slice(3);
  if (!PATH_OK.test(path)) return new Response('Not Found', { status: 404 });
  const range = req.headers.get('Range');
  const pass = async () => { // 캐시 없이 그대로 중계(workers.dev 또는 캐시 실패 시)
    const o = await fetch(ORIGIN + path, { headers: range ? { Range: range } : {} });
    return out(o, o.status);
  };
  if (url.hostname.endsWith('.workers.dev')) return pass();

  const cache = caches.default;
  const key = new Request(`${url.origin}/p/${path}`);
  const look = () => cache.match(range ? new Request(key.url, { headers: { Range: range } }) : key); // Range 면 Cloudflare 가 206 으로 잘라 줌
  let hit = await look();
  if (hit) return out(hit, hit.status, 'HIT');

  const o = await fetch(ORIGIN + path);
  if (!o.ok) return new Response(o.status === 400 || o.status === 404 ? 'Not Found' : 'Upstream Error', { status: o.status === 400 ? 404 : o.status });
  const h = new Headers();
  ['Content-Type', 'Content-Length', 'ETag', 'Last-Modified'].forEach(k => o.headers.get(k) && h.set(k, o.headers.get(k)));
  h.set('Cache-Control', `public, max-age=${EDGE_TTL}`);
  h.set('Accept-Ranges', 'bytes');
  try { await cache.put(key, new Response(o.body, { status: 200, headers: h })); } catch { return pass(); }
  hit = await look();
  return hit ? out(hit, hit.status, 'MISS') : pass();
}

// 브라우저로 보낼 응답: 필요한 머리글만, 다른 사이트(캔버스 스토리 이미지)에서도 읽을 수 있게
function out(r, status, tag) {
  const h = new Headers();
  ['Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges', 'ETag', 'Last-Modified'].forEach(k => r.headers.get(k) && h.set(k, r.headers.get(k)));
  if (status === 200 || status === 206) h.set('Cache-Control', `public, max-age=${BROWSER_TTL}, immutable`);
  h.set('Access-Control-Allow-Origin', '*');
  h.set('X-Content-Type-Options', 'nosniff');
  if (tag) h.set('X-Candid-Cache', tag);
  return new Response(r.body, { status, headers: h });
}
