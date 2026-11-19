-- candid. 피드 주인: 승인한 사진의 순서 바꾸기·몇 장 빼기 + 피드 고정(개인 피드 주인·그룹 방장). SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--  · owner_edit_media(게시물, 남길 순서 int[]): 예전 사진 번호(0부터)를 새 순서대로. 새 사진 추가는 안 됨. 최소 1장
--    뺀 사진은 스티커 삭제 + 파일 정리, 남은 사진의 스티커는 바뀐 순서로 옮김
--  · pin_post: 그룹(방장) + 개인 피드(주인) 모두. 피드마다 최대 9개, 고정한 순서대로 맨 위에

create or replace function public.owner_edit_media(p_post uuid, p_keep int[]) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  p public.posts; oldm jsonb; newm jsonb := '[]'::jsonb; n int; i int; k int; t timestamptz := now(); map int[];
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into p from public.posts where id = p_post and media_type in ('image', 'video');
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
    map[i + 1] := k - 1;
    newm := newm || jsonb_build_array(oldm->i);
  end loop;
  for i in 0 .. jsonb_array_length(oldm) - 1 loop
    if map[i + 1] < 0 then
      delete from public.post_stickers where post_id = p_post and media_idx = i;
      insert into public.storage_trash (path)
        select v from (values (oldm->i->>'p'), (oldm->i->>'t')) s(v) where v is not null and v !~ '^https?:'
      on conflict do nothing;
    end if;
  end loop;
  update public.post_stickers set media_idx = map[media_idx + 1]
   where post_id = p_post and media_idx < array_length(map, 1) and map[media_idx + 1] >= 0 and map[media_idx + 1] <> media_idx;
  update public.posts set
    media = case when n > 1 then newm else null end,
    image_path = newm->0->>'p', thumb_path = newm->0->>'t',
    media_type = coalesce(newm->0->>'k', 'image')
   where id = p_post;
  return t;
end $$;
revoke all on function public.owner_edit_media(uuid, int[]) from public, anon;
grant execute on function public.owner_edit_media(uuid, int[]) to authenticated;

create or replace function public.pin_post(p_post uuid, p_on boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare g uuid; o uuid;
begin
  select group_id, owner_id into g, o from public.posts where id = p_post and status = 'approved';
  if g is null and o is null then raise exception 'not_owner' using errcode = 'P0001'; end if;
  if not ((g is not null and public.is_group_owner(g)) or (g is null and o = auth.uid())) then
    raise exception 'not_owner' using errcode = 'P0001';
  end if;
  if p_on and (select count(*) from public.posts
                where pinned_at is not null and id <> p_post
                  and (case when g is not null then group_id = g else group_id is null and owner_id = o end)) >= 9 then
    raise exception 'pin_limit' using errcode = 'P0001';
  end if;
  update public.posts set pinned_at = case when p_on then coalesce(pinned_at, now()) end where id = p_post;
end $$;
revoke all on function public.pin_post(uuid, boolean) from public, anon;
grant execute on function public.pin_post(uuid, boolean) to authenticated;
