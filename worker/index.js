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
  { '/': '/terms*', exclude: true }, { '/': '/privacy*', exclude: true }, { '/': '/legal.css', exclude: true }, { '/': '/*' },
] }] } };

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    if (url.pathname.startsWith('/p/')) return media(req, url, env.MEDIA_ORIGIN || DEFAULT_ORIGIN); // MEDIA_ORIGIN: 로컬 시험용
    if (url.pathname === '/.well-known/apple-app-site-association' || url.pathname === '/apple-app-site-association') return Response.json(AASA, { headers: { 'Cache-Control': 'public, max-age=3600' } });
    return env.ASSETS.fetch(req);
  },
};

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
