-- candid. 보안 패치(엔지니어·디자이너 점검 1순위). SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 36 이후 실행
--  1) 남의 사진 파일이 지워지던 구멍: 다른 게시물·그룹 표지·프로필이 아직 쓰는 파일은 정리 대기열(storage_trash)에 못 들어가게
--     + 사진 수정 함수들은 게시물을 먼저 바꾼 뒤 대기열에 넣도록(자기 자신이 '쓰는 중'으로 잡히지 않게)
--  2) 차단 여부 조회: 나와 관련된 쌍만 답함(남끼리의 차단 관계가 드러나지 않게)
--  3) 친구·그룹 수: 비공개 피드는 볼 수 있는 사람에게만
--  4) 그룹 초대: 서로 친구(맞팔)이고 차단 관계가 아닐 때만, 한 사람이 하루 100명까지
--  5) 익명으로 보낸 사람: 서버에만 몰래 기록 → 받은 사람이 '이 익명 친구 차단·신고' 가능(누군지는 끝까지 안 알려줌)

-- ===== 1) 사진 파일 정리 대기열 지킴이 =====
create or replace function public.path_in_use(x text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.posts p
                  where p.image_path = x or p.thumb_path = x
                     or p.media @> jsonb_build_array(jsonb_build_object('p', x))
                     or p.media @> jsonb_build_array(jsonb_build_object('t', x)))
      or exists (select 1 from public.groups g where g.cover_path = x)
      or exists (select 1 from public.profiles u where u.avatar_url = x or u.avatar_url like '%/' || x)
$$;
revoke all on function public.path_in_use(text) from public, anon, authenticated;

create or replace function public.storage_trash_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.path_in_use(new.path) then return null; end if; -- 아직 누가 쓰는 파일: 지우지 않음
  return new;
end $$;
drop trigger if exists storage_trash_guard on public.storage_trash;
create trigger storage_trash_guard before insert on public.storage_trash for each row execute function public.storage_trash_guard();

-- 사진 빼기·더하기(보낸 사람): 게시물을 먼저 바꾸고 뺀 파일을 대기열로
create or replace function public.edit_post_media(p_post uuid, p_media jsonb) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  p public.posts; oldm jsonb; n int; i int; j int; added boolean; t timestamptz := now(); map int[]; gone text[] := '{}';
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into p from public.posts where id = p_post and author_id = auth.uid() and media_type in ('image', 'video') for update;
  if p.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if jsonb_typeof(p_media) is distinct from 'array' then raise exception 'bad_media' using errcode = 'P0001'; end if;
  n := jsonb_array_length(p_media);
  if n < 1 or n > 10 then raise exception 'bad_count' using errcode = 'P0001'; end if;
  if not public.media_paths_ok(coalesce(p.group_id, p.owner_id), p_media) then raise exception 'bad_path' using errcode = 'P0001'; end if;
  oldm := case when p.media is not null and jsonb_array_length(p.media) > 0 then p.media
               else jsonb_build_array(jsonb_build_object('p', p.image_path, 't', p.thumb_path, 'k', p.media_type)) end;
  added := exists (select 1 from jsonb_array_elements(p_media) e
                    where not exists (select 1 from jsonb_array_elements(oldm) o where o->>'p' = e->>'p'));
  if added and p.group_id is null and p.status <> 'pending' then raise exception 'no_add_after_approval' using errcode = 'P0001'; end if;
  if added and p.group_id is not null and not public.can_post_group(p.group_id) then raise exception 'closed' using errcode = 'P0001'; end if;
  map := array_fill(-1, array[jsonb_array_length(oldm)]);
  for i in 0 .. jsonb_array_length(oldm) - 1 loop
    j := null;
    select (x.ord - 1)::int into j from jsonb_array_elements(p_media) with ordinality x(e, ord) where x.e->>'p' = oldm->i->>'p' limit 1;
    if j is null then
      delete from public.post_stickers where post_id = p_post and media_idx = i;
      gone := gone || array[oldm->i->>'p', oldm->i->>'t'];
    else map[i + 1] := j; end if;
  end loop;
  update public.post_stickers set media_idx = map[media_idx + 1]
   where post_id = p_post and media_idx < array_length(map, 1) and map[media_idx + 1] >= 0 and map[media_idx + 1] <> media_idx;
  update public.posts set media = case when n > 1 then p_media else null end,
    image_path = p_media->0->>'p', thumb_path = p_media->0->>'t', media_type = coalesce(p_media->0->>'k', 'image'), edited_at = t
   where id = p_post;
  insert into public.storage_trash (path) select v from unnest(gone) v where v is not null and v !~ '^https?:' on conflict do nothing;
  return t;
end $$;

