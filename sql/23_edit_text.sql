-- candid. 글 수정: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 22_private_default.sql 이후 실행
--
--  · 내가 보낸(올린) 사진의 한마디 수정 — 로그인해서 보낸 사람만(익명은 불가). 개인 피드·그룹 모두. '수정됨' 표시용 edited_at
--  · 내가 친구 피드에 보낸 사진 삭제 — 보낸 사람이 직접(파일은 서버가 정리)
--  · 댓글 수정 — 쓴 사람만. edited_at
--  · 피드 주인은 친구가 쓴 글(한마디)을 바꿀 수 없음 — 주인은 승인·숨기기·답 달기만

-- 1) 게시물 한마디 수정
alter table public.posts add column if not exists edited_at timestamptz;

create or replace function public.edit_post_text(p_post uuid, p_text text) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v text := nullif(btrim(coalesce(p_text, '')), ''); n timestamptz := now();
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if v is not null and char_length(v) > 80 then raise exception 'too_long' using errcode = 'P0001'; end if;
  update public.posts set text = v, edited_at = n
   where id = p_post and author_id = auth.uid() and media_type in ('image', 'video');
  if not found then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  return n;
end $$;
revoke all on function public.edit_post_text(uuid, text) from public, anon;
grant execute on function public.edit_post_text(uuid, text) to authenticated;

-- 2) 친구 피드에 내가 보낸 사진 삭제(그룹은 18 의 'posts group delete' 로 이미 가능)
create or replace function public.delete_my_post(p_post uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.posts;
begin
  select * into p from public.posts where id = p_post and author_id = auth.uid() and group_id is null;
  if p.id is null then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  insert into public.storage_trash (path)
    select x from (
      select p.image_path as x union select p.thumb_path
      union select e->>'p' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e
      union select e->>'t' from jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e) s
    where x is not null and x !~ '^https?:'
  on conflict do nothing;
  delete from public.posts where id = p_post;
end $$;
revoke all on function public.delete_my_post(uuid) from public, anon;
grant execute on function public.delete_my_post(uuid) to authenticated;

-- 3) 피드 주인이 바꿀 수 있는 칸만 허용(한마디 text 는 제외) — 승인·되돌리기·숨기기·답
revoke update on public.posts from authenticated;
grant update (status, approved_at, hidden_at, answer, answered_at) on public.posts to authenticated;

-- 4) 댓글 수정(쓴 사람만)
alter table public.comments add column if not exists edited_at timestamptz;
drop policy if exists "comments update own" on public.comments;
create policy "comments update own" on public.comments for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
grant update (body, edited_at) on public.comments to authenticated;
