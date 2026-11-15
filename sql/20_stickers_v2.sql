-- candid. 스티커 개편: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 19_private_feed.sql 이후 실행
-- 목록은 tools/stickers.js 에서 자동 생성 — 직접 고치지 말 것
--
--  · 움직이는 이모지 71개 + 이모지 53개
--  · 텍스트 스티커·미니 아이템 그림·중복 이모지는 은퇴: 이미 붙인 건 그대로 보이고, 새로 붙일 수는 없음
--  · 한 게시물에 한 사람당 스티커 1개(여러 장 게시물도 전체에서 1개), 게시물당 전체 100개까지
--  · 비공개 피드는 볼 수 있는 사람만 꾸밀 수 있음

-- 1) 스티커 목록(active=false: 나중에 가챠를 켜도 뽑기 대상에서 제외)
insert into public.items (id, kind, name, rarity, data, active, sort) values
  ('a_1f44d', 'sticker', '👍', 'common', '{"e":"👍","img":"/brand/stk/1f44d.webp","anim":true,"free":true}'::jsonb, false, 1000),
  ('a_2764_fe0f', 'sticker', '❤️', 'common', '{"e":"❤️","img":"/brand/stk/2764_fe0f.webp","anim":true,"free":true}'::jsonb, false, 1001),
  ('a_1f525', 'sticker', '🔥', 'common', '{"e":"🔥","img":"/brand/stk/1f525.webp","anim":true,"free":true}'::jsonb, false, 1002),
  ('a_1f970', 'sticker', '🥰', 'common', '{"e":"🥰","img":"/brand/stk/1f970.webp","anim":true,"free":true}'::jsonb, false, 1003),
  ('a_1f44f', 'sticker', '👏', 'common', '{"e":"👏","img":"/brand/stk/1f44f.webp","anim":true,"free":true}'::jsonb, false, 1004),
  ('a_1f601', 'sticker', '😁', 'common', '{"e":"😁","img":"/brand/stk/1f601.webp","anim":true,"free":true}'::jsonb, false, 1005),
  ('a_1f923', 'sticker', '🤣', 'common', '{"e":"🤣","img":"/brand/stk/1f923.webp","anim":true,"free":true}'::jsonb, false, 1006),
  ('a_1f602', 'sticker', '😂', 'common', '{"e":"😂","img":"/brand/stk/1f602.webp","anim":true,"free":true}'::jsonb, false, 1007),
  ('a_1f60d', 'sticker', '😍', 'common', '{"e":"😍","img":"/brand/stk/1f60d.webp","anim":true,"free":true}'::jsonb, false, 1008),
  ('a_1f979', 'sticker', '🥹', 'common', '{"e":"🥹","img":"/brand/stk/1f979.webp","anim":true,"free":true}'::jsonb, false, 1009),
  ('a_1f62d', 'sticker', '😭', 'common', '{"e":"😭","img":"/brand/stk/1f62d.webp","anim":true,"free":true}'::jsonb, false, 1010),
  ('a_1f389', 'sticker', '🎉', 'common', '{"e":"🎉","img":"/brand/stk/1f389.webp","anim":true,"free":true}'::jsonb, false, 1011),
  ('a_1f929', 'sticker', '🤩', 'common', '{"e":"🤩","img":"/brand/stk/1f929.webp","anim":true,"free":true}'::jsonb, false, 1012),
  ('a_1f973', 'sticker', '🥳', 'common', '{"e":"🥳","img":"/brand/stk/1f973.webp","anim":true,"free":true}'::jsonb, false, 1013),
  ('a_1f4af', 'sticker', '💯', 'common', '{"e":"💯","img":"/brand/stk/1f4af.webp","anim":true,"free":true}'::jsonb, false, 1014),
  ('a_2764_fe0f_200d_1f525', 'sticker', '❤️‍🔥', 'common', '{"e":"❤️‍🔥","img":"/brand/stk/2764_fe0f_200d_1f525.webp","anim":true,"free":true}'::jsonb, false, 1015),
  ('a_1f60e', 'sticker', '😎', 'common', '{"e":"😎","img":"/brand/stk/1f60e.webp","anim":true,"free":true}'::jsonb, false, 1016),
  ('a_1f92f', 'sticker', '🤯', 'common', '{"e":"🤯","img":"/brand/stk/1f92f.webp","anim":true,"free":true}'::jsonb, false, 1017),
  ('a_1f631', 'sticker', '😱', 'common', '{"e":"😱","img":"/brand/stk/1f631.webp","anim":true,"free":true}'::jsonb, false, 1018),
  ('a_1f633', 'sticker', '😳', 'common', '{"e":"😳","img":"/brand/stk/1f633.webp","anim":true,"free":true}'::jsonb, false, 1019),
  ('a_1f914', 'sticker', '🤔', 'common', '{"e":"🤔","img":"/brand/stk/1f914.webp","anim":true,"free":true}'::jsonb, false, 1020),
  ('a_1f928', 'sticker', '🤨', 'common', '{"e":"🤨","img":"/brand/stk/1f928.webp","anim":true,"free":true}'::jsonb, false, 1021),
  ('a_1f610', 'sticker', '😐', 'common', '{"e":"😐","img":"/brand/stk/1f610.webp","anim":true,"free":true}'::jsonb, false, 1022),
  ('a_1f644', 'sticker', '🙄', 'common', '{"e":"🙄","img":"/brand/stk/1f644.webp","anim":true,"free":true}'::jsonb, false, 1023),
  ('a_1f62c', 'sticker', '😬', 'common', '{"e":"😬","img":"/brand/stk/1f62c.webp","anim":true,"free":true}'::jsonb, false, 1024),
  ('a_1f62e', 'sticker', '😮', 'common', '{"e":"😮","img":"/brand/stk/1f62e.webp","anim":true,"free":true}'::jsonb, false, 1025),
  ('a_1fae0', 'sticker', '🫠', 'common', '{"e":"🫠","img":"/brand/stk/1fae0.webp","anim":true,"free":true}'::jsonb, false, 1026),
  ('a_1f635_200d_1f4ab', 'sticker', '😵‍💫', 'common', '{"e":"😵‍💫","img":"/brand/stk/1f635_200d_1f4ab.webp","anim":true,"free":true}'::jsonb, false, 1027),
  ('a_1f92d', 'sticker', '🤭', 'common', '{"e":"🤭","img":"/brand/stk/1f92d.webp","anim":true,"free":true}'::jsonb, false, 1028),
  ('a_1f924', 'sticker', '🤤', 'common', '{"e":"🤤","img":"/brand/stk/1f924.webp","anim":true,"free":true}'::jsonb, false, 1029),
  ('a_1f97a', 'sticker', '🥺', 'common', '{"e":"🥺","img":"/brand/stk/1f97a.webp","anim":true,"free":true}'::jsonb, false, 1030),
  ('a_1f971', 'sticker', '🥱', 'common', '{"e":"🥱","img":"/brand/stk/1f971.webp","anim":true,"free":true}'::jsonb, false, 1031),
  ('a_1f634', 'sticker', '😴', 'common', '{"e":"😴","img":"/brand/stk/1f634.webp","anim":true,"free":true}'::jsonb, false, 1032),
  ('a_1f607', 'sticker', '😇', 'common', '{"e":"😇","img":"/brand/stk/1f607.webp","anim":true,"free":true}'::jsonb, false, 1033),
  ('a_1f608', 'sticker', '😈', 'common', '{"e":"😈","img":"/brand/stk/1f608.webp","anim":true,"free":true}'::jsonb, false, 1034),
  ('a_1f921', 'sticker', '🤡', 'common', '{"e":"🤡","img":"/brand/stk/1f921.webp","anim":true,"free":true}'::jsonb, false, 1035),
  ('a_1f47b', 'sticker', '👻', 'common', '{"e":"👻","img":"/brand/stk/1f47b.webp","anim":true,"free":true}'::jsonb, false, 1036),
  ('a_1f480', 'sticker', '💀', 'common', '{"e":"💀","img":"/brand/stk/1f480.webp","anim":true,"free":true}'::jsonb, false, 1037),
  ('a_1f47d', 'sticker', '👽', 'common', '{"e":"👽","img":"/brand/stk/1f47d.webp","anim":true,"free":true}'::jsonb, false, 1038),
  ('a_1f47e', 'sticker', '👾', 'common', '{"e":"👾","img":"/brand/stk/1f47e.webp","anim":true,"free":true}'::jsonb, false, 1039),
  ('a_1f913', 'sticker', '🤓', 'common', '{"e":"🤓","img":"/brand/stk/1f913.webp","anim":true,"free":true}'::jsonb, false, 1040),
  ('a_1f92a', 'sticker', '🤪', 'common', '{"e":"🤪","img":"/brand/stk/1f92a.webp","anim":true,"free":true}'::jsonb, false, 1041),
  ('a_1f618', 'sticker', '😘', 'common', '{"e":"😘","img":"/brand/stk/1f618.webp","anim":true,"free":true}'::jsonb, false, 1042),
  ('a_1f48b', 'sticker', '💋', 'common', '{"e":"💋","img":"/brand/stk/1f48b.webp","anim":true,"free":true}'::jsonb, false, 1043),
  ('a_1f648', 'sticker', '🙈', 'common', '{"e":"🙈","img":"/brand/stk/1f648.webp","anim":true,"free":true}'::jsonb, false, 1044),
  ('a_1f440', 'sticker', '👀', 'common', '{"e":"👀","img":"/brand/stk/1f440.webp","anim":true,"free":true}'::jsonb, false, 1045),
  ('a_1f64f', 'sticker', '🙏', 'common', '{"e":"🙏","img":"/brand/stk/1f64f.webp","anim":true,"free":true}'::jsonb, false, 1046),
  ('a_1f44c', 'sticker', '👌', 'common', '{"e":"👌","img":"/brand/stk/1f44c.webp","anim":true,"free":true}'::jsonb, false, 1047),
  ('a_1f91d', 'sticker', '🤝', 'common', '{"e":"🤝","img":"/brand/stk/1f91d.webp","anim":true,"free":true}'::jsonb, false, 1048),
  ('a_1f64c', 'sticker', '🙌', 'common', '{"e":"🙌","img":"/brand/stk/1f64c.webp","anim":true,"free":true}'::jsonb, false, 1049),
  ('a_1f4aa', 'sticker', '💪', 'common', '{"e":"💪","img":"/brand/stk/1f4aa.webp","anim":true,"free":true}'::jsonb, false, 1050),
  ('a_1fae1', 'sticker', '🫡', 'common', '{"e":"🫡","img":"/brand/stk/1fae1.webp","anim":true,"free":true}'::jsonb, false, 1051),
  ('a_1faf6', 'sticker', '🫶', 'common', '{"e":"🫶","img":"/brand/stk/1faf6.webp","anim":true,"free":true}'::jsonb, false, 1052),
  ('a_1f917', 'sticker', '🤗', 'common', '{"e":"🤗","img":"/brand/stk/1f917.webp","anim":true,"free":true}'::jsonb, false, 1053),
  ('a_1f496', 'sticker', '💖', 'common', '{"e":"💖","img":"/brand/stk/1f496.webp","anim":true,"free":true}'::jsonb, false, 1054),
  ('a_1f494', 'sticker', '💔', 'common', '{"e":"💔","img":"/brand/stk/1f494.webp","anim":true,"free":true}'::jsonb, false, 1055),
  ('a_2728', 'sticker', '✨', 'common', '{"e":"✨","img":"/brand/stk/2728.webp","anim":true,"free":true}'::jsonb, false, 1056),
  ('a_1f31f', 'sticker', '🌟', 'common', '{"e":"🌟","img":"/brand/stk/1f31f.webp","anim":true,"free":true}'::jsonb, false, 1057),
  ('a_26a1', 'sticker', '⚡', 'common', '{"e":"⚡","img":"/brand/stk/26a1.webp","anim":true,"free":true}'::jsonb, false, 1058),
  ('a_1f308', 'sticker', '🌈', 'common', '{"e":"🌈","img":"/brand/stk/1f308.webp","anim":true,"free":true}'::jsonb, false, 1059),
  ('a_1f3c6', 'sticker', '🏆', 'common', '{"e":"🏆","img":"/brand/stk/1f3c6.webp","anim":true,"free":true}'::jsonb, false, 1060),
  ('a_1f37e', 'sticker', '🍾', 'common', '{"e":"🍾","img":"/brand/stk/1f37e.webp","anim":true,"free":true}'::jsonb, false, 1061),
  ('a_1f382', 'sticker', '🎂', 'common', '{"e":"🎂","img":"/brand/stk/1f382.webp","anim":true,"free":true}'::jsonb, false, 1062),
  ('a_1f388', 'sticker', '🎈', 'common', '{"e":"🎈","img":"/brand/stk/1f388.webp","anim":true,"free":true}'::jsonb, false, 1063),
  ('a_1f984', 'sticker', '🦄', 'common', '{"e":"🦄","img":"/brand/stk/1f984.webp","anim":true,"free":true}'::jsonb, false, 1064),
  ('a_1f431', 'sticker', '🐱', 'common', '{"e":"🐱","img":"/brand/stk/1f431.webp","anim":true,"free":true}'::jsonb, false, 1065),
  ('a_1f4a9', 'sticker', '💩', 'common', '{"e":"💩","img":"/brand/stk/1f4a9.webp","anim":true,"free":true}'::jsonb, false, 1066),
  ('a_1f621', 'sticker', '😡', 'common', '{"e":"😡","img":"/brand/stk/1f621.webp","anim":true,"free":true}'::jsonb, false, 1067),
  ('a_1f911', 'sticker', '🤑', 'common', '{"e":"🤑","img":"/brand/stk/1f911.webp","anim":true,"free":true}'::jsonb, false, 1068),
  ('a_1f60a', 'sticker', '😊', 'common', '{"e":"😊","img":"/brand/stk/1f60a.webp","anim":true,"free":true}'::jsonb, false, 1069),
  ('a_1f643', 'sticker', '🙃', 'common', '{"e":"🙃","img":"/brand/stk/1f643.webp","anim":true,"free":true}'::jsonb, false, 1070),
  ('e_18', 'sticker', '⭐', 'common', '{"e":"⭐","free":true}'::jsonb, false, 1071),
  ('e_20', 'sticker', '🍀', 'common', '{"e":"🍀","free":true}'::jsonb, false, 1072),
  ('e_23', 'sticker', '🐶', 'common', '{"e":"🐶","free":true}'::jsonb, false, 1073),
  ('e_25', 'sticker', '🐰', 'common', '{"e":"🐰","free":true}'::jsonb, false, 1074),
  ('e_26', 'sticker', '🐻', 'common', '{"e":"🐻","free":true}'::jsonb, false, 1075),
  ('e_27', 'sticker', '🐼', 'common', '{"e":"🐼","free":true}'::jsonb, false, 1076),
  ('e_28', 'sticker', '🐨', 'common', '{"e":"🐨","free":true}'::jsonb, false, 1077),
  ('e_29', 'sticker', '🦊', 'common', '{"e":"🦊","free":true}'::jsonb, false, 1078),
  ('e_30', 'sticker', '🐸', 'common', '{"e":"🐸","free":true}'::jsonb, false, 1079),
  ('e_31', 'sticker', '🐥', 'common', '{"e":"🐥","free":true}'::jsonb, false, 1080),
  ('e_32', 'sticker', '🐧', 'common', '{"e":"🐧","free":true}'::jsonb, false, 1081),
  ('e_33', 'sticker', '🐹', 'common', '{"e":"🐹","free":true}'::jsonb, false, 1082),
  ('e_34', 'sticker', '🦋', 'common', '{"e":"🦋","free":true}'::jsonb, false, 1083),
  ('e_35', 'sticker', '🌸', 'common', '{"e":"🌸","free":true}'::jsonb, false, 1084),
  ('e_36', 'sticker', '🌷', 'common', '{"e":"🌷","free":true}'::jsonb, false, 1085),
  ('e_37', 'sticker', '🌻', 'common', '{"e":"🌻","free":true}'::jsonb, false, 1086),
  ('e_38', 'sticker', '🌼', 'common', '{"e":"🌼","free":true}'::jsonb, false, 1087),
  ('e_39', 'sticker', '💐', 'common', '{"e":"💐","free":true}'::jsonb, false, 1088),
  ('e_40', 'sticker', '🍓', 'common', '{"e":"🍓","free":true}'::jsonb, false, 1089),
  ('e_41', 'sticker', '🍑', 'common', '{"e":"🍑","free":true}'::jsonb, false, 1090),
  ('e_42', 'sticker', '🍒', 'common', '{"e":"🍒","free":true}'::jsonb, false, 1091),
  ('e_43', 'sticker', '🍉', 'common', '{"e":"🍉","free":true}'::jsonb, false, 1092),
  ('e_44', 'sticker', '🍰', 'common', '{"e":"🍰","free":true}'::jsonb, false, 1093),
  ('e_45', 'sticker', '🍕', 'common', '{"e":"🍕","free":true}'::jsonb, false, 1094),
  ('e_46', 'sticker', '🍔', 'common', '{"e":"🍔","free":true}'::jsonb, false, 1095),
  ('e_47', 'sticker', '🍟', 'common', '{"e":"🍟","free":true}'::jsonb, false, 1096),
  ('e_48', 'sticker', '🍩', 'common', '{"e":"🍩","free":true}'::jsonb, false, 1097),
  ('e_49', 'sticker', '🍦', 'common', '{"e":"🍦","free":true}'::jsonb, false, 1098),
  ('e_50', 'sticker', '🧋', 'common', '{"e":"🧋","free":true}'::jsonb, false, 1099),
  ('e_51', 'sticker', '☕', 'common', '{"e":"☕","free":true}'::jsonb, false, 1100),
  ('e_52', 'sticker', '🍺', 'common', '{"e":"🍺","free":true}'::jsonb, false, 1101),
  ('e_53', 'sticker', '🎀', 'common', '{"e":"🎀","free":true}'::jsonb, false, 1102),
  ('e_54', 'sticker', '🎁', 'common', '{"e":"🎁","free":true}'::jsonb, false, 1103),
  ('e_55', 'sticker', '🧸', 'common', '{"e":"🧸","free":true}'::jsonb, false, 1104),
  ('e_56', 'sticker', '🌙', 'common', '{"e":"🌙","free":true}'::jsonb, false, 1105),
  ('e_57', 'sticker', '☀️', 'common', '{"e":"☀️","free":true}'::jsonb, false, 1106),
  ('e_58', 'sticker', '☁️', 'common', '{"e":"☁️","free":true}'::jsonb, false, 1107),
  ('e_59', 'sticker', '🫧', 'common', '{"e":"🫧","free":true}'::jsonb, false, 1108),
  ('e_60', 'sticker', '🌊', 'common', '{"e":"🌊","free":true}'::jsonb, false, 1109),
  ('e_61', 'sticker', '📸', 'common', '{"e":"📸","free":true}'::jsonb, false, 1110),
  ('e_62', 'sticker', '🎵', 'common', '{"e":"🎵","free":true}'::jsonb, false, 1111),
  ('e_63', 'sticker', '🎧', 'common', '{"e":"🎧","free":true}'::jsonb, false, 1112),
  ('e_64', 'sticker', '💎', 'common', '{"e":"💎","free":true}'::jsonb, false, 1113),
  ('e_65', 'sticker', '👑', 'common', '{"e":"👑","free":true}'::jsonb, false, 1114),
  ('e_66', 'sticker', '🕶️', 'common', '{"e":"🕶️","free":true}'::jsonb, false, 1115),
  ('e_67', 'sticker', '💄', 'common', '{"e":"💄","free":true}'::jsonb, false, 1116),
  ('e_68', 'sticker', '💅', 'common', '{"e":"💅","free":true}'::jsonb, false, 1117),
  ('e_69', 'sticker', '🧿', 'common', '{"e":"🧿","free":true}'::jsonb, false, 1118),
  ('e_70', 'sticker', '⚽', 'common', '{"e":"⚽","free":true}'::jsonb, false, 1119),
  ('e_71', 'sticker', '🏀', 'common', '{"e":"🏀","free":true}'::jsonb, false, 1120),
  ('e_72', 'sticker', '🎮', 'common', '{"e":"🎮","free":true}'::jsonb, false, 1121),
  ('e_73', 'sticker', '🚀', 'common', '{"e":"🚀","free":true}'::jsonb, false, 1122),
  ('e_74', 'sticker', '📍', 'common', '{"e":"📍","free":true}'::jsonb, false, 1123)
on conflict (id) do update set name = excluded.name, data = excluded.data, active = false, sort = excluded.sort;

-- 2) 은퇴: 새로 붙일 수 없게(free 해제). 텍스트 스티커 t_text 포함
update public.items set data = (data - 'free') || '{"retired": true}'::jsonb
 where id in ('e_01', 'e_02', 'e_03', 'e_04', 'e_05', 'e_06', 'e_07', 'e_08', 'e_09', 'e_10', 'e_11', 'e_12', 'e_13', 'e_14', 'e_15', 'e_16', 'e_17', 'e_19', 'e_21', 'e_22', 'e_24', 'm_kkk', 'm_legend', 'm_insaeng', 'm_heart', 'm_sparkle', 'm_mustache', 'm_glasses', 'm_blush', 'm_me', 'm_crown', 't_text');

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
