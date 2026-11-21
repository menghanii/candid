-- candid. 투표 취소(다시 투표) (SQL Editor 에 붙여넣고 Run, 여러 번 실행해도 안전). 41 이후 실행
--  내가 누른 투표를 다시 눌러 취소할 수 있게(로그인 사용자)

drop policy if exists "votes delete own" on public.poll_votes;
create policy "votes delete own" on public.poll_votes for delete to authenticated
  using (user_id = auth.uid() and voter_key = 'u:' || auth.uid()::text);
grant delete on public.poll_votes to authenticated;

-- 로그인 안 하고(기기 키) 투표한 경우에도 취소할 수 있게
create or replace function public.remove_poll_vote(p_post uuid, p_key text) returns void
language sql security definer set search_path = '' as $$
  delete from public.poll_votes
   where post_id = p_post and voter_key = p_key
     and (auth.uid() is null or user_id = auth.uid());
$$;
revoke all on function public.remove_poll_vote(uuid, text) from public;
grant execute on function public.remove_poll_vote(uuid, text) to anon, authenticated;
