// candid. 무료 스티커(친구 사진 꾸미기용) — 수정 후 `node tools/stickers.js` 실행하면
// index.html 의 FREE_STICKERS 와 sql/20_stickers_v2.sql 이 함께 갱신됨
//
// 종류
//  · 움직이는 이모지(ANIM): Google Noto Emoji 애니메이션(CC BY 4.0) → brand/stk/<코드>.webp (160px, 15fps 로 줄임)
//    받기·줄이기: tools/stk-fetch.sh
//  · 이모지(EMOJI): 기기 글꼴 그대로
//  · 은퇴(RETIRED): 예전에 붙인 스티커가 계속 보이도록 목록엔 남기되, 트레이에는 안 보이고 새로 붙일 수도 없음
//    (텍스트 스티커 t_text, 미니 아이템 그림, 움직이는 버전이 생긴 예전 이모지)

// [Noto 코드, 이모지] — 텔레그램 반응처럼 자주 쓰는 순서
const ANIM = [
  ['1f44d', '👍'], ['2764_fe0f', '❤️'], ['1f525', '🔥'], ['1f970', '🥰'], ['1f44f', '👏'], ['1f601', '😁'],
  ['1f923', '🤣'], ['1f602', '😂'], ['1f60d', '😍'], ['1f979', '🥹'], ['1f62d', '😭'], ['1f389', '🎉'],
  ['1f929', '🤩'], ['1f973', '🥳'], ['1f4af', '💯'], ['2764_fe0f_200d_1f525', '❤️‍🔥'], ['1f60e', '😎'], ['1f92f', '🤯'],
  ['1f631', '😱'], ['1f633', '😳'], ['1f914', '🤔'], ['1f928', '🤨'], ['1f610', '😐'], ['1f644', '🙄'],
  ['1f62c', '😬'], ['1f62e', '😮'], ['1fae0', '🫠'], ['1f635_200d_1f4ab', '😵‍💫'], ['1f92d', '🤭'], ['1f924', '🤤'],
  ['1f97a', '🥺'], ['1f971', '🥱'], ['1f634', '😴'], ['1f607', '😇'], ['1f608', '😈'], ['1f921', '🤡'],
  ['1f47b', '👻'], ['1f480', '💀'], ['1f47d', '👽'], ['1f47e', '👾'], ['1f913', '🤓'], ['1f92a', '🤪'],
  ['1f618', '😘'], ['1f48b', '💋'], ['1f648', '🙈'], ['1f440', '👀'], ['1f64f', '🙏'], ['1f44c', '👌'],
  ['1f91d', '🤝'], ['1f64c', '🙌'], ['1f4aa', '💪'], ['1fae1', '🫡'], ['1faf6', '🫶'], ['1f917', '🤗'],
  ['1f496', '💖'], ['1f494', '💔'], ['2728', '✨'], ['1f31f', '🌟'], ['26a1', '⚡'], ['1f308', '🌈'],
  ['1f3c6', '🏆'], ['1f37e', '🍾'], ['1f382', '🎂'], ['1f388', '🎈'], ['1f984', '🦄'], ['1f431', '🐱'],
  ['1f4a9', '💩'], ['1f621', '😡'], ['1f911', '🤑'], ['1f60a', '😊'], ['1f643', '🙃'],
];
// 예전 이모지 24개(e_01~e_24). 움직이는 버전이 있는 것은 은퇴, 나머지(⭐🍀🐶)는 계속 씀
const OLD_EMOJI = ['😂', '😍', '🥹', '😎', '🤣', '😭', '🥳', '😳', '🤪', '😘', '👍', '👏', '🙌', '💯', '🔥', '✨', '💖', '⭐', '🌈', '🍀', '🎉', '🎂', '🐶', '🐱'];
// 새 이모지(e_25~): 동물·꽃·음식·소품 위주(얼굴·손은 움직이는 쪽에)
const NEW_EMOJI = ['🐰', '🐻', '🐼', '🐨', '🦊', '🐸', '🐥', '🐧', '🐹', '🦋', '🌸', '🌷', '🌻', '🌼', '💐', '🍓', '🍑', '🍒', '🍉', '🍰',
  '🍕', '🍔', '🍟', '🍩', '🍦', '🧋', '☕', '🍺', '🎀', '🎁', '🧸', '🌙', '☀️', '☁️', '🫧', '🌊', '📸', '🎵', '🎧', '💎',
  '👑', '🕶️', '💄', '💅', '🧿', '⚽', '🏀', '🎮', '🚀', '📍'];
