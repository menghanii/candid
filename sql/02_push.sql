-- candid. 푸시 알림: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)

create table if not exists public.push_subscriptions (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "push own select" on public.push_subscriptions;
create policy "push own select" on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
drop policy if exists "push own insert" on public.push_subscriptions;
create policy "push own insert" on public.push_subscriptions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "push own update" on public.push_subscriptions;
create policy "push own update" on public.push_subscriptions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "push own delete" on public.push_subscriptions;
create policy "push own delete" on public.push_subscriptions for delete to authenticated using (user_id = auth.uid());

grant select, insert, update, delete on public.push_subscriptions to authenticated;

-- Edge Function(서버)이 읽고 정리할 수 있도록
grant select on public.posts to service_role;
grant select, delete on public.push_subscriptions to service_role;
