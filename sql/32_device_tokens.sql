-- candid. iPhone 앱 푸시(APNs) 기기 토큰: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 앱이 알림 허용을 받으면 register_device 로 토큰을 저장 → notify-owner 함수가 웹 푸시와 함께 iPhone 으로도 보냄
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles on delete cascade,
  platform text not null default 'ios',
  sandbox boolean,                       -- 개발용 빌드 토큰이면 true (함수가 처음 보낼 때 알아내서 기록)
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from anon, authenticated;   -- 앱에서는 아래 함수로만
grant select, insert, update, delete on public.device_tokens to service_role; -- 알림 함수(notify-owner)가 읽고 정리할 수 있게

-- 토큰 등록: 같은 기기에서 다른 계정으로 로그인하면 토큰 주인이 바뀜
create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'login_required' using errcode = 'P0001'; end if;
  if p_token is null or p_token !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'bad_token' using errcode = 'P0001'; end if;
  insert into public.device_tokens (token, user_id) values (lower(p_token), auth.uid())
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now(),
    sandbox = case when public.device_tokens.user_id = excluded.user_id then public.device_tokens.sandbox else null end;
end $$;
create or replace function public.unregister_device(p_token text) returns void
language sql security definer set search_path = '' as $$
  delete from public.device_tokens where token = lower(p_token) and user_id = auth.uid()
$$;
revoke all on function public.register_device(text), public.unregister_device(text) from public, anon;
grant execute on function public.register_device(text), public.unregister_device(text) to authenticated;
