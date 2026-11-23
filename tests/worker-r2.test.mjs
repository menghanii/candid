// 워커 R2 시험: 가짜 R2·Supabase·캐시로 올리기·보기·지우기·권한 확인 (실제 서버에는 아무것도 쓰지 않음, 인터넷 불필요)
// 실행: node tests/worker-r2.test.mjs   (worker/index.js 를 고쳤으면 꼭 돌릴 것)
import { copyFileSync } from 'node:fs'; import { tmpdir } from 'node:os'; import { join } from 'node:path'; import { pathToFileURL } from 'node:url';
const SRC = process.argv[2] || (() => { const p = join(tmpdir(), `candid-worker-${process.pid}.mjs`); copyFileSync(new URL('../worker/index.js', import.meta.url), p); return pathToFileURL(p).href; })();
const SB = 'https://erlrviaqnnlfeehizlxc.supabase.co', ORIG = SB + '/storage/v1/object/public/photos/';
const ME = '11111111-1111-4111-8111-111111111111', OTHER = '22222222-2222-4222-8222-222222222222', GROUP = '33333333-3333-4333-8333-333333333333', NOBODY = '44444444-4444-4444-8444-444444444444';
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const TOK = `${b64({ alg: 'HS256' })}.${b64({ sub: ME })}.sig-valid`, BAD = `${b64({ alg: 'HS256' })}.${b64({ sub: ME })}.sig-forged`;
const SERVICE = 'svc.key.jwt';
const profiles = new Set([ME, OTHER]), groupMembers = { [GROUP]: [ME] };
const supaFiles = new Map([[`${OTHER}/old.jpg`, Buffer.from([0xff, 0xd8, 0xff, 1, 2, 3])]]);
const trash = new Set([`${GROUP}/t1.jpg`]);
let fetchLog = [];
const valid = h => { const a = h.get?.('Authorization') || h.Authorization; return !a ? null : a === `Bearer ${TOK}` ? ME : 'bad'; };
globalThis.fetch = async (u, init = {}) => {
  u = String(u); fetchLog.push(u); const h = new Headers(init.headers || {});
  if (u.startsWith(ORIG)) {
    const f = supaFiles.get(u.slice(ORIG.length));
    if (!f) return new Response('{"error":"not_found"}', { status: 400 });
    return new Response(init.method === 'HEAD' ? null : f, { status: 200, headers: { 'Content-Type': 'image/jpeg', 'Content-Length': String(f.length) } });
  }
  if (u.startsWith(SB + '/auth/v1/user')) { const v = valid(h); return v === ME ? Response.json({ id: ME }) : new Response('{}', { status: 401 }); }
  if (u.startsWith(SB + '/rest/v1/profiles')) { if (valid(h) === 'bad') return new Response('{}', { status: 401 }); const id = new URL(u).searchParams.get('id').slice(3); return Response.json(profiles.has(id) ? [{ id }] : []); }
  if (u.startsWith(SB + '/rest/v1/rpc/can_upload_group_folder')) { const v = valid(h); if (v === 'bad') return new Response('{}', { status: 401 }); const f = JSON.parse(init.body).f; return Response.json(!!v && (groupMembers[f] || []).includes(v)); }
  if (u.startsWith(SB + '/rest/v1/storage_trash')) {
    if (h.get('apikey') !== SERVICE || h.get('Authorization') !== `Bearer ${SERVICE}`) return new Response('{"code":"42501"}', { status: 401 });
    const list = decodeURIComponent(new URL(u).searchParams.get('path')).replace(/^in\.\(|\)$/g, '').split(',').map(x => x.replace(/"/g, ''));
    return Response.json(list.filter(p => trash.has(p)).map(path => ({ path })));
  }
  throw new Error('unexpected fetch ' + u);
};
// 가짜 R2
const r2 = new Map();
const MEDIA = {
  async head(k) { return r2.has(k) ? { size: r2.get(k).b.length } : null; },
  async put(k, v, o) { r2.set(k, { b: Buffer.from(v instanceof ArrayBuffer ? new Uint8Array(v) : v), type: o?.httpMetadata?.contentType, up: new Date() }); },
  async delete(ks) { [].concat(ks).forEach(k => r2.delete(k)); },
  async get(k, o = {}) {
    const x = r2.get(k); if (!x) return null;
    let body = x.b, range;
    const rh = o.range?.get?.('Range');
    if (rh) { const m = /bytes=(\d*)-(\d*)/.exec(rh); if (m[1] === '') { range = { suffix: +m[2] }; body = x.b.subarray(x.b.length - +m[2]); } else { const s = +m[1], e = m[2] ? +m[2] : x.b.length - 1; if (s >= x.b.length) throw new Error('InvalidRange'); range = { offset: s, length: e - s + 1 }; body = x.b.subarray(s, e + 1); } }
    return { body: new Blob([body]).stream(), size: x.b.length, range, httpEtag: '"e1"', httpMetadata: { contentType: x.type }, uploaded: x.up };
  },
};
// 가짜 Cloudflare 캐시
const cstore = new Map();
globalThis.caches = { default: {
  async match(req) { const e = cstore.get(req.url); if (!e) return undefined; const rg = req.headers.get('Range'); if (rg && e.status === 200) { const m = /bytes=(\d+)-(\d*)/.exec(rg); const s = +m[1], en = m[2] ? +m[2] : e.b.length - 1; return new Response(e.b.subarray(s, en + 1), { status: 206, headers: { ...e.h, 'Content-Range': `bytes ${s}-${en}/${e.b.length}` } }); } return new Response(e.status === 200 ? e.b : 'Not Found', { status: e.status, headers: e.h }); },
  async put(req, res) { const b = Buffer.from(await res.arrayBuffer()); cstore.set(req.url, { b, status: res.status, h: Object.fromEntries(res.headers) }); },
  async delete(req) { return cstore.delete(req.url); },
} };
let limited = false;
const UPLOAD_LIMIT = { async limit() { return { success: !limited }; } };
const { default: W } = await import(SRC);
const env = { MEDIA, UPLOAD_LIMIT, ASSETS: { fetch: () => new Response('asset') } };
const waits = []; const ctx = { waitUntil: p => waits.push(p) };
const call = async (path, init = {}, host = 'https://candid-feed.com') => { const r = await W.fetch(new Request(host + path, init), env, ctx); await Promise.all(waits.splice(0)); return r; };
let fails = 0; const ok = (c, m) => { console.log((c ? '✅' : '❌') + ' ' + m); if (!c) fails++; };
const JPG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 9, 9, 9, 9]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.from([1, 0, 0, 0]), Buffer.from('WEBPVP8 ')]);
const put = (path, body, tok, extra = {}) => call('/upload/' + path, { method: 'PUT', body, headers: { 'Content-Type': 'image/jpeg', ...(tok ? { Authorization: 'Bearer ' + tok } : {}), ...extra } });

