-- candid. 닷 잡기(이스터에그): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
--
--  · 화면에 가끔 나타나는 닷을 누르면 잡힘. 색마다 희귀도가 다름(블루 70% … 무지개 0.2%)
--  · 잡은 닷은 프로필 소개 아래에 잡은 순서대로 전시 → 누구나 볼 수 있음
--  · 1인 하루 30마리까지(도배 방지)
create table if not exists public.dot_catches (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  kind text not null check (kind in ('blue', 'mint', 'pink', 'lemon', 'purple', 'ink', 'gold', 'rainbow')),
  created_at timestamptz not null default now()
);
create index if not exists dot_catches_user_idx on public.dot_catches (user_id, created_at);
alter table public.dot_catches enable row level security;
drop policy if exists "dots read" on public.dot_catches;
create policy "dots read" on public.dot_catches for select using (true);
revoke all on public.dot_catches from anon, authenticated;
grant select on public.dot_catches to anon, authenticated;   -- 잡기는 catch_dot 함수로만

create or replace function public.catch_dot(p_kind text) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if (select count(*) from public.dot_catches where user_id = auth.uid() and created_at > now() - interval '1 day') >= 30 then
    raise exception 'daily_limit' using errcode = 'P0001';
  end if;
  insert into public.dot_catches (user_id, kind) values (auth.uid(), p_kind);
  select count(*) into n from public.dot_catches where user_id = auth.uid();
  return n;
end $$;
revoke all on function public.catch_dot(text) from public, anon;
grant execute on function public.catch_dot(text) to authenticated;
