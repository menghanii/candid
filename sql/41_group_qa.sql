-- candid. 그룹 투표·질문 + 댓글형 답변 (SQL Editor 에 붙여넣고 Run, 여러 번 실행해도 안전). 40 이후 실행
--  1) 그룹에도 투표·질문 올리기 허용(멤버, 바로 게시)
--  2) 그룹 투표는 그룹에 참여한(활성) 누구나(올린 사람 포함) 투표 가능
--  3) 질문의 답변은 comments 로 저장: 개인 질문은 피드 주인만, 그룹 질문은 그룹 멤버 누구나, 여러 개 가능

-- 1) 그룹 게시물 insert: 사진·영상 + 투표·질문
drop policy if exists "posts insert" on public.posts;
create policy "posts insert" on public.posts for insert to anon, authenticated
  with check (
    (group_id is null and status = 'pending' and approved_at is null and answer is null
      and (author_id is null or author_id = auth.uid())
      and (
        (media_type in ('image', 'video') and image_path like owner_id::text || '/%'
          and (thumb_path is null or thumb_path like owner_id::text || '/%')
          and public.media_paths_ok(owner_id, media))
        or (media_type in ('poll', 'question') and image_path is null and thumb_path is null and media is null)
      ))
    or (group_id is not null and owner_id is null and auth.uid() is not null and author_id = auth.uid()
      and status = 'approved' and answer is null and pinned_at is null and not flagged
      and (
        (media_type in ('image', 'video') and image_path like group_id::text || '/%'
          and (thumb_path is null or thumb_path like group_id::text || '/%')
          and public.media_paths_ok(group_id, media))
        or (media_type in ('poll', 'question') and image_path is null and thumb_path is null and media is null)
      )
      and public.can_post_group(group_id))
  );

-- 2) 투표: 개인 투표는 피드 주인 불가(그대로) / 그룹 투표는 활성 멤버 누구나(올린 사람 포함)
drop policy if exists "votes add" on public.poll_votes;
create policy "votes add" on public.poll_votes for insert to anon, authenticated
  with check (
    exists (select 1 from public.posts p
             where p.id = post_id and p.status = 'approved' and p.media_type = 'poll'
               and option < jsonb_array_length(p.poll_options)
               and (
                 (p.group_id is null and (auth.uid() is null or p.owner_id <> auth.uid()))
                 or (p.group_id is not null and auth.uid() is not null and public.can_post_group(p.group_id))
               ))
    and (
      (auth.uid() is null and voter_key like 'g:%' and user_id is null)
      or (voter_key = 'u:' || auth.uid()::text and user_id = auth.uid())
    )
  );

-- 3) 댓글 = 질문 답변: 질문이면 개인은 피드 주인만, 그룹은 멤버만 (그 외 댓글은 기존 그대로)
drop policy if exists "comments add own" on public.comments;
create policy "comments add own" on public.comments for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.posts p
      where p.id = post_id and p.status = 'approved'
        and (
          p.media_type <> 'question'
          or (p.group_id is null and p.owner_id = auth.uid())
          or (p.group_id is not null and public.can_post_group(p.group_id))
        )
    )
  );