// ---- 올리기 ----
let r = await put(`${OTHER}/a1.jpg`, JPG); ok(r.status === 200 && r2.get(`${OTHER}/a1.jpg`)?.type === 'image/jpeg', `로그인 없이 친구 폴더에 사진 보내기 → R2 저장 (${r.status})`);
ok(r.headers.get('Access-Control-Allow-Origin') === '*', '앱(다른 주소)에서 올려도 CORS 허용');
r = await put(`${ME}/a2.webp`, WEBP, TOK); ok(r.status === 200 && r2.get(`${ME}/a2.webp`)?.type === 'image/webp', '로그인해서 내 폴더에 webp 올리기');
r = await put(`${ME}/v1.mp4`, Buffer.from('....ftypisom'), TOK); ok(r.status === 200 && r2.get(`${ME}/v1.mp4`)?.type === 'video/mp4', '영상(mp4) 올리기');
r = await put(`${NOBODY}/x.jpg`, JPG); ok(r.status === 403 && !r2.has(`${NOBODY}/x.jpg`), `없는 사람 폴더에는 못 올림 (${r.status})`);
r = await put(`${GROUP}/g1.jpg`, JPG); ok(r.status === 403, '로그인 없이 그룹 폴더에는 못 올림');
r = await put(`${GROUP}/g1.jpg`, JPG, TOK); ok(r.status === 200 && r2.has(`${GROUP}/g1.jpg`), '그룹 멤버는 그룹 폴더에 올림');
groupMembers[GROUP] = []; r = await put(`${GROUP}/g2.jpg`, JPG, TOK); ok(r.status === 403, '멤버가 아니면(마감·탈퇴) 그룹 폴더에 못 올림'); groupMembers[GROUP] = [ME];
r = await put(`${ME}/f1.jpg`, JPG, BAD); ok(r.status === 403 && !r2.has(`${ME}/f1.jpg`), '가짜 로그인 토큰이면 못 올림');
r = await put(`abc/x.jpg`, JPG); ok(r.status === 403, '폴더 이름이 id 형식이 아니면 거절');
r = await put(`${ME}/x.png`, JPG, TOK); ok(r.status === 400, '허용 안 된 형식(png) 거절');
r = await put(`${ME}/../x.jpg`, JPG, TOK); ok(r.status >= 400 && r.status < 500, '경로 조작(..) 거절');
r = await put(`${ME}/fake.jpg`, Buffer.from('<html><script>'), TOK); ok(r.status === 415 && !r2.has(`${ME}/fake.jpg`), '사진이 아닌 파일을 .jpg 로 올리면 거절');
r = await put(`${ME}/big.jpg`, JPG, TOK, { 'Content-Length': String(11 * 1024 * 1024) }); ok(r.status === 413, '10MB 넘으면 거절(머리글)');
r = await put(`${ME}/big2.mp4`, Buffer.alloc(10 * 1024 * 1024 + 1), TOK); ok(r.status === 413 && !r2.has(`${ME}/big2.mp4`), '10MB 넘으면 거절(실제 크기)');
r = await put(`${ME}/empty.jpg`, Buffer.alloc(0), TOK); ok(r.status === 400, '빈 파일 거절');
r = await put(`${OTHER}/a1.jpg`, JPG); ok(r.status === 409, 'R2 에 이미 있는 이름은 덮어쓰기 거절');
r = await put(`${OTHER}/old.jpg`, JPG); ok(r.status === 409 && !r2.has(`${OTHER}/old.jpg`), '예전 저장소(Supabase)에 있는 사진도 바꿔치기 거절');
limited = true; r = await put(`${ME}/rl.jpg`, JPG, TOK); ok(r.status === 429, '너무 많이 올리면 잠깐 막음(429)'); limited = false;
r = await call(`/upload/${ME}/x.jpg`, { method: 'OPTIONS' }); ok(r.status === 204 && /PUT/.test(r.headers.get('Access-Control-Allow-Methods')) && /authorization/.test(r.headers.get('Access-Control-Allow-Headers')), '사전 확인(OPTIONS) 응답');
r = await call(`/upload/${ME}/x.jpg`, { method: 'GET' }); ok(r.status === 405, 'GET 으로 올리기 주소 접근 거절');

