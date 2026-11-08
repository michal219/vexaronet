// Kompatibilita s novými klíči Supabase (sb_publishable_ / sb_secret_): klíče nejsou JWT a smí se posílat jen v hlavičce `apikey`.
// `Authorization: Bearer` smí nést jen JWT přihlášeného uživatele (podle dokumentace Supabase „Migrating to publishable and secret API keys“,
// oddíl Known limitations). Test spustí skutečné Cloudflare funkce s podvrženým fetch a zkontroluje KAŽDÝ požadavek na Supabase.
//   node tests/key_headers.test.mjs
import assert from 'node:assert/strict';

const SB = 'https://micymdbqgzeckiqyvvkn.supabase.co', SK = 'sb_secret_TESTONLY0000000000000000', USER = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.sig';
const seen = []; let n = 0;
globalThis.fetch = async function (url, o = {}) {
  // jako Cloudflare Workers: fetch volaný jako metoda cizího objektu (o.fetchFn(...)) selže
  if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation');
  url = String(url); const h = Object.fromEntries(Object.entries(o.headers || {}).map(([k, v]) => [k.toLowerCase(), String(v)]));
  const J = (x, s = 200) => new Response(JSON.stringify(x), { status: s, headers: { 'content-type': 'application/json' } });
  if (url.startsWith(SB)) {
    seen.push({ url: url.slice(SB.length), h });
    if (url.includes('/auth/v1/user')) return J({ id: '00000000-0000-0000-0000-0000000000a1' });
    if (url.includes('/rest/v1/company_members')) return J([{ role: 'owner', company_id: '00000000-0000-0000-0000-0000000000c1' }]);
    if (url.includes('/rest/v1/subscriptions')) return J([{ plan: 'pro', status: 'active' }]);
    if (url.includes('reserve_help_chat')) return J({ ok: true });
    if (url.includes('dsa_submit')) return J({ id: 'n1', ref: 'DSA-1' });
    if (url.includes('marketing_unsubscribe')) return J({ ok: true });
    if (url.includes('profile_get')) return J({ active: null });
    return J({});
  }
  if (url.startsWith('https://generativelanguage.googleapis.com/')) return J({ candidates: [{ content: { parts: [{ text: 'ok' }] } }], usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 } });
  if (url.startsWith('https://api.resend.com/')) return J({ id: 'm1' });
  return J({});
};
const env = { SUPABASE_SERVICE_KEY: SK, GEMINI_API_KEY: 'g', RESEND_API_KEY: 'r' };
const post = (path, body, hdr = {}) => new Request('https://vexaronet.com' + path, { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': '203.0.113.' + (++n), ...hdr }, body: JSON.stringify(body) });
const run = async (mod, req) => (await import('../functions/api/' + mod + '.js')).onRequest({ request: req, env });

await run('chat', post('/api/chat', { messages: [{ role: 'user', content: 'Ahoj' }] }));
await run('dsa-notice', post('/api/dsa-notice', { urls: ['https://vexaronet.com/?w=abc'], category: 'jine', explanation: 'Zkušební oznámení pro test hlaviček klíčů.', name: 'Test', email: 't@example.invalid', good_faith: true }));
await run('unsubscribe', post('/api/unsubscribe', { token: 'a'.repeat(64) }));
await run('ai-marketing', post('/api/ai-marketing', { action: 'strategy', cid: '00000000-0000-0000-0000-0000000000c1', key: 'kontrola-123' }, { authorization: 'Bearer ' + USER }));
await run('advisor', post('/api/advisor', { cid: '00000000-0000-0000-0000-0000000000c1', messages: [{ role: 'user', content: 'Ahoj' }] }, { authorization: 'Bearer ' + USER }));
await run('subscribe', post('/api/subscribe', { email: 'a@example.invalid', name: 'Test', consent: true, age_ok: true }));
await run('book', post('/api/book', { slug: 'abc', service: '00000000-0000-0000-0000-000000000001', start: '2026-12-01T10:00:00Z', name: 'Test', email: 'a@example.invalid' }));

console.log('požadavky: ' + seen.map((r) => r.url.split('?')[0]).join(', '));
assert.ok(seen.length >= 5, 'funkce mají volat Supabase (zachyceno ' + seen.length + ')');
for (const r of seen) {
  const a = r.h.authorization;
  assert.ok(!a || (a.startsWith('Bearer ') && a.slice(7).split('.').length === 3 && !a.includes('sb_')), `klíč v Authorization: ${r.url} -> ${a}`);
  assert.ok(r.h.apikey, 'chybí apikey: ' + r.url);
}
const svc = seen.filter((r) => r.h.apikey === SK);
assert.ok(svc.length >= 2 && svc.every((r) => !r.h.authorization), 'tajný klíč jen v apikey, bez Authorization');
assert.ok(seen.some((r) => r.h.authorization === 'Bearer ' + USER), 'token přihlášeného uživatele se dál posílá v Authorization');
assert.ok(seen.some((r) => r.url.includes('reserve_help_chat')) && seen.some((r) => r.url.includes('reserve_ai')), 'limit chatu i limit AI se skutečně zavolají (fetch jako funkce, ne metoda)');
// klíč vložený v Cloudflare se zalomením řádku / neviditelným znakem se před použitím očistí
const total = seen.length; seen.length = 0; env.SUPABASE_SERVICE_KEY = '\n ' + SK + '\u200b\r\n';
await run('chat', post('/api/chat', { messages: [{ role: 'user', content: 'Ahoj' }] }));
assert.equal(seen[0]?.h.apikey, SK, 'očištěný klíč v apikey');
console.log('OK   klíč se zalomením řádku a neviditelným znakem se před použitím očistí');
console.log(`OK   ${total} požadavků na Supabase: klíče jen v apikey, Authorization nese jen JWT uživatele (tajný klíč ve ${svc.length} požadavcích)`);
console.log('VŠECHNY KONTROLY PROŠLY');
