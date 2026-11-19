// Supabase 접속 정보 (publishable 키는 공개돼도 되는 키. 권한은 RLS 정책이 지킴)
// 비워두면 샘플 데이터로 도는 데모 모드가 됩니다.
window.FG_CONFIG = {
  SUPABASE_URL: 'https://erlrviaqnnlfeehizlxc.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_LfUJRHztENtaEmt7YV_bzQ_iboVhvn3',
  PROVIDERS: ['kakao', 'google'], // Supabase에서 켠 로그인만 남기기
  VAPID_PUBLIC_KEY: 'BA1pPJ0-hFg1kIB5JskH0DDhxUzAx5fpZjR-ANhxXMnxuoeUFQdwtj9GQOWdLmidhcZtE-Iyj6u7Jok1DMOI2P0', // 푸시 알림 공개키 (공개돼도 됨)
  // 광고: 공급자 순서는 AdMob(iOS 앱) → 하우스 광고. admob 은 Google 시험용 ID(실제 광고 단위 ID 를 받으면 교체하고 testing: false)
  ADS: { enabled: true, every: 8, minGapSec: 90, dailyCap: 12, house: true,
         admob: { iosInterstitial: 'ca-app-pub-3940256099942544/4411468910', testing: true } },
};
