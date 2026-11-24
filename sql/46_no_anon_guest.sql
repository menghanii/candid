-- 46: '익명으로 받지 않기'를 켠 사람에게는 로그인하지 않은 사람도 보낼 수 없게
--  (예전에는 '익명의 친구' 이름만 막아서, 로그인 없이 이름을 직접 적으면 보낼 수 있었음 — 다른 사람 이름을 적어 사칭도 가능)
--  40_send_rules.sql 의 posts_send_guard 를 이 한 줄만 바꿔 다시 만듦. Supabase SQL Editor 에서 실행
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
  -- 익명을 받지 않으면: 로그인하지 않고(이름을 직접 적어) 보내는 것도 누군지 확인할 수 없으니 익명으로 봄
  if not o.allow_anon and (new.author_name = '익명의 친구' or auth.uid() is null) then raise exception 'send_no_anon' using errcode = 'P0001'; end if;
  if auth.uid() is not null and public.is_blocked_pair(auth.uid(), o.id) then raise exception 'send_blocked' using errcode = 'P0001'; end if;
  if new.sender_device is not null and exists (select 1 from public.device_blocks d where d.owner_id = o.id and d.device = new.sender_device) then
    raise exception 'send_blocked' using errcode = 'P0001';
  end if;
  perform set_config('candid.dev', coalesce(new.sender_device, ''), true);
  new.sender_device := null;
  return new;
end $$;
