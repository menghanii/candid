# 그룹 (공유 앨범)

결혼식·여행·동아리처럼 한 주제로 여러 명이 같이 사진을 모으는 공간. 누구나 만들 수 있고, 만든 사람이 방장.

## 규칙

| 항목 | 비공개 (private) | 공개 (public) |
|---|---|---|
| 보기 | 멤버만 | 누구나(로그인 없이도) |
| 검색 | 안 나옴 | 이름·@아이디로 나옴 |
| 참여 | 초대 링크로 신청 → 방장 승인 | `바로 참여`: 참여하기 = 바로 멤버+팔로우 / `승인 후 참여`: 팔로우는 누구나, 멤버는 신청 → 방장 승인 |
| 사진 수 | 제한 없음 | 최근 99개. 넘으면 오래된 것부터 자동 삭제(📌 고정은 남음, 최대 9개) |
| 도배 방지 | 없음 | 1인당 하루 N개(기본 10, 방장이 1~100) |

- 공개 범위는 만든 뒤 바꿀 수 없음(DB 에서 수정 권한 자체가 없음)
- 올리기: 로그인한 멤버만, 사진·영상만, 승인 없이 바로 게시. 올린 사람 이름은 프로필 이름으로 고정
- 좋아요·댓글: 볼 수 있는 로그인 사용자 / 스티커 꾸미기: 멤버·팔로워
- 팔로우한 그룹의 새 사진은 릴스에 섞여 나옴(그룹 이름 배지)
- 신고: 서로 다른 3명이 신고하면 자동으로 가려짐(방장·올린 사람에게만 보임). 방장은 삭제하거나 다시 보이게 할 수 있음
- 방장: 정보 수정, 대표 사진, 참여 신청 승인·거절, 멤버 내보내기, 방장 넘기기, 업로드 마감/재개, 초대 링크 새로 만들기, 그룹 삭제, 게시물 고정·삭제
- 1인당 그룹 개설 30개까지 (25 SQL)
- 푸시: 방장은 새 사진 알림 켬, 다른 멤버·팔로워는 끔으로 시작(그룹 ⋯ 메뉴에서 켜기). 10분 안에 여러 장이 올라오면 묶어서 "새 사진 N장"

## 주소

- 그룹: `?g=그룹아이디`
- 초대 링크: `?gi=초대코드` (비공개·승인제 그룹. 방장이 새로 만들면 예전 링크는 막힘)
- 로그인 안 한 채 그룹·초대 화면에서 로그인하면 그 화면으로 돌아옴(`localStorage.candid_return`)

## 데이터

`sql/18_groups.sql`

- `groups`: 그룹. `invite_code`·`last_notified_at` 은 앱에서 못 읽음(칸 단위 권한)
- `group_members`: role `owner|member`, status `pending|active`. 추가·승인은 함수로만
- `group_follows`: 팔로우 + `notify`(새 사진 푸시)
- `posts.group_id`: 그룹 게시물은 `owner_id` 없이 저장 → 개인 피드 화면·쿼리에 섞이지 않음. `pinned_at`, `flagged` 추가
- `post_reports`: 신고
- `storage_trash`: 지워진 그룹 사진·영상 경로. 알림 함수가 호출될 때마다 저장소에서 지움(SQL 에서 직접 파일 삭제는 막혀 있어서)
- 함수(rpc): `join_group`, `approve_member`, `follow_group`, `group_invite_code`, `group_by_invite`, `transfer_group`, `pin_post`, `report_post`, `unflag_post`

## 설정 순서

1. SQL Editor 에서 `sql/18_groups.sql` 실행
2. 알림 함수(`notify-owner`)를 `supabase/functions/notify-owner/index.ts` 로 다시 배포
3. (선택) 참여 신청 푸시: Database → Webhooks → Create, Table `group_members`, Events `Insert` → 같은 함수, 헤더 `x-webhook-secret`

## 검증

`sql/18_groups.sql` 은 PGlite(브라우저용 Postgres)에서 01~18 을 순서대로 실행하고 57개 시나리오(권한·99개 정리·고정·도배 제한·신고·초대·방장 넘기기 등)로 확인함. 두 번 실행해도 안전.