const F = 'font-family="Pretendard,Apple SD Gothic Neo,sans-serif" font-weight="900"';
// 은퇴한 미니 아이템(예전 스티커 표시용으로만 남김)
const MINI = [
  ['m_kkk', '말풍선 ㅋㅋㅋ', `<svg viewBox="0 0 120 78"><path d="M14 4h92a12 12 0 0 1 12 12v32a12 12 0 0 1-12 12H44L26 74l4-14H14A12 12 0 0 1 2 48V16A12 12 0 0 1 14 4z" fill="#fff" stroke="#111" stroke-width="3"/><text x="60" y="44" text-anchor="middle" ${F} font-size="30" fill="#111">ㅋㅋㅋ</text></svg>`],
  ['m_legend', '레전드', `<svg viewBox="0 0 130 54"><g transform="rotate(-6 65 27)"><rect x="6" y="8" width="118" height="38" rx="8" fill="#ffd60a" stroke="#111" stroke-width="3"/><text x="65" y="36" text-anchor="middle" ${F} font-size="24" fill="#111">레전드</text></g></svg>`],
  ['m_insaeng', '인생샷 도장', `<svg viewBox="0 0 100 100"><g transform="rotate(-12 50 50)" fill="none" stroke="#ff3b30"><circle cx="50" cy="50" r="44" stroke-width="5"/><circle cx="50" cy="50" r="35" stroke-width="2"/><text x="50" y="58" text-anchor="middle" ${F} font-size="22" fill="#ff3b30" stroke="none">인생샷</text></g></svg>`],
  ['m_heart', '하트', `<svg viewBox="0 0 100 90"><path d="M50 86S6 58 6 28A22 22 0 0 1 50 16a22 22 0 0 1 44 12c0 30-44 58-44 58z" fill="#ff4d8d" stroke="#fff" stroke-width="4"/><ellipse cx="30" cy="30" rx="8" ry="5" fill="#fff" opacity=".7" transform="rotate(-30 30 30)"/></svg>`],
  ['m_sparkle', '반짝이', `<svg viewBox="0 0 100 100"><g fill="#ffd60a" stroke="#fff" stroke-width="2"><path d="M40 8l7 23 23 7-23 7-7 23-7-23-23-7 23-7z"/><path d="M76 52l4 12 12 4-12 4-4 12-4-12-12-4 12-4z"/><path d="M22 70l3 8 8 3-8 3-3 8-3-8-8-3 8-3z"/></g></svg>`],
  ['m_mustache', '콧수염', `<svg viewBox="0 0 120 44"><path d="M60 14c-6-10-22-14-34-6S8 30 2 26c4 12 22 18 36 12s18-12 22-16c4 4 8 10 22 16s32 0 36-12c-6 4-12-10-24-18S66 4 60 14z" fill="#1c1c1e"/></svg>`],
  ['m_glasses', '선글라스', `<svg viewBox="0 0 130 50"><path d="M4 12h122" stroke="#111" stroke-width="5" stroke-linecap="round"/><path d="M10 12h46v8c0 14-8 24-23 24S10 34 10 20z" fill="#111"/><path d="M74 12h46v8c0 14-8 24-23 24S74 34 74 20z" fill="#111"/><path d="M18 18l10 10M82 18l10 10" stroke="#fff" stroke-width="3" stroke-linecap="round" opacity=".55"/></svg>`],
  ['m_blush', '볼터치', `<svg viewBox="0 0 140 40"><g fill="#ff6b9d" opacity=".75"><ellipse cx="22" cy="20" rx="20" ry="13"/><ellipse cx="118" cy="20" rx="20" ry="13"/></g><g stroke="#fff" stroke-width="2.5" stroke-linecap="round" opacity=".8"><path d="M12 16l4 8M20 14l4 8M28 16l4 8M108 16l4 8M116 14l4 8M124 16l4 8"/></g></svg>`],
  ['m_me', '"나" 화살표', `<svg viewBox="0 0 110 80"><text x="8" y="34" ${F} font-size="30" fill="#2b50ff" stroke="#fff" stroke-width="5" paint-order="stroke">나</text><path d="M44 22c22-2 40 10 48 36" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round"/><path d="M44 22c22-2 40 10 48 36" fill="none" stroke="#2b50ff" stroke-width="5" stroke-linecap="round"/><path d="M80 54l13 10 4-16" fill="none" stroke="#2b50ff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg>`],
  ['m_crown', '왕관', `<svg viewBox="0 0 110 80"><path d="M8 26l22 18 25-34 25 34 22-18-8 46H16z" fill="#ffc300" stroke="#b8860b" stroke-width="3" stroke-linejoin="round"/><circle cx="55" cy="10" r="6" fill="#ff3b30"/><circle cx="8" cy="26" r="5" fill="#2b50ff"/><circle cx="102" cy="26" r="5" fill="#2b50ff"/><rect x="18" y="62" width="74" height="8" rx="2" fill="#b8860b"/></svg>`],
];
const animChars = new Set(ANIM.map(a => a[1]));
const sticker = (id, name, data) => ({ id, kind: 'sticker', name, rarity: 'common', data });
const FREE = [
  ...ANIM.map(([cp, e]) => sticker(`a_${cp}`, e, { e, img: `/brand/stk/${cp}.webp`, anim: true, free: true })),
  ...OLD_EMOJI.map((e, i) => sticker(`e_${String(i + 1).padStart(2, '0')}`, e, animChars.has(e) ? { e, retired: true } : { e, free: true })),
  ...NEW_EMOJI.map((e, i) => sticker(`e_${String(i + 25).padStart(2, '0')}`, e, { e, free: true })),
  ...MINI.map(([id, name, svg]) => sticker(id, name, { svg, mini: true, retired: true })),
];

