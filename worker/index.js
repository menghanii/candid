// candid. Cloudflare Worker
//  · 앱 화면(index.html·이미지 등)은 예전처럼 정적 파일로 (env.ASSETS)
//  · /p/<경로> : 사진·영상 보기. Cloudflare 캐시 → R2(바인딩 MEDIA) → 없으면 예전 저장소(Supabase photos)에서 가져와 R2 로 복사
//    (캐시는 직접 연결한 도메인 candid-feed.com 에서만 동작. *.workers.dev 에서는 캐시 없이 R2·예전 저장소만)
//  · PUT /upload/<경로> : 사진·영상 올리기(R2). 권한은 Supabase 저장소 규칙과 같게 Supabase 에 물어봄
//  · /a/<내 id>/<파일>.jpg : 프로필 사진 보기(GET)·올리기(PUT, 본인만). R2 의 avatars/ 아래
//  · POST /media/delete : 내 폴더 파일 지우기(게시물 삭제 후) · /media/delete-avatars : 계정 삭제 전 내 프로필 사진 전부 · /media/trash : 서버(알림 함수)가 버릴 파일 정리 · /media/migrate : 예전 파일 일괄 복사
const DEFAULT_ORIGIN = 'https://erlrviaqnnlfeehizlxc.supabase.co/storage/v1/object/public/photos/';
const SB = 'https://erlrviaqnnlfeehizlxc.supabase.co';
const SB_KEY = 'sb_publishable_LfUJRHztENtaEmt7YV_bzQ_iboVhvn3'; // 공개 키(앱에도 들어 있음)
const MAX_BYTES = 10 * 1024 * 1024; // 파일당 10MB (05 SQL 과 같음)
const TYPE = { jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime' };
const CACHE_CC = 'public, max-age=31536000, s-maxage=2592000, immutable'; // 전용 주소(R2)로 보낼 때: 브라우저 1년, Cloudflare 30일
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EDGE_TTL = 60 * 60 * 24 * 30;      // Cloudflare 에 30일 보관(지운 사진이 오래 남지 않게)
const BROWSER_TTL = 60 * 60 * 24 * 365;  // 브라우저는 1년(파일 이름이 무작위라 내용이 안 바뀜)
const PATH_OK = /^[0-9a-zA-Z_-]{1,64}\/[0-9a-zA-Z_-]{1,80}\.(webp|jpe?g|png|mp4|webm|mov)$/;
// 프로필 사진: /a/<내 id>/<무작위>.jpg (R2 에는 avatars/ 아래에). 예전 것은 Supabase avatars 저장소
const AV_ORIGIN = 'https://erlrviaqnnlfeehizlxc.supabase.co/storage/v1/object/public/avatars/';
const AV_OK = /^[0-9a-f-]{36}\/[0-9a-zA-Z_-]{1,80}\.jpg$/;
const AV_MAX = 1024 * 1024; // 1MB (03 SQL 과 같음)

// iPhone 앱 링크(유니버설 링크): candid-feed.com 링크를 누르면 앱이 설치돼 있으면 앱으로 열림
// 사진 중계(/p/), 이미지·번역 파일, 약관 페이지는 제외
const AUTH_ORIGIN = 'https://erlrviaqnnlfeehizlxc.supabase.co'; // 로그인 넘김을 허용할 Supabase 주소(다른 곳으로는 안 넘김)
const AASA = { applinks: { details: [{ appIDs: ['92KNXMVFG4.com.candidfeed.app'], components: [
  { '/': '/p/*', exclude: true }, { '/': '/a/*', exclude: true }, { '/': '/upload/*', exclude: true }, { '/': '/media/*', exclude: true }, { '/': '/brand/*', exclude: true }, { '/': '/i18n/*', exclude: true },
  { '/': '/terms*', exclude: true }, { '/': '/privacy*', exclude: true }, { '/': '/support*', exclude: true }, { '/': '/legal.css', exclude: true }, { '/': '/auth/*', exclude: true }, { '/': '/' }, { '/': '/*' },
] }] } };

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url);
    // 앱 로그인 시작(/auth/go?u=…): iPhone 의 "○○을(를) 사용하여 로그인" 창에 supabase.co 대신 candid-feed.com 이 보이도록, 우리 주소에서 Supabase 로그인 주소로 넘김
    if (url.pathname === '/auth/go') {
      const u = url.searchParams.get('u') || '';
      if (!u.startsWith(AUTH_ORIGIN + '/auth/v1/authorize?')) return new Response('bad request', { status: 400 });
      return Response.redirect(u, 302);
    }
    if (url.pathname.startsWith('/p/')) return media(req, url, env, ctx);
    if (url.pathname.startsWith('/a/')) return req.method === 'PUT' || req.method === 'OPTIONS' ? mediaApi(req, url, env).catch(() => json({ error: 'server' }, 500)) : media(req, url, env, ctx);
    if (url.pathname.startsWith('/upload/') || url.pathname.startsWith('/media/')) return mediaApi(req, url, env).catch(() => json({ error: 'server' }, 500));
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

