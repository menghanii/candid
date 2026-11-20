-- candid. 사진 받기 설정 + 로그인 없이 보낸 사람도 차단(기기 단위). SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 38 이후 실행
--  1) 피드 주인이 정함: 누가 보낼 수 있나(누구나 / 로그인한 사람만 / 내 친구만), 익명으로 받기(켜기/끄기)
--  2) 보낸 기기 표시(앱·브라우저마다 무작위 값)를 서버에만 기록 → 로그인 안 하고 보낸 사람도 '보낸 사람 차단' 가능
--     (게시물 칸에는 남기지 않음 — 넣는 순간 빼서 따로 보관. 받는 사람에게도 누군지 알려주지 않음)

-- 1) 받기 설정
alter table public.profiles add column if not exists send_policy text not null default 'anyone';
alter table public.profiles drop constraint if exists profiles_send_policy_check;
alter table public.profiles add constraint profiles_send_policy_check check (send_policy in ('anyone', 'login', 'friends'));
alter table public.profiles add column if not exists allow_anon boolean not null default true;
grant update (send_policy, allow_anon) on public.profiles to authenticated;

-- 2) 보낸 기기
alter table public.posts add column if not exists sender_device text;
alter table public.posts drop constraint if exists posts_sender_device_len;
alter table public.posts add constraint posts_sender_device_len check (sender_device is null or char_length(sender_device) <= 64);
alter table public.post_senders alter column user_id drop not null;
alter table public.post_senders add column if not exists device text;

create table if not exists public.device_blocks (
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  device text not null,
  created_at timestamptz not null default now(),
  primary key (owner_id, device)
);
alter table public.device_blocks enable row level security; -- 정책 없음 = 함수로만
revoke all on public.device_blocks from anon, authenticated;

-- 보내기 전 확인(친구 피드에 보낼 때만): 받기 설정·차단을 지키고, 기기 값은 빼서 따로 보관
create or replace function public.posts_send_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare o public.profiles;
begin
  if new.group_id is not null then return new; end if;
  select * into o from public.profiles where id = new.owner_id;
  if o.id is null or o.id = auth.uid() then
    perform set_config('candid.dev', '', true); new.sender_device := null; return new;
  end if;
  if o.send_policy = 'login' and auth.uid() is null then raise exception 'send_login_required' using errcode = 'P0001'; end if;
  if o.send_policy = 'friends' and not exists (select 1 from public.follows f where f.follower_id = o.id and f.followee_id = auth.uid()) then
    raise exception 'send_friends_only' using errcode = 'P0001';
  end if;
  if not o.allow_anon and new.author_name = '익명의 친구' then raise exception 'send_no_anon' using errcode = 'P0001'; end if;
  if auth.uid() is not null and public.is_blocked_pair(auth.uid(), o.id) then raise exception 'send_blocked' using errcode = 'P0001'; end if;
  if new.sender_device is not null and exists (select 1 from public.device_blocks d where d.owner_id = o.id and d.device = new.sender_device) then
    raise exception 'send_blocked' using errcode = 'P0001';
  end if;
  perform set_config('candid.dev', coalesce(new.sender_device, ''), true);
  new.sender_device := null;
  return new;
end $$;
drop trigger if exists posts_send_guard on public.posts;
create trigger posts_send_guard before insert on public.posts for each row execute function public.posts_send_guard();

-- 이름을 안 밝힌 보냄(익명 · 로그인 없이)은 보낸 계정·기기를 서버에만 기록
create or replace function public.posts_note_sender() returns trigger
language plpgsql security definer set search_path = '' as $$
declare dev text := nullif(current_setting('candid.dev', true), '');
begin
  if new.group_id is null and new.author_id is null and (auth.uid() is not null or dev is not null) then
    insert into public.post_senders (post_id, user_id, device) values (new.id, auth.uid(), dev) on conflict do nothing;
  end if;
  return null;
end $$;

-- 받은 사람(피드 주인)이 보낸 사람을 차단: 계정이면 계정 차단, 기기만 있으면 그 기기에서 더 못 보내게. 누군지는 돌려주지 않음
create or replace function public.block_anon_sender(p_post uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s uuid; d text; done boolean := false;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select ps.user_id, ps.device into s, d from public.post_senders ps join public.posts p on p.id = ps.post_id
   where ps.post_id = p_post and p.owner_id = auth.uid();
  if s is not null and s <> auth.uid() then
    insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), s) on conflict do nothing;
    delete from public.follows where (follower_id = auth.uid() and followee_id = s) or (follower_id = s and followee_id = auth.uid());
    done := true;
  end if;
  if d is not null then
    insert into public.device_blocks (owner_id, device) values (auth.uid(), d) on conflict do nothing;
    done := true;
  end if;
  return done;
end $$;
revoke all on function public.block_anon_sender(uuid) from public, anon;
grant execute on function public.block_anon_sender(uuid) to authenticated;
