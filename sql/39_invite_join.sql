-- candid. 초대 링크로 오면 바로 멤버(승인 단계 없음). SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--  · 초대 링크(코드)는 멤버만 받을 수 있으므로, 링크를 받은 사람은 이미 초대받은 것으로 봄
--  · 링크 없이 공개 그룹에 신청하는 경우는 그대로(누구나 참여 그룹은 바로, 승인제는 방장 승인)
--  · 링크가 퍼졌으면 방장이 '새 링크 만들기'로 예전 링크를 막을 수 있음
create or replace function public.join_group(p_group uuid, p_code text default null) returns text
language plpgsql security definer set search_path = '' as $$
declare g public.groups; cur text; invited boolean;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into g from public.groups where id = p_group;
  if g.id is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  invited := p_code is not null and p_code = g.invite_code;
  select status into cur from public.group_members where group_id = g.id and user_id = auth.uid();
  if cur = 'pending' and invited then
    update public.group_members set status = 'active', approved_at = now() where group_id = g.id and user_id = auth.uid();
    insert into public.group_follows (group_id, user_id) values (g.id, auth.uid()) on conflict do nothing;
    return 'active';
  end if;
  if cur is not null then return cur; end if;
  if g.visibility = 'private' and not invited then raise exception 'invite_required' using errcode = 'P0001'; end if;
  if invited or (g.visibility = 'public' and g.join_mode = 'open') then
    insert into public.group_members (group_id, user_id, status, approved_at) values (g.id, auth.uid(), 'active', now());
    insert into public.group_follows (group_id, user_id) values (g.id, auth.uid()) on conflict do nothing;
    return 'active';
  end if;
  insert into public.group_members (group_id, user_id, status) values (g.id, auth.uid(), 'pending');
  return 'pending';
end $$;
