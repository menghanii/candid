-- candid. 그룹(공유 앨범): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 17_profile_lang.sql 까지 실행한 뒤에 실행 (16 을 안 했어도 이 파일이 스티커 규칙을 최신으로 맞춤)
--
-- 규칙 요약
--  · 그룹은 누구나 개설(1인 30개까지, 25 SQL), 개설한 사람이 방장
--  · private: 초대 링크로 참여 신청 → 방장 승인 → 멤버. 멤버만 보고 올림. 검색 안 됨
--  · public : 누구나 봄. join_mode 'open' = 참여하면 바로 멤버+팔로우 / 'approval' = 팔로우는 누구나, 멤버는 신청 후 방장 승인
--  · public/private 은 만든 뒤 바꿀 수 없음
--  · 업로드는 로그인한 멤버만, 승인 없이 바로 게시. 사진·영상만
--  · public 그룹은 피드 99개까지: 넘으면 오래된 것부터 자동 삭제(방장이 고정한 것은 남김, 고정은 최대 9개)
--  · public 그룹 도배 방지: 1인당 하루 daily_limit 개(기본 10, 방장이 1~100 으로 조정)
--  · 방장이 '업로드 마감'하면 보기만 되는 앨범
--  · 스티커 꾸미기는 멤버와 팔로워 / 좋아요·댓글은 볼 수 있는 로그인 사용자
--  · 신고 3명 이상이면 자동으로 가려짐(방장·올린 사람에게만 보임). 방장은 삭제하거나 다시 보이게 할 수 있음
--  · 그룹 게시물은 posts 에 owner_id 없이(group_id 로) 저장 → 개인 피드 화면·쿼리에는 섞이지 않음

-- ============================================================
-- 1) 그룹
-- ============================================================
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  handle text not null,
  name text not null check (char_length(btrim(name)) between 1 and 30),
  bio text check (bio is null or char_length(bio) <= 120),
  cover_path text,
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  visibility text not null check (visibility in ('private', 'public')),
  join_mode text not null default 'open' check (join_mode in ('open', 'approval')),
  closed boolean not null default false,
  daily_limit int not null default 10 check (daily_limit between 1 and 100),
  invite_code text not null default left(replace(gen_random_uuid()::text, '-', ''), 12),
  member_count int not null default 0,
  follower_count int not null default 0,
  last_notified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint groups_private_approval check (visibility = 'public' or join_mode = 'approval'),
  constraint groups_handle_format check (
    handle ~ '^[a-z0-9_]{3,20}$'
    and handle not in ('admin','candid','help','support','root','system','null','undefined','api','www','official','me','settings','new'))
);
create unique index if not exists groups_handle_key on public.groups (handle);
create unique index if not exists groups_invite_key on public.groups (invite_code);
create index if not exists groups_owner_idx on public.groups (owner_id);

-- 멤버: role owner|member, status pending(신청·승인 대기)|active
create table if not exists public.group_members (
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  status text not null default 'pending' check (status in ('pending', 'active')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  primary key (group_id, user_id)
);
create index if not exists group_members_user_idx on public.group_members (user_id);

-- 팔로우: 새 사진이 릴스에 뜸. notify = 새 사진 푸시 받기(방장은 켬, 나머지는 끔으로 시작)
create table if not exists public.group_follows (
  group_id uuid not null references public.groups on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  notify boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists group_follows_user_idx on public.group_follows (user_id);

-- ============================================================
-- 2) 권한 확인 함수 (권한 규칙 안에서 같은 테이블을 다시 조회하는 무한 반복을 피하려고 security definer)
-- ============================================================
create or replace function public.is_group_owner(g uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.groups x where x.id = g and x.owner_id = auth.uid())
$$;
create or replace function public.is_group_member(g uuid) returns boolean   -- 승인된 멤버(방장 포함)
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.group_members m where m.group_id = g and m.user_id = auth.uid() and m.status = 'active')
$$;
create or replace function public.can_view_group(g uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.groups x where x.id = g and x.visibility = 'public') or public.is_group_member(g)
$$;
create or replace function public.can_post_group(g uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and public.is_group_member(g)
     and exists (select 1 from public.groups x where x.id = g and not x.closed)
$$;
-- 사진 저장소 폴더 이름(그룹 id 문자열)으로 업로드 가능 여부: 멤버(마감 전) 또는 방장(커버 사진)
create or replace function public.can_upload_group_folder(f text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.groups x where x.id::text = f
                  and (public.can_post_group(x.id) or x.owner_id = auth.uid()))
$$;
create or replace function public.can_decorate_group(g uuid) returns boolean  -- 멤버 또는 팔로워
language sql stable security definer set search_path = '' as $$
  select public.can_view_group(g) and (public.is_group_member(g)
    or exists (select 1 from public.group_follows f where f.group_id = g and f.user_id = auth.uid()))
$$;
revoke all on function public.is_group_owner(uuid), public.is_group_member(uuid), public.can_view_group(uuid),
  public.can_post_group(uuid), public.can_upload_group_folder(text), public.can_decorate_group(uuid) from public;
grant execute on function public.is_group_owner(uuid), public.is_group_member(uuid), public.can_view_group(uuid),
  public.can_post_group(uuid), public.can_upload_group_folder(text), public.can_decorate_group(uuid) to anon, authenticated;

-- ============================================================
-- 3) 그룹 테이블 권한 (RLS)
-- ============================================================
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_follows enable row level security;

