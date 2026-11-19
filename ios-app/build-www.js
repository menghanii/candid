// 웹앱 파일을 앱에 담을 www 폴더로 복사(앱은 이 파일로 켜지고, 데이터는 Supabase·candid-feed.com 에서 받음)
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..'), out = path.join(__dirname, 'www');
fs.rmSync(out, { recursive: true, force: true }); fs.mkdirSync(out, { recursive: true });
const copy = rel => fs.cpSync(path.join(root, rel), path.join(out, rel), { recursive: true });
['index.html', 'config.js', 'demo.js', 'manifest.json', 'favicon.ico', 'apple-touch-icon.png', 'brand', 'i18n', 'terms.html', 'privacy.html', 'legal.css'].forEach(copy);
// 개발용(node build-www.js --demo): 서버 접속 정보를 비워 데모 모드(샘플 데이터, 서버에 아무것도 안 씀) + 자동 로그인
if (process.argv.includes('--demo')) {
  fs.writeFileSync(path.join(out, 'config.js'), "window.FG_CONFIG = { SUPABASE_URL: '', SUPABASE_ANON_KEY: '', PROVIDERS: ['kakao', 'google'], DEMO_AUTO_LOGIN: true };\n");
  console.log('개발용 데모 모드로 준비');
}
// 출시용(node build-www.js --release): 개발 점검 기록 끄기
if (process.argv.includes('--release')) {
  const f = path.join(out, 'config.js');
  fs.writeFileSync(f, fs.readFileSync(f, 'utf8') + "\nwindow.FG_CONFIG.RELEASE = true;\n");
  console.log('출시용으로 준비(점검 기록 끔)');
}
console.log('www 준비 완료:', fs.readdirSync(out).join(', '));
