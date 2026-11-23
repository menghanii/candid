// 예전 사진·영상(Supabase photos 저장소)을 Cloudflare R2 로 한 번에 복사
// 실행: node tools/migrate-r2.mjs            (저장소 루트에서. 몇 번 다시 돌려도 이미 옮긴 파일은 건너뜀)
//      node tools/migrate-r2.mjs --dry-run  (목록만 세어 봄)
// 필요한 것: secrets.local.env 에 SUPABASE_SERVICE_ROLE_KEY=… (git 에 안 올라감). 키는 화면에 출력하지 않음
// 워커(/media/migrate)는 이 키로 서버 전용 표(storage_trash)를 읽어 보고 서버 키일 때만 복사함
import { readFileSync } from 'node:fs';

const SB = 'https://erlrviaqnnlfeehizlxc.supabase.co';
const API = process.env.MEDIA_API || 'https://candid-feed.com';
const DRY = process.argv.includes('--dry-run');
const env = Object.fromEntries(readFileSync(new URL('../secrets.local.env', import.meta.url), 'utf8').split('\n')
  .map(l => l.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map(m => [m[1], m[2].replace(/^["']|["']$/g, '')]));
const KEY = env.SUPABASE_SERVICE_ROLE_KEY;
if (!KEY) { console.error('secrets.local.env 에 SUPABASE_SERVICE_ROLE_KEY 가 없어요'); process.exit(1); }
const H = KEY.split('.').length === 3 ? { apikey: KEY, Authorization: `Bearer ${KEY}` } : { apikey: KEY };

async function list(prefix) {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await fetch(`${SB}/storage/v1/object/list/photos`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }) });
    if (!r.ok) throw new Error(`목록 읽기 실패 ${r.status}`);
    const rows = await r.json();
    out.push(...rows);
    if (rows.length < 1000) return out;
  }
}

const files = [];
for (const d of await list('')) {
  if (d.id) continue; // 폴더만(맨 위에는 파일이 없음)
  for (const f of await list(d.name)) if (f.id) files.push({ path: `${d.name}/${f.name}`, size: f.metadata?.size || 0 });
}
const total = files.reduce((s, f) => s + f.size, 0);
console.log(`예전 저장소 파일 ${files.length}개 · ${(total / 1024 / 1024).toFixed(1)}MB`);
if (DRY) process.exit(0);

const sum = { copied: 0, skipped: 0, missing: 0, failed: 0 };
for (let i = 0; i < files.length; i += 20) {
  const paths = files.slice(i, i + 20).map(f => f.path);
  const r = await fetch(`${API}/media/migrate`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-service-key': KEY }, body: JSON.stringify({ paths }) });
  if (r.status === 401) { console.error('워커가 서버 키를 거절했어요(키 확인)'); process.exit(1); }
  if (!r.ok) { sum.failed += paths.length; continue; }
  const j = await r.json();
  sum.copied += j.copied; sum.skipped += j.skipped; sum.missing += j.missing.length;
  process.stdout.write(`\r${Math.min(i + 20, files.length)}/${files.length}`);
}
console.log(`\n복사 ${sum.copied} · 이미 있음 ${sum.skipped} · 원본 없음 ${sum.missing} · 실패 ${sum.failed}${sum.failed ? ' (다시 돌리면 실패한 것만 이어서 함)' : ''}`);
