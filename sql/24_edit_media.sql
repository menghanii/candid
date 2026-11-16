-- candid. 게시물 사진 추가·삭제: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 23_edit_text.sql 이후 실행
--
--  · 올린(보낸) 사람만, 사진·영상 게시물만. 1~10장
--  · 그룹: 추가·삭제 모두 가능(업로드 마감된 그룹은 삭제만)
--  · 친구 피드: 이미 올라간 게시물에는 새 사진을 추가할 수 없음(주인 승인 없이 늘어나지 않게) — 빼기만
--  · 뺀 사진의 파일은 서버가 정리, 그 사진에 붙은 스티커는 함께 삭제, 나머지 스티커는 바뀐 순서에 맞춰 옮김
--  · '수정됨' 표시(edited_at)

create or replace function public.edit_post_media(p_post uuid, p_media jsonb) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  p public.posts; oldm jsonb; n int; i int; j int; added boolean; t timestamptz := now(); map int[];
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  select * into p from public.posts where id = p_post and author_id = auth.uid() and media_type in ('image', 'video');
  if p.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if jsonb_typeof(p_media) is distinct from 'array' then raise exception 'bad_media' using errcode = 'P0001'; end if;
  n := jsonb_array_length(p_media);
  if n < 1 or n > 10 then raise exception 'bad_count' using errcode = 'P0001'; end if;
  if not public.media_paths_ok(coalesce(p.group_id, p.owner_id), p_media) then raise exception 'bad_path' using errcode = 'P0001'; end if;

  oldm := case when p.media is not null and jsonb_array_length(p.media) > 0 then p.media
               else jsonb_build_array(jsonb_build_object('p', p.image_path, 't', p.thumb_path, 'k', p.media_type)) end;
  added := exists (select 1 from jsonb_array_elements(p_media) e
                    where not exists (select 1 from jsonb_array_elements(oldm) o where o->>'p' = e->>'p'));
  if added and p.group_id is null and p.status <> 'pending' then raise exception 'no_add_after_approval' using errcode = 'P0001'; end if;
  if added and p.group_id is not null and not public.can_post_group(p.group_id) then raise exception 'closed' using errcode = 'P0001'; end if;

  -- 예전 i번째 사진이 새 목록의 j번째로: 뺀 사진은 스티커 삭제 + 파일 정리, 남은 사진은 스티커 순서를 한 번에 옮김
  map := array_fill(-1, array[jsonb_array_length(oldm)]);
  for i in 0 .. jsonb_array_length(oldm) - 1 loop
    j := null;
    select (x.ord - 1)::int into j from jsonb_array_elements(p_media) with ordinality x(e, ord) where x.e->>'p' = oldm->i->>'p' limit 1;
    if j is null then
      delete from public.post_stickers where post_id = p_post and media_idx = i;
      insert into public.storage_trash (path)
        select v from (values (oldm->i->>'p'), (oldm->i->>'t')) s(v) where v is not null and v !~ '^https?:'
      on conflict do nothing;
    else
      map[i + 1] := j;
    end if;
  end loop;
  update public.post_stickers set media_idx = map[media_idx + 1]
   where post_id = p_post and media_idx < array_length(map, 1) and map[media_idx + 1] >= 0 and map[media_idx + 1] <> media_idx;

  update public.posts set
    media = case when n > 1 then p_media else null end,
    image_path = p_media->0->>'p', thumb_path = p_media->0->>'t',
    media_type = coalesce(p_media->0->>'k', 'image'), edited_at = t
   where id = p_post;
  return t;
end $$;
revoke all on function public.edit_post_media(uuid, jsonb) from public, anon;
grant execute on function public.edit_post_media(uuid, jsonb) to authenticated;
