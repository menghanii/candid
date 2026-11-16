# candid. — 친구들이 만들어주는 나의 피드

서버 없는 정적 웹앱 + Supabase(무료: DB · 소셜 로그인 · 사진 저장소).

```
index.html     앱 전체 (UI + 로직)
config.js      Supabase 접속 정보 + 푸시 공개키
sw.js          서비스 워커 (푸시 알림 수신)
manifest.json  홈 화면 앱 설정
brand/         아이콘·OG 이미지
sql/           DB 변경 SQL (번호 순서대로 실행)
supabase/functions/notify-owner/  푸시 발송 서버 함수
```

## 1. Supabase 프로젝트 만들기 (5분)
1. https://supabase.com 가입 → **New project** (Region: Northeast Asia (Seoul))
2. **SQL Editor** → `sql/` 폴더의 SQL을 **번호 순서대로** 하나씩 붙여넣고 **Run** (아래 표 참고)
3. **Project Settings → API** 에서 `Project URL`, `anon public` 키를 `config.js` 에 입력

## 2. 로그인 켜기 (Authentication → Sign In / Providers)
콜백 URL은 공통으로 `https://<프로젝트ID>.supabase.co/auth/v1/callback`

**Google**
1. https://console.cloud.google.com → API 및 서비스 → OAuth 동의 화면 설정 → 사용자 인증 정보 → OAuth 클라이언트 ID(웹 애플리케이션)
2. 승인된 리디렉션 URI 에 위 콜백 URL 추가
3. Client ID / Secret 을 Supabase Google provider 에 입력 후 Enable

**Kakao**
1. https://developers.kakao.com → 내 애플리케이션 → 앱 추가
2. 카카오 로그인 활성화, Redirect URI 에 위 콜백 URL 등록
3. 동의항목: 닉네임 · 프로필 사진 설정. 이메일(account_email)은 비즈 앱 전환이 필요할 수 있음
   → 이메일 동의를 못 켜면 Supabase Kakao 설정의 "Allow users without an email" 옵션을 켜기
4. REST API 키 → Client ID, 보안 → Client Secret 코드 생성 후 Supabase Kakao provider 에 입력

하나만 쓸 거면 `config.js` 의 `PROVIDERS` 에서 다른 하나를 지우기.

**Authentication → URL Configuration**
- Site URL: 배포 주소 (`https://candid-feed.com/`)
- Redirect URLs: 배포 주소와 `http://localhost:3000/**` 추가

> 배포 도메인을 바꾸면(예: GitHub Pages → Cloudflare Pages) Site URL / Redirect URLs 도 새 도메인으로 바꿔야 로그인이 됩니다.

## 3. 로컬 실행
```bash
python3 -m http.server 3000   # → http://localhost:3000
```

## 4. 무료 배포 — Cloudflare
현재 배포: **https://candid-feed.com** (예전 주소 https://candid.candidcrew.workers.dev 도 계속 동작)

- `wrangler.jsonc` + `worker/index.js`: 정적 파일은 그대로 내보내고, `/p/<경로>` 는 Supabase 사진 저장소를 중계하며 Cloudflare 캐시에 30일 보관(Supabase 전송량 절약). 캐시는 직접 연결한 도메인에서만 동작
- `.assetsignore`: 정적 파일로 올리지 않을 파일(Worker 코드·도구 등)

- **Workers**: Workers & Pages → Create → Workers → Git 연결(Workers Builds) 또는 Wrangler 로 배포. 빌드 없이 저장소 루트를 정적 자산으로 올립니다.
- **Pages(대안)**: Workers & Pages → Create → Pages → Connect to Git → Framework preset None, Build command 비움, Build output directory `/`.

배포 후:
1. 그 주소를 Supabase **Authentication → URL Configuration** 의 Site URL / Redirect URLs 에 추가
2. `index.html` 의 `og:image` 절대 URL 을 배포 도메인으로 유지
3. PWA 설치·푸시 구독은 도메인(origin)에 묶이므로 이전 후 다시 설치·알림 켜기