-- 순서 바꾸기·빼기(주인·방장): 같은 방식
create or replace function public.owner_edit_media(p_post uuid, p_keep int[]) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  p public.posts; oldm jsonb; newm jsonb := '[]'::jsonb; n int; i int; k int; t timestamptz := now(); map int[]; gone text[] := '{}';
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into p from public.posts where id = p_post and media_type in ('image', 'video') for update;
  if p.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if not ((p.group_id is null and p.owner_id = auth.uid()) or (p.group_id is not null and public.is_group_owner(p.group_id))) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  oldm := case when p.media is not null and jsonb_array_length(p.media) > 0 then p.media
               else jsonb_build_array(jsonb_build_object('p', p.image_path, 't', p.thumb_path, 'k', p.media_type)) end;
  n := coalesce(array_length(p_keep, 1), 0);
  if n < 1 then raise exception 'bad_count' using errcode = 'P0001'; end if;
  map := array_fill(-1, array[jsonb_array_length(oldm)]);
  for k in 1 .. n loop
    i := p_keep[k];
    if i is null or i < 0 or i >= jsonb_array_length(oldm) or map[i + 1] >= 0 then raise exception 'bad_order' using errcode = 'P0001'; end if;
    map[i + 1] := k - 1; newm := newm || jsonb_build_array(oldm->i);
  end loop;
  for i in 0 .. jsonb_array_length(oldm) - 1 loop
    if map[i + 1] < 0 then
      delete from public.post_stickers where post_id = p_post and media_idx = i;
      gone := gone || array[oldm->i->>'p', oldm->i->>'t'];
    end if;
  end loop;
  update public.post_stickers set media_idx = map[media_idx + 1]
   where post_id = p_post and media_idx < array_length(map, 1) and map[media_idx + 1] >= 0 and map[media_idx + 1] <> media_idx;
  update public.posts set media = case when n > 1 then newm else null end,
    image_path = newm->0->>'p', thumb_path = newm->0->>'t', media_type = coalesce(newm->0->>'k', 'image')
   where id = p_post;
  insert into public.storage_trash (path) select v from unnest(gone) v where v is not null and v !~ '^https?:' on conflict do nothing;
  return t;
end $$;

-- 친구 피드에 내가 보낸 사진 삭제: 먼저 지우고 파일을 대기열로
create or replace function public.delete_my_post(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.posts;
begin
  select * into p from public.posts where id = p_post and author_id = auth.uid() and group_id is null;
  if p.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  delete from public.posts where id = p_post;
  insert into public.storage_trash (path)
    select x from (
      select p.image_path as x union select p.thumb_path
      union select e->>'p' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e
      union select e->>'t' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e) s
    where x is not null and x !~ '^https?:'
  on conflict do nothing;
end $$;

-- ===== 2) 차단 여부: 나와 관련된 쌍만 =====
create or replace function public.is_blocked_pair(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select a is not null and b is not null and a <> b
     and auth.uid() is not null and auth.uid() in (a, b)
     and exists (select 1 from public.blocks x where (x.blocker_id = a and x.blocked_id = b) or (x.blocker_id = b and x.blocked_id = a))
$$;

-- ===== 3) 친구·그룹 수: 비공개 피드는 볼 수 있는 사람만 =====
create or replace function public.profile_counts(p_user uuid) returns table (friends bigint, groups bigint)
language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.follows f where f.follower_id = p_user),
         (select count(*) from public.group_members m where m.user_id = p_user and m.status = 'active')
   where public.can_view_feed(p_user)
$$;

-- ===== 4) 그룹 초대: 맞팔 + 차단 아님 + 하루 100명 =====
create or replace function public.invite_to_group(p_group uuid, p_users uuid[]) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if not public.is_group_member(p_group) then raise exception 'not_member' using errcode = 'P0001'; end if;
  if coalesce(array_length(p_users, 1), 0) > 50 then raise exception 'too_many' using errcode = 'P0001'; end if;
  if (select count(*) from public.group_invites where invited_by = auth.uid() and created_at > now() - interval '1 day') >= 100 then
    raise exception 'too_many' using errcode = 'P0001';
  end if;
  with ins as (
    insert into public.group_invites (group_id, user_id, invited_by)
    select p_group, u, auth.uid() from unnest(p_users) u
     where u <> auth.uid()
       and exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = u)
       and exists (select 1 from public.follows f where f.follower_id = u and f.followee_id = auth.uid())
       and not public.is_blocked_pair(auth.uid(), u)
       and not exists (select 1 from public.group_members m where m.group_id = p_group and m.user_id = u)
    on conflict do nothing returning 1)
  select count(*) into n from ins;
  return n;
end $$;

-- ===== 5) 익명으로 보낸 사람(서버만 앎) =====
create table if not exists public.post_senders (
  post_id uuid primary key references public.posts on delete cascade,
  user_id uuid not null references public.profiles on delete cascade
);
alter table public.post_senders enable row level security; -- 정책 없음 = 아무도 직접 못 읽음
revoke all on public.post_senders from anon, authenticated;

create or replace function public.posts_note_sender() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.author_id is null and auth.uid() is not null then
    insert into public.post_senders (post_id, user_id) values (new.id, auth.uid()) on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists posts_note_sender on public.posts;
create trigger posts_note_sender after insert on public.posts for each row execute function public.posts_note_sender();

-- 받은 사람(피드 주인)이 익명 친구를 차단: 누군지는 돌려주지 않음. 이후 그 사람은 내 피드에 못 보내고 서로 안 보임
create or replace function public.block_anon_sender(p_post uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare s uuid;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select ps.user_id into s from public.post_senders ps join public.posts p on p.id = ps.post_id
   where ps.post_id = p_post and p.owner_id = auth.uid();
  if s is null then return false; end if; -- 로그인 안 하고 보낸 익명은 막을 대상이 없음
  if s = auth.uid() then return false; end if;
  insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), s) on conflict do nothing;
  delete from public.follows where (follower_id = auth.uid() and followee_id = s) or (follower_id = s and followee_id = auth.uid());
  return true;
end $$;
revoke all on function public.block_anon_sender(uuid) from public, anon;
grant execute on function public.block_anon_sender(uuid) to authenticated;