async function media(req, url, env, ctx) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return new Response('Method Not Allowed', { status: 405 });
  const av = url.pathname.startsWith('/a/'), path = url.pathname.slice(3);
  if (!(av ? AV_OK : PATH_OK).test(path)) return new Response('Not Found', { status: 404 });
  const range = req.headers.get('Range');
  const ORIGIN = av ? AV_ORIGIN : env.MEDIA_ORIGIN || DEFAULT_ORIGIN; // MEDIA_ORIGIN: 로컬 시험용
  const rkey = av ? `avatars/${path}` : path; // R2 안의 이름
  const pass = async () => { const o = await source(env, ctx, ORIGIN, path, range, rkey); return out(o, o.status); }; // 캐시 없이(workers.dev 또는 캐시 실패 시)
  if (url.hostname.endsWith('.workers.dev')) return pass();

  const cache = caches.default;
  const key = new Request(`${url.origin}${url.pathname.slice(0, 3)}${path}`);
  const look = () => cache.match(range ? new Request(key.url, { headers: { Range: range } }) : key); // Range 면 Cloudflare 가 206 으로 잘라 줌
  let hit = await look();
  if (hit) return out(hit, hit.status, 'HIT');

  const o = await source(env, ctx, ORIGIN, path, null, rkey);
  if (!o.ok) {
    const nf = o.status === 400 || o.status === 404;
    const r = new Response(nf ? 'Not Found' : 'Upstream Error', { status: nf ? 404 : o.status, headers: { 'Cache-Control': 'public, max-age=60', 'Access-Control-Allow-Origin': '*' } });
    if (nf) ctx.waitUntil(cache.put(key, r.clone()).catch(() => {})); // 없는 주소를 계속 두드려도 1분 동안은 R2·Supabase 까지 안 감
    return r;
  }
  const h = new Headers();
  ['Content-Type', 'Content-Length', 'ETag', 'Last-Modified'].forEach(k => o.headers.get(k) && h.set(k, o.headers.get(k)));
  h.set('Cache-Control', `public, max-age=${EDGE_TTL}`);
  h.set('Accept-Ranges', 'bytes');
  try { await cache.put(key, new Response(o.body, { status: 200, headers: h })); } catch { return pass(); }
  hit = await look();
  return hit ? out(hit, hit.status, 'MISS') : pass();
}

// 원본 읽기: R2 → 없으면 예전 저장소(Supabase)에서 가져와 R2 에 복사(이후로는 R2 에서)
async function source(env, ctx, ORIGIN, path, range, rkey = path) {
  if (env.MEDIA) {
    let o;
    try { o = await env.MEDIA.get(rkey, range ? { range: new Headers({ Range: range }) } : {}); }
    catch { return new Response('Range Not Satisfiable', { status: 416 }); }
    if (o) {
      const h = new Headers({ 'Content-Type': o.httpMetadata?.contentType || typeOf(path) || 'application/octet-stream', ETag: o.httpEtag, 'Last-Modified': o.uploaded.toUTCString(), 'Accept-Ranges': 'bytes' });
      if (range && o.range) {
        const r = o.range, off = r.suffix != null ? Math.max(0, o.size - r.suffix) : (r.offset ?? 0);
        const len = r.suffix != null ? o.size - off : (r.length ?? o.size - off);
        h.set('Content-Range', `bytes ${off}-${off + len - 1}/${o.size}`); h.set('Content-Length', String(len));
        return new Response(o.body, { status: 206, headers: h });
      }
      h.set('Content-Length', String(o.size));
      return new Response(o.body, { status: 200, headers: h });
    }
  }
  const o = await fetch(ORIGIN + path, range ? { headers: { Range: range } } : {});
  if (!o.ok || range || !env.MEDIA) return o;
  const buf = await o.arrayBuffer();
  const type = o.headers.get('Content-Type') || typeOf(path) || 'application/octet-stream';
  ctx.waitUntil(env.MEDIA.put(rkey, buf, { httpMetadata: { contentType: type, cacheControl: CACHE_CC } }).catch(() => {}));
  return new Response(buf, { status: 200, headers: { 'Content-Type': type, 'Content-Length': String(buf.byteLength) } });
}

