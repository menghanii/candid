-- candid. Candids 은하용 서버 함수 2개. SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--  · my_interactions(): 블루 은하 — 나와 많이 주고받은 친구·그룹 순위(최근 90일)
--  · trending_sources(): 트렌딩 은하 — 내 친구·내 그룹이 아닌 공개 피드·공개 그룹 중 최근 7일 활발한 곳 20개

-- 블루 은하: 친한 정도 점수(최근 90일)
--   내가 좋아요 2 · 댓글 3 · 스티커 2 · 내가 친구 피드를 채워줌 4 · 친구가 내 피드를 채워줌 4 · 내가 그룹에 올림 3
create or replace function public.my_interactions() returns table (k text, score bigint)
language sql stable security definer set search_path = '' as $$
  with since as (select now() - interval '90 days' as t)
  select x.k, sum(x.w)::bigint from (
    select case when p.group_id is not null then 'g:' || p.group_id else 'u:' || p.owner_id end as k, 2 as w
      from public.likes l join public.posts p on p.id = l.post_id, since
      where l.user_id = auth.uid() and l.created_at > since.t
    union all
    select case when p.group_id is not null then 'g:' || p.group_id else 'u:' || p.owner_id end, 3
      from public.comments c join public.posts p on p.id = c.post_id, since
      where c.user_id = auth.uid() and c.created_at > since.t
    union all
    select case when p.group_id is not null then 'g:' || p.group_id else 'u:' || p.owner_id end, 2
      from public.post_stickers s join public.posts p on p.id = s.post_id, since
      where s.user_id = auth.uid() and s.created_at > since.t
    union all
    select 'u:' || p.owner_id, 4 from public.posts p, since
      where p.author_id = auth.uid() and p.owner_id is not null and p.owner_id <> auth.uid() and p.created_at > since.t
    union all
    select 'u:' || p.author_id, 4 from public.posts p, since
      where p.owner_id = auth.uid() and p.author_id is not null and p.author_id <> auth.uid() and p.created_at > since.t
    union all
    select 'g:' || p.group_id, 3 from public.posts p, since
      where p.author_id = auth.uid() and p.group_id is not null and p.created_at > since.t
  ) x
  where x.k is not null and x.k <> 'u:' || auth.uid()
  group by x.k
  order by 2 desc
  limit 300
$$;
revoke all on function public.my_interactions() from public, anon;
grant execute on function public.my_interactions() to authenticated;

-- 트렌딩 은하: 최근 7일 승인된 사진 수 ×2 + 그 사진들의 좋아요 수. 공개 피드·공개 그룹만, 내 친구·내 그룹·차단 관계는 뺌
create or replace function public.trending_sources() returns table (
  kind text, id uuid, name text, handle text, avatar text, posts bigint, likes bigint, latest timestamptz, score bigint
)
language sql stable security definer set search_path = '' as $$
  with recent as (
    select p.id, p.owner_id, p.group_id, p.approved_at
    from public.posts p
    where p.status = 'approved' and not p.flagged and p.approved_at > now() - interval '7 days'
  ),
  lk as (select l.post_id, count(*) as n from public.likes l join recent r on r.id = l.post_id group by l.post_id),
  feeds as (
    select 'user'::text as kind, pr.id, pr.name, pr.handle, pr.avatar_url as avatar,
           count(r.id) as posts, coalesce(sum(lk.n), 0) as likes, max(r.approved_at) as latest
    from recent r join public.profiles pr on pr.id = r.owner_id
    left join lk on lk.post_id = r.id
    where r.group_id is null and not pr.is_private and pr.onboarded
      and pr.id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      and not exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = pr.id)
      and not public.is_blocked_pair(auth.uid(), pr.id)
    group by pr.id
  ),
  grps as (
    select 'group'::text, g.id, g.name, g.handle, g.cover_path,
           count(r.id), coalesce(sum(lk.n), 0), max(r.approved_at)
    from recent r join public.groups g on g.id = r.group_id
    left join lk on lk.post_id = r.id
    where g.visibility = 'public'
      and not exists (select 1 from public.group_members m where m.group_id = g.id and m.user_id = auth.uid())
      and not exists (select 1 from public.group_follows gf where gf.group_id = g.id and gf.user_id = auth.uid())
    group by g.id
  )
  select *, (posts * 2 + likes)::bigint from (select * from feeds union all select * from grps) t
  order by 9 desc, latest desc
  limit 20
$$;
revoke all on function public.trending_sources() from public;
grant execute on function public.trending_sources() to anon, authenticated;
