-- candid. 스티커 꾸미기: 텍스트(최대 40자) + 회전 — SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 10_free_stickers.sql 이후 실행

-- 1) 스티커에 회전·텍스트·텍스트 스타일 칸 추가
alter table public.post_stickers add column if not exists rot real not null default 0;
alter table public.post_stickers add column if not exists text text;
alter table public.post_stickers add column if not exists style text;
alter table public.post_stickers drop constraint if exists post_stickers_rot_range;
alter table public.post_stickers add constraint post_stickers_rot_range check (rot between -180 and 180);
alter table public.post_stickers drop constraint if exists post_stickers_text_len;
alter table public.post_stickers add constraint post_stickers_text_len check (text is null or char_length(text) between 1 and 40);
alter table public.post_stickers drop constraint if exists post_stickers_style_kind;
alter table public.post_stickers add constraint post_stickers_style_kind check (style is null or style in ('plain', 'box', 'hl'));

-- 2) 텍스트 스티커용 무료 아이템(누구나 사용, 가챠 대상 아님)
insert into public.items (id, kind, name, rarity, data, active, sort)
values ('t_text', 'sticker', '텍스트', 'common', '{"free": true, "text": true}'::jsonb, false, 999)
on conflict (id) do update set data = excluded.data, active = false;

-- 3) 자기 스티커는 위치·크기·회전·글자·스타일 수정 가능
revoke update on public.post_stickers from authenticated;
grant update (x, y, scale, rot, text, style, updated_at) on public.post_stickers to authenticated;
