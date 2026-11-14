-- candid. 투표·질문 게시물에도 스티커 붙이기: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 13 의 can_add_sticker 는 사진·영상 게시물만 허용 → 투표·질문도 허용 (나머지 조건은 그대로)

create or replace function public.can_add_sticker(p_post uuid, p_idx int, p_item text) returns boolean
language sql stable security definer set search_path = '' as $$
  select
    -- 피드에 올라간 게시물(사진·영상·투표·질문)에만. 투표·질문은 한 장이라 0번만
    exists (select 1 from public.posts p where p.id = p_post and p.status = 'approved'
             and (p.media_type in ('image', 'video') or (p.media_type in ('poll', 'question') and p_idx = 0)))
    -- 무료 스티커이거나, 가챠로 가진 스티커만
    and exists (select 1 from public.items t where t.id = p_item and t.kind = 'sticker'
                 and (coalesce((t.data->>'free')::boolean, false)
                      or exists (select 1 from public.inventory i where i.user_id = auth.uid() and i.item_id = t.id)))
    -- 사진 1장(카드 1장)에 1인 10개, 전체 40개까지
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx and s.user_id = auth.uid()) < 10
    and (select count(*) from public.post_stickers s where s.post_id = p_post and s.media_idx = p_idx) < 40
$$;
revoke all on function public.can_add_sticker(uuid, int, text) from public, anon;
grant execute on function public.can_add_sticker(uuid, int, text) to authenticated;
