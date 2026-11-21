// candid. 빌드 전 필수 테스트 (외부 의존성 없음) — node tests/run-tests.js
//  · 모든 인라인 스크립트 문법
//  · 공통 모듈(normSearch/searchMatch/recentPosts/memberSub/memberWho) 단위 동작
//  · 친구/그룹 작성 진입 공통화(시트 닫기 → composeTarget)
//  · 은하 이름(Blue/Pink/Purple Orbit)
//  · i18n 누락 0
const fs = require('fs'), path = require('path'), { spawnSync } = require('child_process');
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
let failed = 0;
const ok = (cond, msg) => { if (cond) console.log('  ✓ ' + msg); else { failed++; console.error('  ✗ ' + msg); } };
const eq = (a, b, msg) => ok(JSON.stringify(a) === JSON.stringify(b), msg + (JSON.stringify(a) === JSON.stringify(b) ? '' : `\n     got ${JSON.stringify(a)}\n     want ${JSON.stringify(b)}`));

// 1) 인라인 스크립트 문법
console.log('\n[1] inline script syntax');
{
  const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let m, n = 0;
  while ((m = re.exec(html))) {
    if (/\bsrc=/.test(m[1] || '')) continue;
    n++;
    try { new Function(m[2]); ok(true, 'script #' + n + ' parses'); }
    catch (e) { ok(false, 'script #' + n + ' syntax: ' + e.message); }
  }
  ok(n === 4, 'found 4 inline scripts (got ' + n + ')');
}

// 2) 공통 모듈 추출 + 단위 테스트
console.log('\n[2] shared helpers');
const start = html.indexOf('const normSearch =');
const mw = html.indexOf('const memberWho =');
const end = mw >= 0 ? html.indexOf('\n', mw) : -1;
if (start < 0 || end < 0) { ok(false, 'helper block not found'); }
const snippet = html.slice(start, end);
const factory = new Function('sb', 'GPOST_COLS', 'POST_COLS', 'II', 't', 'ago', 'feedUrl', 'avatar', 'esc',
  snippet + '\nreturn { normSearch, searchMatch, recentPosts, memberSub, memberWho };');
const calls = [];
const sb = { from: t => { const q = { t, a: [] }; calls.push(q); const add = (k, v) => { q.a.push([k, v]); return q; }; q.select = c => add('select', c); q.eq = (k, v) => add('eq', [k, v]); q.in = (k, v) => add('in', [k, v]); q.gte = (k, v) => add('gte', [k, v]); q.order = (k, v) => add('order', [k, v]); q.limit = n => add('limit', n); return q; } };
const t = (s, v) => v ? s.replace(/\{(\w+)\}/g, (m, k) => v[k] ?? m) : s;
const H = factory(sb, 'GCOLS', 'PCOLS', { crown: 'CROWN' }, t, () => '3분 전', id => '/u/' + id, () => '<av>', s => String(s));

// normSearch
eq(H.normSearch('  @Foo '), 'foo', 'normSearch trims/case/@');
eq(H.normSearch('@'), '', 'normSearch lone @');
eq(H.normSearch(null), '', 'normSearch null-safe');

// searchMatch
const people = [
  { id: '1', name: '김하늘', handle: 'sky' },
  { id: '2', name: 'Alex', handle: 'alex_99', email: 'a@x.com' },
];
ok(H.searchMatch(people, '').length === 2, 'searchMatch empty query returns all');
eq(H.searchMatch(people, '@SKY').map(x => x.id), ['1'], 'searchMatch @handle, case-insensitive');
eq(H.searchMatch(people, 'alex').map(x => x.id), ['2'], 'searchMatch name/handle');
eq(H.searchMatch(people, 'a@x.com').length, 0, 'searchMatch ignores email by default');
eq(H.searchMatch(people, 'a@x.com', { email: true }).map(x => x.id), ['2'], 'searchMatch email opt-in');
eq(H.searchMatch(people, 'zzz'), [], 'searchMatch no match');

// recentPosts (mock records into the returned chain's .a)
let q = H.recentPosts({ owner: 'u1', limit: 7 });
eq(q.t, 'posts', 'recentPosts owner table');
eq(q.a, [['select', 'PCOLS'], ['eq', ['status', 'approved']], ['eq', ['owner_id', 'u1']], ['order', ['approved_at', { ascending: false }]], ['limit', 7]], 'recentPosts owner query shape');
q = H.recentPosts({ group: 'g1', since: 'S', cols: 'C' });
eq(q.a, [['select', 'C'], ['eq', ['status', 'approved']], ['eq', ['group_id', 'g1']], ['eq', ['flagged', false]], ['gte', ['approved_at', 'S']], ['order', ['approved_at', { ascending: false }]], ['limit', 20]], 'recentPosts group query shape');
q = H.recentPosts({ owner: ['a', 'b'] });
ok(q.a.some(x => x[0] === 'in' && x[1][0] === 'owner_id'), 'recentPosts owner array uses in()');
q = H.recentPosts({ group: ['a', 'b'] });
ok(q.a.some(x => x[0] === 'in' && x[1][0] === 'group_id') && q.a.some(x => x[0] === 'eq' && x[1][0] === 'flagged'), 'recentPosts group array uses in()+flagged');