-- 보기: public 은 누구나, private 은 멤버·신청자·방장만 (초대 링크 화면은 아래 group_by_invite 함수로)
drop policy if exists "groups read" on public.groups;
create policy "groups read" on public.groups for select using (
  visibility = 'public' or owner_id = auth.uid()
  or exists (select 1 from public.group_members m where m.group_id = groups.id and m.user_id = auth.uid()));
drop policy if exists "groups create" on public.groups;
create policy "groups create" on public.groups for insert to authenticated with check (owner_id = auth.uid());
drop policy if exists "groups owner update" on public.groups;
create policy "groups owner update" on public.groups for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "groups owner delete" on public.groups;
create policy "groups owner delete" on public.groups for delete to authenticated using (owner_id = auth.uid());

-- 초대 코드(invite_code)·알림 기록은 클라이언트에 안 보이게: 칸 단위로 허용
revoke all on public.groups from anon, authenticated;
grant select (id, handle, name, bio, cover_path, owner_id, visibility, join_mode, closed, daily_limit, member_count, follower_count, created_at)
  on public.groups to anon, authenticated;
grant insert (handle, name, bio, cover_path, owner_id, visibility, join_mode, daily_limit) on public.groups to authenticated;
-- visibility 는 수정 권한을 주지 않음 → public/private 전환 불가
grant update (handle, name, bio, cover_path, join_mode, closed, daily_limit) on public.groups to authenticated;
grant delete on public.groups to authenticated;

-- 멤버 목록: 내 줄, 방장은 신청자까지, 볼 수 있는 그룹이면 승인된 멤버
drop policy if exists "members read" on public.group_members;
create policy "members read" on public.group_members for select using (
  user_id = auth.uid() or public.is_group_owner(group_id) or (status = 'active' and public.can_view_group(group_id)));
-- 나가기(방장 제외) · 내보내기/신청 거절(방장)
drop policy if exists "members leave or kick" on public.group_members;
create policy "members leave or kick" on public.group_members for delete to authenticated using (
  (user_id = auth.uid() and role <> 'owner') or (public.is_group_owner(group_id) and user_id <> auth.uid()));
revoke all on public.group_members from anon, authenticated;
grant select on public.group_members to anon, authenticated;
grant delete on public.group_members to authenticated;   -- 추가·승인은 아래 함수로만

drop policy if exists "gfollows read" on public.group_follows;
create policy "gfollows read" on public.group_follows for select to authenticated using (user_id = auth.uid() or public.is_group_owner(group_id));
drop policy if exists "gfollows notify own" on public.group_follows;
create policy "gfollows notify own" on public.group_follows for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "gfollows remove own" on public.group_follows;
create policy "gfollows remove own" on public.group_follows for delete to authenticated using (user_id = auth.uid());
revoke all on public.group_follows from anon, authenticated;
grant select, delete on public.group_follows to authenticated;
grant update (notify) on public.group_follows to authenticated;  -- 팔로우 추가는 follow_group 함수로만

