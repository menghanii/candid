-- candid. 친구 피드에서도 '친구 수·그룹 수'를 보여주기 위한 함수. SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--  · 숫자만 돌려줌(누구인지는 안 알려줌). 비공개 그룹도 개수에만 포함
create or replace function public.profile_counts(p_user uuid) returns table (friends bigint, groups bigint)
language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.follows f where f.follower_id = p_user),
         (select count(*) from public.group_members m where m.user_id = p_user and m.status = 'active')
$$;
revoke all on function public.profile_counts(uuid) from public;
grant execute on function public.profile_counts(uuid) to anon, authenticated;