// memberSub / memberWho
eq(H.memberSub({ role: 'owner' }), 'CROWN 방장', 'memberSub owner');
eq(H.memberSub({ role: 'member', status: 'pending', created_at: 'x', prof: {} }, true), '3분 전 신청', 'memberSub pending with time');
eq(H.memberSub({ role: 'member', status: 'active', prof: { handle: 'sky' } }), '@sky', 'memberSub handle');
eq(H.memberSub({ role: 'member', status: 'active', prof: {} }), '', 'memberSub empty');
const who = H.memberWho({ user_id: 'u9', role: 'member', prof: { name: '<b>', handle: 'h' } });
ok(who.includes('/u/u9') && who.includes('<av>') && who.includes('&lt;b&gt;') === false && who.includes('<b>'), 'memberWho links feed/avatar/name');

// 3) 친구/그룹 작성 진입 공통화
console.log('\n[3] compose unification');
ok(/const choose = target => \{ closeSheet\(\); setTimeout\(\(\) => composeTarget\(target\), 200\); \};/.test(html), 'picker closes sheet then composeTarget');
ok(/function pickFriendToSend\(\) \{ return pickDestination\('friend'\); \}/.test(html), 'pickFriendToSend delegates');
ok(/function pickGroupToPost\(\) \{ return pickDestination\('group'\); \}/.test(html), 'pickGroupToPost delegates');
ok(/function composeToGroup\(g\) \{ if \(g\) composeTarget\(\{ group: g \}\); \}/.test(html), 'composeToGroup delegates');
ok(/function composeTo\(prof\) \{ composeTarget\(prof\); \}/.test(html), 'composeTo delegates');

// 4) 은하 이름
console.log('\n[4] galaxy names');
ok(/name: 'Blue Orbit'/.test(html) && /name: 'Pink Orbit'/.test(html) && /name: 'Purple Orbit'/.test(html), 'Blue/Pink/Purple Orbit names');
ok(!/name: '[^']*은하'/.test(html), 'no Korean galaxy display names remain');

// 5) i18n 누락 0
console.log('\n[5] i18n');
{
  const r = spawnSync(process.execPath, [path.join(root, 'tools', 'i18n-check.js')], { encoding: 'utf8' });
  ok(r.status === 0, 'tools/i18n-check.js passes' + (r.status ? '\n' + (r.stdout || '') + (r.stderr || '') : ''));
}