-- ============================================================
-- 4) 자동 처리 (트리거)
-- ============================================================
-- 개설: 1인 30개까지, 방장을 멤버·팔로워(알림 켬)로 등록
create or replace function public.groups_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.groups where owner_id = new.owner_id) >= 30 then
    raise exception 'group_limit' using errcode = 'P0001', hint = '그룹은 1인당 30개까지 만들 수 있어요';
  end if;
  if new.visibility = 'private' then new.join_mode := 'approval'; end if;
  new.member_count := 0; new.follower_count := 0; new.closed := false;
  return new;
end $$;
drop trigger if exists groups_before_insert on public.groups;
create trigger groups_before_insert before insert on public.groups for each row execute function public.groups_before_insert();

create or replace function public.groups_after_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.group_members (group_id, user_id, role, status, approved_at) values (new.id, new.owner_id, 'owner', 'active', now())
    on conflict (group_id, user_id) do update set role = 'owner', status = 'active';
  insert into public.group_follows (group_id, user_id, notify) values (new.id, new.owner_id, true) on conflict do nothing;
  return new;
end $$;
drop trigger if exists groups_after_insert on public.groups;
create trigger groups_after_insert after insert on public.groups for each row execute function public.groups_after_insert();

-- 멤버 수·팔로워 수
create or replace function public.group_counts() returns trigger
language plpgsql security definer set search_path = '' as $$
declare g uuid := coalesce(new.group_id, old.group_id);
begin
  update public.groups set
    member_count = (select count(*) from public.group_members where group_id = g and status = 'active'),
    follower_count = (select count(*) from public.group_follows where group_id = g)
  where id = g;
  return null;
end $$;
drop trigger if exists group_members_count on public.group_members;
create trigger group_members_count after insert or update or delete on public.group_members for each row execute function public.group_counts();
drop trigger if exists group_follows_count on public.group_follows;
create trigger group_follows_count after insert or delete on public.group_follows for each row execute function public.group_counts();

-- 멤버가 나가거나 내보내지면: private 그룹 / 바로 참여(open) 그룹은 팔로우도 같이 정리
create or replace function public.group_members_after_delete() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.groups x where x.id = old.group_id and (x.visibility = 'private' or x.join_mode = 'open')) then
    delete from public.group_follows where group_id = old.group_id and user_id = old.user_id;
  end if;
  return null;
end $$;
drop trigger if exists group_members_after_delete on public.group_members;
create trigger group_members_after_delete after delete on public.group_members for each row execute function public.group_members_after_delete();

-- ============================================================
-- 5) 그룹 게시물 (posts 에 group_id)
-- ============================================================
alter table public.posts add column if not exists group_id uuid references public.groups on delete cascade;
alter table public.posts add column if not exists pinned_at timestamptz;
alter table public.posts add column if not exists flagged boolean not null default false;
alter table public.posts alter column owner_id drop not null;
alter table public.posts drop constraint if exists posts_owner_or_group;
alter table public.posts add constraint posts_owner_or_group check ((owner_id is null) <> (group_id is null));
create index if not exists posts_group_idx on public.posts (group_id, created_at desc) where group_id is not null;
create index if not exists posts_group_author_idx on public.posts (group_id, author_id, created_at desc) where group_id is not null;

-- 보기: 개인 피드는 예전 그대로 / 그룹은 볼 수 있는 사람에게(신고로 가려진 건 방장·올린 사람만)
drop policy if exists "posts read" on public.posts;
create policy "posts read" on public.posts for select using (
  (group_id is null and (status = 'approved' or owner_id = auth.uid()))
  or (group_id is not null and (
       (status = 'approved' and not flagged and public.can_view_group(group_id))
       or author_id = auth.uid() or public.is_group_owner(group_id))));

-- 올리기: 개인 피드(09 와 같음) 또는 그룹(로그인 멤버, 사진·영상, 그룹 폴더, 바로 게시)
drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    (group_id is null and status = 'pending' and approved_at is null and answer is null
      and (author_id is null or author_id = auth.uid())
      and (
        (media_type in ('image', 'video') and image_path like owner_id::text || '/%'
          and (thumb_path is null or thumb_path like owner_id::text || '/%')
          and public.media_paths_ok(owner_id, media))
        or (media_type in ('poll', 'question') and image_path is null and thumb_path is null and media is null)
      ))
    or (group_id is not null and owner_id is null and auth.uid() is not null and author_id = auth.uid()
      and status = 'approved' and answer is null and pinned_at is null and not flagged
      and media_type in ('image', 'video') and image_path like group_id::text || '/%'
      and (thumb_path is null or thumb_path like group_id::text || '/%')
      and public.media_paths_ok(group_id, media)
      and public.can_post_group(group_id))
  );

