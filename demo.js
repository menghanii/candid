// candid. 데모 모드 전용: Supabase 설정이 비어 있을 때 index.html 이 이 파일을 불러와 샘플 데이터로 동작(서버에 아무것도 안 씀)
// ---------- 데모 모드 (Supabase 설정 전, 샘플 데이터로 화면 확인용) ----------
function demoClient() {
  const ss = { get: k => { try { return sessionStorage.getItem(k); } catch { return null; } },
               set: (k, v) => { try { sessionStorage.setItem(k, v); } catch {} } };
  const ME = { id: 'demo', user_metadata: { name: '민수' } };
  const tones = [['#f6d5c4','#e9967a'],['#d9dfe8','#8fa3bf'],['#e8e2c8','#b8a970'],['#d8e5d3','#7fa27a'],['#ecd3df','#b9789a'],
                 ['#d4e4ea','#5f97ad'],['#efe0c9','#d08a4e'],['#e1dbef','#8a7cc0'],['#f1d9d2','#c0665a'],['#dde3d6','#95a07f'],['#e7dccd','#a88864'],['#d5dde9','#6c7fa8']];
  const art = (i) => {
    const [a, b] = tones[i % tones.length], cx = 30 + (i * 37) % 60, cy = 25 + (i * 23) % 40;
    return 'data:image/svg+xml;utf8,' + encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1000"><defs><linearGradient id="g" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs>`
      + `<rect width="800" height="1000" fill="url(#g)"/><circle cx="${cx * 8}" cy="${cy * 10}" r="${120 + i * 9 % 90}" fill="#fff" opacity=".35"/>`
      + `<rect y="720" width="800" height="280" fill="${b}" opacity=".45"/></svg>`);
  };
  const H = 3600e3, now = Date.now(), t = h => new Date(now - h * H).toISOString();
  const seed = [
    ['지수', MISSIONS[0], '이 표정 레전드 ㅋㅋㅋ'], ['민호', MISSIONS[1], '인생샷 인정합니다'], ['익명의 친구', MISSIONS[2], '자는 척하더니 결국 잠'],
    ['서연', MISSIONS[3], '고1 수학여행.. 기억나지?'], ['태윤', MISSIONS[4], '걸어다니는 텐션'], ['지수', MISSIONS[5], '제주도 그날'],
    ['하린', MISSIONS[1], '이건 프사 해야 됨'], ['민호', MISSIONS[0], ''], ['익명의 친구', MISSIONS[2], '집중력 1000%'],
  ].map(([author_name, mission, text], i) => ({ id: 'a' + i, owner_id: 'demo', author_name, mission, text, image_path: art(i),
      status: 'approved', created_at: t(i * 20 + 30), approved_at: t(i * 20 + 5) }));
  const pend = [['서연', MISSIONS[0], '이거 올려도 되지? ㅎㅎ'], ['익명의 친구', MISSIONS[3], '중2 때 사진 발견함'], ['하린', MISSIONS[1], '우리 학교 축제 때']]
    .map(([author_name, mission, text], i) => ({ id: 'p' + i, owner_id: 'demo', author_name, mission, text, image_path: art(9 + i),
      status: 'pending', created_at: t(i * 2 + .3), approved_at: null }));
  // 친구 2명(f1, f2)의 피드 — 홈 릴스 데모용
  const fposts = [['f1', '지수', MISSIONS[0], '오늘 지수 표정 실화냐', 0.5], ['f2', '태윤', MISSIONS[2], '몰래 찍었는데 너무 잘 나옴', 2], ['f1', '민수', MISSIONS[1], '이건 인정이지', 5], ['f2', '하린', MISSIONS[3], '중학교 졸업식 ㅋㅋ', 9]]
    .map(([owner_id, author_name, mission, text, h], i) => ({ id: 'f' + i, owner_id, author_name, mission, text, image_path: art(3 + i * 2), status: 'approved', created_at: t(h + 1), approved_at: t(h) }));
  let db; try { db = JSON.parse(ss.get('demo_db2')); } catch {}
  db = db || {
    profiles: [{ id: 'demo', name: '민수', handle: 'minsu', avatar_url: null, onboarded: true, is_private: false }, { id: 'f1', name: '지수', handle: 'jisoo', avatar_url: null, onboarded: true, bio: '굴욕샷 환영' }, { id: 'f2', name: '태윤', handle: 'taeyun', avatar_url: null, onboarded: true }],
    posts: [...seed, ...pend, ...fposts],
    follows: [{ follower_id: 'demo', followee_id: 'f1' }, { follower_id: 'demo', followee_id: 'f2' }],
    likes: [{ post_id: 'f0', user_id: 'f2' }, { post_id: 'f0', user_id: 'f1' }, { post_id: 'f1', user_id: 'f1' }],
    comments: [{ id: 'c1', post_id: 'f0', user_id: 'f2', body: '이거 진짜 레전드다 ㅋㅋㅋ', created_at: t(0.3) }],
    poll_votes: [{ post_id: 'q1', voter_key: 'u:f2', option: 0 }, { post_id: 'q1', voter_key: 'g:x1', option: 1 }, { post_id: 'q1', voter_key: 'g:x2', option: 0 }],
  };
  // 투표·질문 데모: 지수 피드의 투표, 태윤 피드의 답한 질문, 내(민수) 승인함의 질문
  db.posts.push(
    { id: 'q1', owner_id: 'f1', author_name: '태윤', mission: '투표', media_type: 'poll', text: '지수 다음 머리 스타일은?', poll_options: ['단발 가자', '지금이 최고', '탈색 도전'], status: 'approved', created_at: t(0.9), approved_at: t(0.8) },
    { id: 'q2', owner_id: 'f2', author_name: '하린', mission: '질문', media_type: 'question', text: '우리 처음 만난 날 기억나?', answer: '당연하지 ㅋㅋ 신입생 OT에서 네가 길 잃어서 내가 데려다줌', status: 'approved', created_at: t(1.6), approved_at: t(1.5) },
    { id: 'q3', owner_id: 'demo', author_name: '지수', mission: '질문', media_type: 'question', text: '요즘 제일 빠져 있는 거 뭐야?', status: 'pending', created_at: t(0.2), approved_at: null },
  );
  // 여러 장 게시물·스티커 데모: 지수 피드에 3장짜리 게시물, 내 스티커 몇 개, 이미 붙은 친구 스티커
  db.posts.push({ id: 'm1', owner_id: 'f1', author_name: '하린', mission: null, text: '제주도 3박 4일 요약', media_type: 'image',
    media: [1, 5, 8].map(i => ({ p: art(i), t: art(i), k: 'image' })), image_path: art(1), thumb_path: art(1), status: 'approved', created_at: t(0.5), approved_at: t(0.45) });
  if (!db.inventory || !db.inventory.length) db.inventory = ['sticker_star', 'sticker_cat', 'sticker_crown', 'sticker_fire'].map(item_id => ({ user_id: 'demo', item_id, count: 1 }));
  if (!db.post_stickers) db.post_stickers = [
    { id: 's1', post_id: 'm1', media_idx: 0, user_id: 'f2', item_id: 'sticker_fire', x: 0.78, y: 0.7, scale: 1 },
    { id: 's2', post_id: 'a0', media_idx: 0, user_id: 'f1', item_id: 'sticker_crown', x: 0.3, y: 0.25, scale: 1.2 }];
  // 그룹 데모: 지수가 만든 공개 그룹(나는 멤버), 내가 만든 비공개 그룹(태윤이 참여 신청)
  if (!db.groups) {
    db.groups = [
      { id: 'g1', handle: 'jisoo_bday', name: '지수 생일파티 🎂', bio: '11/21 홍대 · 찍은 사진 다 올려줘!', cover_path: null, owner_id: 'f1', visibility: 'public', join_mode: 'open', closed: false, daily_limit: 10, member_count: 3, follower_count: 3, invite_code: 'demoinvite01', created_at: t(30) },
      { id: 'g2', handle: 'family_trip', name: '우리 가족 제주 여행', bio: '2026 여름', cover_path: null, owner_id: 'demo', visibility: 'private', join_mode: 'approval', closed: false, daily_limit: 10, member_count: 2, follower_count: 2, invite_code: 'demoinvite02', created_at: t(60) }];
    db.group_members = [
      { group_id: 'g1', user_id: 'f1', role: 'owner', status: 'active', created_at: t(30) }, { group_id: 'g1', user_id: 'f2', role: 'member', status: 'active', created_at: t(20) },
      { group_id: 'g1', user_id: 'demo', role: 'member', status: 'active', created_at: t(10) },
      { group_id: 'g2', user_id: 'demo', role: 'owner', status: 'active', created_at: t(60) }, { group_id: 'g2', user_id: 'f1', role: 'member', status: 'active', created_at: t(50) },
      { group_id: 'g2', user_id: 'f2', role: 'member', status: 'pending', created_at: t(0.4) }];
    db.group_follows = [{ group_id: 'g1', user_id: 'f1', notify: true }, { group_id: 'g1', user_id: 'f2' }, { group_id: 'g1', user_id: 'demo' }, { group_id: 'g2', user_id: 'demo', notify: true }, { group_id: 'g2', user_id: 'f1' }];
    [['g1', 'f1', '지수', '케이크 등장 🎂', 0.7, 2], ['g1', 'f2', '태윤', '단체샷 건짐', 1.2, 4], ['g1', 'demo', '민수', '', 3, 6], ['g1', 'f2', '태윤', '2차 노래방', 4, 7],
     ['g2', 'demo', '민수', '성산일출봉', 26, 8], ['g2', 'f1', '지수', '흑돼지 최고', 27, 10], ['g2', 'demo', '민수', '', 28, 11]]
      .forEach(([group_id, author_id, author_name, text, h, i], k) => db.posts.push({ id: 'gp' + k, owner_id: null, group_id, author_id, author_name, text, image_path: art(i), media_type: 'image', status: 'approved', created_at: t(h), approved_at: t(h), pinned_at: k === 1 ? t(1) : null, flagged: false }));
  }
  db.posts = db.posts.filter((p, i, a) => a.findIndex(x => x.id === p.id) === i);
  const persist = () => ss.set('demo_db2', JSON.stringify(db));
  const demoCanView = gid => { const g = db.groups.find(x => x.id === gid); return !!g && (g.visibility === 'public' || (loggedIn() && db.group_members.some(m => m.group_id === gid && m.user_id === ME.id && m.status === 'active'))); };
  const loggedIn = () => ss.get('demo_login') === '1';
  if (cfg.DEMO_AUTO_LOGIN && ss.get('demo_login') == null) ss.set('demo_login', '1'); // 개발용 앱: 로그인 없이 바로 데모 계정으로
  const files = {};

  function from(table) {
    let op = 'select', payload, single = false, order = null, lim = 0, sel = false; const filters = [];
    const run = () => {
      db[table] = db[table] || [];
      let rows = db[table].filter(r => filters.every(([k, v, how]) => how === 'in' ? v.includes(r[k]) : how === 'neq' ? r[k] !== v : how === 'gte' ? (r[k] || '') >= v : how === 're' ? v.test(r[k] || '') : how === 'or' ? v.some(([c, re]) => re.test(r[c] || '')) : how === 'is' ? (r[k] ?? null) === v : how === 'notnull' ? r[k] != null : r[k] === v));
      if (op === 'insert' && Array.isArray(payload)) { // 여러 개 한 번에 추가
        const all = payload; for (const p of all) { payload = p; run(); } return { data: null, error: null };
      }
      if (op === 'insert') {
        const row = { id: 'x' + Math.random().toString(36).slice(2), created_at: new Date().toISOString(), ...payload };
        if (table === 'posts') Object.assign(row, { status: 'pending', approved_at: null, ...payload });
        if (table === 'posts' && row.group_id) Object.assign(row, { owner_id: null, status: 'approved', approved_at: row.created_at, flagged: false, pinned_at: null });
        if (table === 'groups') {
          if (db.groups.filter(g => g.owner_id === ME.id).length >= GROUP_OWN_MAX) return { data: null, error: { message: 'group_limit' } };
          if (db.groups.some(g => g.handle === row.handle)) return { data: null, error: { message: 'duplicate key value violates unique constraint "groups_handle_key"', code: '23505' } };
          Object.assign(row, { owner_id: ME.id, closed: false, daily_limit: 10, member_count: 1, follower_count: 1, cover_path: null, invite_code: Math.random().toString(36).slice(2, 14), join_mode: row.visibility === 'private' ? 'approval' : row.join_mode });
          db.group_members.push({ group_id: row.id, user_id: ME.id, role: 'owner', status: 'active', created_at: row.created_at });
          db.group_follows.push({ group_id: row.id, user_id: ME.id, notify: true });
        }
        if (table === 'likes' || table === 'comments') row.user_id = row.user_id || ME.id;
        if (table === 'follows') row.follower_id = row.follower_id || ME.id;
        ['image_path', 'thumb_path'].forEach(k => { if (files[row[k]]) row[k] = files[row[k]]; }); // 새로고침해도 사진 유지
        db[table].push(row); persist(); return { data: sel ? (single ? row : [row]) : null, error: null };
      }
      if (op === 'update') { rows.forEach(r => Object.assign(r, payload)); persist(); return { data: null, error: null }; }
      if (op === 'delete') { db[table] = db[table].filter(r => !rows.includes(r)); persist(); return { data: null, error: null }; }
      if (table === 'posts') rows = rows.filter(r => r.group_id
        ? (!r.flagged && r.status === 'approved' && demoCanView(r.group_id)) || (loggedIn() && (r.author_id === ME.id || db.groups.find(g => g.id === r.group_id)?.owner_id === ME.id))
        : r.status === 'approved' || (loggedIn() && r.owner_id === ME.id)); // RLS 흉내
      if (table === 'groups') rows = rows.filter(g => g.visibility === 'public' || (loggedIn() && db.group_members.some(m => m.group_id === g.id && m.user_id === ME.id)));
      if ((table === 'group_members' || table === 'group_follows') && !loggedIn()) rows = rows.filter(m => table === 'group_members' && m.status === 'active' && demoCanView(m.group_id));
      if (table === 'follows' && !loggedIn()) rows = [];
      if (table === 'comments') rows = rows.map(r => ({ ...r, profiles: db.profiles.find(p => p.id === r.user_id) || null }));
      if (order) rows = [...rows].sort((a, b) => (a[order[0]] < b[order[0]] ? -1 : 1) * (order[1] ? 1 : -1));
      if (lim) rows = rows.slice(0, lim);
      return { data: single ? rows[0] || null : rows, error: null };
    };
    const b = {
      select: () => (sel = true, b), is: (k, v) => (filters.push([k, v, 'is']), b), not: (k, o, v) => (filters.push([k, v, o === 'is' && v === null ? 'notnull' : 'neq']), b), eq: (k, v) => (filters.push([k, v]), b), neq: (k, v) => (filters.push([k, v, 'neq']), b), gte: (k, v) => (filters.push([k, v, 'gte']), b), in: (k, arr) => (filters.push([k, arr, 'in']), b),
      ilike: (k, pat) => (filters.push([k, new RegExp(pat.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*'), 'i'), 're']), b),
      // or('name.ilike.%x%,handle.ilike.%x%') 흉내: 조건 중 하나라도 맞으면 통과
      or: expr => (filters.push([null, expr.split(',').map(c => { const [k, , p] = c.split('.'); return [k, new RegExp(p.replace(/%/g, '.*'), 'i')]; }), 'or']), b),
      maybeSingle: () => (single = true, b), limit: n => (lim = n, b),
      order: (k, o = {}) => (order = [k, o.ascending !== false], b),
      insert: p => (op = 'insert', payload = p, b), update: p => (op = 'update', payload = p, b), delete: () => (op = 'delete', b),
      then: (res, rej) => new Promise(r => setTimeout(r, 120)).then(run).then(res, rej),
    };
    return b;
  }
  // 비공개 피드 데모: 하린(f3)은 비공개이고 나를 추가하지 않음 → 잠김 / 서연(f4)은 나를 추가함 → 친구 탭 '나를 추가한 친구'
  if (!db.profiles.some(p => p.id === 'f3')) {
    db.profiles.push({ id: 'f3', name: '하린', handle: 'harin', avatar_url: null, onboarded: true, is_private: true, bio: '비공개 피드' },
                     { id: 'f4', name: '서연', handle: 'seoyeon', avatar_url: null, onboarded: true });
    db.follows.push({ follower_id: 'f4', followee_id: 'demo', created_at: t(0.7) });
    db.posts.push({ id: 'h1', owner_id: 'f3', author_name: '지수', mission: null, text: '', image_path: art(7), status: 'approved', created_at: t(3), approved_at: t(2.9) });
  }
  // 가챠 함수(RPC) 흉내: 데모는 뽑기권 5장으로 시작
  async function rpc(fn, args = {}) {
    db.inventory = db.inventory || []; if (db.gtix == null) db.gtix = 5;
    const prof = db.profiles.find(p => p.id === ME.id); prof.equipped = prof.equipped || {};
    await new Promise(r => setTimeout(r, 150));
    const G_ = id => db.groups.find(g => g.id === id), mem = (g, u) => db.group_members.find(m => m.group_id === g && m.user_id === u);
    const recount = g => { const x = G_(g); if (x) { x.member_count = db.group_members.filter(m => m.group_id === g && m.status === 'active').length; x.follower_count = db.group_follows.filter(f => f.group_id === g).length; } };
    const ok = data => (persist(), { data, error: null }), no = message => ({ data: null, error: { message } });
    if (fn === 'group_by_invite') { const g = db.groups.find(x => x.invite_code === args.p_code); return { data: g ? { ...g, owner_name: db.profiles.find(p => p.id === g.owner_id)?.name } : null, error: null }; }
    if (fn === 'join_group') {
      const g = G_(args.p_group); if (!g) return no('not_found');
      const cur = mem(g.id, ME.id); if (cur) return { data: cur.status, error: null };
      if (g.visibility === 'private' && args.p_code !== g.invite_code) return no('invite_required');
      const open = g.visibility === 'public' && g.join_mode === 'open';
      db.group_members.push({ group_id: g.id, user_id: ME.id, role: 'member', status: open ? 'active' : 'pending', created_at: new Date().toISOString() });
      if (open && !db.group_follows.some(f => f.group_id === g.id && f.user_id === ME.id)) db.group_follows.push({ group_id: g.id, user_id: ME.id, notify: false });
      recount(g.id); return ok(open ? 'active' : 'pending');
    }
    if (fn === 'approve_member') { const m = mem(args.p_group, args.p_user); if (m) m.status = 'active'; if (!db.group_follows.some(f => f.group_id === args.p_group && f.user_id === args.p_user)) db.group_follows.push({ group_id: args.p_group, user_id: args.p_user }); recount(args.p_group); return ok(null); }
    if (fn === 'follow_group') { if (!db.group_follows.some(f => f.group_id === args.p_group && f.user_id === ME.id)) db.group_follows.push({ group_id: args.p_group, user_id: ME.id, notify: false }); recount(args.p_group); return ok(null); }
    if (fn === 'group_invite_code') { const g = G_(args.p_group); if (args.p_new) g.invite_code = Math.random().toString(36).slice(2, 14); return ok(g.invite_code); }
    if (fn === 'transfer_group') { const g = G_(args.p_group); mem(g.id, ME.id).role = 'member'; mem(g.id, args.p_user).role = 'owner'; g.owner_id = args.p_user; return ok(null); }
    if (fn === 'profile_counts') return ok([{ friends: db.follows?.filter(f => f.follower_id === args.p_user).length || 0, groups: (db.group_members || []).filter(m => m.user_id === args.p_user && m.status === 'active').length }]);
    if (fn === 'owner_edit_media') { const p = db.posts.find(x => x.id === args.p_post); const old = p.media?.length ? p.media : [{ p: p.image_path, t: p.thumb_path, k: p.media_type }]; const m = args.p_keep.map(i => old[i]); Object.assign(p, { media: m.length > 1 ? m : null, image_path: m[0].p, thumb_path: m[0].t, media_type: m[0].k || 'image' }); return ok(new Date().toISOString()); }
    if (fn === 'pin_post') { const p = db.posts.find(x => x.id === args.p_post); if (args.p_on && db.posts.filter(x => (p.group_id ? x.group_id === p.group_id : !x.group_id && x.owner_id === p.owner_id) && x.pinned_at && x.id !== p.id).length >= 9) return no('pin_limit'); p.pinned_at = args.p_on ? new Date().toISOString() : null; return ok(null); }
    if (fn === 'block_user') { db.blocks = db.blocks || []; if (!db.blocks.some(b => b.blocked_id === args.p_user)) db.blocks.push({ blocker_id: ME.id, blocked_id: args.p_user }); db.follows = db.follows.filter(f => !((f.follower_id === ME.id && f.followee_id === args.p_user) || (f.follower_id === args.p_user && f.followee_id === ME.id))); return ok(null); }
    if (fn === 'unblock_user') { db.blocks = (db.blocks || []).filter(b => b.blocked_id !== args.p_user); return ok(null); }
    if (fn === 'report_content') { db.reports = db.reports || []; db.reports.push(args); return ok(db.reports.filter(r => r.p_target === args.p_target).length); }
    if (fn === 'invite_to_group') { db.group_invites = db.group_invites || []; let n = 0; args.p_users.forEach(u => { if (!db.group_invites.some(x => x.group_id === args.p_group && x.user_id === u) && !db.group_members.some(m => m.group_id === args.p_group && m.user_id === u)) { db.group_invites.push({ group_id: args.p_group, user_id: u, invited_by: ME.id, created_at: new Date().toISOString() }); n++; } }); return ok(n); }
    if (fn === 'my_group_invites') { const inv = (db.group_invites || []).filter(x => x.user_id === ME.id); return { data: inv.map(x => ({ group: G_(x.group_id), by: db.profiles.find(p => p.id === x.invited_by), at: x.created_at })), error: null }; }
    if (fn === 'answer_group_invite') { db.group_invites = (db.group_invites || []).filter(x => !(x.group_id === args.p_group && x.user_id === ME.id)); if (!args.p_accept) return ok('declined'); db.group_members.push({ group_id: args.p_group, user_id: ME.id, role: 'member', status: 'active' }); db.group_follows.push({ group_id: args.p_group, user_id: ME.id }); recount(args.p_group); return ok('active'); }
    if (fn === 'catch_dot') { db.dot_catches = db.dot_catches || []; db.dot_catches.push({ user_id: ME.id, kind: args.p_kind, created_at: new Date().toISOString() }); return ok(db.dot_catches.filter(d => d.user_id === ME.id).length); }
    if (fn === 'edit_post_media') { const p = db.posts.find(x => x.id === args.p_post); if (!p || p.author_id !== ME.id) return no('not_allowed'); const m = args.p_media; Object.assign(p, { media: m.length > 1 ? m : null, image_path: m[0].p, thumb_path: m[0].t, media_type: m[0].k, edited_at: new Date().toISOString() }); return ok(p.edited_at); }
    if (fn === 'edit_post_text') { const p = db.posts.find(x => x.id === args.p_post); if (!p || p.author_id !== ME.id) return no('not_allowed'); p.text = args.p_text || null; p.edited_at = new Date().toISOString(); return ok(p.edited_at); }
    if (fn === 'delete_my_post') { const i = db.posts.findIndex(x => x.id === args.p_post && x.author_id === ME.id && !x.group_id); if (i < 0) return no('not_allowed'); db.posts.splice(i, 1); return ok(null); }
    if (fn === 'can_view_feed') { const o = db.profiles.find(p => p.id === args.o); return { data: !o?.is_private || args.o === ME.id || db.follows.some(f => f.follower_id === args.o && f.followee_id === ME.id), error: null }; }
    if (fn === 'report_post') { const p = db.posts.find(x => x.id === args.p_post); if (p.author_id === ME.id) return no('own_post'); p.reports = (p.reports || 0) + 1; if (p.reports >= 3) p.flagged = true; return ok(p.reports); }
    if (fn === 'unflag_post') { const p = db.posts.find(x => x.id === args.p_post); p.flagged = false; p.reports = 0; return ok(null); }
    if (fn === 'gacha_status') return { data: { tickets: db.gtix, earned: 0, used: 0, bonus: 5 }, error: null };
    if (fn === 'pull_gacha') {
      if (db.gtix < 1) return { data: null, error: { message: 'no_ticket' } };
      const r = Math.random(), rar = r < 0.01 ? 'legendary' : r < 0.10 ? 'epic' : r < 0.40 ? 'rare' : 'common';
      const pool = ITEM_CATALOG.filter(i => i.rarity === rar), it = pool[Math.floor(Math.random() * pool.length)];
      let inv = db.inventory.find(x => x.item_id === it.id); if (inv) inv.count++; else db.inventory.push(inv = { user_id: ME.id, item_id: it.id, count: 1 });
      db.gtix--; persist();
      return { data: { id: it.id, kind: it.kind, name: it.name, rarity: rar, count: inv.count, tickets: db.gtix }, error: null };
    }
    if (fn === 'equip_item') {
      const { p_kind: k, p_item: id } = args, eq = { ...prof.equipped };
      if (id && !db.inventory.some(x => x.item_id === id)) return { data: null, error: { message: 'not_owned' } };
      if (k === 'sticker') { let a = [...(eq.stickers || [])]; if (a.includes(id)) a = a.filter(x => x !== id); else { if (a.length >= 3) a.shift(); a.push(id); } eq.stickers = a; }
      else if (!id || eq[k] === id) delete eq[k]; else eq[k] = id;
      prof.equipped = eq; persist(); return { data: eq, error: null };
    }
    return { data: null, error: { message: 'unknown rpc' } };
  }
  const toDataUrl = blob => new Promise(r => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(blob); });
  // 데모 전용 하단 바: 시점 전환
  setTimeout(() => {
    const bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;left:50%;bottom:calc(84px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:40;display:flex;gap:4px;align-items:center;padding:5px 5px 5px 14px;border-radius:999px;background:var(--fg);color:var(--bg);font-size:12px;font-weight:600;box-shadow:0 8px 24px rgba(0,0,0,.18)';
    const on = loggedIn();
    const pill = (label, active, fn) => `<button onclick="${fn}" style="border:0;border-radius:999px;padding:7px 12px;font-size:12px;font-weight:600;white-space:nowrap;background:${active ? 'var(--bg)' : 'transparent'};color:${active ? 'var(--fg)' : 'var(--bg)'}">${label}</button>`;
    bar.innerHTML = `<span style="opacity:.6;margin-right:6px">DEMO</span>${pill('주인장 시점', on, "demoView(1)")}${pill('친구 시점', !on, "demoView(0)")}${pill('↺', false, "demoReset()")}`;
    document.body.appendChild(bar);
    document.getElementById('toast').style.bottom = '76px';
    document.body.style.paddingBottom = '72px';
  });
  window.demoView = v => { ss.set('demo_login', v ? '1' : '0'); location.href = location.pathname + '?u=demo'; };
  window.demoReset = () => { try { sessionStorage.clear(); } catch {} location.href = location.pathname; };

  return {
    auth: {
      getSession: async () => ({ data: { session: loggedIn() ? { user: ME } : null } }),
      signInWithOAuth: async () => { ss.set('demo_login', '1'); location.href = location.pathname; },
      signOut: async () => ss.set('demo_login', '0'),
    },
    from, rpc,
    storage: { from: () => ({
      getPublicUrl: p => ({ data: { publicUrl: files[p] || p } }),
      upload: async (p, blob) => { files[p] = await toDataUrl(blob); return { error: null }; },
      remove: async () => ({ error: null }),
    }) },
    _files: files,
  };
}

