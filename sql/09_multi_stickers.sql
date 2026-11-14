-- candid. 여러 장 게시물 + 친구 사진 스티커 꾸미기: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 08_gacha.sql 이후에 실행 (스티커는 가챠로 뽑은 것만 쓸 수 있음)

-- 1) 여러 장 게시물: media = [{"p": 본문 경로, "t": 썸네일 경로, "k": "image"|"video"}, ...] 최대 10장
--    image_path/thumb_path/media_type 은 첫 장 기준으로 계속 채움(예전 화면·알림과 호환)
alter table public.posts add column if not exists media jsonb;
alter table public.posts drop constraint if exists posts_media_len;
alter table public.posts add constraint posts_media_len check (media is null or (jsonb_typeof(media) = 'array' and jsonb_array_length(media) between 1 and 10));

-- 모든 사진·영상 경로가 피드 주인 폴더 안인지 확인
create or replace function public.media_paths_ok(owner uuid, m jsonb) returns boolean
language sql immutable as $$
  select coalesce(bool_and(
           (e->>'p') like owner::text || '/%'
           and ((e->>'t') is null or (e->>'t') like owner::text || '/%')
           and coalesce(e->>'k', 'image') in ('image', 'video')), true)
    from jsonb_array_elements(coalesce(m, '[]'::jsonb)) e
$$;

drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    status = 'pending' and approved_at is null and answer is null
    and (author_id is null or author_id = auth.uid())
    and (
      (media_type in ('image', 'video') and image_path like owner_id::text || '/%'
        and (thumb_path is null or thumb_path like owner_id::text || '/%')
        and public.media_paths_ok(owner_id, media))
      or (media_type in ('poll', 'question') and image_path is null and thumb_path is null and media is null)
    )
  );

-- 2) 친구 사진 스티커: 스티커 하나 = 한 줄 → 여러 명이 동시에 붙여도 서로 덮어쓰지 않음
create table if not exists public.post_stickers (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts on delete cascade,
  media_idx int not null default 0 check (media_idx between 0 and 9),   -- 여러 장 중 몇 번째 사진
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  item_id text not null references public.items,
  x real not null check (x between 0 and 1),                            -- 사진 폭/높이 대비 위치(0~1)
  y real not null check (y between 0 and 1),
  scale real not null default 1 check (scale between 0.4 and 3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists post_stickers_post_idx on public.post_stickers (post_id);
alter table public.post_stickers enable row level security;

-- 보기: 피드에 올라간 게시물의 스티커는 누구나
drop policy if exists "stickers read" on public.post_stickers;
create policy "stickers read" on public.post_stickers for select
  using (exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));

-- 붙이기: 로그인 + 가챠로 가진 스티커만 + 1인당 사진 1장에 5개, 사진 1장 전체 30개까지
drop policy if exists "stickers add own" on public.post_stickers;
create policy "stickers add own" on public.post_stickers for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved' and p.media_type in ('image', 'video'))
    and exists (select 1 from public.inventory i join public.items t on t.id = i.item_id
                 where i.user_id = auth.uid() and i.item_id = post_stickers.item_id and t.kind = 'sticker')
    and (select count(*) from public.post_stickers s where s.post_id = post_stickers.post_id and s.media_idx = post_stickers.media_idx and s.user_id = auth.uid()) < 5
    and (select count(*) from public.post_stickers s where s.post_id = post_stickers.post_id and s.media_idx = post_stickers.media_idx) < 30
  );

-- 옮기기·크기: 자기 스티커만 (위치·크기 칸만 수정 가능)
drop policy if exists "stickers move own" on public.post_stickers;
create policy "stickers move own" on public.post_stickers for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 떼기: 자기 스티커 또는 피드 주인(승인 없는 대신 주인이 언제든 정리 가능)
drop policy if exists "stickers remove" on public.post_stickers;
create policy "stickers remove" on public.post_stickers for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.owner_id = auth.uid()));

grant select on public.post_stickers to anon, authenticated;
grant insert, delete on public.post_stickers to authenticated;
grant update (x, y, scale, updated_at) on public.post_stickers to authenticated;
