-- candid. 사용자 차단 + 신고 확대(앱스토어 필수): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 29_delete_account.sql 이후 실행
--
-- 차단
--  · 차단하면 서로의 게시물·댓글이 안 보이고(내 피드에 이미 올라간 그 사람 사진은 나만 보임 — 지울 수 있게), 친구 관계·그룹 초대가 끊김
--  · 차단당한 사람은 나를 친구로 추가하거나, 내 피드에 사진을 보내거나, 내 게시물에 댓글·스티커를 달 수 없음
--  · 기존 규칙은 그대로 두고 '추가 제한(restrictive)' 규칙으로 덧붙임
-- 신고
--  · 게시물(개인 피드·그룹), 댓글, 사용자 신고. 서로 다른 3명이 신고한 게시물·댓글은 자동으로 가려짐(올린 사람·주인에게만 보임)
--  · 모든 신고는 content_reports 에 쌓임 → Supabase Table Editor 에서 확인·조치

-- ============ 차단 ============
create table if not exists public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles on delete cascade,
  blocked_id uuid not null references public.profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);
alter table public.blocks enable row level security;
drop policy if exists "blocks read own" on public.blocks;
create policy "blocks read own" on public.blocks for select to authenticated using (blocker_id = auth.uid());
revoke all on public.blocks from anon, authenticated;
grant select on public.blocks to authenticated;   -- 차단·해제는 함수로만

-- 두 사람 사이에 차단이 있는가(어느 쪽이든). 비로그인·빈 값이면 false
create or replace function public.is_blocked_pair(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select a is not null and b is not null and a <> b and exists (
    select 1 from public.blocks x where (x.blocker_id = a and x.blocked_id = b) or (x.blocker_id = b and x.blocked_id = a))
$$;
revoke all on function public.is_blocked_pair(uuid, uuid) from public;
grant execute on function public.is_blocked_pair(uuid, uuid) to anon, authenticated;

create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if p_user = auth.uid() then raise exception 'self' using errcode = 'P0001'; end if;
  insert into public.blocks (blocker_id, blocked_id) values (auth.uid(), p_user) on conflict do nothing;
  delete from public.follows where (follower_id = auth.uid() and followee_id = p_user) or (follower_id = p_user and followee_id = auth.uid());
  delete from public.group_invites where (user_id = auth.uid() and invited_by = p_user) or (user_id = p_user and invited_by = auth.uid());
end $$;
create or replace function public.unblock_user(p_user uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.blocks where blocker_id = auth.uid() and blocked_id = p_user
$$;
revoke all on function public.block_user(uuid), public.unblock_user(uuid) from public, anon;
grant execute on function public.block_user(uuid), public.unblock_user(uuid) to authenticated;

-- 게시물 보기: 차단 관계면 안 보임(내 피드의 게시물은 주인인 나에게는 보임 — 지울 수 있게)
drop policy if exists "posts block read" on public.posts;
create policy "posts block read" on public.posts as restrictive for select using (
  owner_id = auth.uid()
  or (not public.is_blocked_pair(auth.uid(), owner_id) and not public.is_blocked_pair(auth.uid(), author_id)));
-- 내 피드로 보내기: 주인이 나를 차단했으면 불가
drop policy if exists "posts block insert" on public.posts;
create policy "posts block insert" on public.posts as restrictive for insert with check (
  owner_id is null or not public.is_blocked_pair(auth.uid(), owner_id));
-- 댓글 보기·달기
drop policy if exists "comments block read" on public.comments;
create policy "comments block read" on public.comments as restrictive for select using (not public.is_blocked_pair(auth.uid(), user_id));
drop policy if exists "comments block insert" on public.comments;
create policy "comments block insert" on public.comments as restrictive for insert with check (
  not exists (select 1 from public.posts p where p.id = post_id
               and (public.is_blocked_pair(auth.uid(), p.owner_id) or public.is_blocked_pair(auth.uid(), p.author_id))));
-- 스티커 붙이기
drop policy if exists "stickers block insert" on public.post_stickers;
create policy "stickers block insert" on public.post_stickers as restrictive for insert with check (
  not exists (select 1 from public.posts p where p.id = post_id
               and (public.is_blocked_pair(auth.uid(), p.owner_id) or public.is_blocked_pair(auth.uid(), p.author_id))));
-- 친구 추가
drop policy if exists "follows block insert" on public.follows;
create policy "follows block insert" on public.follows as restrictive for insert with check (not public.is_blocked_pair(follower_id, followee_id));

-- ============ 신고 ============
alter table public.comments add column if not exists flagged boolean not null default false;
create table if not exists public.content_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null default auth.uid() references public.profiles on delete cascade,
  kind text not null check (kind in ('post', 'comment', 'user')),
  target_id uuid not null,
  reason text check (reason is null or char_length(reason) <= 60),
  created_at timestamptz not null default now(),
  unique (reporter_id, kind, target_id)
);
create index if not exists content_reports_target_idx on public.content_reports (kind, target_id);
alter table public.content_reports enable row level security;   -- 정책 없음: 앱에서는 함수로 넣기만, 확인은 대시보드에서
revoke all on public.content_reports from anon, authenticated;

-- 신고된 개인 피드 게시물·댓글 가리기(3명 이상): 올린 사람·주인에게만 보임
drop policy if exists "posts flagged read" on public.posts;
create policy "posts flagged read" on public.posts as restrictive for select using (
  not flagged or owner_id = auth.uid() or author_id = auth.uid() or (group_id is not null and public.is_group_owner(group_id)));
drop policy if exists "comments flagged read" on public.comments;
create policy "comments flagged read" on public.comments as restrictive for select using (
  not flagged or user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id and p.owner_id = auth.uid()));

