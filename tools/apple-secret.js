// Supabase 의 Apple 로그인 "Secret Key" 만들기(최대 6개월 유효 → 만료 전 다시 실행)
// 사용: node tools/apple-secret.js | pbcopy   (키 파일은 secrets/AuthKey_<KeyID>.p8, 화면에 출력하지 말 것)
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const TEAM = '92KNXMVFG4', KEY_ID = 'US4K565QXD', CLIENT = 'com.candidfeed.web';
const pem = fs.readFileSync(path.join(__dirname, '..', 'secrets', `AuthKey_${KEY_ID}.p8`), 'utf8');
const b64 = o => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
const now = Math.floor(Date.now() / 1000), exp = now + 180 * 24 * 3600;
const head = b64({ alg: 'ES256', kid: KEY_ID }), body = b64({ iss: TEAM, iat: now, exp, aud: 'https://appleid.apple.com', sub: CLIENT });
const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: pem, dsaEncoding: 'ieee-p1363' }).toString('base64url');
process.stdout.write(`${head}.${body}.${sig}`);
process.stderr.write(`만료: ${new Date(exp * 1000).toISOString().slice(0, 10)}\n`);
