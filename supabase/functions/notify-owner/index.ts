// candid. 푸시 알림 — posts 에 새 행이 들어오면(DB 웹훅) 주인장에게 웹 푸시 발송
// 필요한 Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, WEBHOOK_SECRET, SITE_URL
import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const env = (k: string) => (Deno.env.get(k) ?? '').trim();
const SITE = env('SITE_URL') || 'https://menghanii.github.io/candid/';
let sb: ReturnType<typeof createClient> | null = null;

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

Deno.serve(async (req) => {
  const problem = setup();
  if (problem) { console.error(problem); return new Response(problem, { status: 500 }); }
  // 웹훅에서 온 요청인지 확인 (공유 비밀값 헤더)
  if (!env('WEBHOOK_SECRET') || req.headers.get('x-webhook-secret') !== env('WEBHOOK_SECRET')) {
    return new Response('unauthorized', { status: 401 });
  }
  const body = await req.json().catch(() => null);
  const id = body?.record?.id;
  if (body?.type !== 'INSERT' || body?.table !== 'posts' || !id) return new Response('ignored');

  // 페이로드를 믿지 않고 DB에서 다시 확인: 존재하고, 대기 중이고, 방금 들어온 것만
  const { data: post } = await sb!.from('posts')
    .select('id, owner_id, author_name, mission, status, created_at').eq('id', id).maybeSingle();
  if (!post || post.status !== 'pending' || Date.now() - new Date(post.created_at).getTime() > 5 * 60_000) {
    return new Response('skip');
  }

  const { data: subs, error } = await sb!.from('push_subscriptions').select('*').eq('user_id', post.owner_id);
  if (error) { console.error(error); return new Response('db error', { status: 500 }); }

  const payload = JSON.stringify({
    title: '누군가 너에게 사진을 보냈어 👀',
    body: `${post.author_name}님이 '${post.mission ?? '사진'}'을(를) 보냈어요. 승인함에서 확인해 보세요.`,
    url: `${SITE}?u=${post.owner_id}&tab=inbox`,
  });

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
  return Response.json({ sent });
});
