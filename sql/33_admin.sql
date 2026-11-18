-- candid. 관리자: 전체 사용자 목록(관리자만). SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 관리자 추가: insert into public.admins (user_id) values ('사용자 id');  · 빼기: delete from public.admins where user_id = '...';
create table if not exists public.admins (
  user_id uuid primary key references public.profiles on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;   -- 정책 없음: 앱에서 직접 못 읽음(아래 함수로만)
revoke all on public.admins from anon, authenticated;
grant select, insert, update, delete on public.admins to service_role;

-- 첫 관리자: 운영자 계정
insert into public.admins (user_id) values ('7b235dd4-ec87-4575-bdb7-67a4f7fcc35c') on conflict do nothing;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.admins where user_id = auth.uid())
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- 전체 사용자 + 간단한 활동 수치(가입 최신순). 관리자가 아니면 거절
create or replace function public.admin_users() returns table (
  id uuid, name text, handle text, avatar_url text, created_at timestamptz, onboarded boolean, is_private boolean,
  friends bigint, followers bigint, received bigint, sent bigint, groups bigint, last_post timestamptz, email text, provider text
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'not_admin' using errcode = 'P0001'; end if;
  return query
  select p.id, p.name, p.handle, p.avatar_url, p.created_at, p.onboarded, p.is_private,
    (select count(*) from public.follows f where f.follower_id = p.id),
    (select count(*) from public.follows f where f.followee_id = p.id),
    (select count(*) from public.posts x where x.owner_id = p.id),
    (select count(*) from public.posts x where x.author_id = p.id),
    (select count(*) from public.group_members m where m.user_id = p.id and m.status = 'active'),
    (select max(x.created_at) from public.posts x where x.author_id = p.id),
    u.email::text, (u.raw_app_meta_data ->> 'provider')::text
  from public.profiles p left join auth.users u on u.id = p.id
  order by p.created_at desc;
end $$;
revoke all on function public.admin_users() from public, anon;
grant execute on function public.admin_users() to authenticated;
