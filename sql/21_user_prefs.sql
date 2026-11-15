-- candid. 내 설정(친구·그룹 목록 순서 등)을 계정에 저장: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 본인만 읽고 쓸 수 있음. 실행 전에는 앱이 이 기기에만 저장함
create table if not exists public.user_prefs (
  user_id uuid primary key default auth.uid() references public.profiles on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_prefs enable row level security;
drop policy if exists "prefs own read" on public.user_prefs;
create policy "prefs own read" on public.user_prefs for select to authenticated using (user_id = auth.uid());
drop policy if exists "prefs own insert" on public.user_prefs;
create policy "prefs own insert" on public.user_prefs for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "prefs own update" on public.user_prefs;
create policy "prefs own update" on public.user_prefs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.user_prefs from anon, authenticated;
grant select, insert, update on public.user_prefs to authenticated;
-- 너무 큰 값 방지(목록 순서 정도만)
alter table public.user_prefs drop constraint if exists user_prefs_size;
alter table public.user_prefs add constraint user_prefs_size check (pg_column_size(data) < 32768);
