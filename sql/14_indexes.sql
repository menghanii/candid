-- candid. 조회 성능용 인덱스: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 13_fix_sticker_policy.sql 까지 실행한 뒤에 실행

-- 1) 홈(릴스): 친구들의 '승인된' 게시물을 최신순으로
--    where owner_id in (...) and status = 'approved' order by approved_at desc
create index if not exists posts_feed_idx
  on public.posts (owner_id, approved_at desc)
  where status = 'approved';

-- 2) 프로필: 한 사람의 게시물을 최신순으로
--    where owner_id = ... order by created_at desc
create index if not exists posts_owner_created_idx
  on public.posts (owner_id, created_at desc);

-- 3) 스티커 개수 확인(붙이기): 사진·사용자별 카운트
--    where post_id = ... and media_idx = ... and user_id = ...
create index if not exists post_stickers_count_idx
  on public.post_stickers (post_id, media_idx, user_id);