// ---- 보기 ----
r = await call(`/p/${OTHER}/a1.jpg`); let b = Buffer.from(await r.arrayBuffer());
ok(r.status === 200 && b.equals(JPG) && r.headers.get('Content-Type') === 'image/jpeg' && r.headers.get('X-Candid-Cache') === 'MISS', `R2 사진 보기 (${r.status} ${r.headers.get('X-Candid-Cache')})`);
r = await call(`/p/${OTHER}/a1.jpg`); ok(r.headers.get('X-Candid-Cache') === 'HIT', '두 번째는 캐시에서');
const VID = Buffer.from(Array.from({ length: 100 }, (_, i) => i)); await MEDIA.put(`${ME}/v2.mp4`, VID, { httpMetadata: { contentType: 'video/mp4' } });
r = await call(`/p/${ME}/v2.mp4`, { headers: { Range: 'bytes=10-19' } }); b = Buffer.from(await r.arrayBuffer());
ok(r.status === 206 && r.headers.get('Content-Range') === 'bytes 10-19/100' && b.equals(VID.subarray(10, 20)), '영상 구간 요청(Range) → 206 (캐시 경로)');
r = await call(`/p/${ME}/v2.mp4`, { headers: { Range: 'bytes=90-' } }, 'https://candid.x.workers.dev'); b = Buffer.from(await r.arrayBuffer());
ok(r.status === 206 && r.headers.get('Content-Range') === 'bytes 90-99/100' && r.headers.get('Content-Length') === '10' && b.equals(VID.subarray(90)), 'workers.dev 에서 R2 구간 요청 → 206');
r = await call(`/p/${ME}/v2.mp4`, { headers: { Range: 'bytes=-5' } }, 'https://candid.x.workers.dev'); b = Buffer.from(await r.arrayBuffer());
ok(r.status === 206 && r.headers.get('Content-Range') === 'bytes 95-99/100' && b.equals(VID.subarray(95)), '끝에서부터 구간(bytes=-5)');
r = await call(`/p/${ME}/v2.mp4`, {}, 'https://candid.x.workers.dev'); ok(r.status === 200 && r.headers.get('Content-Length') === '100', 'workers.dev 전체 받기');
// 예전 저장소 → R2 로 복사
r = await call(`/p/${OTHER}/old.jpg`); b = Buffer.from(await r.arrayBuffer());
ok(r.status === 200 && b.equals(supaFiles.get(`${OTHER}/old.jpg`)), '예전(Supabase) 사진도 그대로 보임');
ok(r2.has(`${OTHER}/old.jpg`) && r2.get(`${OTHER}/old.jpg`).b.equals(supaFiles.get(`${OTHER}/old.jpg`)), '한 번 열리면 R2 로 복사됨');
supaFiles.delete(`${OTHER}/old.jpg`); cstore.clear(); fetchLog = [];
r = await call(`/p/${OTHER}/old.jpg`); ok(r.status === 200 && !fetchLog.some(u => u.startsWith(ORIG)), '복사된 뒤에는 Supabase 를 안 봄');
fetchLog = []; r = await call(`/p/${ME}/none.jpg`); ok(r.status === 404, '없는 사진 → 404');
fetchLog = []; r = await call(`/p/${ME}/none.jpg`); ok(r.status === 404 && fetchLog.length === 0, '없는 주소를 또 두드려도 1분간은 Supabase 까지 안 감');
r = await call(`/p/a/b/c.jpg`); ok(r.status === 404, "이상한 경로(폴더 여러 단계) 404");
r = await call(`/p/${OTHER}/a1.jpg`, { method: 'POST' }); ok(r.status === 405, '보기 주소에 POST 거절');

