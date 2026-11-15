-- candid. 비공개 피드: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 18_groups.sql 이후 실행
--
-- 규칙
--  · 프로필에서 '비공개 피드'를 켜면, 내가 친구로 추가한 사람만 내 피드(올라간 게시물)를 볼 수 있음
--  · 상대가 나를 친구로 추가한 것만으로는 못 봄 → 내가 그 사람을 친구로 추가해야 보임 (팔로우/팔로잉과 같은 개념)
--  · 피드 채워주기(사진 보내기)는 비공개여도 누구나 가능 — 어차피 주인이 승인해야 올라감
--  · 게시물이 안 보이면 좋아요·댓글·투표·스티커도 함께 안 보임(모두 posts 보기 권한을 따라감)

alter table public.profiles add column if not exists is_private boolean not null default false;
grant update (is_private) on public.profiles to authenticated;

-- 이 사람(o)의 개인 피드를 지금 사용자가 볼 수 있는가
create or replace function public.can_view_feed(o uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(o = auth.uid(), false)
      or not coalesce((select p.is_private from public.profiles p where p.id = o), false)
      or exists (select 1 from public.follows f where f.follower_id = o and f.followee_id = auth.uid())
$$;
revoke all on function public.can_view_feed(uuid) from public;
grant execute on function public.can_view_feed(uuid) to anon, authenticated;

-- 게시물 보기: 개인 피드는 '주인' 또는 '올라간 것 + 볼 수 있는 사람' / 그룹은 18 과 같음
drop policy if exists "posts read" on public.posts;
create policy "posts read" on public.posts for select using (
  (group_id is null and (owner_id = auth.uid() or (status = 'approved' and public.can_view_feed(owner_id))))
  or (group_id is not null and (
       (status = 'approved' and not flagged and public.can_view_group(group_id))
       or author_id = auth.uid() or public.is_group_owner(group_id))));

-- (덧붙임) 한 게시물에 사진·영상 최대 10개: 앱에서만 막던 것을 서버에서도 확인
create or replace function public.media_paths_ok(owner uuid, m jsonb) returns boolean
language sql immutable as $$
  select jsonb_array_length(coalesce(m, '[]'::jsonb)) <= 10
     and coalesce(bool_and(
           (e->>'p') like owner::text || '/%'
           and ((e->>'t') is null or (e->>'t') like owner::text || '/%')
           and coalesce(e->>'k', 'image') in ('image', 'video')), true)
    from jsonb_array_elements(coalesce(m, '[]'::jsonb)) e
$$;