- `_headers` 로 index.html·config.js·sw.js 는 캐시하지 않고 `brand/` 는 7일 캐시합니다.
- `secrets.local.env` 는 `.gitignore` 에 있어 Git 배포에는 안 올라갑니다. 폴더를 통째로 드래그 업로드하면 올라갈 수 있으니 **Git 연동**을 권장합니다.
- 저장소 루트를 그대로 자산으로 올리면 `sql/`, `tools/`, `supabase/`, `README.md` 도 공개됩니다(비밀은 없지만, 필요 없으면 빌드 시 공개 파일만 `dist/` 로 복사해 올리세요).

대안: Netlify(월 100GB), Render(월 100GB), GitHub Pages(월 100GB 소프트 한도). Vercel Hobby는 비상업용만 허용.

## 권한 구조 (sql/01_schema.sql 의 RLS)
| 누가 | 할 수 있는 것 |
|---|---|
| 누구나(비로그인 친구 포함) | 승인된 게시물 보기, `pending` 상태로만 게시물 던지기 |
| 주인장(로그인) | 내 대기함 보기, 승인 / 거절 / 내리기 |

## 알려진 한계 (MVP)
- 비로그인 업로드라 스팸 방지 없음 → 필요 시 Supabase Edge Function + 캡차/레이트리밋
- 대기 중 사진도 URL을 알면 접근 가능 (경로가 랜덤 UUID라 추측은 어려움)
- 새 게시물 알림(카톡/푸시) 없음

## 5. 푸시 알림 (친구가 사진을 보내면 주인장에게 알림)
구성: `sw.js`(알림 수신) · `manifest.json`(홈 화면 앱) · `sql/02_push.sql`(구독 테이블) · `supabase/functions/notify-owner`(발송)

1. **SQL Editor** 에서 `sql/02_push.sql` 실행
2. **Edge Functions → Deploy a new function → Via Editor**, 이름 `notify-owner`, `supabase/functions/notify-owner/index.ts` 붙여넣고 Deploy
   - 함수 설정에서 **Verify JWT** 끄기 (대신 `x-webhook-secret` 헤더로 검증)
3. **Edge Functions → Secrets** 에 `secrets.local.env` 의 4개 값 등록 (이 파일은 git 에 올리지 않음)
4. **Database → Webhooks → Create**
   - Table `posts`, Events `Insert`, Type `Supabase Edge Functions` → `notify-owner`
   - HTTP Headers 에 `x-webhook-secret: <WEBHOOK_SECRET 값>` 추가
   - **같은 방법으로 하나 더**: Table `post_stickers`, Events `Insert` → 같은 함수 (친구가 내 사진을 꾸미면 알림)
   - (그룹) Table `group_members`, Events `Insert` → 같은 함수 (그룹 참여 신청이 오면 방장에게 알림)
   - 대시보드의 함수 이름은 `notify-owner` (Edge Functions → notify-owner → Code 에 이 파일을 붙여넣고 Deploy updates)
5. 앱에서 🔔 → 알림 켜기 (iPhone 은 Safari 공유 → 홈 화면에 추가 후 홈 화면 아이콘으로 열어야 함)

## 6. 프로필 설정 (이름/사진 직접 선택)
SQL Editor 에서 `sql/03_profile.sql` 실행. 첫 로그인 시 프로필 설정 화면이 뜨고, 이후 메뉴 → 프로필 편집 또는 내 프로필 사진을 눌러 변경.

## 그룹 (공유 앨범)
여러 명이 한 주제로 사진을 모으는 공간. 규칙·데이터·설정 순서는 [`docs/GROUPS.md`](docs/GROUPS.md).

## 다국어
한국어·영어·일본어. 기기 언어에 맞춰 자동으로 바뀌고, ☰ 메뉴에서 직접 고를 수 있음. 구조와 새 언어 추가 방법은 [`docs/I18N.md`](docs/I18N.md).

