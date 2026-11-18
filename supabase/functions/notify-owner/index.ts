// candid. 푸시 알림 — DB 웹훅으로 호출되어 피드 주인에게 웹 푸시 발송
//  - posts INSERT: 친구가 사진·투표·질문을 보냄
//  - post_stickers INSERT: 친구가 내 사진을 스티커로 꾸밈 (한 번 저장에 여러 개면 알림 1번)
//  - posts INSERT (그룹): 그룹 새 사진 → 알림 켠 팔로워에게. 10분 안에 또 올라오면 묶어서 다음에 'N장'
//  - group_members INSERT: 그룹 참여 신청 → 방장에게 (웹훅 notify-group-join 필요)
//  - 호출될 때마다: 지워진 그룹 사진·영상 파일 정리(storage_trash)
// 필요한 Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, WEBHOOK_SECRET, SITE_URL
// iPhone 앱 푸시(선택, 32 SQL): APNS_KEY_P8(키 파일 내용), APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC(앱 번들 ID). 없으면 웹 푸시만
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SITE = env('SITE_URL') || 'https://candid-feed.com/';
let sb: ReturnType<typeof createClient> | null = null;

// 다국어: 받는 사람 프로필의 lang(ko/en/ja…)으로 보냄. 새 언어는 아래 표에 추가 (앱은 i18n/<코드>.js)
const MSG: Record<string, Record<string, string>> = {
  ko: { postTitle: '누군가 너에게 사진을 보냈어 👀', postBody: "{name}님이 '{mission}'을(를) 보냈어요. 대기 피드에서 확인해 보세요.",
        stkTitle: '누가 내 사진을 꾸몄어요 ✨', stkBody: '{name}님이 내 사진에 스티커를 붙였어요. 확인해 보세요.', photo: '사진', friend: '친구', anon: '익명의 친구',
        gTitle: '{group} 📸', gOne: '{name}님이 새 사진을 올렸어요', gMany: '새 사진 {n}장이 올라왔어요',
        joinTitle: '참여 신청이 왔어요 🙋', joinBody: "{name}님이 '{group}' 참여를 신청했어요. 승인해 주세요.",
        invTitle: '그룹 초대가 왔어요 💌', invBody: "{name}님이 '{group}'에 초대했어요. 수락하면 같이 사진을 모을 수 있어요." },
  en: { postTitle: 'Someone sent you a photo 👀', postBody: '{name} sent you “{mission}”. Check it in Pending.',
        stkTitle: 'Someone decorated your photo ✨', stkBody: '{name} added stickers to your photo. Take a look!', photo: 'a photo', friend: 'A friend', anon: 'Anonymous friend',
        gTitle: '{group} 📸', gOne: '{name} posted a new photo', gMany: '{n} new photos were posted',
        joinTitle: 'New join request 🙋', joinBody: '{name} asked to join “{group}”. Review the request.',
        invTitle: 'You’re invited 💌', invBody: '{name} invited you to “{group}”. Accept to share photos together.' },
  ja: { postTitle: '誰かが写真を送ってくれたよ 👀', postBody: '{name}さんが「{mission}」を送りました。承認待ちで確認してね。',
        stkTitle: '誰かが写真をデコったよ ✨', stkBody: '{name}さんがあなたの写真にステッカーを貼りました。見てみて！', photo: '写真', friend: '友達', anon: '匿名の友達',
        gTitle: '{group} 📸', gOne: '{name}さんが新しい写真を投稿しました', gMany: '新しい写真が{n}枚投稿されました',
        joinTitle: '参加リクエストが届きました 🙋', joinBody: '{name}さんが「{group}」への参加をリクエストしました。承認してね。',
        invTitle: 'グループに招待されました 💌', invBody: '{name}さんが「{group}」に招待しました。承認すると一緒に写真を集められます。' },
};
// DB 에 한국어로 저장되는 미션 이름
const MISSION: Record<string, Record<string, string>> = {
  en: { '제일 웃긴 사진': 'Funniest photo', '제일 잘 나온 사진': 'Best photo', '몰래 찍은 사진': 'Candid shot', '우리만 아는 흑역사': 'Our secret cringe', '나를 한 단어로': 'Me in one word', '자유': 'Anything', '투표': 'a poll', '질문': 'a question' },
  ja: { '제일 웃긴 사진': '一番おもしろい写真', '제일 잘 나온 사진': '一番よく撮れた写真', '몰래 찍은 사진': 'こっそり撮った写真', '우리만 아는 흑역사': '二人だけの黒歴史', '나를 한 단어로': '私をひとことで', '자유': '自由', '투표': '投票', '질문': '質問' },
};
const fill = (s: string, v: Record<string, string>) => s.replace(/\{(\w+)\}/g, (m, k) => v[k] ?? m);
async function langOf(uid: string) {
  const { data } = await sb!.from('profiles').select('lang').eq('id', uid).maybeSingle();
  const l = (data as { lang?: string } | null)?.lang;
  return l && MSG[l] ? l : 'ko'; // lang 칸이 없거나(17 SQL 전) 모르는 언어면 한국어
}

