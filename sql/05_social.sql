-- candid. 친구·좋아요·댓글·동영상: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 게시물: 동영상 지원 + 썸네일 경로
alter table public.posts add column if not exists media_type text not null default 'image';
alter table public.posts drop constraint if exists posts_media_type;
alter table public.posts add constraint posts_media_type check (media_type in ('image', 'video'));
alter table public.posts add column if not exists thumb_path text;

drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    status = 'pending' and approved_at is null
    and (author_id is null or author_id = auth.uid())
    and image_path like owner_id::text || '/%'
    and (thumb_path is null or thumb_path like owner_id::text || '/%')
  );

-- 사진 저장소: WebP·동영상 허용, 파일당 10MB (클라이언트에서 압축해서 보통 사진 0.2MB, 10초 영상 2~3MB)
update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime']
 where id = 'photos';

-- 2) 친구 (한 방향 추가: follower 가 followee 를 친구로 추가)
create table if not exists public.follows (
  follower_id uuid not null default auth.uid() references public.profiles on delete cascade,
  followee_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee_idx on public.follows (followee_id);
alter table public.follows enable row level security;
drop policy if exists "follows read own" on public.follows;
create policy "follows read own" on public.follows for select to authenticated
  using (follower_id = auth.uid() or followee_id = auth.uid());
drop policy if exists "follows add own" on public.follows;
create policy "follows add own" on public.follows for insert to authenticated with check (follower_id = auth.uid());
drop policy if exists "follows remove own" on public.follows;
create policy "follows remove own" on public.follows for delete to authenticated using (follower_id = auth.uid());
grant select, insert, delete on public.follows to authenticated;

-- 3) 좋아요 (피드에 올라간 게시물에만)
create table if not exists public.likes (
  post_id uuid not null references public.posts on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.likes enable row level security;
drop policy if exists "likes read" on public.likes;
create policy "likes read" on public.likes for select
  using (exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));
drop policy if exists "likes add own" on public.likes;
create policy "likes add own" on public.likes for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));
drop policy if exists "likes remove own" on public.likes;
create policy "likes remove own" on public.likes for delete to authenticated using (user_id = auth.uid());
grant select on public.likes to anon, authenticated;
grant insert, delete on public.likes to authenticated;

-- 4) 댓글 (로그인 사용자만, 200자, 본인 또는 피드 주인이 삭제 가능)
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  body text not null check (char_length(body) between 1 and 200),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id, created_at);
alter table public.comments enable row level security;
drop policy if exists "comments read" on public.comments;
create policy "comments read" on public.comments for select
  using (exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));
drop policy if exists "comments add own" on public.comments;
create policy "comments add own" on public.comments for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));
drop policy if exists "comments delete" on public.comments;
create policy "comments delete" on public.comments for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.owner_id = auth.uid()));
grant select on public.comments to anon, authenticated;
grant insert, delete on public.comments to authenticated;
