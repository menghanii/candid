-- candid. 그룹에 친구 초대(이미 가입한 친구를 골라서): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 26_notifications.sql 이후 실행
--
--  · 그룹 멤버가 '내가 친구로 추가한 사람' 중에서 골라 초대(도배 방지: 아무나 초대 불가, 한 번에 50명까지)
--  · 받은 사람은 알림·그룹 탭에서 수락/거절
--  · 수락: 방장이 초대했거나 공개+바로 참여 그룹이면 바로 멤버(+팔로우), 그 밖에는 방장 승인 대기(초대 링크와 같음)
--  · 알림 목록(my_notifications)에 '초대' 추가
create table if not exists public.group_invites (
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,      -- 초대받은 사람
  invited_by uuid not null default auth.uid() references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_invites_user_idx on public.group_invites (user_id, created_at desc);
alter table public.group_invites enable row level security;
drop policy if exists "ginv read" on public.group_invites;
create policy "ginv read" on public.group_invites for select to authenticated
  using (user_id = auth.uid() or invited_by = auth.uid() or public.is_group_owner(group_id));
drop policy if exists "ginv cancel" on public.group_invites;
create policy "ginv cancel" on public.group_invites for delete to authenticated
  using (user_id = auth.uid() or invited_by = auth.uid() or public.is_group_owner(group_id));
revoke all on public.group_invites from anon, authenticated;
grant select, delete on public.group_invites to authenticated;   -- 초대는 invite_to_group 함수로만
grant select on public.group_invites to service_role;

-- 초대 보내기: 멤버만, 내가 친구로 추가한 사람만, 이미 멤버·신청 중인 사람은 건너뜀. 새로 보낸 수를 돌려줌
create or replace function public.invite_to_group(p_group uuid, p_users uuid[]) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if not public.is_group_member(p_group) then raise exception 'not_member' using errcode = 'P0001'; end if;
  if coalesce(array_length(p_users, 1), 0) > 50 then raise exception 'too_many' using errcode = 'P0001'; end if;
  with ins as (
    insert into public.group_invites (group_id, user_id, invited_by)
    select p_group, u, auth.uid() from unnest(p_users) u
     where u <> auth.uid()
       and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = u)
       and not exists (select 1 from public.group_members m where m.group_id = p_group and m.user_id = u)
    on conflict do nothing returning 1)
  select count(*) into n from ins;
  return n;
end $$;

-- 받은 초대 목록(그룹 탭용): 그룹 정보 + 초대한 사람
create or replace function public.my_group_invites() returns json
language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
      'group', json_build_object('id', g.id, 'handle', g.handle, 'name', g.name, 'cover_path', g.cover_path, 'visibility', g.visibility, 'member_count', g.member_count),
      'by', json_build_object('id', p.id, 'name', p.name, 'avatar_url', p.avatar_url),
      'at', gi.created_at) order by gi.created_at desc), '[]'::json)
    from public.group_invites gi
    join public.groups g on g.id = gi.group_id
    left join public.profiles p on p.id = gi.invited_by
   where gi.user_id = auth.uid()
$$;

