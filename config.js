// Supabase 접속 정보 (publishable 키는 공개돼도 되는 키. 권한은 RLS 정책이 지킴)
// 비워두면 샘플 데이터로 도는 데모 모드가 됩니다.
window.FG_CONFIG = {
  SUPABASE_URL: 'https://erlrviaqnnlfeehizlxc.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_LfUJRHztENtaEmt7YV_bzQ_iboVhvn3',
  APP_STORE_URL: '', // 앱 출시 후 App Store 주소(예: https://apps.apple.com/app/id1234567890). 비어 있으면 공유 링크는 웹에서 이어짐
  PROVIDERS: ['kakao', 'google'], // Supabase에서 켠 로그인만 남기기
  VAPID_PUBLIC_KEY: 'BA1pPJ0-hFg1kIB5JskH0DDhxUzAx5fpZjR-ANhxXMnxuoeUFQdwtj9GQOWdLmidhcZtE-Iyj6u7Jok1DMOI2P0', // 푸시 알림 공개키 (공개돼도 됨)
  // 광고: 공급자 순서는 AdMob(iOS 앱) → 하우스 광고
  //   feed: Candids 사진 사이 광고(first 장 뒤, 그다음 every 장마다) · interstitial: 몇 장마다 뜨는 전면 광고(지금 끔)
  //   admob.iosNative: 네이티브 광고 단위 ID(비어 있으면 출시용 앱은 하우스 광고만. 개발용 앱은 Google 시험 광고)
  ADS: { enabled: true, house: true, feed: { first: 3, every: 5 },
         interstitial: false, every: 8, minGapSec: 90, dailyCap: 12,
         admob: { iosInterstitial: 'ca-app-pub-5294097797182712/1457522986', iosNative: 'ca-app-pub-5294097797182712/8539157847' } }, // testing 을 안 적으면: 개발용 앱은 시험 광고, 출시용(npm run release)은 실제 광고
};