-- 지우기: 개인 피드 주인(예전 그대로) + 그룹은 올린 사람·방장
drop policy if exists "posts group delete" on public.posts;
create policy "posts group delete" on public.posts for delete to authenticated
  using (group_id is not null and (author_id = auth.uid() or public.is_group_owner(group_id)));
-- 수정: 그룹 게시물은 owner_id 가 없어 기존 '주인 수정' 규칙에 안 걸림 → 고정·신고 해제는 아래 함수로만

-- 올리기 전: 게시 시간, 이름은 프로필 이름으로, public 그룹은 하루 개수 제한
create or replace function public.posts_group_before_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
declare g public.groups;
begin
  if new.group_id is null then return new; end if;
  select * into g from public.groups where id = new.group_id;
  new.status := 'approved'; new.approved_at := now(); new.pinned_at := null; new.flagged := false; new.answer := null;
  new.author_name := coalesce((select left(p.name, 12) from public.profiles p where p.id = new.author_id), new.author_name);
  if g.visibility = 'public' and (select count(*) from public.posts
       where group_id = new.group_id and author_id = new.author_id and created_at > now() - interval '24 hours') >= g.daily_limit then
    raise exception 'daily_limit' using errcode = 'P0001', hint = g.daily_limit::text;
  end if;
  return new;
end $$;
drop trigger if exists posts_group_before_insert on public.posts;
create trigger posts_group_before_insert before insert on public.posts for each row execute function public.posts_group_before_insert();

-- 올린 뒤: public 그룹은 99개 넘으면 고정 안 된 것 중 오래된 것부터 삭제
create or replace function public.posts_group_trim() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pinned int;
begin
  if new.group_id is null or not exists (select 1 from public.groups where id = new.group_id and visibility = 'public') then return null; end if;
  select count(*) into pinned from public.posts where group_id = new.group_id and pinned_at is not null;
  delete from public.posts where id in (
    select id from public.posts where group_id = new.group_id and pinned_at is null
     order by created_at desc offset greatest(0, 99 - pinned));
  return null;
end $$;
drop trigger if exists posts_group_trim on public.posts;
create trigger posts_group_trim after insert on public.posts for each row execute function public.posts_group_trim();

-- 지워진 그룹 게시물의 사진·영상 파일은 '버릴 파일' 목록에 → 알림 함수(서버)가 저장소에서 지움
-- (SQL 에서 저장소 파일을 직접 지우는 건 막혀 있음)
create table if not exists public.storage_trash (
  path text primary key,
  created_at timestamptz not null default now()
);
alter table public.storage_trash enable row level security;   -- 정책 없음 = 서버(service_role)만
revoke all on public.storage_trash from anon, authenticated;

create or replace function public.posts_group_trash() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.group_id is null then return null; end if;
  insert into public.storage_trash (path)
    select x from (
      select old.image_path as x union select old.thumb_path
      union select e->>'p' from jsonb_array_elements(coalesce(old.media, '[]'::jsonb)) e
      union select e->>'t' from jsonb_array_elements(coalesce(old.media, '[]'::jsonb)) e) s
    where x is not null and x !~ '^https?:'
  on conflict do nothing;
  return null;
end $$;
drop trigger if exists posts_group_trash on public.posts;
create trigger posts_group_trash after delete on public.posts for each row execute function public.posts_group_trash();

create or replace function public.groups_cover_trash() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.cover_path is not null and (tg_op = 'DELETE' or new.cover_path is distinct from old.cover_path) then
    insert into public.storage_trash (path) values (old.cover_path) on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists groups_cover_trash on public.groups;
create trigger groups_cover_trash after update or delete on public.groups for each row execute function public.groups_cover_trash();

-- 사진 저장소: 그룹 폴더 photos/{group_id}/... 에는 멤버(마감 전)·방장만 업로드
drop policy if exists "photos group upload" on storage.objects;
create policy "photos group upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.can_upload_group_folder((storage.foldername(name))[1]));

