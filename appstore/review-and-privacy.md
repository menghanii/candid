# 심사 정보 · 앱 개인정보 설문 답안

## 1. 앱 심사 정보 (App Review Information)

### 로그인 정보
- "로그인 필요" 체크
- 사용자 이름 / 암호: **심사용 Google 계정**(또는 카카오)을 하나 만들어 적기
  - 미리 친구 1~2명(내 다른 계정)과 사진 몇 장, 그룹 1개를 만들어 두면 심사원이 바로 기능을 볼 수 있음
  - Apple 로그인이 TestFlight 에서 잘 되면 "Sign in with Apple 로도 가능"이라고 메모에 같이 적기

### 연락처
- 이름: MYUNGHAN YANG · 이메일: contact@candid-feed.com · 전화: (본인 번호)

### 메모 (영어로 붙여넣기)
```
Sign in: use the demo account above (Google), or "Continue with Apple" on the first screen.

What the app does: friends send photos to each other's feeds and the feed owner approves which photos appear. Users can also create shared group albums. The home screen ("Candids") shows friends and groups orbiting around the user; tapping one opens their photos full screen.

The demo account already has friends, photos and a group. A brand-new account starts empty: tap the search icon (top right) to find friends or public groups, or tap ＋ (bottom) to create a group.

User-generated content safeguards (Guideline 1.2):
- Terms of Service (shown on sign-in) prohibit objectionable content: https://candid-feed.com/terms.html
- Report: "⋯" menu on any post or comment → 신고하기 (Report); on a user's feed "⋯" → Report
- Block: user's feed "⋯" → 차단하기 (Block). Photos sent anonymously can be blocked with "⋯" → 이 익명 친구 차단 (Block this anonymous sender)
- Posts and comments reported by 3 different users are hidden automatically
- The operator reviews every report within 24 hours and removes violating content and accounts
- Nothing appears on a user's own feed without their approval
- Account deletion in-app: ☰ → Settings → 계정 삭제 (Delete account)

Permissions:
- Photo library (read): to show the in-app photo picker. If the user allows only selected photos or denies, the system photo picker is used instead.
- Photo library (add): to save photos the user chooses to save.
- Camera: to take a photo/video to send.
- Notifications: new photos, comments and group invites.
- App Tracking Transparency: asked once; if allowed, ads may be personalized. If not, only non-personalized ads are shown.

Ads: native ads (Google AdMob) appear between photos in the Candids view and are labeled "광고 (Ad)".

Support: https://candid-feed.com/support.html · contact@candid-feed.com
```

## 2. 앱 개인정보 (App Privacy) 설문 답안

**데이터를 수집합니까?** → 예

| 데이터 유형 | 항목 | 사용 목적 | 사용자와 연결 | 추적에 사용 |
|---|---|---|---|---|
| 연락처 정보 | 이름, 이메일 주소 | 앱 기능 | 예 | 아니요 |
| 사용자 콘텐츠 | 사진 또는 비디오 | 앱 기능 | 예 | 아니요 |
| 사용자 콘텐츠 | 기타 사용자 콘텐츠(한마디·댓글·투표·스티커) | 앱 기능 | 예 | 아니요 |
| 식별자 | 사용자 ID | 앱 기능 | 예 | 아니요 |
| 식별자 | 기기 ID(광고 식별자, 추적을 허용한 경우) | 제3자 광고 | 예 | **예** |
| 사용 데이터 | 제품 상호작용(좋아요·본 사진) | 앱 기능 | 예 | 아니요 |
| 사용 데이터 | 광고 데이터(광고 노출·클릭) | 제3자 광고 | 예 | **예** |
| 진단 | 충돌 데이터·성능 데이터(AdMob SDK 가 수집) | 제3자 광고 | 아니요 | 아니요 |

- **"추적" 질문**: 예 — 사용자가 추적을 허용하면 광고 식별자로 맞춤 광고(AdMob). 앱이 추적 허용을 묻는 창(ATT)을 띄우므로 이 답과 맞아야 함
- 위치, 연락처(주소록), 건강, 금융, 검색 기록, 민감 정보 → 수집 안 함
- 참고: AdMob 의 공식 안내(Google "App Store 데이터 공개")와 다르면 그쪽을 따르기

## 3. 그 밖에 입력할 것
- 수출 규정: 빌드에 "암호화 사용 안 함(표준 HTTPS 만)"으로 이미 설정됨 → 따로 묻지 않음
- 광고 식별자(IDFA) 사용 여부 질문이 나오면: 예 · 앱 내 광고 제공
- 연령 등급 설문: 사용자 생성 콘텐츠 "예", 무제한 웹 접근 "아니요", 나머지 "없음"
