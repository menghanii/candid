-- candid. 데모 친구와 그 게시물·좋아요·댓글·친구 관계를 모두 삭제
-- (계정 삭제 → 프로필 → 게시물/좋아요/댓글/친구 관계가 연쇄 삭제됨)
delete from auth.users where email like '%@candid.invalid';