// 6) 화면 이동·동선(플로우) 배선
console.log('\n[6] flow wiring');
{
  const has = (re, msg) => ok(re.test(html), msg);
  // ⊕ 만들기 → 친구/그룹 대상 선택
  has(/setTimeout\(pickFriendToSend,250\)/, 'create sheet opens friend picker');
  has(/setTimeout\(pickGroupToPost,250\)/, 'create sheet opens group picker');
  has(/const choose = target => \{ closeSheet\(\); setTimeout\(\(\) => composeTarget\(target\), 200\); \};/, 'destination picker closes sheet then composes');
  has(/choose\(\{ group: MYG\.groups\.get\(b\.dataset\.g\) \}\)/, 'group row select → compose target(group)');
  has(/choose\(list\.find\(x => x\.id === b\.dataset\.id\)\)/, 'friend row select → compose target(profile)');
  // 작성 화면 진입: 그룹은 바로 사진첩(pick), 친구는 일반
  has(/openCompose\(0, false, 'media', true\);/, 'group compose opens media picker directly');
  has(/openCompose\(0, false, 'media'\);/, 'friend compose opens composer');
  has(/const GT = S\.group \|\| null;/, 'composer detects group target');
  has(/if \(GT\) mode = 'media';/, 'group compose forces media mode');
  // 그룹 화면 → 사진 올리기
  has(/onclick="composeToGroup\(G\.g\)"/, 'group page upload buttons enter composeToGroup');
  // 궤도(홈) 탭 동선
  has(/if \(x\.trend\) return openTrending\(x\);/, 'orbit tap on trending opens source');
  has(/if \(!x\.posts\.length\) return go\(x\.g \? gUrl\(x\.g\) : feedUrl\(x\.o\.id\)\);/, 'orbit tap without posts navigates to feed/group');
  has(/openOrbitStack\(x\);/, 'orbit tap with posts opens stack');
  // 트렌딩 → 최근 사진 → 보기 / 없으면 이동
  has(/x\.g \? recentPosts\(\{ group: x\.g\.id, limit: 20 \}\) : recentPosts\(\{ owner: x\.o\.id, limit: 20 \}\)/, 'trending fetches recent posts by source');
  has(/if \(error \|\| !data\?\.length\) return go\(x\.g \? gUrl\(x\.g\) : feedUrl\(x\.o\.id\)\);/, 'trending empty/error falls back to source page');
  has(/openOrbitStack\(\{ \.\.\.x, posts: data \}, x\.o\);/, 'trending with posts opens stack');
  // 검색 결과 링크 → 피드/그룹
  has(/listRow\(\{ href: feedUrl\(p\.id\)/, 'people rows link to feed');
  has(/href="\$\{gUrl\(g\)\}"/, 'group rows link to group page');
  // 그룹 관리 동선: 승인/거절/더보기
  has(/data-ok="\$\{m\.user_id\}"/, 'manage renders approve action');
  has(/data-no="\$\{m\.user_id\}"/, 'manage renders reject action');
  has(/data-more="\$\{m\.user_id\}"/, 'manage renders member more action');
  // 빈 목록에서 다음 동선
  has(/setTimeout\(openSearch,250\)/, 'empty friend picker offers search');
  has(/setTimeout\(openCreateGroup,250\)/, 'empty group picker offers create');
}

// 7) 미디어 기본 비율 (사진 3:4 · 영상은 기존 유지)
console.log('\n[7] media ratios');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/\.cmp-media\.has\.frame34 \{ aspect-ratio:3\/4;/, 'photo composer frame is 3:4');
  has(/const FW = 900, FH = 1200, f = frameMath/, 'photo output crops to 3:4');
  has(/classList\.toggle\('frame34', m\.kind === 'image'\)/, 'image uses the 3:4 frame');
  has(/if \(m\.tagName === 'IMG'\) return set\(3, 4\);/, 'uploaded photos display at 3:4 (incl. existing)');
  has(/return set\(9, 16\);/, 'videos display at 9:16');
  has(/\.rcar \.stage > img \{[^}]*aspect-ratio:3\/4/, 'reel photo default is 3:4');
  has(/\.rcar \.stage > video \{[^}]*aspect-ratio:9\/16/, 'reel video default is 9:16');
  has(/\.rcar \.carwrap\.p:not\(\.multi\) \{ aspect-ratio:3\/4;/, 'reel photo card is 3:4');
  has(/\.rcar \.carwrap\.v:not\(\.multi\) \{ aspect-ratio:9\/16;/, 'reel video card is 9:16');
  has(/\.rcar \.slide\.p \{ aspect-ratio:3\/4;/, 'reel photo slide is 3:4');
  has(/\.rcar \.slide\.v \{ aspect-ratio:9\/16;/, 'reel video slide is 9:16');
  has(/carwrap\$\{kc\(items\[0\]\)\}/, 'reel carwrap tagged by kind');
  has(/slide\$\{kc\(m\)\}/, 'reel slide tagged by kind');
  has(/\.post-media \.stage > img \{[^}]*aspect-ratio:3\/4/, 'post photo default is 3:4');
  has(/\.post-media \.stage > video \{[^}]*aspect-ratio:9\/16/, 'post video default is 9:16');
  has(/\.cmp-media\.has\.frame916 \{ aspect-ratio:9\/16;/, 'video composer frame is 9:16');
  has(/classList\.toggle\('frame916', m\.kind === 'video'\)/, 'video uses the 9:16 frame');
  has(/\.grid button\.p \{ aspect-ratio:3\/4;/, 'grid photo tiles are 3:4');
  has(/\.grid button\.v \{ aspect-ratio:9\/16;/, 'grid video tiles are 9:16');
  has(/isText\(p\) \? 't' : isVideo\(p\) \? 'v' : 'p'/, 'profile grid tiles tagged by kind');
  has(/\.dstage\.pic > img \{ aspect-ratio:3\/4;/, 'decorate photo frame is 3:4');
  has(/\.dstage\.vid > img \{ aspect-ratio:9\/16;/, 'decorate video frame is 9:16');
  has(/dstage\$\{m \? \(m\.k === 'video' \? ' vid' : ' pic'\) : ' tstage'\}/, 'decorate frame tagged by kind');
  ok(!/frame9\b/.test(html), 'legacy 9:16 photo frame removed');
}

console.log('\n' + (failed ? `FAILED: ${failed} check(s)` : 'ALL TESTS PASSED'));
if (require.main === module) process.exit(failed ? 1 : 0);
else if (failed) throw new Error('candid pre-build tests failed');
