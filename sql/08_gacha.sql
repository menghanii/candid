-- candid. 가챠 꾸미기: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 뽑기·뽑기권 계산·장착은 모두 이 DB 함수에서만 처리 → 앱을 조작해도 결과를 바꿀 수 없음
-- 아이템 목록은 tools/items.js 에서 관리 (node tools/items.js 로 아래 목록 자동 갱신)

-- 1) 아이템 카탈로그 (누구나 읽기)
create table if not exists public.items (
  id text primary key,
  kind text not null check (kind in ('frame', 'theme', 'sticker', 'name')),
  name text not null,
  rarity text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  data jsonb not null default '{}',
  active boolean not null default true,
  sort int not null default 0
);
alter table public.items enable row level security;
drop policy if exists "items read" on public.items;
create policy "items read" on public.items for select using (true);
grant select on public.items to anon, authenticated;

-- @@ITEMS-BEGIN (tools/items.js 에서 자동 생성 — 직접 고치지 말 것)
insert into public.items (id, kind, name, rarity, data, sort) values
  ('frame_mint', 'frame', '민트 링', 'common', '{"bg":"#3ee8b5"}'::jsonb, 0),
  ('frame_peach', 'frame', '피치 링', 'common', '{"bg":"#ffb199"}'::jsonb, 1),
  ('frame_mono', 'frame', '체커 링', 'common', '{"bg":"repeating-conic-gradient(#fff 0 15deg,#111 0 30deg)"}'::jsonb, 2),
  ('frame_sunset', 'frame', '선셋', 'rare', '{"bg":"linear-gradient(135deg,#ff7e5f,#feb47b)"}'::jsonb, 3),
  ('frame_ocean', 'frame', '오션', 'rare', '{"bg":"linear-gradient(135deg,#2b50ff,#00d2ff)"}'::jsonb, 4),
  ('frame_neon', 'frame', '네온', 'epic', '{"bg":"#39ff14","glow":"#39ff14"}'::jsonb, 5),
  ('frame_rainbow', 'frame', '레인보우', 'epic', '{"bg":"conic-gradient(#ff3b30,#ff9500,#ffcc00,#34c759,#00c7be,#2b50ff,#af52de,#ff3b30)","spin":true}'::jsonb, 6),
  ('frame_aurora', 'frame', '오로라', 'legendary', '{"bg":"conic-gradient(#00ffa3,#03e1ff,#dc1fff,#ff6ec7,#00ffa3)","spin":true,"glow":"#dc1fff"}'::jsonb, 7),
  ('theme_sky', 'theme', '하늘', 'common', '{"bg":"linear-gradient(160deg,#a1c4fd,#c2e9fb)"}'::jsonb, 8),
  ('theme_peach', 'theme', '복숭아', 'common', '{"bg":"linear-gradient(160deg,#ffecd2,#fcb69f)"}'::jsonb, 9),
  ('theme_mint', 'theme', '풀잎', 'common', '{"bg":"linear-gradient(160deg,#d4fc79,#96e6a1)"}'::jsonb, 10),
  ('theme_night', 'theme', '밤하늘', 'rare', '{"bg":"linear-gradient(160deg,#0f2027,#203a43,#2c5364)","stars":true}'::jsonb, 11),
  ('theme_berry', 'theme', '베리', 'rare', '{"bg":"linear-gradient(160deg,#8e2de2,#4a00e0)"}'::jsonb, 12),
  ('theme_film', 'theme', '필름', 'epic', '{"bg":"linear-gradient(160deg,#1c1c1c,#3a3a3a)","film":true}'::jsonb, 13),
  ('theme_galaxy', 'theme', '갤럭시', 'legendary', '{"bg":"radial-gradient(circle at 20% 30%,#ff6ec7 0,transparent 38%),radial-gradient(circle at 80% 20%,#2b50ff 0,transparent 42%),radial-gradient(circle at 60% 95%,#00ffa3 0,transparent 38%),#0b0b2a","stars":true}'::jsonb, 14),
  ('sticker_daisy', 'sticker', '데이지', 'common', '{"e":"🌼"}'::jsonb, 15),
  ('sticker_star', 'sticker', '별', 'common', '{"e":"⭐"}'::jsonb, 16),
  ('sticker_clover', 'sticker', '네잎클로버', 'common', '{"e":"🍀"}'::jsonb, 17),
  ('sticker_camera', 'sticker', '카메라', 'common', '{"e":"📸"}'::jsonb, 18),
  ('sticker_cat', 'sticker', '고양이', 'rare', '{"e":"🐱"}'::jsonb, 19),
  ('sticker_berry', 'sticker', '딸기', 'rare', '{"e":"🍓"}'::jsonb, 20),
  ('sticker_unicorn', 'sticker', '유니콘', 'epic', '{"e":"🦄"}'::jsonb, 21),
  ('sticker_fire', 'sticker', '불꽃', 'epic', '{"e":"🔥"}'::jsonb, 22),
  ('sticker_crown', 'sticker', '왕관', 'legendary', '{"e":"👑"}'::jsonb, 23),
  ('name_blue', 'name', '블루 네임', 'common', '{"color":"#2b50ff"}'::jsonb, 24),
  ('name_sunset', 'name', '선셋 네임', 'rare', '{"grad":"linear-gradient(90deg,#ff7e5f,#feb47b)"}'::jsonb, 25),
  ('name_glow', 'name', '글로우 네임', 'epic', '{"glow":"#5c7cff"}'::jsonb, 26),
  ('name_holo', 'name', '홀로그램 네임', 'legendary', '{"grad":"linear-gradient(90deg,#00ffa3,#03e1ff,#dc1fff,#ff6ec7,#00ffa3)","anim":true}'::jsonb, 27)
