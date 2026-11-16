-- candid. 1인당 만들 수 있는 그룹 수 10 → 30: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)

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