-- ============================================================
-- 6) 댓글·스티커 규칙 보완
-- ============================================================
-- 댓글 삭제: 본인, 개인 피드 주인, 그룹 방장
drop policy if exists "comments delete" on public.comments;
create policy "comments delete" on public.comments for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.posts p where p.id = post_id
    and (p.owner_id = auth.uid() or (p.group_id is not null and public.is_group_owner(p.group_id)))));

-- 스티커: 16 과 같음 + 그룹 게시물은 멤버·팔로워만, 신고로 가려진 것은 불가
create or replace function public.can_add_sticker(p_post uuid, p_idx int, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select
    exists (select 1 from public.posts p where p.id = p_post and p.status = 'approved' and not p.flagged
             and (p.media_type in ('image', 'video') or (p.media_type in ('poll', 'question') and p_idx = 0))
             and (p.group_id is null or public.can_decorate_group(p.group_id)))
    and exists (select 1 from public.items t where t.id = p_item and t.kind = 'sticker'
                 and (coalesce((t.data->>'free')::boolean, false)
                      or exists (select 1 from public.inventory i where i.user_id = auth.uid() and i.item_id = t.id)))
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx and s.user_id = auth.uid()) < 10
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx) < 40
$$;
revoke all on function public.can_add_sticker(uuid, int, text) from public, anon;
grant execute on function public.can_add_sticker(uuid, int, text) to authenticated;

-- ============================================================
-- 7) 신고: 서로 다른 3명이 신고하면 자동으로 가려짐
-- ============================================================
create table if not exists public.post_reports (
  post_id uuid not null references public.posts on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  reason text check (reason is null or char_length(reason) <= 40),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
alter table public.post_reports enable row level security;
drop policy if exists "reports read own" on public.post_reports;
create policy "reports read own" on public.post_reports for select to authenticated using (user_id = auth.uid());
revoke all on public.post_reports from anon, authenticated;
grant select on public.post_reports to authenticated;   -- 신고 추가는 report_post 함수로만

-- ============================================================
-- 8) 함수 (앱에서 rpc 로 호출)
-- ============================================================
-- 초대 링크 화면용 그룹 정보 (비로그인도 이름·사진은 볼 수 있게)
create or replace function public.group_by_invite(p_code text) returns json
language sql stable security definer set search_path = '' as $$
  select json_build_object('id', g.id, 'handle', g.handle, 'name', g.name, 'bio', g.bio, 'cover_path', g.cover_path,
           'visibility', g.visibility, 'join_mode', g.join_mode, 'closed', g.closed, 'member_count', g.member_count,
           'owner_name', (select p.name from public.profiles p where p.id = g.owner_id))
    from public.groups g where g.invite_code = p_code
$$;