// 시작 시 바로 죽지 않도록, 요청이 올 때 설정을 점검하고 빠진 항목 이름만 알려줌 (값은 노출하지 않음)
function setup(): string | null {
  const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'VAPID_PUBLIC_KEY', 'VAPID_PRIVATE_KEY', 'WEBHOOK_SECRET'];
  const missing = required.filter((k) => !env(k));
  if (missing.length) return `missing secrets: ${missing.join(', ')}`;
  try {
    webpush.setVapidDetails('mailto:noreply@candid.app', env('VAPID_PUBLIC_KEY'), env('VAPID_PRIVATE_KEY'));
  } catch (e) {
    return `invalid VAPID keys: ${(e as Error).message}`;
  }
  sb ??= createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));
  return null;
}

// 지워진 그룹 게시물의 파일 정리 (실패해도 알림에는 영향 없음)
async function purgeTrash() {
  const { data } = await sb!.from('storage_trash').select('path').limit(200);
  const paths = (data ?? []).map((r: { path: string }) => r.path);
  if (!paths.length) return;
  const { error } = await sb!.storage.from('photos').remove(paths);
  if (!error) await sb!.from('storage_trash').delete().in('path', paths);
}

// ---------- iPhone 앱 푸시(APNs) ----------
const b64url = (b: Uint8Array | string) => btoa(typeof b === 'string' ? b : String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
let apnsJwt = { tok: '', at: 0 };
async function apnsAuth() {
  if (apnsJwt.tok && Date.now() - apnsJwt.at < 45 * 60_000) return apnsJwt.tok; // Apple 규칙: 20분~1시간마다 새로
  const pem = env('APNS_KEY_P8').replace(/\\n/g, '\n');
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const unsigned = `${b64url(JSON.stringify({ alg: 'ES256', kid: env('APNS_KEY_ID') }))}.${b64url(JSON.stringify({ iss: env('APNS_TEAM_ID'), iat: Math.floor(Date.now() / 1000) }))}`;
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned)));
  apnsJwt = { tok: `${unsigned}.${b64url(sig)}`, at: Date.now() };
  return apnsJwt.tok;
}
// 한 기기에 보내기: 출시 서버 먼저, 개발용 토큰이면(BadDeviceToken) 개발 서버로. 만료된 토큰은 지움
async function apnsSend(row: { token: string; sandbox: boolean | null }, p: { title?: string; body?: string; url?: string; tag?: string }) {
  const body = JSON.stringify({ aps: { alert: { title: p.title ?? '', body: p.body ?? '' }, sound: 'default', 'thread-id': p.tag ?? 'candid' }, url: p.url ?? '' });
  const hosts = row.sandbox === true ? [true] : row.sandbox === false ? [false] : [false, true];
  for (const sandbox of hosts) {
    const r = await fetch(`https://${sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'}/3/device/${row.token}`, {
      method: 'POST', body,
      headers: { authorization: `bearer ${await apnsAuth()}`, 'apns-topic': env('APNS_TOPIC') || 'com.candidfeed.app', 'apns-push-type': 'alert', 'apns-priority': '10' },
    });
    if (r.ok) { if (row.sandbox !== sandbox) await sb!.from('device_tokens').update({ sandbox }).eq('token', row.token); return true; }
    const reason = ((await r.json().catch(() => ({}))) as { reason?: string }).reason ?? '';
    if (r.status === 410 || reason === 'Unregistered') { await sb!.from('device_tokens').delete().eq('token', row.token); return false; }
    if ((reason === 'BadDeviceToken' || reason === 'BadEnvironmentKeyInToken') && hosts.length > 1 && !sandbox) continue; // 개발용 토큰(또는 개발 전용 키) → 개발 서버로
    if (reason === 'BadDeviceToken') await sb!.from('device_tokens').delete().eq('token', row.token);
    else console.error('apns failed', r.status, reason);
    return false;
  }
  return false;
}
async function sendApns(uid: string, payload: string) {
  if (!env('APNS_KEY_P8') || !env('APNS_KEY_ID') || !env('APNS_TEAM_ID')) return 0;
  const { data, error } = await sb!.from('device_tokens').select('token, sandbox').eq('user_id', uid);
  if (error) return 0; // 32 SQL 전이면 테이블이 없음
  let p = {}; try { p = JSON.parse(payload); } catch { /* 그대로 */ }
  const ok = await Promise.all((data ?? []).map((row) => apnsSend(row as { token: string; sandbox: boolean | null }, p).catch((e) => { console.error('apns error', e); return false; })));
  return ok.filter(Boolean).length;
}