// ---- 지우기(내 게시물) ----
r = await call('/media/delete', { method: 'POST', body: JSON.stringify({ paths: [`${ME}/a2.webp`] }) }); ok(r.status === 401 && r2.has(`${ME}/a2.webp`), '로그인 없이 지우기 거절');
r = await call('/media/delete', { method: 'POST', headers: { Authorization: 'Bearer ' + BAD }, body: JSON.stringify({ paths: [`${ME}/a2.webp`] }) }); ok(r.status === 401 && r2.has(`${ME}/a2.webp`), '가짜 토큰으로 지우기 거절');
await call(`/p/${ME}/a2.webp`);
r = await call('/media/delete', { method: 'POST', headers: { Authorization: 'Bearer ' + TOK, 'Content-Type': 'application/json' }, body: JSON.stringify({ paths: [`${ME}/a2.webp`, `${OTHER}/a1.jpg`, `${GROUP}/g1.jpg`] }) });
let j = await r.json(); ok(r.status === 200 && j.deleted === 1 && !r2.has(`${ME}/a2.webp`), '내 폴더 파일은 지워짐');
ok(r2.has(`${OTHER}/a1.jpg`) && r2.has(`${GROUP}/g1.jpg`), '남의 폴더·그룹 폴더 파일은 안 지워짐');
ok(!cstore.has(`https://candid-feed.com/p/${ME}/a2.webp`), '지운 파일은 캐시에서도 지움');