-- 참여: public+open → 바로 멤버(+팔로우) / public+approval → 신청 / private → 초대 링크 필요
-- 초대 코드가 있으면 private 도 신청 가능. 돌려주는 값: 'active' | 'pending'
create or replace function public.join_group(p_group uuid, p_code text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.groups; cur text;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into g from public.groups where id = p_group;
  if g.id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  select status into cur from public.group_members where group_id = g.id and user_id = auth.uid();
  if cur is not null then return cur; end if;
  if g.visibility = 'private' and (p_code is null or p_code <> g.invite_code) then
    raise exception 'invite_required' using errcode = 'P0001';
  end if;
  if g.visibility = 'public' and g.join_mode = 'open' then
    insert into public.group_members (group_id, user_id, status, approved_at) values (g.id, auth.uid(), 'active', now());
    insert into public.group_follows (group_id, user_id) values (g.id, auth.uid()) on conflict do nothing;
    return 'active';
  end if;
  insert into public.group_members (group_id, user_id, status) values (g.id, auth.uid(), 'pending');
  return 'pending';
end $$;

-- 방장: 신청 승인 (승인하면 팔로우도 같이)
create or replace function public.approve_member(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner' using errcode = 'P0001'; end if;
  update public.group_members set status = 'active', approved_at = now() where group_id = p_group and user_id = p_user and status = 'pending';
  if found then insert into public.group_follows (group_id, user_id) values (p_group, p_user) on conflict do nothing; end if;
end $$;

-- 팔로우: 볼 수 있는 그룹만(private 은 멤버만)
create or replace function public.follow_group(p_group uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if not public.can_view_group(p_group) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  insert into public.group_follows (group_id, user_id) values (p_group, auth.uid()) on conflict do nothing;
end $$;

-- 초대 코드 보기(방장·멤버) / 새로 만들기(방장, 예전 링크는 막힘)
create or replace function public.group_invite_code(p_group uuid, p_new boolean default false) returns text
language plpgsql security definer set search_path = '' as $$
declare c text;
begin
  if p_new then
    if not public.is_group_owner(p_group) then raise exception 'not_owner' using errcode = 'P0001'; end if;
    update public.groups set invite_code = left(replace(gen_random_uuid()::text, '-', ''), 12) where id = p_group returning invite_code into c;
    return c;
  end if;
  if not public.is_group_member(p_group) then raise exception 'not_member' using errcode = 'P0001'; end if;
  select invite_code into c from public.groups where id = p_group;
  return c;
end $$;

-- 방장 넘기기: 승인된 멤버에게만
create or replace function public.transfer_group(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_user and status = 'active') then
    raise exception 'not_member' using errcode = 'P0001';
  end if;
  update public.group_members set role = 'member' where group_id = p_group and user_id = auth.uid();
  update public.group_members set role = 'owner' where group_id = p_group and user_id = p_user;
  update public.groups set owner_id = p_user where id = p_group;
  insert into public.group_follows (group_id, user_id, notify) values (p_group, p_user, true)
    on conflict (group_id, user_id) do update set notify = true;
end $$;

-- 방장: 고정/해제 (최대 9개)
create or replace function public.pin_post(p_post uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare g uuid;
begin
  select group_id into g from public.posts where id = p_post;
  if g is null or not public.is_group_owner(g) then raise exception 'not_owner' using errcode = 'P0001'; end if;
  if p_on and (select count(*) from public.posts where group_id = g and pinned_at is not null and id <> p_post) >= 9 then
    raise exception 'pin_limit' using errcode = 'P0001';
  end if;
  update public.posts set pinned_at = case when p_on then coalesce(pinned_at, now()) end where id = p_post;
end $$;

-- 신고: 볼 수 있는 그룹 게시물만, 본인 게시물 제외. 3명 이상이면 가려짐. 돌려주는 값: 신고 수
create or replace function public.report_post(p_post uuid, p_reason text default null) returns int
language plpgsql security definer set search_path = '' as $$
declare p public.posts; n int;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into p from public.posts where id = p_post;
  if p.id is null or p.group_id is null or p.status <> 'approved' or not public.can_view_group(p.group_id) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p.author_id = auth.uid() then raise exception 'own_post' using errcode = 'P0001'; end if;
  insert into public.post_reports (post_id, user_id, reason) values (p_post, auth.uid(), left(p_reason, 40)) on conflict do nothing;
  select count(*) into n from public.post_reports where post_id = p_post;
  if n >= 3 then update public.posts set flagged = true where id = p_post; end if;
  return n;
end $$;

-- 방장: 신고로 가려진 게시물 다시 보이게(신고 기록 초기화)
create or replace function public.unflag_post(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare g uuid;
begin
  select group_id into g from public.posts where id = p_post;
  if g is null or not public.is_group_owner(g) then raise exception 'not_owner' using errcode = 'P0001'; end if;
  delete from public.post_reports where post_id = p_post;
  update public.posts set flagged = false where id = p_post;
end $$;

revoke all on function public.group_by_invite(text), public.join_group(uuid, text), public.approve_member(uuid, uuid),
  public.follow_group(uuid), public.group_invite_code(uuid, boolean), public.transfer_group(uuid, uuid),
  public.pin_post(uuid, boolean), public.report_post(uuid, text), public.unflag_post(uuid) from public;
grant execute on function public.group_by_invite(text) to anon, authenticated;
grant execute on function public.join_group(uuid, text), public.approve_member(uuid, uuid), public.follow_group(uuid),
  public.group_invite_code(uuid, boolean), public.transfer_group(uuid, uuid), public.pin_post(uuid, boolean),
  public.report_post(uuid, text), public.unflag_post(uuid) to authenticated;

-- ============================================================
-- 9) 알림 함수(서버, service_role)가 읽고 쓰는 것
-- ============================================================
grant select, update on public.groups to service_role;
grant select on public.group_members, public.group_follows, public.profiles to service_role;
grant select, delete on public.storage_trash to service_role;
