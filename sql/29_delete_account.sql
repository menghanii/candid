-- candid. 회원 탈퇴(앱스토어 필수): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전). 28_group_invites.sql 이후 실행
--
--  · 내 계정과 내 데이터 전부 삭제: 내 피드·사진, 내가 만든 그룹(그 안의 사진 포함), 좋아요·댓글·스티커, 친구 관계, 알림 구독, 닷 등
--    (auth.users 를 지우면 profiles 와 그에 딸린 것들이 연쇄로 지워짐)
--  · 내가 다른 그룹에 올린 사진도 삭제
--  · 내가 친구 피드에 보내서 친구가 받은(승인·대기) 사진은 친구의 것이므로 남기고, 보낸 사람만 '탈퇴한 친구'로 익명 처리
--  · 사진 파일은 storage_trash 로 보내 알림 함수가 정리(프로필 사진 파일은 앱이 탈퇴 직전에 직접 지움)
create or replace function public.delete_my_account(p_confirm text) returns void
language plpgsql security definer set search_path = '' as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if p_confirm is distinct from 'DELETE' then raise exception 'confirm_required' using errcode = 'P0001'; end if;

  -- 1) 내 피드 게시물의 파일을 정리 대기열로(그룹 게시물은 삭제 트리거가 알아서 넣음)
  insert into public.storage_trash (path)
    select x from (
      select p.image_path as x from public.posts p where p.owner_id = me
      union select p.thumb_path from public.posts p where p.owner_id = me
      union select e->>'p' from public.posts p, jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e where p.owner_id = me
      union select e->>'t' from public.posts p, jsonb_array_elements(coalesce(p.media, '[]'::jsonb)) e where p.owner_id = me) s
    where x is not null and x !~ '^https?:'
  on conflict do nothing;

  -- 2) 다른 그룹에 내가 올린 사진 삭제(파일은 트리거가 대기열로)
  delete from public.posts where group_id is not null and author_id = me;

  -- 3) 친구 피드에 보낸 사진은 남기고 익명 처리
  update public.posts set author_id = null, author_name = '탈퇴한 친구'
   where group_id is null and author_id = me and owner_id <> me;

  -- 4) 계정 삭제 → 프로필과 그에 딸린 데이터 연쇄 삭제
  delete from auth.users where id = me;
end $$;
revoke all on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated;
