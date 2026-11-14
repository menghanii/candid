-- candid. 스티커는 붙인 사람만 떼기·수정 가능 (피드 주인도 친구 스티커는 못 뗌): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 09 에서는 피드 주인도 친구 스티커를 뗄 수 있었음 → 본인 것만으로 변경

drop policy if exists "stickers remove" on public.post_stickers;
drop policy if exists "stickers remove own" on public.post_stickers;
create policy "stickers remove own" on public.post_stickers for delete to authenticated
  using (user_id = auth.uid());

-- 옮기기·크기·회전·글자도 본인 것만 (09 와 같음, 확인용으로 다시 만듦)
drop policy if exists "stickers move own" on public.post_stickers;
create policy "stickers move own" on public.post_stickers for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
