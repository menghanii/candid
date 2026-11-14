// candid. 꾸미기 아이템 카탈로그 — 여기서 수정 후 `node tools/items.js` 실행하면
// sql/08_gacha.sql 의 아이템 목록과 index.html 의 ITEM_CATALOG 가 함께 갱신됨
// kind: frame(프로필 프레임) | theme(커버 배너) | sticker(아바타 스티커) | name(이름 효과)
// rarity: common 60% · rare 30% · epic 9% · legendary 1%
const ITEMS = [
  // 프레임: bg(링 배경), glow(빛), spin(회전)
  ['frame_mint', 'frame', '민트 링', 'common', { bg: '#3ee8b5' }],
  ['frame_peach', 'frame', '피치 링', 'common', { bg: '#ffb199' }],
  ['frame_mono', 'frame', '체커 링', 'common', { bg: 'repeating-conic-gradient(#fff 0 15deg,#111 0 30deg)' }],
  ['frame_sunset', 'frame', '선셋', 'rare', { bg: 'linear-gradient(135deg,#ff7e5f,#feb47b)' }],
  ['frame_ocean', 'frame', '오션', 'rare', { bg: 'linear-gradient(135deg,#2b50ff,#00d2ff)' }],
  ['frame_neon', 'frame', '네온', 'epic', { bg: '#39ff14', glow: '#39ff14' }],
  ['frame_rainbow', 'frame', '레인보우', 'epic', { bg: 'conic-gradient(#ff3b30,#ff9500,#ffcc00,#34c759,#00c7be,#2b50ff,#af52de,#ff3b30)', spin: true }],
  ['frame_aurora', 'frame', '오로라', 'legendary', { bg: 'conic-gradient(#00ffa3,#03e1ff,#dc1fff,#ff6ec7,#00ffa3)', spin: true, glow: '#dc1fff' }],
  // 커버 테마: bg(배너 배경), stars(반짝임), film(필름 구멍)
  ['theme_sky', 'theme', '하늘', 'common', { bg: 'linear-gradient(160deg,#a1c4fd,#c2e9fb)' }],
  ['theme_peach', 'theme', '복숭아', 'common', { bg: 'linear-gradient(160deg,#ffecd2,#fcb69f)' }],
  ['theme_mint', 'theme', '풀잎', 'common', { bg: 'linear-gradient(160deg,#d4fc79,#96e6a1)' }],
  ['theme_night', 'theme', '밤하늘', 'rare', { bg: 'linear-gradient(160deg,#0f2027,#203a43,#2c5364)', stars: true }],
  ['theme_berry', 'theme', '베리', 'rare', { bg: 'linear-gradient(160deg,#8e2de2,#4a00e0)' }],
  ['theme_film', 'theme', '필름', 'epic', { bg: 'linear-gradient(160deg,#1c1c1c,#3a3a3a)', film: true }],
  ['theme_galaxy', 'theme', '갤럭시', 'legendary', { bg: 'radial-gradient(circle at 20% 30%,#ff6ec7 0,transparent 38%),radial-gradient(circle at 80% 20%,#2b50ff 0,transparent 42%),radial-gradient(circle at 60% 95%,#00ffa3 0,transparent 38%),#0b0b2a', stars: true }],
  // 스티커: e(이모지)
  ['sticker_daisy', 'sticker', '데이지', 'common', { e: '🌼' }],
  ['sticker_star', 'sticker', '별', 'common', { e: '⭐' }],
  ['sticker_clover', 'sticker', '네잎클로버', 'common', { e: '🍀' }],
  ['sticker_camera', 'sticker', '카메라', 'common', { e: '📸' }],
  ['sticker_cat', 'sticker', '고양이', 'rare', { e: '🐱' }],
  ['sticker_berry', 'sticker', '딸기', 'rare', { e: '🍓' }],
  ['sticker_unicorn', 'sticker', '유니콘', 'epic', { e: '🦄' }],
  ['sticker_fire', 'sticker', '불꽃', 'epic', { e: '🔥' }],
  ['sticker_crown', 'sticker', '왕관', 'legendary', { e: '👑' }],
  // 이름 효과: color(단색), grad(그라데이션 글자), glow(빛), anim(흐르는 효과)
  ['name_blue', 'name', '블루 네임', 'common', { color: '#2b50ff' }],
  ['name_sunset', 'name', '선셋 네임', 'rare', { grad: 'linear-gradient(90deg,#ff7e5f,#feb47b)' }],
  ['name_glow', 'name', '글로우 네임', 'epic', { glow: '#5c7cff' }],
  ['name_holo', 'name', '홀로그램 네임', 'legendary', { grad: 'linear-gradient(90deg,#00ffa3,#03e1ff,#dc1fff,#ff6ec7,#00ffa3)', anim: true }],
];

if (require.main === module) {
  const fs = require('fs'), path = require('path'), root = path.join(__dirname, '..');
  const q = s => `'${String(s).replace(/'/g, "''")}'`;
  // 1) SQL 아이템 목록 갱신 (sql/08_gacha.sql 의 마커 사이)
  const sqlPath = path.join(root, 'sql/08_gacha.sql');
  const rows = ITEMS.map(([id, k, n, r, d], i) => `  (${q(id)}, ${q(k)}, ${q(n)}, ${q(r)}, ${q(JSON.stringify(d))}::jsonb, ${i})`).join(',\n');
  let sql = fs.readFileSync(sqlPath, 'utf8');
  sql = sql.replace(/-- @@ITEMS-BEGIN[\s\S]*?-- @@ITEMS-END/, `-- @@ITEMS-BEGIN (tools/items.js 에서 자동 생성 — 직접 고치지 말 것)
insert into public.items (id, kind, name, rarity, data, sort) values
${rows}
on conflict (id) do update set kind = excluded.kind, name = excluded.name, rarity = excluded.rarity, data = excluded.data, sort = excluded.sort, active = true;
-- @@ITEMS-END`);
  fs.writeFileSync(sqlPath, sql);
  // 2) 앱 카탈로그 갱신 (index.html 의 마커 사이)
  const htmlPath = path.join(root, 'index.html');
  let html = fs.readFileSync(htmlPath, 'utf8');
  html = html.replace(/\/\/ @@CATALOG-BEGIN[\s\S]*?\/\/ @@CATALOG-END/, `// @@CATALOG-BEGIN (tools/items.js 에서 자동 생성 — 직접 고치지 말 것)
const ITEM_CATALOG = ${JSON.stringify(ITEMS.map(([id, kind, name, rarity, data]) => ({ id, kind, name, rarity, data })))};
// @@CATALOG-END`);
  fs.writeFileSync(htmlPath, html);
  console.log(`items: ${ITEMS.length} → sql/08_gacha.sql, index.html`);
}
module.exports = ITEMS;