on conflict (id) do update set kind = excluded.kind, name = excluded.name, rarity = excluded.rarity, data = excluded.data, sort = excluded.sort, active = true;
-- @@ITEMS-END

-- 2) 보유 아이템 (본인만 읽기, 쓰기는 함수만)
create table if not exists public.inventory (
  user_id uuid not null references public.profiles on delete cascade,
  item_id text not null references public.items on delete cascade,
  count int not null default 1,
  first_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
alter table public.inventory enable row level security;
drop policy if exists "inventory own" on public.inventory;
create policy "inventory own" on public.inventory for select to authenticated using (user_id = auth.uid());
grant select on public.inventory to authenticated;

-- 3) 뽑기 기록 (본인만 읽기)
create table if not exists public.gacha_pulls (
  id bigserial primary key,
  user_id uuid not null references public.profiles on delete cascade,
  item_id text not null references public.items,
  rarity text not null,
  created_at timestamptz not null default now()
);
create index if not exists gacha_pulls_user_idx on public.gacha_pulls (user_id);
alter table public.gacha_pulls enable row level security;
drop policy if exists "pulls own" on public.gacha_pulls;
create policy "pulls own" on public.gacha_pulls for select to authenticated using (user_id = auth.uid());
grant select on public.gacha_pulls to authenticated;

-- 4) 장착 정보: {"frame": id, "theme": id, "name": id, "stickers": [id, ...]} — 친구도 볼 수 있게 프로필에 저장
alter table public.profiles add column if not exists equipped jsonb not null default '{}';

-- 5) 뽑기권 = 가입 선물 3장 + 승인 보상 - 사용한 장수
--    승인 보상: 내 피드에 승인된 게시물 기준, 하루(한국 시간) 최대 3장, 같은 친구 이름은 하루 1장
create or replace function public.gacha_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); earned int; used int;
begin
  if uid is null then raise exception 'login_required'; end if;
  select coalesce(sum(least(n, 3)), 0) into earned from (
    select (approved_at at time zone 'Asia/Seoul')::date as d, count(distinct lower(author_name)) as n
      from public.posts where owner_id = uid and status = 'approved' and approved_at is not null
     group by 1) x;
  select count(*) into used from public.gacha_pulls where user_id = uid;
  return jsonb_build_object('tickets', greatest(0, earned + 3 - used), 'earned', earned, 'used', used, 'bonus', 3);
end $$;

-- 6) 뽑기: 일반 60% · 레어 30% · 에픽 9% · 전설 1%
create or replace function public.pull_gacha() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); st jsonb; r float8; rar text; it record; cnt int;
begin
  if uid is null then raise exception 'login_required'; end if;
  perform pg_advisory_xact_lock(hashtext('gacha:' || uid::text)); -- 동시에 여러 번 눌러도 한 번씩만
  st := public.gacha_status();
  if (st->>'tickets')::int < 1 then raise exception 'no_ticket'; end if;
  r := random();
  rar := case when r < 0.01 then 'legendary' when r < 0.10 then 'epic' when r < 0.40 then 'rare' else 'common' end;
  select * into it from public.items where rarity = rar and active order by random() limit 1;
  insert into public.inventory (user_id, item_id) values (uid, it.id)
    on conflict (user_id, item_id) do update set count = public.inventory.count + 1
    returning count into cnt;
  insert into public.gacha_pulls (user_id, item_id, rarity) values (uid, it.id, rar);
  return jsonb_build_object('id', it.id, 'kind', it.kind, 'name', it.name, 'rarity', rar, 'count', cnt,
                            'tickets', (st->>'tickets')::int - 1);
end $$;

-- 7) 장착/해제: 가진 아이템만. 스티커는 최대 3개(넘으면 가장 오래된 것 빼고 추가), 같은 걸 다시 누르면 해제
create or replace function public.equip_item(p_kind text, p_item text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); eq jsonb; arr jsonb;
begin
  if uid is null then raise exception 'login_required'; end if;
  if p_kind not in ('frame', 'theme', 'sticker', 'name') then raise exception 'bad_kind'; end if;
  if p_item is not null and not exists (
    select 1 from public.inventory i join public.items t on t.id = i.item_id
     where i.user_id = uid and i.item_id = p_item and t.kind = p_kind) then
    raise exception 'not_owned';
  end if;
  select coalesce(equipped, '{}') into eq from public.profiles where id = uid;
  if p_kind = 'sticker' then
    arr := coalesce(eq->'stickers', '[]');
    if p_item is null then arr := '[]';
    elsif arr ? p_item then arr := arr - p_item;
    else
      if jsonb_array_length(arr) >= 3 then arr := arr - 0; end if;
      arr := arr || to_jsonb(p_item);
    end if;
    eq := jsonb_set(eq, '{stickers}', arr);
  elsif p_item is null or eq->>p_kind = p_item then
    eq := eq - p_kind;
  else
    eq := jsonb_set(eq, array[p_kind], to_jsonb(p_item));
  end if;
  update public.profiles set equipped = eq where id = uid;
  return eq;
end $$;

revoke all on function public.gacha_status() from public, anon;
revoke all on function public.pull_gacha() from public, anon;
revoke all on function public.equip_item(text, text) from public, anon;
grant execute on function public.gacha_status() to authenticated;
grant execute on function public.pull_gacha() to authenticated;
grant execute on function public.equip_item(text, text) to authenticated;
