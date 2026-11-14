-- candid. 피드에서 내리기 = 삭제 대신 '되돌리기한 피드'로 보관: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- status: pending(승인 대기) · approved(피드에 공개) · hidden(주인이 내림, 주인만 보임)

alter table public.posts drop constraint if exists posts_status_check;
alter table public.posts add constraint posts_status_check check (status in ('pending', 'approved', 'hidden'));
alter table public.posts add column if not exists hidden_at timestamptz;
-- 읽기 정책은 그대로: 공개는 approved 만, 주인은 pending·hidden 까지 (owner_id = auth.uid())