// ---- 버릴 파일 정리(서버) ----
await MEDIA.put(`${GROUP}/t1.jpg`, JPG, {}); await MEDIA.put(`${GROUP}/t2.jpg`, JPG, {});
r = await call('/media/trash', { method: 'POST', body: JSON.stringify({ paths: [`${GROUP}/t1.jpg`] }) }); ok(r.status === 401 && r2.has(`${GROUP}/t1.jpg`), '서버 키 없이 정리 거절');
r = await call('/media/trash', { method: 'POST', headers: { 'x-service-key': 'sb_publishable_LfUJRHztENtaEmt7YV_bzQ_iboVhvn3' }, body: JSON.stringify({ paths: [`${GROUP}/t1.jpg`] }) }); ok(r.status === 401 && r2.has(`${GROUP}/t1.jpg`), '공개 키로는 정리 거절');
r = await call('/media/trash', { method: 'POST', headers: { 'x-service-key': SERVICE }, body: JSON.stringify({ paths: [`${GROUP}/t1.jpg`, `${GROUP}/t2.jpg`] }) }); j = await r.json();
ok(r.status === 200 && j.deleted === 1 && !r2.has(`${GROUP}/t1.jpg`) && r2.has(`${GROUP}/t2.jpg`), '서버 키여도 버릴 목록에 있는 파일만 지움');

// ---- 일괄 복사 ----
supaFiles.set(`${ME}/m1.jpg`, JPG); supaFiles.set(`${ME}/m2.jpg`, JPG); await MEDIA.put(`${ME}/m2.jpg`, WEBP, {});
r = await call('/media/migrate', { method: 'POST', body: JSON.stringify({ paths: [`${ME}/m1.jpg`] }) }); ok(r.status === 401 && !r2.has(`${ME}/m1.jpg`), '서버 키 없이 일괄 복사 거절');
r = await call('/media/migrate', { method: 'POST', headers: { 'x-service-key': SERVICE }, body: JSON.stringify({ paths: [`${ME}/m1.jpg`, `${ME}/m2.jpg`, `${ME}/gone.jpg`] }) }); j = await r.json();
ok(j.copied === 1 && j.skipped === 1 && j.missing.length === 1 && r2.get(`${ME}/m1.jpg`).b.equals(JPG) && r2.get(`${ME}/m2.jpg`).b.equals(WEBP), `일괄 복사: 새 것만 복사, 이미 있는 건 그대로 (${JSON.stringify(j)})`);

// ---- 기존 기능 ----
r = await call('/auth/go?u=' + encodeURIComponent(SB + '/auth/v1/authorize?provider=apple')); ok(r.status === 302, '로그인 넘김(/auth/go) 그대로');
r = await call('/auth/go?u=https://evil.com'); ok(r.status === 400, '다른 주소로 넘김은 거절 그대로');
r = await call('/.well-known/apple-app-site-association'); ok((await r.json()).applinks, '앱 링크 파일 그대로');
r = await call('/media/xyz', { method: 'POST' }); ok(r.status === 404, '없는 API 404');
const env2 = { ...env, MEDIA: undefined }; r = await W.fetch(new Request(`https://candid-feed.com/upload/${ME}/z.jpg`, { method: 'PUT', body: JPG }), env2, ctx); ok(r.status === 503, 'R2 연결이 없으면 올리기는 503(조용히 망가지지 않음)');
console.log(fails ? `\n실패 ${fails}개` : '\n모두 통과');
process.exit(fails ? 1 : 0);
