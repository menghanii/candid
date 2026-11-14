-- candid. 프로필에 언어 저장(푸시 알림을 받는 사람 언어로 보내기 위해): SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)
-- 앱이 로그인할 때 기기 언어(또는 메뉴에서 고른 언어)를 자동으로 저장함. 값: ko / en / ja …

alter table public.profiles add column if not exists lang text;
alter table public.profiles drop constraint if exists profiles_lang_ok;
alter table public.profiles add constraint profiles_lang_ok check (lang is null or lang ~ '^[a-z]{2}$');
grant update (lang) on public.profiles to authenticated;
