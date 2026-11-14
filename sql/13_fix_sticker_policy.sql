-- candid. 스티커 붙이기 오류 수정 (42P17 infinite recursion detected in policy for relation "post_stickers")
-- SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 원인: 붙이기 권한 규칙이 '이미 몇 개 붙었는지' 세려고 같은 테이블을 다시 조회 → 그 조회에도 권한 규칙이 걸려 무한 반복
-- 해결: 조건 확인을 권한 규칙이 다시 적용되지 않는 함수(security definer)로 분리

create or replace function public.can_add_sticker(p_post uuid, p_idx int, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select
    -- 피드에 올라간 사진·영상 게시물에만
    exists (select 1 from public.posts p where p.id = p_post and p.status = 'approved' and p.media_type in ('image', 'video'))
    -- 무료 스티커이거나, 가챠로 가진 스티커만
    and exists (select 1 from public.items t where t.id = p_item and t.kind = 'sticker'
                 and (coalesce((t.data->>'free')::boolean, false)
                      or exists (select 1 from public.inventory i where i.user_id = auth.uid() and i.item_id = t.id)))
    -- 사진 1장에 1인 10개, 전체 40개까지
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx and s.user_id = auth.uid()) < 10
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx) < 40
$$;
revoke all on function public.can_add_sticker(uuid, int, text) from public, anon;
grant execute on function public.can_add_sticker(uuid, int, text) to authenticated;

drop policy if exists "stickers add own" on public.post_stickers;
create policy "stickers add own" on public.post_stickers for insert to authenticated
  with check (user_id = auth.uid() and public.can_add_sticker(post_id, media_idx, item_id));
