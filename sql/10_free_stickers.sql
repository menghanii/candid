-- candid. 친구 사진 꾸미기용 무료 스티커(이모지 24 + 미니 아이템 10) — 누구나 사용 가능
-- SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 09_multi_stickers.sql 이후 실행
-- 목록은 tools/stickers.js 에서 자동 생성 — 직접 고치지 말 것

-- 1) 무료 스티커를 아이템 목록에 추가(active=false: 나중에 가챠를 켜도 뽑기 대상에서 제외)
insert into public.items (id, kind, name, rarity, data, active, sort) values
  ('e_01', 'sticker', '😂', 'common', '{"e":"😂","free":true}'::jsonb, false, 1000),
  ('e_02', 'sticker', '😍', 'common', '{"e":"😍","free":true}'::jsonb, false, 1001),
  ('e_03', 'sticker', '🥹', 'common', '{"e":"🥹","free":true}'::jsonb, false, 1002),
  ('e_04', 'sticker', '😎', 'common', '{"e":"😎","free":true}'::jsonb, false, 1003),
  ('e_05', 'sticker', '🤣', 'common', '{"e":"🤣","free":true}'::jsonb, false, 1004),
  ('e_06', 'sticker', '😭', 'common', '{"e":"😭","free":true}'::jsonb, false, 1005),
  ('e_07', 'sticker', '🥳', 'common', '{"e":"🥳","free":true}'::jsonb, false, 1006),
  ('e_08', 'sticker', '😳', 'common', '{"e":"😳","free":true}'::jsonb, false, 1007),
  ('e_09', 'sticker', '🤪', 'common', '{"e":"🤪","free":true}'::jsonb, false, 1008),
  ('e_10', 'sticker', '😘', 'common', '{"e":"😘","free":true}'::jsonb, false, 1009),
  ('e_11', 'sticker', '👍', 'common', '{"e":"👍","free":true}'::jsonb, false, 1010),
  ('e_12', 'sticker', '👏', 'common', '{"e":"👏","free":true}'::jsonb, false, 1011),
  ('e_13', 'sticker', '🙌', 'common', '{"e":"🙌","free":true}'::jsonb, false, 1012),
  ('e_14', 'sticker', '💯', 'common', '{"e":"💯","free":true}'::jsonb, false, 1013),
  ('e_15', 'sticker', '🔥', 'common', '{"e":"🔥","free":true}'::jsonb, false, 1014),
  ('e_16', 'sticker', '✨', 'common', '{"e":"✨","free":true}'::jsonb, false, 1015),
  ('e_17', 'sticker', '💖', 'common', '{"e":"💖","free":true}'::jsonb, false, 1016),
  ('e_18', 'sticker', '⭐', 'common', '{"e":"⭐","free":true}'::jsonb, false, 1017),
  ('e_19', 'sticker', '🌈', 'common', '{"e":"🌈","free":true}'::jsonb, false, 1018),
  ('e_20', 'sticker', '🍀', 'common', '{"e":"🍀","free":true}'::jsonb, false, 1019),
  ('e_21', 'sticker', '🎉', 'common', '{"e":"🎉","free":true}'::jsonb, false, 1020),
  ('e_22', 'sticker', '🎂', 'common', '{"e":"🎂","free":true}'::jsonb, false, 1021),
  ('e_23', 'sticker', '🐶', 'common', '{"e":"🐶","free":true}'::jsonb, false, 1022),
  ('e_24', 'sticker', '🐱', 'common', '{"e":"🐱","free":true}'::jsonb, false, 1023),
  ('m_kkk', 'sticker', '말풍선 ㅋㅋㅋ', 'common', '{"svg":"<svg viewBox=\"0 0 120 78\"><path d=\"M14 4h92a12 12 0 0 1 12 12v32a12 12 0 0 1-12 12H44L26 74l4-14H14A12 12 0 0 1 2 48V16A12 12 0 0 1 14 4z\" fill=\"#fff\" stroke=\"#111\" stroke-width=\"3\"/><text x=\"60\" y=\"44\" text-anchor=\"middle\" font-family=\"Pretendard,Apple SD Gothic Neo,sans-serif\" font-weight=\"900\" font-size=\"30\" fill=\"#111\">ㅋㅋㅋ</text></svg>","free":true,"mini":true}'::jsonb, false, 1024),
  ('m_legend', 'sticker', '레전드', 'common', '{"svg":"<svg viewBox=\"0 0 130 54\"><g transform=\"rotate(-6 65 27)\"><rect x=\"6\" y=\"8\" width=\"118\" height=\"38\" rx=\"8\" fill=\"#ffd60a\" stroke=\"#111\" stroke-width=\"3\"/><text x=\"65\" y=\"36\" text-anchor=\"middle\" font-family=\"Pretendard,Apple SD Gothic Neo,sans-serif\" font-weight=\"900\" font-size=\"24\" fill=\"#111\">레전드</text></g></svg>","free":true,"mini":true}'::jsonb, false, 1025),
  ('m_insaeng', 'sticker', '인생샷 도장', 'common', '{"svg":"<svg viewBox=\"0 0 100 100\"><g transform=\"rotate(-12 50 50)\" fill=\"none\" stroke=\"#ff3b30\"><circle cx=\"50\" cy=\"50\" r=\"44\" stroke-width=\"5\"/><circle cx=\"50\" cy=\"50\" r=\"35\" stroke-width=\"2\"/><text x=\"50\" y=\"58\" text-anchor=\"middle\" font-family=\"Pretendard,Apple SD Gothic Neo,sans-serif\" font-weight=\"900\" font-size=\"22\" fill=\"#ff3b30\" stroke=\"none\">인생샷</text></g></svg>","free":true,"mini":true}'::jsonb, false, 1026),
  ('m_heart', 'sticker', '하트', 'common', '{"svg":"<svg viewBox=\"0 0 100 90\"><path d=\"M50 86S6 58 6 28A22 22 0 0 1 50 16a22 22 0 0 1 44 12c0 30-44 58-44 58z\" fill=\"#ff4d8d\" stroke=\"#fff\" stroke-width=\"4\"/><ellipse cx=\"30\" cy=\"30\" rx=\"8\" ry=\"5\" fill=\"#fff\" opacity=\".7\" transform=\"rotate(-30 30 30)\"/></svg>","free":true,"mini":true}'::jsonb, false, 1027),
  ('m_sparkle', 'sticker', '반짝이', 'common', '{"svg":"<svg viewBox=\"0 0 100 100\"><g fill=\"#ffd60a\" stroke=\"#fff\" stroke-width=\"2\"><path d=\"M40 8l7 23 23 7-23 7-7 23-7-23-23-7 23-7z\"/><path d=\"M76 52l4 12 12 4-12 4-4 12-4-12-12-4 12-4z\"/><path d=\"M22 70l3 8 8 3-8 3-3 8-3-8-8-3 8-3z\"/></g></svg>","free":true,"mini":true}'::jsonb, false, 1028),
  ('m_mustache', 'sticker', '콧수염', 'common', '{"svg":"<svg viewBox=\"0 0 120 44\"><path d=\"M60 14c-6-10-22-14-34-6S8 30 2 26c4 12 22 18 36 12s18-12 22-16c4 4 8 10 22 16s32 0 36-12c-6 4-12-10-24-18S66 4 60 14z\" fill=\"#1c1c1e\"/></svg>","free":true,"mini":true}'::jsonb, false, 1029),
  ('m_glasses', 'sticker', '선글라스', 'common', '{"svg":"<svg viewBox=\"0 0 130 50\"><path d=\"M4 12h122\" stroke=\"#111\" stroke-width=\"5\" stroke-linecap=\"round\"/><path d=\"M10 12h46v8c0 14-8 24-23 24S10 34 10 20z\" fill=\"#111\"/><path d=\"M74 12h46v8c0 14-8 24-23 24S74 34 74 20z\" fill=\"#111\"/><path d=\"M18 18l10 10M82 18l10 10\" stroke=\"#fff\" stroke-width=\"3\" stroke-linecap=\"round\" opacity=\".55\"/></svg>","free":true,"mini":true}'::jsonb, false, 1030),
  ('m_blush', 'sticker', '볼터치', 'common', '{"svg":"<svg viewBox=\"0 0 140 40\"><g fill=\"#ff6b9d\" opacity=\".75\"><ellipse cx=\"22\" cy=\"20\" rx=\"20\" ry=\"13\"/><ellipse cx=\"118\" cy=\"20\" rx=\"20\" ry=\"13\"/></g><g stroke=\"#fff\" stroke-width=\"2.5\" stroke-linecap=\"round\" opacity=\".8\"><path d=\"M12 16l4 8M20 14l4 8M28 16l4 8M108 16l4 8M116 14l4 8M124 16l4 8\"/></g></svg>","free":true,"mini":true}'::jsonb, false, 1031),
  ('m_me', 'sticker', '"나" 화살표', 'common', '{"svg":"<svg viewBox=\"0 0 110 80\"><text x=\"8\" y=\"34\" font-family=\"Pretendard,Apple SD Gothic Neo,sans-serif\" font-weight=\"900\" font-size=\"30\" fill=\"#2b50ff\" stroke=\"#fff\" stroke-width=\"5\" paint-order=\"stroke\">나</text><path d=\"M44 22c22-2 40 10 48 36\" fill=\"none\" stroke=\"#fff\" stroke-width=\"9\" stroke-linecap=\"round\"/><path d=\"M44 22c22-2 40 10 48 36\" fill=\"none\" stroke=\"#2b50ff\" stroke-width=\"5\" stroke-linecap=\"round\"/><path d=\"M80 54l13 10 4-16\" fill=\"none\" stroke=\"#2b50ff\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>","free":true,"mini":true}'::jsonb, false, 1032),
  ('m_crown', 'sticker', '왕관', 'common', '{"svg":"<svg viewBox=\"0 0 110 80\"><path d=\"M8 26l22 18 25-34 25 34 22-18-8 46H16z\" fill=\"#ffc300\" stroke=\"#b8860b\" stroke-width=\"3\" stroke-linejoin=\"round\"/><circle cx=\"55\" cy=\"10\" r=\"6\" fill=\"#ff3b30\"/><circle cx=\"8\" cy=\"26\" r=\"5\" fill=\"#2b50ff\"/><circle cx=\"102\" cy=\"26\" r=\"5\" fill=\"#2b50ff\"/><rect x=\"18\" y=\"62\" width=\"74\" height=\"8\" rx=\"2\" fill=\"#b8860b\"/></svg>","free":true,"mini":true}'::jsonb, false, 1033)
on conflict (id) do update set name = excluded.name, data = excluded.data, active = false, sort = excluded.sort;

-- 2) 스티커 붙이기 권한: 무료 스티커는 누구나(로그인), 그 외는 가진 것만. 사진 1장에 1인 10개, 전체 40개까지
drop policy if exists "stickers add own" on public.post_stickers;
create policy "stickers add own" on public.post_stickers for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved' and p.media_type in ('image', 'video'))
    and exists (select 1 from public.items t where t.id = post_stickers.item_id and t.kind = 'sticker'
                 and (coalesce((t.data->>'free')::boolean, false)
                      or exists (select 1 from public.inventory i where i.user_id = auth.uid() and i.item_id = t.id)))
    and (select count(*) from public.post_stickers s where s.post_id = post_stickers.post_id and s.media_idx = post_stickers.media_idx and s.user_id = auth.uid()) < 10
    and (select count(*) from public.post_stickers s where s.post_id = post_stickers.post_id and s.media_idx = post_stickers.media_idx) < 40
  );