if (require.main === module) {
  const fs = require('fs'), path = require('path'), root = path.join(__dirname, '..');
  const missing = ANIM.filter(([cp]) => !fs.existsSync(path.join(root, 'brand/stk', cp + '.webp')));
  if (missing.length) { console.error('brand/stk 에 없는 파일:', missing.map(a => a[0]).join(' ')); process.exit(1); }
  const q = s => `'${String(s).replace(/'/g, "''")}'`;
  const live = FREE.filter(i => !i.data.retired), retired = FREE.filter(i => i.data.retired);
  const sql = `-- candid. 스티커 개편: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 19_private_feed.sql 이후 실행
-- 목록은 tools/stickers.js 에서 자동 생성 — 직접 고치지 말 것
--
--  · 움직이는 이모지 ${ANIM.length}개 + 이모지 ${live.length - ANIM.length}개
--  · 텍스트 스티커·미니 아이템 그림·중복 이모지는 은퇴: 이미 붙인 건 그대로 보이고, 새로 붙일 수는 없음
--  · 한 게시물에 한 사람당 스티커 1개(여러 장 게시물도 전체에서 1개), 게시물당 전체 100개까지
--  · 비공개 피드는 볼 수 있는 사람만 꾸밀 수 있음

-- 1) 스티커 목록(active=false: 나중에 가챠를 켜도 뽑기 대상에서 제외)
insert into public.items (id, kind, name, rarity, data, active, sort) values
${live.map((i, n) => `  (${q(i.id)}, 'sticker', ${q(i.name)}, 'common', ${q(JSON.stringify(i.data))}::jsonb, false, ${1000 + n})`).join(',\n')}
on conflict (id) do update set name = excluded.name, data = excluded.data, active = false, sort = excluded.sort;

-- 2) 은퇴: 새로 붙일 수 없게(free 해제). 텍스트 스티커 t_text 포함
update public.items set data = (data - 'free') || '{"retired": true}'::jsonb
 where id in (${[...retired.map(i => q(i.id)), q('t_text')].join(', ')});

-- 3) 붙이기 권한
create or replace function public.can_add_sticker(p_post uuid, p_idx int, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select
    exists (select 1 from public.posts p where p.id = p_post and p.status = 'approved' and not p.flagged
             and (p.media_type in ('image', 'video') or (p.media_type in ('poll', 'question') and p_idx = 0))
             and (case when p.group_id is null then public.can_view_feed(p.owner_id) else public.can_decorate_group(p.group_id) end))
    and exists (select 1 from public.items t where t.id = p_item and t.kind = 'sticker'
                 and (coalesce((t.data->>'free')::boolean, false)
                      or exists (select 1 from public.inventory i where i.user_id = auth.uid() and i.item_id = t.id)))
    -- 한 게시물에 한 사람당 1개, 게시물당 전체 100개
    and not exists (select 1 from public.post_stickers s where s.post_id = p_post and s.user_id = auth.uid())
    and (select count(*) from public.post_stickers s where s.post_id = p_post) < 100
$$;
revoke all on function public.can_add_sticker(uuid, int, text) from public, anon;
grant execute on function public.can_add_sticker(uuid, int, text) to authenticated;

-- 4) 글자 수정 권한 회수(텍스트 스티커 은퇴). 옮기기·크기·회전은 그대로
revoke update on public.post_stickers from authenticated;
grant update (x, y, scale, rot, updated_at) on public.post_stickers to authenticated;
`;
  fs.writeFileSync(path.join(root, 'sql/20_stickers_v2.sql'), sql);
  const htmlPath = path.join(root, 'index.html');
  let html = fs.readFileSync(htmlPath, 'utf8');
  const block = `// @@FREE-BEGIN (tools/stickers.js 에서 자동 생성 — 직접 고치지 말 것)
const FREE_STICKERS = ${JSON.stringify(FREE)};
// @@FREE-END`;
  html = html.replace(/\/\/ @@FREE-BEGIN[\s\S]*?\/\/ @@FREE-END/, () => block);
  fs.writeFileSync(htmlPath, html);
  console.log(`stickers: 움직이는 ${ANIM.length} + 이모지 ${live.length - ANIM.length} (은퇴 ${retired.length}) → index.html, sql/20_stickers_v2.sql`);
}
module.exports = FREE;
