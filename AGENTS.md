# AGENTS.md — candid. 작업 규칙

이 문서는 **사람과 AI 에이전트 모두**가 따른다. 특히 빌드/배포 전 테스트는 예외 없이 필수다.

## 0. 최우선 규칙 — 빌드 전 테스트 필수

아래 작업을 **시작하기 전에 반드시** 테스트를 실행하고, 하나라도 실패하면 **즉시 중단**한다. 실패를 무시하거나 테스트를 건너뛰고 빌드하지 않는다.

```bash
node tests/run-tests.js        # 저장소 루트
# 또는
cd ios-app && npm test
```

성공 출력은 `ALL TESTS PASSED` 이고 종료 코드는 `0` 이어야 한다.

### 테스트가 필수인 작업
- `cd ios-app && node build-www.js`
- `cd ios-app && npm run build | sync | dev | release`
- Xcode 시뮬레이터 빌드/실행, Archive
- TestFlight 업로드, 배포
- 웹 번들(`ios-app/www`) 재생성

### 자동 게이트
`ios-app/build-www.js`가 파일을 복사하기 **전에** `tests/run-tests.js`를 `require`한다. 실패하면 예외로 빌드가 중단된다. 따라서 `build`, `sync`, `dev`, `release`는 자동으로 게이트를 거친다.

### 자동 게이트를 우회하는 경로 (주의)
아래는 `build-www.js`를 거치지 않으므로 테스트가 자동 실행되지 않는다. 실행 전에 **수동으로** `node tests/run-tests.js`를 먼저 돌린다.
- `npx cap sync ios` (단독)
- `npx cap run ios`
- Xcode에서 바로 Run / Product > Archive
- `xcodebuild ...`
- 웹 번들을 갱신하지 않는 배포 스크립트

Xcode 빌드에도 강제하려면 Target > Build Phases > **New Run Script Phase**에 아래를 추가한다(경로는 프로젝트 구조에 맞게 확인).

```sh
cd "$SRCROOT/../../.." && node tests/run-tests.js
```

### 빌드 업로드는 사용자 확인 후 (필수)
Archive/TestFlight 업로드·배포는 **사용자에게 먼저 물어보고** 진행한다. 수정할 때마다 자동으로 빌드/업로드하지 않는다. 테스트와 로컬 빌드까지만 수행하고, 업로드는 확인을 받은 뒤에 한다.

## 1. 테스트 구성 (`tests/run-tests.js`)
외부 의존성 없이 Node 내장 기능만 사용한다.
1. `index.html` 인라인 스크립트 4개 문법 검사
2. 공통 모듈 단위 테스트: `normSearch`, `searchMatch`, `recentPosts`, `memberSub`, `memberWho`
3. 친구/그룹 작성 진입 공통화(시트 닫기 → `composeTarget`)
4. 은하 이름: `Blue/Pink/Purple Orbit`, 한글 이름 잔존 없음
5. i18n 누락 0 (`tools/i18n-check.js`)
6. **동선/동작 배선**: ⊕ → 친구/그룹 선택, 작성 화면 진입, 그룹 업로드, 궤도 탭 이동, 트렌딩 진입/폴백, 검색 결과 링크, 그룹 관리 승인/거절/더보기, 빈 목록의 다음 동선

자세한 내용과 수동 시뮬레이터 체크리스트는 `docs/TESTING.md`를 본다.

## 2. 테스트 실패 시
1. 실패한 체크의 `✗` 메시지를 확인한다.
2. 코드를 고치거나, 리팩터링으로 문자열/구조가 바뀌었다면 `tests/run-tests.js`의 해당 검증을 **실제 동작에 맞게** 갱신한다(검증을 약화시키지 않는다).
3. `node tests/run-tests.js`가 `ALL TESTS PASSED`가 될 때까지 반복한다.
4. 그 다음에만 빌드/배포를 진행한다.

## 3. iOS 빌드 메모
- 시뮬레이터 확인은 정상이다.
- Xcode는 `ios-app/ios/App/App.xcworkspace`(CocoaPods) 사용.
- 시뮬레이터 빌드 예:
  ```bash
  cd ios-app
  xcodebuild -workspace ios/App/App.xcworkspace -scheme App -sdk iphonesimulator \
    -configuration Debug -destination 'id=6D662C7C-1812-4B9E-A56C-3F640E468138' \
    CODE_SIGNING_ALLOWED=NO build
  ```
- TestFlight Archive/업로드는 Apple Developer 서명/프로비저닝 + App Store Connect 인증이 필요하다.
