// 웹앱 파일을 앱에 담을 www 폴더로 복사(앱은 이 파일로 켜지고, 데이터는 Supabase·candid-feed.com 에서 받음)
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..'), out = path.join(__dirname, 'www');
fs.rmSync(out, { recursive: true, force: true }); fs.mkdirSync(out, { recursive: true });
const copy = rel => fs.cpSync(path.join(root, rel), path.join(out, rel), { recursive: true });
['index.html', 'config.js', 'manifest.json', 'favicon.ico', 'apple-touch-icon.png', 'brand', 'i18n', 'terms.html', 'privacy.html', 'legal.css'].forEach(copy);
console.log('www 준비 완료:', fs.readdirSync(out).join(', '));