-- 신고하기: 같은 사람은 같은 대상에 한 번. 게시물·댓글은 3명이면 가림. 신고 수를 돌려줌
create or replace function public.report_content(p_kind text, p_target uuid, p_reason text default null) returns int
language plpgsql security definer set search_path = '' as $$
declare n int; p public.posts; c public.comments;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if p_kind = 'post' then
    select * into p from public.posts where id = p_target;
    if p.id is null or p.status <> 'approved' then raise exception 'not_allowed' using errcode = 'P0001'; end if;
    if p.author_id = auth.uid() or p.owner_id = auth.uid() then raise exception 'own_post' using errcode = 'P0001'; end if;
    if p.group_id is not null and not public.can_view_group(p.group_id) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
    if p.group_id is null and not public.can_view_feed(p.owner_id) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
    insert into public.post_reports (post_id, user_id, reason) values (p_target, auth.uid(), left(p_reason, 40)) on conflict do nothing;
    select count(*) into n from public.post_reports where post_id = p_target;
    if n >= 3 then update public.posts set flagged = true where id = p_target; end if;
  elsif p_kind = 'comment' then
    select * into c from public.comments where id = p_target;
    if c.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
    if c.user_id = auth.uid() then raise exception 'own_post' using errcode = 'P0001'; end if;
  elsif p_kind = 'user' then
    if p_target = auth.uid() then raise exception 'self' using errcode = 'P0001'; end if;
  else
    raise exception 'bad_kind' using errcode = 'P0001';
  end if;
  insert into public.content_reports (reporter_id, kind, target_id, reason) values (auth.uid(), p_kind, p_target, left(p_reason, 60))
  on conflict do nothing;
  select count(*) into n from public.content_reports where kind = p_kind and target_id = p_target;
  if p_kind = 'comment' and n >= 3 then update public.comments set flagged = true where id = p_target; end if;
  return n;
end $$;
revoke all on function public.report_content(text, uuid, text) from public, anon;
grant execute on function public.report_content(text, uuid, text) to authenticated;
