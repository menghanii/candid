-- candid. 보관함 '내가 보낸 피드' + 승인 전 보내기 취소. SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--
--  · my_sent_posts(): 로그인한 내가 친구 피드에 보낸 글 중 승인 대기(pending)만 최신순으로
--  · delete_my_post(): 승인 대기(pending)인 내가 보낸 글만 취소. 승인된 글은 삭제 불가
--    (기존 23/38 의 delete_my_post 를 대체)

create or replace function public.my_sent_posts()
returns table (
  id uuid, owner_id uuid, owner_name text, owner_handle text, owner_avatar text,
  media_type text, text text, answer text, status text, created_at timestamptz, approved_at timestamptz,
  image_path text, thumb_path text, media jsonb
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.owner_id, pr.name, pr.handle, pr.avatar_url,
         p.media_type, p.text, p.answer, p.status, p.created_at, p.approved_at,
         p.image_path, p.thumb_path, p.media
  from public.posts p
  join public.profiles pr on pr.id = p.owner_id
  where p.author_id = auth.uid()
    and p.group_id is null
    and p.owner_id is not null
    and p.owner_id <> auth.uid()
    and p.status = 'pending'
  order by p.created_at desc
  limit 100
$$;
revoke all on function public.my_sent_posts() from public, anon;
grant execute on function public.my_sent_posts() to authenticated;

create or replace function public.delete_my_post(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.posts;
begin
  select * into p
    from public.posts
   where id = p_post
     and author_id = auth.uid()
     and group_id is null
     and status = 'pending';
  if p.id is null then
    if exists (select 1 from public.posts x
                where x.id = p_post and x.author_id = auth.uid()
                  and x.group_id is null and x.status <> 'pending') then
      raise exception 'already_approved' using errcode = 'P0001';
    end if;
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  delete from public.posts where id = p_post;
  insert into public.storage_trash (path)
    select x from (
      select p.image_path as x union select p.thumb_path
      union select e->>'p' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e
      union select e->>'t' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e) s
    where x is not null and x !~ '^https?:'
  on conflict do nothing;
end $$;
revoke all on function public.delete_my_post(uuid) from public, anon;
grant execute on function public.delete_my_post(uuid) to authenticated;
