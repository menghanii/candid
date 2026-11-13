-- candid. 데모 친구 4명 + 게시물 14개(영상 1개) + 좋아요·댓글
-- SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전(같은 데이터는 건너뜀).
-- 지우려면 demo_cleanup.sql 실행.
-- 사진: Unsplash(무료 라이선스), 영상: MDN CC0 샘플

-- 1) 가짜 계정 (로그인 불가, 이메일 도메인 .invalid 로 구분)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change)
values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'jisoo@candid.invalid', '', now(),
   '{"provider":"demo","providers":["demo"]}', '{"name":"지수"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'taeyun@candid.invalid', '', now(),
   '{"provider":"demo","providers":["demo"]}', '{"name":"태윤"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'harin@candid.invalid', '', now(),
   '{"provider":"demo","providers":["demo"]}', '{"name":"하린"}', now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'dohyun@candid.invalid', '', now(),
   '{"provider":"demo","providers":["demo"]}', '{"name":"도현"}', now(), now(), '', '', '', '')
on conflict (id) do nothing;

-- 2) 프로필 (가입 트리거가 만든 행을 채움)
update public.profiles set name = '지수', onboarded = true, bio = '굴욕샷 환영 📸 단 너무 심한 건 거절함', avatar_url = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&h=200&fit=crop&q=70&fm=jpg' where id = 'd0000000-0000-4000-8000-000000000001';
update public.profiles set name = '태윤', onboarded = true, bio = '먹는 게 남는 거', avatar_url = 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=200&h=200&fit=crop&q=70&fm=jpg' where id = 'd0000000-0000-4000-8000-000000000002';
update public.profiles set name = '하린', onboarded = true, bio = '고양이 집사 🐈', avatar_url = 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=200&h=200&fit=crop&q=70&fm=jpg' where id = 'd0000000-0000-4000-8000-000000000003';
update public.profiles set name = '도현', onboarded = true, bio = '산이 좋아', avatar_url = 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=200&h=200&fit=crop&q=70&fm=jpg' where id = 'd0000000-0000-4000-8000-000000000004';