async function sendTo(uid: string, payload: string) {
  const apns = sendApns(uid, payload);
  const { data: subs, error } = await sb!.from('push_subscriptions').select('*').eq('user_id', uid);
  if (error) { console.error(error); return await apns; }
  let sent = 0;
  await Promise.all((subs ?? []).map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await sb!.from('push_subscriptions').delete().eq('endpoint', s.endpoint); // 만료된 구독 정리
      else console.error('push failed', code, e);
    }
  }));
  return sent + await apns;
}

Deno.serve(async (req) => {
  const problem = setup();
  if (problem) { console.error(problem); return new Response(problem, { status: 500 }); }
  // 웹훅에서 온 요청인지 확인 (공유 비밀값 헤더)
  if (!env('WEBHOOK_SECRET') || req.headers.get('x-webhook-secret') !== env('WEBHOOK_SECRET')) {
    return new Response('unauthorized', { status: 401 });
  }
  await purgeTrash().catch((e) => console.error('purge failed', e)); // 18 SQL 전이면 테이블이 없어 조용히 실패
  const body = await req.json().catch(() => null);
  const rec = body?.record;
  if (body?.type !== 'INSERT' || !rec) return new Response('ignored');
  const id = rec.id;
  const fresh = (iso: string) => Date.now() - new Date(iso).getTime() <= 5 * 60_000;

  // 그룹 초대(친구 골라서) → 초대받은 사람 (28 SQL, 웹훅: group_invites Insert)
  if (body.table === 'group_invites') {
    const { data: v } = await sb!.from('group_invites').select('group_id, user_id, invited_by, created_at')
      .eq('group_id', rec.group_id).eq('user_id', rec.user_id).maybeSingle();
    if (!v || !fresh(v.created_at)) return new Response('skip');
    const [{ data: g }, { data: who }] = await Promise.all([
      sb!.from('groups').select('name').eq('id', v.group_id).maybeSingle(),
      sb!.from('profiles').select('name').eq('id', v.invited_by).maybeSingle()]);
    if (!g) return new Response('skip');
    const L = MSG[await langOf(v.user_id)];
    const sent = await sendTo(v.user_id, JSON.stringify({
      title: L.invTitle, body: fill(L.invBody, { name: who?.name ?? L.friend, group: g.name }), url: `${SITE}?groups=1`,
    }));
    return Response.json({ sent });
  }
  // 그룹 참여 신청 → 방장
  if (body.table === 'group_members') {
    const { data: m } = await sb!.from('group_members').select('group_id, user_id, status, created_at')
      .eq('group_id', rec.group_id).eq('user_id', rec.user_id).maybeSingle();
    if (!m || m.status !== 'pending' || !fresh(m.created_at)) return new Response('skip');
    const { data: g } = await sb!.from('groups').select('id, handle, name, owner_id').eq('id', m.group_id).maybeSingle();
    if (!g) return new Response('skip');
    const { data: who } = await sb!.from('profiles').select('name').eq('id', m.user_id).maybeSingle();
    const L = MSG[await langOf(g.owner_id)];
    const sent = await sendTo(g.owner_id, JSON.stringify({
      title: L.joinTitle, body: fill(L.joinBody, { name: who?.name ?? L.friend, group: g.name }), url: `${SITE}?g=${g.handle}&manage=1`,
    }));
    return Response.json({ sent });
  }
  if (!id) return new Response('ignored');

  let ownerId = '', payload = '';
  if (body.table === 'posts') {
    // 페이로드를 믿지 않고 DB에서 다시 확인: 존재하고, 방금 들어온 것만
    const { data: post } = await sb!.from('posts').select('*').eq('id', id).maybeSingle();
    if (!post || !fresh(post.created_at)) return new Response('skip');
    if (post.group_id) {
      // 그룹 새 사진: 10분에 한 번만 알림(그 사이 올라온 건 다음 알림에 'N장'으로)
      const { data: g } = await sb!.from('groups').select('id, handle, name, last_notified_at').eq('id', post.group_id).maybeSingle();
      if (!g) return new Response('skip');
      const cutoff = new Date(Date.now() - 10 * 60_000).toISOString();
      const { data: claimed } = await sb!.from('groups').update({ last_notified_at: new Date().toISOString() })
        .eq('id', g.id).or(`last_notified_at.is.null,last_notified_at.lt.${cutoff}`).select('id');
      if (!claimed?.length) return new Response('skip (batched)');
      let n = 1;
      if (g.last_notified_at) {
        const { count } = await sb!.from('posts').select('id', { count: 'exact', head: true }).eq('group_id', g.id).gt('created_at', g.last_notified_at);
        n = Math.max(1, count ?? 1);
      }
      const { data: fol } = await sb!.from('group_follows').select('user_id').eq('group_id', g.id).eq('notify', true);
      let sent = 0;
      for (const f of (fol ?? []).filter((f: { user_id: string }) => f.user_id !== post.author_id)) {
        const L = MSG[await langOf(f.user_id)];
        sent += await sendTo(f.user_id, JSON.stringify({
          title: fill(L.gTitle, { group: g.name }),
          body: n > 1 ? fill(L.gMany, { n: String(n) }) : fill(L.gOne, { name: post.author_name || L.friend }),
          url: `${SITE}?g=${g.handle}`,
        }));
      }
      return Response.json({ sent });
    }
    if (post.status !== 'pending') return new Response('skip');
    ownerId = post.owner_id;
    const L = MSG[await langOf(post.owner_id)], lang = Object.keys(MSG).find(k => MSG[k] === L)!;
    const name = post.author_name === '익명의 친구' ? L.anon : post.author_name;
    const mission = post.mission ? (MISSION[lang]?.[post.mission] ?? post.mission) : L.photo;
    payload = JSON.stringify({
      title: L.postTitle,
      body: fill(L.postBody, { name, mission }),
      url: `${SITE}?u=${post.owner_id}&tab=inbox&p=${post.id}`, // 그 사진을 바로 열기
    });
  } else if (body.table === 'post_stickers') {
    const { data: st } = await sb!.from('post_stickers').select('id, post_id, user_id, created_at').eq('id', id).maybeSingle();
    if (!st || !fresh(st.created_at)) return new Response('skip');
    const { data: post } = await sb!.from('posts').select('*').eq('id', st.post_id).maybeSingle();
    // 받는 사람: 개인 피드는 주인, 그룹은 사진을 올린 사람
    const target = post?.group_id ? post.author_id : post?.owner_id;
    if (!post || post.status !== 'approved' || !target || target === st.user_id) return new Response('skip'); // 내가 내 사진 꾸민 건 알림 없음
    // 같은 사람이 같은 게시물에 1분 안에 붙인 스티커 중 가장 앞의 것 하나에만 알림(한 번 저장 = 알림 1번)
    const { data: batch } = await sb!.from('post_stickers').select('id')
      .eq('post_id', st.post_id).eq('user_id', st.user_id)
      .gte('created_at', new Date(new Date(st.created_at).getTime() - 60_000).toISOString())
      .order('id', { ascending: true }).limit(1);
    if (batch?.[0] && batch[0].id !== st.id) return new Response('skip (batched)');
    const { data: who } = await sb!.from('profiles').select('name').eq('id', st.user_id).maybeSingle();
    ownerId = target;
    let url = `${SITE}?u=${target}&p=${post.id}`; // 꾸민 그 사진을 바로 열기
    if (post.group_id) {
      const { data: g } = await sb!.from('groups').select('handle').eq('id', post.group_id).maybeSingle();
      url = `${SITE}?g=${g?.handle ?? ''}&p=${post.id}`;
    }
    const L = MSG[await langOf(target)];
    payload = JSON.stringify({ title: L.stkTitle, body: fill(L.stkBody, { name: who?.name ?? L.friend }), url });
  } else {
    return new Response('ignored');
  }

  return Response.json({ sent: await sendTo(ownerId, payload) });
});
