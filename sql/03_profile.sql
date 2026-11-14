-- candid. 프로필 설정(이름/사진 직접 선택): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 프로필 컬럼: 온보딩 완료 여부, 소셜(카카오/Google) 프로필 사진 보관
alter table public.profiles add column if not exists onboarded boolean not null default false;
alter table public.profiles add column if not exists social_avatar_url text;

-- 기존 가입자: 소셜 사진은 따로 보관하고, 기본은 기본 아이콘(null)으로
update public.profiles
   set social_avatar_url = coalesce(social_avatar_url, avatar_url), avatar_url = null
 where onboarded = false;

-- 2) 신규 가입 시: 이름은 소셜 이름, 사진은 기본 아이콘(null), 소셜 사진은 선택지로만 보관
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name, avatar_url, social_avatar_url) values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'nickname',
      new.raw_user_meta_data->>'preferred_username',
      split_part(new.email, '@', 1),
      '친구'), 20),
    null,
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture')
  ) on conflict (id) do nothing;
  return new;
end $$;

-- 3) 본인이 바꿀 수 있는 컬럼만 허용
revoke update on public.profiles from authenticated;
grant update (name, avatar_url, onboarded) on public.profiles to authenticated;

-- 4) 프로필 사진 저장소: avatars/{user_id}/{uuid}.jpg, 본인만 업로드/삭제
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "avatars upload" on storage.objects;
create policy "avatars upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars delete" on storage.objects;
create policy "avatars delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
