-- candid. 아이디(@handle): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 규칙: 영문 소문자·숫자·밑줄 3~20자, 중복 불가, 예약어 금지. 로그인은 소셜 그대로(아이디는 프로필·검색·링크용)

alter table public.profiles add column if not exists handle text;

-- 1) 아이디 자동 생성: 이메일 앞부분(영문)을 다듬어 쓰고, 없거나 겹치면 숫자를 붙임
create or replace function public.gen_handle(base text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  b text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]', '', 'g'), 14);
  h text;
begin
  if char_length(b) < 3 or b in ('admin','candid','help','support','root','system','null','undefined','api','www','official','me','settings')
    then b := 'user'; end if;
  h := b;
  while exists (select 1 from public.profiles where handle = h) loop
    h := b || '_' || (floor(random() * 9000) + 1000)::int;
  end loop;
  return h;
end $$;

-- 2) 기존 사용자 채우기 (데모 친구는 이메일 앞부분이 jisoo 등이라 그대로 씀)
update public.profiles p
   set handle = public.gen_handle(split_part(u.email, '@', 1))
  from auth.users u
 where u.id = p.id and p.handle is null;
update public.profiles set handle = public.gen_handle(null) where handle is null;

-- 3) 형식·중복 제약
alter table public.profiles drop constraint if exists profiles_handle_format;
alter table public.profiles add constraint profiles_handle_format check (
  handle ~ '^[a-z0-9_]{3,20}$'
  and handle not in ('admin','candid','help','support','root','system','null','undefined','api','www','official','me','settings')
);
create unique index if not exists profiles_handle_key on public.profiles (handle);
alter table public.profiles alter column handle set not null;

-- 4) 새 가입자도 자동 생성 (가입 트리거 갱신)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, name, avatar_url, social_avatar_url, handle) values (
    new.id,
    left(coalesce(
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'nickname',
      new.raw_user_meta_data->>'preferred_username',
      split_part(new.email, '@', 1),
      '친구'), 20),
    null,
    coalesce(new.raw_user_meta_data->>'avatar_url', new.raw_user_meta_data->>'picture'),
    public.gen_handle(split_part(new.email, '@', 1))
  ) on conflict (id) do nothing;
  return new;
end $$;

-- 5) 본인이 바꿀 수 있는 칸에 handle 추가
grant update (name, avatar_url, onboarded, bio, handle) on public.profiles to authenticated;
