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

// textTheme: 파스텔 팔레트/코너/결정성
{
  const a = html.indexOf('const TEXT_THEMES ='), b = html.indexOf('// 그리드·승인함 썸네일용 카드', a);
  const src = html.slice(a, b);
  const TH = new Function('DOT', src + '\nreturn { TEXT_THEMES, CORNERS, MOODS, textTheme, textThemeVars };')(() => '<dot>');
  const t1 = TH.textTheme('abc'), t2 = TH.textTheme('abc');
  eq(TH.TEXT_THEMES.length, 10, '10 pastel palettes');
  eq(TH.CORNERS.length, 4, '4 corners');
  eq(TH.MOODS.length, 6, '6 character moods');
  eq(t1.key, t2.key, 'textTheme is deterministic');
  ok(TH.TEXT_THEMES.some(t => t.key === t1.key), 'textTheme picks a palette');
  ok(TH.CORNERS.includes(t1.corner), 'textTheme picks a corner');
  ok(TH.MOODS.includes(t1.mood), 'textTheme picks a mood');
  ok(/--tbg:/.test(TH.textThemeVars(t1)) && /--tacc:/.test(TH.textThemeVars(t1)), 'textThemeVars output');
  eq(TH.textTheme({ id: 'x', theme: 'rose' }).key, 'rose', 'stored theme key is respected');
  const combos = new Set();
  for (let i = 0; i < 5000; i++) { const t = TH.textTheme('id-' + i); combos.add(t.key + '|' + t.corner + '|' + t.mood); }
  eq(combos.size, 240, '240 combinations are reachable');
}
// libMonthLabel: 잘못된 시간값 NaN 방지 + 년/월
{
  const a = html.indexOf('function libMonthLabel(sec)'), b = html.indexOf('const libDur', a);
  const tStub = (s, v) => v ? s.replace(/\{(\w+)\}/g, (m, k) => v[k] ?? m) : s;
  const F = new Function('LANG', 't', html.slice(a, b) + '\nreturn libMonthLabel;')('ko', tStub);
  eq(F(NaN), '', 'libMonthLabel guards NaN');
  eq(F(undefined), '', 'libMonthLabel guards undefined');
  eq(F(0), '', 'libMonthLabel guards zero');
  eq(F(Math.floor(new Date(2026, 10, 15).getTime() / 1000)), '2026년 11월', 'libMonthLabel year/month');
}
// albumParams: 앨범 id와 subtype을 함께 전달
{
  const line = html.match(/const albumParams = [^\n]+/)[0];
  const F = new Function(line + '\nreturn albumParams;')();
  eq(F(null, null), {}, 'no album → no params');
  eq(F('a', null), { albumId: 'a' }, 'album id only');
  eq(F(null, 202), { albumSubtype: 202 }, 'album subtype only');
  eq(F('a', 202), { albumId: 'a', albumSubtype: 202 }, 'album id + subtype');
}

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
  // 작성 화면 진입: 그룹도 사진·투표·질문 중 고를 수 있게 작성 화면부터
  has(/openCompose\(0, false, 'media', false\);/, 'group compose opens composer with mode choice');
  has(/openCompose\(0, false, 'media'\);/, 'friend compose opens composer');
  has(/const GT = S\.group \|\| null;/, 'composer detects group target');
  ok(!/if \(GT\) mode = 'media';/.test(html), 'group compose no longer forces media mode');
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
  // 작성: 새 사진 3:4, 영상 9:16
  has(/\.cmp-media\.has\.frame34 \{ aspect-ratio:3\/4;/, 'new photo composer frame is 3:4');
  has(/const FW = 900, FH = 1200, f = frameMath/, 'new photo output crops to 3:4');
  has(/classList\.toggle\('frame34', m\.kind === 'image'\)/, 'image composer uses the 3:4 frame');
  has(/\.cmp-media\.has\.frame916 \{ aspect-ratio:9\/16;/, 'video composer frame is 9:16');
  has(/classList\.toggle\('frame916', m\.kind === 'video'\)/, 'video composer uses the 9:16 frame');
  // 피드: 사진 3:4 칸 · 영상 9:16 칸, 원본은 잘리지 않게 contain, 남는 곳은 메인 색
  has(/if \(m\.tagName === 'IMG'\) return set\(3, 4\);/, 'feed photo frame is 3:4');
  has(/return set\(9, 16\);/, 'feed video frame is 9:16');
  has(/\.rcar \.carwrap\.p:not\(\.multi\) \{ aspect-ratio:3\/4;/, 'reel photo card is 3:4');
  has(/\.rcar \.slide\.p \{ aspect-ratio:3\/4;/, 'reel photo slide is 3:4');
  has(/\.rcar \.carwrap\.v:not\(\.multi\) \{ aspect-ratio:9\/16;/, 'reel video card is 9:16');
  has(/\.rcar \.slide\.v \{ aspect-ratio:9\/16;/, 'reel video slide is 9:16');
  has(/\.rcar \.stage\.fit > img \{ aspect-ratio:var\(--ar\); object-fit:contain;/, 'reel photos are contained (no crop)');
  has(/\.rcar \.stage\.fit > video \{ aspect-ratio:var\(--ar\); object-fit:contain;/, 'reel videos are contained (no crop)');
  has(/\.post-media \.stage\.fit > img, \.post-media \.stage\.fit > video \{ aspect-ratio:var\(--ar\); object-fit:contain;/, 'post media is contained (no crop)');
  has(/\.post-media \.slide\.filled, \.post-media \.carwrap\.filled \{ background:var\(--fill\);/, 'post media fills margins with main color');
  has(/function paintFill\(st, url\) \{[\s\S]*?if \(!box \|\| !url\) return;/, 'main-color fill applies outside reels');
  has(/carwrap\$\{kc\(items\[0\]\)\}/, 'reel carwrap tagged by kind');
  has(/slide\$\{kc\(m\)\}/, 'reel slide tagged by kind');
  // 피드 썸네일 격자는 무조건 3:4
  has(/\.grid button \{[^}]*aspect-ratio:3\/4/, 'feed grid thumbnails are fixed 3:4');
  ok(!/\.grid button\.(p|v) \{/.test(html), 'no per-kind grid overrides');
  // 꾸미기 틀: 사진 3:4 · 영상 9:16
  has(/\.dstage\.pic > img \{ aspect-ratio:3\/4;/, 'decorate photo frame is 3:4');
  has(/\.dstage\.vid > img \{ aspect-ratio:9\/16;/, 'decorate video frame is 9:16');
  // 영상 구간 바 위치
  {
    const pi = html.indexOf('id="pick"'), ti = html.indexOf('id="trim"'), mi = html.indexOf('id="mtools"');
    ok(pi >= 0 && ti > pi && ti < mi, 'video trim bar sits directly below the media, before thumbnails');
  }
  ok(!/frame9\b/.test(html), 'legacy 9:16 photo frame removed');
}

// 8) 앱 안 사진첩: 앨범 이동·날짜 손잡이·NaN 방지
console.log('\n[8] photo library');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/\.lib-knob \{[^}]*height:36px/, 'date handle keeps its original height');
  has(/sel\.length = 0/, 'album switch clears selection');
  has(/if \(e\.target\.closest\('\.lib-sc'\)\) return;/, 'photo grid taps do not drag the sheet');
  has(/sc\.style\.touchAction = 'pan-y'/, 'photo grid scrolls vertically');
  has(/document\.querySelectorAll\('\.libw'\)/, 'stale photo sheets are cleared');
  has(/el\.style\.pointerEvents = 'none'/, 'closing photo sheet stops blocking touches');
  has(/if \(!done\) finish\(null\)/, 'close always cleans up the sheet');
  has(/sheet\.style\.touchAction = 'pan-y'/, 'photo sheet allows native scrolling');
  has(/\.libw\.full \.lib-grab \{ opacity:\.55/, 'pull handle stays visible in full-screen library');
  ok(!/e\.target\.closest\('button'\) && !e\.target\.closest\('\.lib-cell'\)/.test(html), 'sheet can be dragged down from the header buttons');
  has(/sheet\._noClick[\s\S]{0,120}!e\.target\.closest\('\.lib-cell'\)/, 'drag from header does not trigger that button click');
  has(/\.lib-knob b \{ font-size:13px/, 'date label keeps its original 13px');
  has(/\.lib-knob \{[^}]*min-width:112px/, 'date handle is wider');
  has(/\.lib-knob::before \{[^}]*margin-right:16px/, 'space between the grip and the date');
  has(/class="lib-title" data-albums/, 'album dropdown trigger');
  has(/P\.libAlbums\(\)/, 'album list requested from native');
  has(/P\.libList\(albumParams\(album, sub\)\)/, 'selected album sends both id and subtype');
  has(/const albumParams = \(album, sub\) =>/, 'album params helper exists');
  has(/이 모음을 불러오지 못해 최근 항목으로 돌아갈게요/, 'empty album falls back to Recents');
  has(/const seq = \+\+libSeq/, 'stale album loads are ignored');
  has(/data-s=/, 'album rows carry the smart subtype');
  has(/function libMonthLabel\(sec\)/, 'year/month label helper');
  has(/Number\.isFinite\(n\)/, 'invalid timestamps are guarded (no NaN)');
  has(/libMonthLabel\(LIB\.ts\?\.\[i\]\)/, 'knob uses guarded month label');
  has(/setTimeout\(\(\) => scrub\.classList\.remove\('show'\), 1500\)/, 'date handle hides after 1.5s');
  has(/LIB\.ts\.forEach\(\(ts, i\) => \{ const l = libMonthLabel\(ts\)/, 'month buckets use year/month');
  const swift = fs.readFileSync(path.join(root, 'ios-app/ios/App/App/MediaPickerPlugin.swift'), 'utf8');
  ok(/CAPPluginMethod\(name: "libAlbums"/.test(swift), 'native libAlbums is registered');
  ok(/getString\("albumId"\)/.test(swift), 'native libList accepts albumId');
  ok(/getInt\("albumSubtype"\)/.test(swift), 'native libList accepts album subtype');
  ok(/PHAsset\.fetchAssets\(in: c, options: albumOpts\)/.test(swift), 'native album fetch avoids the mediaType filter (Videos)');
  ok(/q\.count > 0/.test(swift), 'native falls through empty album candidates');
  ok(/picked \?\? PHAsset\.fetchAssets\(with: allOpts\)/.test(swift), 'native falls back to all photos if the album is empty');
  ok(/"subtype"/.test(swift), 'native album list includes the subtype');
  ok(/PHAssetCollection\.fetchAssetCollections\(with: \.smartAlbum/.test(swift), 'native lists smart collections');
  ok(/smartAlbumUserLibrary/.test(swift), 'native skips the duplicate Recents collection');
}

// 9) Send to / Post to: 결과 수와 무관하게 화면 높이 고정(공통 목록)
console.log('\n[9] picker height');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/\.pflist \{ height:min\(52vh, 420px\); overflow:auto;/, 'picker list has a fixed height');
  has(/<div id="pdl" class="flist pflist">/, 'friend/group pickers share the fixed list');
  has(/id="pdq" placeholder="\$\{isG \?/, 'search field is shared by friend and group pickers');
  has(/function fillPickList\(\{ \$q, \$l, items, empty, attr, row, pick \}\)/, 'shared picker list/search module');
  ok((html.match(/fillPickList\(\{ \$q, \$l, items: /g) || []).length === 2, 'friend and group pickers both use fillPickList');
  has(/const rows = searchMatch\(items, \$q\.value\)/, 'shared filter uses searchMatch');
  ok(!/\.pflist \{[^}]*max-height:52vh/.test(html), 'picker list no longer shrinks with results');
}

// 10) 그룹 투표·질문 + 댓글형 다중 답변
console.log('\n[10] group polls & answers');
{
  const has = (re, msg) => ok(re.test(html), msg);
  ok(!/if \(GT\) mode = 'media';/.test(html), 'group composer allows poll/question');
  ok(!/cmp-modes intop[^>]*display:none/.test(html), 'composer mode tabs are shown for groups');
  has(/const row = \{ id: draftId, media_type: 'poll'[\s\S]{0,500}group_id: GT\.id/, 'group poll insert uses group author');
  has(/const row = \{ id: draftId, media_type: 'question'[\s\S]{0,500}group_id: GT\.id/, 'group question insert uses group author');
  has(/isGroup && !member \? t\('그룹 멤버만 투표할 수 있어요'\)/, 'group poll is limited to members');
  has(/canAnswerQuestion = p =>/, 'question answer eligibility helper');
  has(/p\?\.media_type === 'question' && me && !canAnswerQuestion\(p\)/, 'answer input hidden for ineligible users');
  has(/isQ \? t\('답변'\) : 'Comments'/, 'question comments are titled answers');
  has(/const qaHTML = p =>/, 'question card renders inline answers');
  has(/data-ansin=/, 'question card has an inline answer input');
  has(/focusAnswer/, 'question comment button focuses inline answers');
  has(/isText\(p\) \? textTile\(p\) :/, 'group grid renders poll/question tiles');
  const sql = fs.readFileSync(path.join(root, 'sql/41_group_qa.sql'), 'utf8');
  ok(/media_type in \('poll', 'question'\)/.test(sql), 'SQL allows group polls/questions');
  ok(/public\.can_post_group\(p\.group_id\)/.test(sql), 'SQL lets group members vote');
  ok(/p\.media_type <> 'question'/.test(sql), 'SQL gates question answers');
}

// 11) 투표·질문 카드 리디자인
console.log('\n[11] poll & question cards');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/const TEXT_THEMES =/, 'pastel theme palettes');
  has(/textThemeChar/, 'blue dot background character');
  has(/class="tchar \$\{t\.corner\}/, 'dot placed at a random corner');
  has(/class="cmp-qcard tcard (poll|question)"/, 'composer shows the same themed poll/question card');
  has(/cmp-qlabel/, 'composer has explicit labels');
  ok(!/머리 스타일은|우리 처음 만난/.test(html), 'example questions removed');
  ok(!/cardDots\(\$reels\)|cardDots\(ov\)/.test(html), 'wandering card dots removed');
  has(/\.rtc \{[^}]*align-items:stretch/, 'text cards fill the reel width');
  ok(!/\.rtc \{[^}]*padding-right:78px/.test(html), 'no narrow right padding');
  has(/s\.mine === i/, 'selected vote can be toggled off');
  has(/\.tchar \{[^}]*opacity:\.5/, 'background character is muted');
  has(/text-shadow:0 1px 0 rgba\(255,255,255,\.82\)/, 'titles have a light shadow for contrast');
  has(/\.from\('poll_votes'\)\.delete\(\)/, 'vote delete request');
  has(/\{n\}명/, 'vote counts per option');
  has(/const ANS = new Map/, 'answer cache');
  has(/function sendAnswer/, 'inline answer submit');
  has(/class="anslist"/, 'inline answers with profiles');
  has(/const textTheme = p =>/, 'theme derived per post');
  const sql2 = fs.readFileSync(path.join(root, 'sql/42_text_theme_vote_toggle.sql'), 'utf8');
  ok(/votes delete own/.test(sql2), 'SQL allows vote cancel');
  ok(/remove_poll_vote/.test(sql2), 'SQL supports anonymous vote cancel');
}

// 12) 사진 편집 화질(원본 기준) + 작성 화면 제스처
console.log('\n[12] image edit quality & composer gestures');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/m\.src0 \|\|= m\.editUrl \|\| m\.previewUrl/, 'cropper uses the original/edit source');
  has(/rotCanvas\(img, ed\.rot \|\| 0, EDIT_MAX\)/, 'final crop uses the high-res edit copy (capped for iPhone canvas limit)');
  has(/const EDIT_MAX = 4096;/, 'edit canvas is capped at 4096px (iPhone canvas limit ~16.7M px)');
  has(/rotCanvas\(img, ed\.rot, EDIT_MAX\)/, 'rotated preview uses the capped high-res copy');
  has(/view\.src = src;/, 'unrotated preview uses the original image');
  has(/function freeMedia[\s\S]*editUrl/, 'edit source is released');
  const swift = fs.readFileSync(path.join(root, 'ios-app/ios/App/App/MediaPickerPlugin.swift'), 'utf8');
  ok(/editPath/.test(swift), 'native export includes an edit copy');
  ok(/3024 \/ CGFloat\(max\(1, max\(a\.pixelWidth, a\.pixelHeight\)\)\)/.test(swift) && /targetSize: target/.test(swift) && !/PHImageManagerMaximumSize/.test(swift), 'native requests photos at the size it uses (<=3024px), not the full original');
  ok(/CGImageSourceCreateThumbnailAtIndex/.test(swift) && /kCGImageSourceCreateThumbnailWithTransform: true/.test(swift), 'picker photos are downsampled while decoding (keeps rotation)');
  ok(/isNetworkAccessAllowed = net/.test(swift) && /req\(false\)[\s\S]{0,200}req\(true\)/.test(swift), 'photos try the on-device copy first, then iCloud');
  ok(/notifyListeners\("libProgress"/.test(swift) && /progressHandler = \{ p, _, _, _ in progress\(p\) \}/.test(swift), 'iCloud download progress is reported to the web');
  ok(/Self\.readable\(u\)[\s\S]{0,120}keepAssets\[u\.path\] = av[\s\S]{0,40}videoInfo\(u\)/.test(swift), 'on-device videos are used in place (no full copy) when readable');
  ok(/copyItem\(at: u, to: dst\)\) != nil \? videoInfo\(dst\)/.test(swift), 'falls back to copying a video the app cannot read in place');
  ok(/deliveryMode = \.mediumQualityFormat/.test(swift), 'iCloud-only videos are downloaded as the 720p version, not the full original');
  ok(/AVAssetExportPreset1280x720/.test(swift) && !/AVAssetExportPresetHighestQuality/.test(swift), 'slow-mo videos are prepared at 720p, not a full highest-quality re-encode');
  has(/addListener\?\.\('libProgress'/, 'library sheet shows iCloud download progress');
  // Candids 보기
  has(/ov\.innerHTML = `<header class="rtop oreel-h">[\s\S]{0,400}<\/header>\s*<div class="reels" id="sreels">/, 'viewer top bar sits outside the scroller (cards cannot cover the ⋯ button)');
  has(/\[data-more\]'\)\?\.addEventListener\('click', \(\) => \{ const cur = curReel\(\$r\)/, '⋯ menu finds the current post by the screen middle');
  has(/const curReel = R => \{ const mid = R\.scrollTop \+ R\.clientHeight \/ 2/, 'curReel uses the vertical middle');
  has(/<a class="rown" href="\$\{own\.link\}"/, 'feed owner avatar sits at the top of the right column');
  ok(!/oreel-who/.test(html), 'owner avatar is no longer next to the back button');
  has(/<div class="rmsg">\$\{aface\}<div class="rmt">/, 'sender avatar sits left of the message and from line');
  has(/<a class="rav" href="\$\{feedUrl\(p\.author_id\)\}"/, 'sender avatar links to the sender feed');
  has(/data-stk-toggle[\s\S]{0,200}onclick="toggleReelStickers\(\)"/, 'sticker show/hide button under share');
  has(/function toggleReelStickers\(\)/, 'sticker toggle exists');
  has(/class="rnext" aria-label="\$\{t\('다음 사진 보기'\)\}">\$\{DOT\('down'/, 'scroll hint is the blue dot');
  ok(!/nb\.classList\.add\('quiet'\)/.test(html), 'scroll hint does not hide while scrolling');
  has(/function restoreSnapGroups\(c\)/, 'cached group membership restores so groups paint with friends');
  has(/mg: \[\.\.\.MYG\.mem\], mf: \[\.\.\.MYG\.fol\], gth: \[\.\.\.GTHUMBS\]/, 'home cache stores group membership and covers');
  has(/--fi:0s" data-k/, 'orbit items appear together (no stagger)');
  has(/prog\?\.remove\?\.\(\)/, 'progress listener is removed after export');
  ok(/let edit = Self\.resize\(img, maxSide: 3024\)/.test(swift) && !/edit = img\b/.test(swift), 'native edit copy is high-res but capped at 3024px (memory · canvas limit)');
  has(/\.page-ov \{[^}]*overflow-x:hidden/, 'composer page locks horizontal scroll');
  has(/\.cfr \{[^}]*touch-action:pan-y/, 'cropper allows vertical page scroll before zoom');
  has(/const ta = \(pts\.size > 1 \|\| ed\.z > 1\.01\) \? 'none' : 'pan-y'/, 'zoomed cropper captures one-finger drags');
  has(/if \(a\.length < 2 && ed\.z <= 1\.01\) return;/, 'dragging after zoom moves the photo');
  ok(!/class="chint"/.test(html), 'cropper has no edit hint text');
}

// 13) 최근 수정 회귀 체크
console.log('\n[13] recent fixes');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/inner\.innerHTML = ''; \$\('\.lib-empty'\)\.hidden = false/, 'album switch clears the grid while loading');
  has(/LIB\.albumSub = sub/, 'album switch stores the smart subtype');
  has(/LIB\.albumSub === a\.subtype/, 'album dropdown highlights by subtype');
  has(/removeEventListener\('pointermove', move\)/, 'library drag listeners are cleaned up');
  ok(!/Date\.now\(\) - \(sheet\._noClick \|\| 0\)/.test(html), 'taps are not ignored right after dragging the sheet');
  has(/\.composer \{[^}]*overflow-x:hidden/, 'composer locks horizontal scrolling');
  has(/\.cmp-body \{[^}]*overflow-x:hidden/, 'composer body locks horizontal scrolling');
  has(/\.mstrip \{[^}]*overscroll-behavior-x:contain/, 'media strip contains horizontal overscroll');
  has(/\.mstrip \{[^}]*touch-action:pan-x pan-y/, 'media strip allows vertical page scroll');
  has(/\.pki \{[^}]*touch-action:pan-x pan-y/, 'media thumbnails allow vertical page scroll');
  has(/\.cmp-sugs \{[^}]*overscroll-behavior-x:contain/, 'suggestion strip contains horizontal overscroll');
  has(/\.page-ov \{[^}]*overflow-y:auto/, 'composer page scrolls vertically');
  has(/if \(a\.length < 2 && ed\.z <= 1\.01\) return;/, 'after zoom, one finger moves the photo');
  has(/const ta = \(pts\.size > 1 \|\| ed\.z > 1\.01\) \? 'none' : 'pan-y'/, 'zoom switches the cropper to drag mode');
  has(/rotCanvas\(img, ed\.rot \|\| 0, EDIT_MAX\)/, 'final crop keeps the capped high-res copy');
  has(/view\.src = src;/, 'preview uses the original image');
  has(/el\.style\.pointerEvents = 'none'/, 'closing photo sheet stops blocking touches');
  has(/sel\.length = 0/, 'album switch clears selection');
  has(/\.tchar \{[^}]*opacity:\.5/, 'background character is muted for readability');
  has(/function placeReelInfo/, 'media info placement helper');
  has(/classList\.add\('below'\)/, 'info can sit directly under the media');
  has(/\.rinfo\.below \{[^}]*bottom:auto !important/, 'below-media info overrides bottom anchoring');
  has(/requestAnimationFrame\(\(\) => placeReelInfo/, 'info placement runs after media loads');
  has(/const draftId = crypto\.randomUUID\(\)/, 'composer prepares the post id up front');
  has(/const theme = textTheme\(draftId\)/, 'composer preview uses the post theme');
  has(/textThemeChar\(theme\)/, 'composer preview shows the same theme character');
  has(/id: draftId, media_type: 'poll'/, 'poll post keeps the preview id');
  has(/id: draftId, media_type: 'question'/, 'question post keeps the preview id');
  has(/const textTheme = p =>/, 'the actual post gets the same random theme from its id');
}

// 14) 빌드 25 추가 회귀: 앨범 조회 이중화/폴백, 상단 드래그, 확대 후 이동
console.log('\n[14] build 25 checks');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/P\.libList\(albumParams\(album, sub\)\)/, 'album id and subtype are sent together');
  has(/이 모음을 불러오지 못해 최근 항목으로 돌아갈게요/, 'empty album falls back to Recents');
  has(/const ta = \(pts\.size > 1 \|\| ed\.z > 1\.01\) \? 'none' : 'pan-y'/, 'zoomed cropper captures drags');
  has(/if \(a\.length < 2 && ed\.z <= 1\.01\) return;/, 'after zoom, one finger moves the photo');
  ok(!/e\.target\.closest\('button'\) && !e\.target\.closest\('\.lib-cell'\)/.test(html), 'sheet drag can start on header buttons');
  has(/sheet\._noClick[\s\S]{0,120}!e\.target\.closest\('\.lib-cell'\)/, 'header drag does not trigger the button click');
  const swift = fs.readFileSync(path.join(root, 'ios-app/ios/App/App/MediaPickerPlugin.swift'), 'utf8');
  ok(/PHAsset\.fetchAssets\(in: c, options: albumOpts\)/.test(swift), 'album fetch skips the mediaType filter');
  ok(/q\.count > 0/.test(swift), 'empty album candidates are skipped');
  ok(/picked \?\? PHAsset\.fetchAssets\(with: allOpts\)/.test(swift), 'album fetch falls back to all photos');
}

// 15) 당겨서 새로고침 차단 + 사진 작성 캡션 제거 (비디오 무관 수정)
console.log('\n[15] pull-to-refresh & composer cleanup');
{
  const has = (re, msg) => ok(re.test(html), msg);
  has(/const blocked = .*\.composer, \.page-ov, \.libw/, 'pull-to-refresh is disabled in library/composer');
  ok(!/\.page-ov \{[^}]*overscroll-behavior-y:contain/.test(html), 'composer is not scroll-locked by overscroll-behavior-y');
  has(/\.page-ov \{[^}]*overflow-y:auto/, 'composer page remains the vertical scroller');
  has(/\.lib-h \{[^}]*touch-action:none/, 'library header owns its drag gesture');
  has(/id="text"/, 'media composer has a message field');
  has(/\{name\}에게 한마디…/, 'message field has a recipient placeholder');
  ok(!/id="sugs"/.test(html), 'media composer suggestion chips remain removed');
  has(/text: \$\('#text'\)\?\.value\.trim\(\) \|\| null/, 'media posts have no caption when removed');
  has(/const ok = await ask\(GT[\s\S]{0,220}이 피드를 올릴까요\?/, 'send asks for confirmation before upload');
  has(/if \(!ok\) return;[\s\S]{0,40}\$send\.disabled = true/, 'cancel keeps the composer from sending');
}

// 16) 보관함: 내가 보낸 피드 + 승인 전 보내기 취소
console.log('\n[16] inbox sent posts & cancel');
{
  const has = (re, msg) => ok(re.test(html), msg);
  const sql43 = fs.readFileSync(path.join(root, 'sql/43_my_sent_posts.sql'), 'utf8');
  ok(/create or replace function public\.my_sent_posts/.test(sql43), 'SQL provides my_sent_posts');
  ok(/p\.author_id = auth\.uid\(\)/.test(sql43), 'sent posts are scoped to the logged-in author');
  ok(/p\.status = 'pending'/.test(sql43), 'sent list only includes pending');
  has(/SENT\.items = error \? \[\] : \(data \|\| \[\]\)\.filter\(x => x\.status === 'pending'\)/, 'approved sent posts are hidden in the inbox');
  ok(/and status = 'pending'/.test(sql43), 'cancel only deletes pending sends');
  ok(/already_approved/.test(sql43), 'approved sends return already_approved');
  has(/>\$\{t\('내가 보낸 피드'\)\}</, 'inbox shows my sent feed');
  has(/async function cancelSentPost/, 'sent pending rows can be canceled');
  has(/p\.status === 'pending' \? `<div class="ab"><button class="btn" onclick="cancelSentPost/, 'cancel button is only on pending rows');
  has(/SENT\.uid !== uid\) loadSent\(\)/, 'sent feed loads for the current owner');
  ok(!/author \? it\(t\('보낸 사진 삭제'\)/.test(html), 'author cannot delete an approved sent post');
  ok(!/_more|장 더 올라왔어요/.test(html), 'group posts are no longer collapsed');
  has(/const stage = v\.closest\('\.stage'\) \|\| reel/, 'video bar is anchored to the video stage');
  has(/\.rcar \.stage > \.vbar \{[^}]*bottom:0/, 'video bar sits exactly at the video bottom');
}

// 17) 투표·질문 작성: 같은 문구, 추가 박스/테두리 없음
console.log('\n[17] poll/question composer prompt');
{
  const has = (re, msg) => ok(re.test(html), msg);
  ok(!/질문을 적어 주세요/.test(html), 'old question prompt is removed');
  has(/\$\('#pq'\)\.value\.trim\(\)\.length >= 1 && opts\.length >= 2/, 'poll allows a one-character question');
  has(/\$\('#qq'\)\.value\.trim\(\)\.length >= 1/, 'question allows one character');
  ok((html.match(/placeholder="\$\{t\('무엇을 물어볼까요\?'\)\}"/g) || []).length >= 2, 'poll and question use the same prompt');
  ok(!/\.cmp-qcard \.cmp-cap\.big \{[^}]*box-shadow:inset/.test(html), 'poll/question field has no box or border');
  ok(!/\.cmp-qcard \.cmp-cap\.big:focus/.test(html), 'poll/question field has no focus border');

  has(/host\.addEventListener\('touchmove', blockScroll, \{ passive: false \}\)/, 'two-finger pinch blocks page scroll');
  has(/raf = requestAnimationFrame\(\(\) => \{ raf = 0; paint\(\); \}\)/, 'cropper paints at most once per frame');
  ok(!/class="cmp-who"\$\{GT \? ' style="display:none"'/.test(html), 'sender block is visible for groups too');
  has(/id="text"[\s\S]{0,4000}class="cmp-who"/, 'sender block sits below the message field');
  has(/const blockPageZoom = e => e\.preventDefault\(\)/, 'page pinch zoom is blocked globally');
  has(/maximum-scale=1, user-scalable=no/, 'viewport disables page scaling');
  has(/input, textarea, select \{ font-size:max\(16px, 1em\) !important; \}/, 'iOS form controls stay at least 16px');
  has(/\.cmp-media\.has\.frame34 \{[^}]*width:min\(45vh, 45dvh, 465px\)[^}]*max-width:100%/, 'composer photo frame is centered within the viewport');
  const vc = fs.readFileSync(path.join(root, 'ios-app/ios/App/App/AppViewController.swift'), 'utf8');
  ok(/pinchGestureRecognizer\?\.isEnabled = false/.test(vc), 'native page pinch zoom is disabled');
  const i18n = ['en', 'ja'].map(l => fs.readFileSync(path.join(root, `i18n/${l}.js`), 'utf8')).join('\n');
  ok(!/다음 머리 스타일|처음 만난 날/.test(i18n), 'poll/question example prompts are removed from every language');
}

console.log('\n' + (failed ? `FAILED: ${failed} check(s)` : 'ALL TESTS PASSED'));
if (require.main === module) process.exit(failed ? 1 : 0);
else if (failed) throw new Error('candid pre-build tests failed');
