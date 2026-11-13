-- candid. 스키마: Supabase 대시보드 > SQL Editor 에 통째로 붙여넣고 Run

-- 1) 프로필 (로그인한 주인장)
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- 소셜 로그인으로 가입하면 프로필 자동 생성
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name, avatar_url) values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'nickname',
      new.raw_user_meta_data->>'preferred_username',
      split_part(new.email, '@', 1),
      '친구'), 30),
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture')
  ) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2) 게시물 (친구가 던진 것)
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles on delete cascade,
  author_id uuid default auth.uid(),          -- 비로그인 친구면 null
  author_name text not null check (char_length(author_name) between 1 and 12),
  mission text check (char_length(mission) <= 40),
  text text check (char_length(text) <= 80),
  image_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved')),
  created_at timestamptz not null default now(),
  approved_at timestamptz
);
create index if not exists posts_owner_idx on public.posts (owner_id, status);

-- 3) 권한 (RLS)
alter table public.profiles enable row level security;
alter table public.posts enable row level security;

-- API 접근 권한 (자동 노출을 끈 프로젝트에서도 동작하도록 필요한 것만 명시)
grant select on public.profiles to anon, authenticated;
grant update (name, avatar_url) on public.profiles to authenticated;
grant select, insert on public.posts to anon, authenticated;
grant update, delete on public.posts to authenticated;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select using (true);
drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update" on public.profiles for update using (auth.uid() = id);

-- 공개: 승인된 것만 / 주인장: 대기함까지
drop policy if exists "posts read" on public.posts;
create policy "posts read" on public.posts for select
  using (status = 'approved' or owner_id = auth.uid());

-- 누구나(비로그인 포함) 던질 수 있지만, 무조건 승인 대기 상태로만
drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    status = 'pending' and approved_at is null
    and (author_id is null or author_id = auth.uid())
    and image_path like owner_id::text || '/%'
  );

-- 승인/거절/내리기는 주인장만
drop policy if exists "posts owner update" on public.posts;
create policy "posts owner update" on public.posts for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "posts owner delete" on public.posts;
create policy "posts owner delete" on public.posts for delete using (owner_id = auth.uid());

-- 4) 사진 저장소: photos/{owner_id}/{uuid}.jpg, jpeg 2MB 이하
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "photos upload" on storage.objects;
create policy "photos upload" on storage.objects for insert to anon, authenticated
  with check (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] in (select id::text from public.profiles)
  );
drop policy if exists "photos owner delete" on storage.objects;
create policy "photos owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
