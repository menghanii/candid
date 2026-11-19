-- candid. 광고: 하우스 광고(직접 받는 광고) 표 + 광고 노출·클릭 기록. SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 광고 추가 예: insert into public.house_ads (title, body, image_url, url, cta) values ('제목', '설명', 'https://…/image.jpg', 'https://…', '자세히 보기');
-- 광고 끄기: update public.house_ads set active = false where id = …;
create table if not exists public.house_ads (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) <= 60),
  body text check (body is null or char_length(body) <= 140),
  image_url text, url text, cta text check (cta is null or char_length(cta) <= 20),
  weight int not null default 1 check (weight between 0 and 100),   -- 여러 개면 이 비율로 나옴
  active boolean not null default true,
  starts_at timestamptz, ends_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.house_ads enable row level security;
drop policy if exists "house_ads read active" on public.house_ads;
create policy "house_ads read active" on public.house_ads for select using (
  active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
revoke all on public.house_ads from anon, authenticated;
grant select on public.house_ads to anon, authenticated;
grant select, insert, update, delete on public.house_ads to service_role;

-- 노출·클릭 기록(어느 광고 회사·어느 자리·누가). 앱에서는 아래 함수로만 넣음
create table if not exists public.ad_events (
  id bigint generated always as identity primary key,
  provider text not null check (char_length(provider) <= 20),
  kind text not null check (kind in ('impression', 'view', 'click')),
  placement text check (placement is null or char_length(placement) <= 30),
  ad_id bigint,
  user_id uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists ad_events_time_idx on public.ad_events (created_at);
alter table public.ad_events enable row level security;   -- 정책 없음: 확인은 대시보드·관리자만
revoke all on public.ad_events from anon, authenticated;
grant select, insert, update, delete on public.ad_events to service_role;

create or replace function public.log_ad_event(p_provider text, p_kind text, p_placement text default null, p_ad bigint default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.ad_events (provider, kind, placement, ad_id, user_id) values (left(p_provider, 20), p_kind, left(p_placement, 30), p_ad, auth.uid())
$$;
revoke all on function public.log_ad_event(text, text, text, bigint) from public;
grant execute on function public.log_ad_event(text, text, text, bigint) to anon, authenticated;