-- 수락/거절: 거절이면 초대만 지움. 수락이면 방장 초대·공개 바로 참여 → 바로 멤버, 아니면 승인 대기
create or replace function public.answer_group_invite(p_group uuid, p_accept boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare inv public.group_invites; g public.groups; cur text;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into inv from public.group_invites where group_id = p_group and user_id = auth.uid();
  if inv.group_id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  delete from public.group_invites where group_id = p_group and user_id = auth.uid();
  if not p_accept then return 'declined'; end if;
  select * into g from public.groups where id = p_group;
  if g.id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  select status into cur from public.group_members where group_id = g.id and user_id = auth.uid();
  if cur is not null then return cur; end if;
  if inv.invited_by = g.owner_id or (g.visibility = 'public' and g.join_mode = 'open') then
    insert into public.group_members (group_id, user_id, status, approved_at) values (g.id, auth.uid(), 'active', now());
    insert into public.group_follows (group_id, user_id) values (g.id, auth.uid()) on conflict do nothing;
    return 'active';
  end if;
  insert into public.group_members (group_id, user_id, status) values (g.id, auth.uid(), 'pending');
  return 'pending';
end $$;
revoke all on function public.invite_to_group(uuid, uuid[]), public.my_group_invites(), public.answer_group_invite(uuid, boolean) from public, anon;
grant execute on function public.invite_to_group(uuid, uuid[]), public.my_group_invites(), public.answer_group_invite(uuid, boolean) to authenticated;

-- 알림 목록에 '초대' 추가(26 의 함수를 이것으로 바꿈)
create or replace function public.my_notifications(p_limit int default 60) returns json
language sql stable security definer set search_path = '' as $$
  with me as (select auth.uid() as id),
  since as (select now() - interval '30 days' as t),
  -- 반응이 올 수 있는 내 게시물: 내 피드에 올라간 것 + 내가 그룹에 올린 것
  mine as (
    select p.id from public.posts p
     where p.status = 'approved'
       and ((p.owner_id = (select id from me)) or (p.group_id is not null and p.author_id = (select id from me)))
  ),
  ev as (
    select 'post'::text as k, p.created_at as at, p.author_id as uid, p.id as post_id, null::text as body, null::uuid as group_id, p.author_name as nm
      from public.posts p
     where p.owner_id = (select id from me) and p.status = 'pending' and p.created_at >= (select t from since)
    union all
    select 'like', l.created_at, l.user_id, l.post_id, null, null, null
      from public.likes l join mine m on m.id = l.post_id
     where l.user_id <> (select id from me) and l.created_at >= (select t from since)
    union all
    select 'comment', c.created_at, c.user_id, c.post_id, c.body, null, null
      from public.comments c join mine m on m.id = c.post_id
     where c.user_id <> (select id from me) and c.created_at >= (select t from since)
    union all
    select 'sticker', s.created_at, s.user_id, s.post_id, null, null, null
      from public.post_stickers s join mine m on m.id = s.post_id
     where s.user_id <> (select id from me) and s.created_at >= (select t from since)
    union all
    select 'follow', f.created_at, f.follower_id, null, null, null, null
      from public.follows f
     where f.followee_id = (select id from me) and f.created_at >= (select t from since)
    union all
    select 'gjoin', gm.created_at, gm.user_id, null, null, gm.group_id, null
      from public.group_members gm join public.groups g on g.id = gm.group_id
     where g.owner_id = (select id from me) and gm.status = 'pending'
    union all
    select 'ginvite', gi.created_at, gi.invited_by, null, null, gi.group_id, null
      from public.group_invites gi
     where gi.user_id = (select id from me)
  ),
  top as (select * from ev where (select id from me) is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 200)))
  select coalesce(json_agg(json_build_object(
      'k', t.k, 'at', t.at, 'uid', t.uid, 'body', t.body, 'nm', t.nm,
      'prof', case when pr.id is null then null else json_build_object('id', pr.id, 'name', pr.name, 'handle', pr.handle, 'avatar_url', pr.avatar_url) end,
      'post', case when p.id is null then null else json_build_object(
          'id', p.id, 'status', p.status, 'author_name', p.author_name, 'author_id', p.author_id, 'mission', p.mission,
          'media_type', p.media_type, 'image_path', p.image_path, 'thumb_path', p.thumb_path, 'media', p.media, 'text', p.text,
          'created_at', p.created_at, 'group_id', p.group_id, 'ghandle', pg.handle) end,
      'group', case when g.id is null then null else json_build_object('id', g.id, 'handle', g.handle, 'name', g.name, 'owner_id', g.owner_id, 'cover_path', g.cover_path, 'visibility', g.visibility) end
    ) order by t.at desc), '[]'::json)
    from top t
    left join public.profiles pr on pr.id = t.uid
    left join public.posts p on p.id = t.post_id
    left join public.groups pg on pg.id = p.group_id
    left join public.groups g on g.id = t.group_id
$$;
revoke all on function public.my_notifications(int) from public, anon;
grant execute on function public.my_notifications(int) to authenticated;
