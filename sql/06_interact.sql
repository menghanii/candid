-- candid. 투표·질문: SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전)

-- 1) 게시물 종류 확장: image | video | poll(투표) | question(질문)
alter table public.posts alter column image_path drop not null;
alter table public.posts add column if not exists poll_options jsonb;     -- 투표 선택지 ["A","B",...]
alter table public.posts add column if not exists answer text;           -- 질문에 대한 주인의 답
alter table public.posts add column if not exists answered_at timestamptz;

alter table public.posts drop constraint if exists posts_media_type;
alter table public.posts add constraint posts_media_type check (media_type in ('image', 'video', 'poll', 'question'));
alter table public.posts drop constraint if exists posts_text_check;
alter table public.posts add constraint posts_text_check check (char_length(text) <= 120);
alter table public.posts drop constraint if exists posts_answer_len;
alter table public.posts add constraint posts_answer_len check (answer is null or char_length(answer) <= 300);
alter table public.posts drop constraint if exists posts_kind_shape;
alter table public.posts add constraint posts_kind_shape check (
  case media_type
    when 'poll' then jsonb_typeof(poll_options) = 'array' and jsonb_array_length(poll_options) between 2 and 5
                     and char_length(coalesce(text, '')) >= 2
    when 'question' then char_length(coalesce(text, '')) >= 2
    else image_path is not null
  end
);

-- 친구(비로그인 포함)가 보내는 게시물: 무조건 대기 상태, 사진·영상은 주인 폴더에만
drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    status = 'pending' and approved_at is null and answer is null
    and (author_id is null or author_id = auth.uid())
    and (
      (media_type in ('image', 'video') and image_path like owner_id::text || '/%'
        and (thumb_path is null or thumb_path like owner_id::text || '/%'))
      or (media_type in ('poll', 'question') and image_path is null and thumb_path is null)
    )
  );

-- 2) 투표: 피드 주인은 참여 불가, 한 사람(기기)당 1표
--    voter_key: 로그인 'u:<사용자ID>' / 비로그인 'g:<기기별 랜덤값>'
create table if not exists public.poll_votes (
  post_id uuid not null references public.posts on delete cascade,
  voter_key text not null,
  user_id uuid references public.profiles on delete cascade,
  option int not null check (option >= 0),
  created_at timestamptz not null default now(),
  primary key (post_id, voter_key)
);
alter table public.poll_votes enable row level security;
drop policy if exists "votes read" on public.poll_votes;
create policy "votes read" on public.poll_votes for select
  using (exists (select 1 from public.posts p where p.id = post_id and p.status = 'approved'));
drop policy if exists "votes add" on public.poll_votes;
create policy "votes add" on public.poll_votes for insert to anon, authenticated
  with check (
    exists (select 1 from public.posts p
             where p.id = post_id and p.status = 'approved' and p.media_type = 'poll'
               and option < jsonb_array_length(p.poll_options)
               and (auth.uid() is null or p.owner_id <> auth.uid()))
    and (
      (auth.uid() is null and voter_key like 'g:%' and user_id is null)
      or (voter_key = 'u:' || auth.uid()::text and user_id = auth.uid())
    )
  );
grant select, insert on public.poll_votes to anon, authenticated;
