// candid. 번역 점검: node tools/i18n-check.js
// index.html 의 t('…') 문구 중 각 언어 사전(i18n/<코드>.js)에 없는 것, 사전에만 있고 안 쓰는 것을 보여줌
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8').split('\n').filter(l => !l.trim().startsWith('//')).join('\n');
const keys = new Set();
// t('...') / t("...") — 첫 인자가 문자열 리터럴인 경우만 (t(변수) 는 사전에 직접 넣어야 함)
for (const m of html.matchAll(/\bt\(\s*(['"])((?:\\.|(?!\1).)*)\1/g)) keys.add(m[2].replace(/\\n/g, '\n').replace(/\\(['"\\])/g, '$1'));
const langs = fs.readdirSync(path.join(root, 'i18n')).filter(f => f.endsWith('.js'));
let bad = 0;
for (const f of langs) {
  const ctx = { window: {} }; vm.runInNewContext(fs.readFileSync(path.join(root, 'i18n', f), 'utf8'), ctx);
  const lang = f.replace('.js', ''), dict = ctx.window.CANDID_I18N[lang] || {};
  const missing = [...keys].filter(k => !(k in dict)), unused = Object.keys(dict).filter(k => !keys.has(k));
  // '안 쓰는 번역'에는 t(변수)·t(조건 ? 'a' : 'b') 로 쓰는 문구도 섞여 있으니 참고만
  console.log(`\n[${lang}] 문구 ${keys.size}개 중 번역 없음 ${missing.length}개, (참고) 직접 안 보이는 번역 ${unused.length}개`);
  missing.forEach(k => console.log('  - 없음:', k));
  bad += missing.length;
}
process.exitCode = bad ? 1 : 0;