-- 3) 게시물 (승인 완료 상태)
insert into public.posts (id, owner_id, author_name, mission, text, image_path, thumb_path, media_type, status, created_at, approved_at)
values
  ('e0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000001', '하린', '제일 잘 나온 사진', '케이블카 앞에서 우리 넷', 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '2 hours', now() - interval '1 hours'),
  ('e0000000-0000-4000-8000-000000000011', 'd0000000-0000-4000-8000-000000000004', '지수', '우리만 아는 흑역사', '다들 이 날 기억하지? ㅋㅋ', 'https://images.unsplash.com/photo-1511632765486-a01980e01a18?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1511632765486-a01980e01a18?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '3 hours', now() - interval '2 hours'),
  ('e0000000-0000-4000-8000-000000000012', 'd0000000-0000-4000-8000-000000000003', '지수', '나를 한 단어로', '고양이 = 하린', 'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '4 hours', now() - interval '3 hours'),
  ('e0000000-0000-4000-8000-000000000013', 'd0000000-0000-4000-8000-000000000002', '도현', '제일 웃긴 사진', '피자 한 판 혼자 다 먹음 ㅋㅋ', 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '5 hours', now() - interval '4 hours'),
  ('e0000000-0000-4000-8000-000000000014', 'd0000000-0000-4000-8000-000000000001', '하린', '자유', '꽃 보러 간 날 🌷', 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', 'https://menghanii.github.io/candid/brand/demo-flower.jpg', 'video', 'approved', now() - interval '6 hours', now() - interval '5 hours'),
  ('e0000000-0000-4000-8000-000000000015', 'd0000000-0000-4000-8000-000000000004', '태윤', '제일 잘 나온 사진', '여름 여행 인생샷', 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '8 hours', now() - interval '7 hours'),
  ('e0000000-0000-4000-8000-000000000016', 'd0000000-0000-4000-8000-000000000001', '태윤', '몰래 찍은 사진', '혼자 웃고 있길래 찍음', 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '10 hours', now() - interval '9 hours'),
  ('e0000000-0000-4000-8000-000000000017', 'd0000000-0000-4000-8000-000000000003', '태윤', '제일 웃긴 사진', '하린이네 강아지 표정 봐', 'https://images.unsplash.com/photo-1543466835-00a7907e9de1?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1543466835-00a7907e9de1?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '13 hours', now() - interval '12 hours'),
  ('e0000000-0000-4000-8000-000000000018', 'd0000000-0000-4000-8000-000000000002', '지수', '나를 한 단어로', '먹보', 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '16 hours', now() - interval '15 hours'),
  ('e0000000-0000-4000-8000-000000000019', 'd0000000-0000-4000-8000-000000000004', '하린', '자유', '별 보러 갔던 날', 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '21 hours', now() - interval '20 hours'),
  ('e0000000-0000-4000-8000-000000000020', 'd0000000-0000-4000-8000-000000000003', '도현', '몰래 찍은 사진', '공부하는 척 ㅋㅋ', 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '27 hours', now() - interval '26 hours'),
  ('e0000000-0000-4000-8000-000000000021', 'd0000000-0000-4000-8000-000000000001', '도현', '자유', '생일 축하해 지수야 🎈', 'https://images.unsplash.com/photo-1530103862676-de8c9debad1d?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1530103862676-de8c9debad1d?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '32 hours', now() - interval '31 hours'),
  ('e0000000-0000-4000-8000-000000000022', 'd0000000-0000-4000-8000-000000000002', '하린', '제일 잘 나온 사진', '화보 찍는 줄', 'https://images.unsplash.com/photo-1488161628813-04466f872be2?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1488161628813-04466f872be2?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '39 hours', now() - interval '38 hours'),
  ('e0000000-0000-4000-8000-000000000023', 'd0000000-0000-4000-8000-000000000004', '지수', '몰래 찍은 사진', '뒷모습 장인', 'https://images.unsplash.com/photo-1503023345310-bd7c1de61c7d?w=1080&h=1350&fit=crop&q=75&fm=jpg', 'https://images.unsplash.com/photo-1503023345310-bd7c1de61c7d?w=480&h=600&fit=crop&q=65&fm=jpg', 'image', 'approved', now() - interval '46 hours', now() - interval '45 hours')
on conflict (id) do nothing;

-- 4) 데모 친구끼리 좋아요·댓글
insert into public.likes (post_id, user_id)
select p.id, f.id from public.posts p cross join public.profiles f
 where p.id::text like 'e0000000-%' and f.id::text like 'd0000000-%' and f.id <> p.owner_id
   and (abs(hashtext(p.id::text || f.id::text)) % 3) <> 0
on conflict do nothing;

insert into public.comments (id, post_id, user_id, body, created_at) values
  ('c0000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000002', '이 날 진짜 재밌었는데 ㅠㅠ', now() - interval '50 minutes'),
  ('c0000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000004', '나 눈 감았네;;', now() - interval '30 minutes'),
  ('c0000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-000000000013', 'd0000000-0000-4000-8000-000000000003', '태윤아 이거 기억 안 나지? ㅋㅋㅋ', now() - interval '3 hours'),
  ('c0000000-0000-4000-8000-000000000004', 'e0000000-0000-4000-8000-000000000016', 'd0000000-0000-4000-8000-000000000003', '이 사진 내가 찍은 거 맞지?', now() - interval '8 hours')
on conflict (id) do nothing;

-- 5) 실제 사용자(데모 친구 제외)가 데모 친구 4명을 친구로 추가
insert into public.follows (follower_id, followee_id)
select me.id, f.id from public.profiles me cross join public.profiles f
 where me.id::text not like 'd0000000-%' and f.id::text like 'd0000000-%'
on conflict do nothing;