## 캐릭터 닷(.)
로고 끝 파란 점이 캐릭터가 된 '닷'. 모양·색·표정·크기·쓰는 곳은 [`docs/CHARACTER.md`](docs/CHARACTER.md), 원본은 `brand/dot-2d*.svg`(앱에서 사용) · `brand/dot-3d-clay.svg`(3D 질감 시안, 아직 미사용).

## SQL 목록 (`sql/`, 번호 순서대로 실행 · 여러 번 실행해도 안전)
| 파일 | 내용 |
|---|---|
| `01_schema.sql` | 기본 테이블(profiles, posts), 권한(RLS), 사진 저장소 |
| `02_push.sql` | 푸시 알림 구독 테이블 |
| `03_profile.sql` | 프로필 설정(온보딩), 프로필 사진 저장소 |
| `04_bio.sql` | 프로필 메시지 |
| `05_social.sql` | 친구(follows), 좋아요, 댓글, 동영상·썸네일 |
| `06_interact.sql` | 투표·질문 게시물, 투표 테이블 |
| `07_handle.sql` | 아이디(@handle) |
| `08_gacha.sql` | 가챠(뽑기권·아이템·인벤토리) |
| `09_multi_stickers.sql` | 여러 장 게시물, 친구 사진 스티커 |
| `10_free_stickers.sql` | 무료 스티커 목록(도구로 자동 생성) |
| `11_hide.sql` | 피드에서 내리기(되돌리기 보관) |
| `12_text_rotate.sql` | 스티커 텍스트·회전 |
| `13_fix_sticker_policy.sql` | 스티커 붙이기 무한 반복(42P17) 수정 |
| `14_indexes.sql` | 조회 성능용 인덱스 |
| `15_sticker_own_only.sql` | 스티커 떼기·수정은 붙인 본인만 |
| `16_text_stickers.sql` | 투표·질문 게시물에도 스티커 |
| `17_profile_lang.sql` | 프로필 언어(푸시 알림을 받는 사람 언어로) |
| `18_groups.sql` | 그룹(공유 앨범): 공개/비공개, 멤버·팔로우, 99개 자동 정리, 고정, 신고, 도배 방지 |
| `19_private_feed.sql` | 비공개 피드(내가 친구로 추가한 사람만 보기), 한 게시물 사진·영상 10개 서버 확인 |
| `20_stickers_v2.sql` | 스티커 개편: 움직이는 이모지 71 + 이모지 53, 텍스트·미니 그림 은퇴, 1인 1개·게시물당 100개 (`tools/stickers.js` 로 생성) |
| `21_user_prefs.sql` | 내 설정 저장(친구·그룹 목록 순서를 계정에 저장, 본인만 읽기·쓰기) |
| `22_private_default.sql` | 모든 개인 피드를 비공개로 전환 + 새 가입자도 비공개로 시작 |
| `23_edit_text.sql` | 글 수정: 보낸 사람이 한마디 수정·친구 피드에 보낸 사진 삭제, 댓글 수정('수정됨'), 피드 주인은 친구 글 변경 불가 |
| `24_edit_media.sql` | 게시물 사진 빼기·더하기(그룹은 더하기 가능, 친구 피드는 빼기만), 스티커 순서 자동 정리 |
| `25_group_limit.sql` | 1인당 만들 수 있는 그룹 10 → 30개 |
| `26_notifications.sql` | 알림 목록을 서버에서 한 번에(최근 30일 최신 60개, 이름·사진·게시물 포함) |
| `demo/seed.sql` | (선택) 데모 친구 4명 + 게시물 |
| `demo/cleanup.sql` | (선택) 데모 친구 전부 삭제 |

새 SQL을 추가할 때는 다음 번호(`19_...sql`)로 만듭니다.

## 사용한 외부 자료

- 움직이는 이모지 스티커(`brand/stk/*.webp`): [Google Noto Emoji 애니메이션](https://googlefonts.github.io/noto-emoji-animation/), CC BY 4.0. 128px·15fps 로 줄여서 사용. 꾸미기 화면 아래에 출처 표시