// ---------- 올리기·지우기 (R2) ----------
// 권한 규칙은 Supabase 저장소 규칙(01·18 SQL)과 같음:
//  올리기: 개인 폴더(= 프로필 id)는 누구나(로그인 없이 사진 보내기 포함) · 그룹 폴더는 올릴 수 있는 멤버·방장만(can_upload_group_folder)
//  지우기: 내 폴더(= 내 id)만 · 버릴 파일 정리·일괄 복사는 서버 키로만
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'PUT, POST, OPTIONS', 'Access-Control-Allow-Headers': 'authorization, content-type, x-service-key', 'Access-Control-Max-Age': '86400' };
const json = (body, status = 200) => Response.json(body, { status, headers: CORS });
const typeOf = path => TYPE[path.split('.').pop().toLowerCase()];
const jwtSub = tok => { try { return JSON.parse(atob(tok.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub || ''; } catch { return ''; } }; // 속도 제한용(가짜 토큰은 아래 권한 확인에서 걸림)
const bearer = req => (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
const sbHeaders = key => (key.split('.').length === 3 ? { apikey: key, Authorization: `Bearer ${key}` } : { apikey: key });
// 사진은 우리 앱이 만든 jpg·webp 만 → 파일 앞부분으로 한 번 더 확인 (영상은 기기마다 형식이 달라 확장자·용량만)
function looksLike(type, b) {
  if (type === 'image/jpeg') return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  if (type === 'image/webp') return String.fromCharCode(...b.subarray(0, 4)) === 'RIFF' && String.fromCharCode(...b.subarray(8, 12)) === 'WEBP';
  return true;
}
// 로그인 토큰의 사용자 id (토큰이 맞는지는 Supabase 가 확인)
async function userId(tok) {
  if (!tok) return null;
  const r = await fetch(`${SB}/auth/v1/user`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${tok}` } });
  return r.ok ? ((await r.json()).id || null) : null;
}
async function canUpload(dir, tok) {
  const h = { apikey: SB_KEY, ...(tok ? { Authorization: `Bearer ${tok}` } : {}) };
  const p = await fetch(`${SB}/rest/v1/profiles?select=id&id=eq.${dir}`, { headers: h });
  if (p.ok && (await p.json()).length) return true;
  if (!tok) return false;
  const g = await fetch(`${SB}/rest/v1/rpc/can_upload_group_folder`, { method: 'POST', headers: { ...h, 'Content-Type': 'application/json' }, body: JSON.stringify({ f: dir }) });
  return g.ok && (await g.json()) === true;
}
// 서버 키 확인: 서버만 읽을 수 있는 storage_trash 를 그 키로 읽어 봄 (읽히면 서버 키). 지울 파일은 그 목록에 있는 것만
async function trashed(key, paths) {
  const r = await fetch(`${SB}/rest/v1/storage_trash?select=path&path=in.(${paths.map(p => `"${p}"`).join(',')})`, { headers: sbHeaders(key) });
  return r.ok ? (await r.json()).map(x => x.path).filter(p => paths.includes(p)) : null;
}
const pathsOf = async req => { const b = await req.json().catch(() => ({})); return (Array.isArray(b?.paths) ? b.paths : []).filter(p => typeof p === 'string' && PATH_OK.test(p)).slice(0, 200); };
async function forget(url, paths, pre = '/p/') { // 이 지역 Cloudflare 캐시에서도 지움
  await Promise.all(paths.map(p => caches.default.delete(new Request(`${url.origin}${pre}${p}`)).catch(() => {})));
}
async function tooMany(req, env, tok) { // 1분에 너무 많이 올리면 잠깐 막음(로그인한 사람은 사용자별, 아니면 IP 별)
  if (!env.UPLOAD_LIMIT) return false;
  const { success } = await env.UPLOAD_LIMIT.limit({ key: tok && jwtSub(tok) ? `u:${jwtSub(tok)}` : `ip:${req.headers.get('CF-Connecting-IP') || ''}` });
  return !success;
}

async function mediaApi(req, url, env) {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (!env.MEDIA) return json({ error: 'not_ready' }, 503);
  // 프로필 사진 올리기: 로그인한 본인 폴더만, jpg 1MB
  if (url.pathname.startsWith('/a/')) {
    if (req.method !== 'PUT') return json({ error: 'method' }, 405);
    const path = url.pathname.slice(3), tok = bearer(req);
    if (!AV_OK.test(path)) return json({ error: 'bad_path' }, 400);
    if (+(req.headers.get('Content-Length') || 0) > AV_MAX) return json({ error: 'too_large' }, 413);
    if (await tooMany(req, env, tok)) return json({ error: 'too_many' }, 429);
    const uid = await userId(tok);
    if (!uid) return json({ error: 'unauthorized' }, 401);
    if (uid !== path.split('/')[0]) return json({ error: 'forbidden' }, 403);
    if (await env.MEDIA.head(`avatars/${path}`) || (await fetch(AV_ORIGIN + path, { method: 'HEAD' })).ok) return json({ error: 'exists' }, 409);
    const body = new Uint8Array(await req.arrayBuffer());
    if (!body.length) return json({ error: 'empty' }, 400);
    if (body.length > AV_MAX) return json({ error: 'too_large' }, 413);
    if (!looksLike('image/jpeg', body)) return json({ error: 'bad_type' }, 415);
    await env.MEDIA.put(`avatars/${path}`, body, { httpMetadata: { contentType: 'image/jpeg', cacheControl: CACHE_CC } });
    return json({ url: `${url.origin}/a/${path}` });
  }
  // 올리기
  if (url.pathname.startsWith('/upload/')) {
    if (req.method !== 'PUT') return json({ error: 'method' }, 405);
    const path = url.pathname.slice(8), type = typeOf(path), dir = path.split('/')[0];
    if (!PATH_OK.test(path) || !type) return json({ error: 'bad_path' }, 400);
    if (!UUID.test(dir)) return json({ error: 'forbidden' }, 403);
    if (+(req.headers.get('Content-Length') || 0) > MAX_BYTES) return json({ error: 'too_large' }, 413);
    const tok = bearer(req);
    if (await tooMany(req, env, tok)) return json({ error: 'too_many' }, 429);
    if (!(await canUpload(dir, tok))) return json({ error: 'forbidden' }, 403);
    // 같은 이름 덮어쓰기 금지(R2·예전 저장소 모두) — 남의 사진을 바꿔치기 못 하게
    if (await env.MEDIA.head(path)) return json({ error: 'exists' }, 409);
    if ((await fetch(DEFAULT_ORIGIN + path, { method: 'HEAD' })).ok) return json({ error: 'exists' }, 409);
    const body = new Uint8Array(await req.arrayBuffer());
    if (!body.length) return json({ error: 'empty' }, 400);
    if (body.length > MAX_BYTES) return json({ error: 'too_large' }, 413);
    if (!looksLike(type, body)) return json({ error: 'bad_type' }, 415);
    await env.MEDIA.put(path, body, { httpMetadata: { contentType: type, cacheControl: CACHE_CC } });
    return json({ path });
  }
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  // 게시물 삭제 후 내 폴더 파일 지우기
  if (url.pathname === '/media/delete') {
    const uid = await userId(bearer(req));
    if (!uid) return json({ error: 'unauthorized' }, 401);
    const paths = (await pathsOf(req)).filter(p => p.split('/')[0] === uid);
    if (paths.length) { await env.MEDIA.delete(paths); await forget(url, paths); }
    return json({ deleted: paths.length });
  }
  // 계정 삭제 직전: 내 프로필 사진 전부 지우기
  if (url.pathname === '/media/delete-avatars') {
    const uid = await userId(bearer(req));
    if (!uid) return json({ error: 'unauthorized' }, 401);
    const keys = (await env.MEDIA.list({ prefix: `avatars/${uid}/` })).objects.map(o => o.key);
    if (keys.length) { await env.MEDIA.delete(keys); await forget(url, keys.map(k => k.slice(8)), '/a/'); }
    return json({ deleted: keys.length });
  }
  // 서버(알림 함수): storage_trash 에 있는 파일 정리
  if (url.pathname === '/media/trash') {
    const key = req.headers.get('x-service-key') || '', paths = await pathsOf(req);
    if (!key) return json({ error: 'unauthorized' }, 401);
    if (!paths.length) return json({ deleted: 0 });
    const ok = await trashed(key, paths);
    if (!ok) return json({ error: 'unauthorized' }, 401);
    if (ok.length) { await env.MEDIA.delete(ok); await forget(url, ok); }
    return json({ deleted: ok.length });
  }
  // 일괄 복사(한 번만): 예전 저장소 파일을 R2 로. 서버 키로만
  if (url.pathname === '/media/migrate') {
    const key = req.headers.get('x-service-key') || '', b = await req.json().catch(() => ({})), av = b?.bucket === 'avatars';
    const paths = (Array.isArray(b?.paths) ? b.paths : []).filter(p => typeof p === 'string' && (av ? AV_OK : PATH_OK).test(p)).slice(0, 200);
    if (!key || !(await trashed(key, ['_/_.jpg']))) return json({ error: 'unauthorized' }, 401);
    const res = { copied: 0, skipped: 0, missing: [] };
    for (const p of paths) {
      const rk = av ? `avatars/${p}` : p;
      if (await env.MEDIA.head(rk)) { res.skipped++; continue; }
      const o = await fetch((av ? AV_ORIGIN : DEFAULT_ORIGIN) + p);
      if (!o.ok) { res.missing.push(p); continue; }
      await env.MEDIA.put(rk, await o.arrayBuffer(), { httpMetadata: { contentType: o.headers.get('Content-Type') || typeOf(p) || 'application/octet-stream', cacheControl: CACHE_CC } });
      res.copied++;
    }
    return json(res);
  }
  return json({ error: 'not_found' }, 404);
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
