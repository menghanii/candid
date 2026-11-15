-- candid. 모든 개인 피드를 비공개로 + 앞으로 가입하는 사람도 비공개로 시작: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 19_private_feed.sql 을 먼저 실행해야 비공개 규칙(내가 친구로 추가한 사람만 보기)이 동작함
-- 사용자는 ☰ 설정 → 피드 공개 범위 에서 언제든 전체 공개로 바꿀 수 있음
alter table public.profiles add column if not exists is_private boolean not null default true;
alter table public.profiles alter column is_private set default true;
update public.profiles set is_private = true where not is_private;
