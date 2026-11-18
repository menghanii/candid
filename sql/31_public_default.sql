-- candid. 피드 기본값을 '전체 공개'로: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 앞으로 가입하는 사람은 공개로 시작하고, 원하면 ☰ 설정 → 피드 공개 범위 에서 비공개로 바꿀 수 있음
alter table public.profiles alter column is_private set default false;

-- (선택) 이미 가입한 사람도 모두 공개로 바꾸려면 아래 줄의 맨 앞 -- 를 지우고 실행
-- 주의: 22번 때 모두 비공개로 바꿨기 때문에, 그 뒤 직접 비공개를 고른 사람도 함께 공개로 바뀜
-- update public.profiles set is_private = false where is_private;
