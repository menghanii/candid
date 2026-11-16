-- candid. 알림 목록을 서버에서 한 번에: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 18_groups.sql 이후 실행
--
-- 예전: 앱이 내 게시물 → 그룹 → 좋아요·댓글·스티커·친구 추가 → 프로필 순서로 5~6번 차례로 물어봐서 느렸음
-- 지금: 최근 30일 알림 중 최신 N개(기본 60)를 이름·프로필 사진·게시물 정보까지 붙여 한 번에 돌려줌. 본인 것만
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
  ),
  top as (select * from ev where (select id from me) is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 200)))
  select coalesce(json_agg(json_build_object(
      'k', t.k, 'at', t.at, 'uid', t.uid, 'body', t.body, 'nm', t.nm,
      'prof', case when pr.id is null then null else json_build_object('id', pr.id, 'name', pr.name, 'handle', pr.handle, 'avatar_url', pr.avatar_url) end,
      'post', case when p.id is null then null else json_build_object(
          'id', p.id, 'status', p.status, 'author_name', p.author_name, 'author_id', p.author_id, 'mission', p.mission,
          'media_type', p.media_type, 'image_path', p.image_path, 'thumb_path', p.thumb_path, 'media', p.media, 'text', p.text,
          'created_at', p.created_at, 'group_id', p.group_id, 'ghandle', pg.handle) end,
      'group', case when g.id is null then null else json_build_object('id', g.id, 'handle', g.handle, 'name', g.name, 'owner_id', g.owner_id) end
    ) order by t.at desc), '[]'::json)
    from top t
    left join public.profiles pr on pr.id = t.uid
    left join public.posts p on p.id = t.post_id
    left join public.groups pg on pg.id = p.group_id
    left join public.groups g on g.id = t.group_id
$$;
revoke all on function public.my_notifications(int) from public, anon;
grant execute on function public.my_notifications(int) to authenticated;
