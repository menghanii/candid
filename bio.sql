-- candid. 프로필 메시지: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
alter table public.profiles add column if not exists bio text;
alter table public.profiles drop constraint if exists profiles_bio_len;
alter table public.profiles add constraint profiles_bio_len check (bio is null or char_length(bio) <= 60);
grant update (name, avatar_url, onboarded, bio) on public.profiles to authenticated;
