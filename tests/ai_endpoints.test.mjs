// Testy kontroly volajícího ve SKUTEČNÝCH souborech AI endpointů (functions/api/*.js) se zamockovaným Supabase a Gemini.
// Žádná síť, žádná placená volání. Hlavní pravidlo: když kontrola selže, poskytovatel AI se nezavolá ani jednou.
//   node tests/ai_endpoints.test.mjs
import assert from 'node:assert/strict';
import guard from '../src/ai_guard.js';
import * as advisor from '../functions/api/advisor.js';
import * as webai from '../functions/api/web-ai.js';
import * as marketing from '../functions/api/marketing.js';
import * as accountant from '../functions/api/accountant.js';
import * as chat from '../functions/api/chat.js';
import * as digest from '../functions/api/digest.js';
import * as subscribe from '../functions/api/subscribe.js';

const C1 = '11111111-1111-1111-1111-111111111111', C2 = '22222222-2222-2222-2222-222222222222', C3 = '33333333-3333-3333-3333-333333333333';
const U_OWNER = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', U_EMP = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', U_OUT = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', U_ADM = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4';
const TOKENS = { owner: U_OWNER, emp: U_EMP, out: U_OUT, adm: U_ADM };
const future = new Date(Date.now() + 20 * 864e5).toISOString(), past = new Date(Date.now() - 864e5).toISOString();
let members, subs, calls, reserveMode, helpCap, resend, GEMINI_TEXT = 'Odpověď asistenta.';
const WEB_JSON = JSON.stringify({ hero: { title: 'Autoservis Konina', subtitle: 'Rychle a férově', cta: 'Objednat' }, about: { title: 'O nás', text: 'Opravujeme auta.' }, services: [{ name: 'Výfuky', desc: 'Výměna a úpravy' }] });
function reset() {
  members = [{ c: C1, u: U_OWNER, r: 'owner' }, { c: C1, u: U_EMP, r: 'employee' }, { c: C2, u: U_ADM, r: 'admin' }, { c: C3, u: U_OWNER, r: 'owner' }];
  subs = { [C1]: { plan: 'pro', status: 'trial', trial_end: future }, [C2]: { plan: 'pro', status: 'trial', trial_end: future }, [C3]: { plan: 'start', status: 'active', trial_end: null } };
  calls = { gemini: 0, urls: [], headers: [], reserve: [], help: [], mail: [] };
  reserveMode = 'ok'; helpCap = true; resend = { status: 200, text: '{}' };
}
const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
globalThis.fetch = async (url, opts = {}) => {
  url = String(url); calls.urls.push(url); calls.headers.push(opts.headers || {});
  const tok = String((opts.headers || {}).authorization || '').replace(/^Bearer\s+/i, '');
  if (url.includes('generativelanguage.googleapis.com')) { calls.gemini++; return J({ candidates: [{ content: { parts: [{ text: GEMINI_TEXT }] } }], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 } }); }
  const uid = TOKENS[tok];
  if (url.endsWith('/auth/v1/user')) return uid ? J({ id: uid, email: tok + '@firma.example' }) : J({}, 401);
  if (url.includes('api.resend.com')) { calls.mail.push(JSON.parse(opts.body)); return new Response(resend.text, { status: resend.status }); }
  if (url.endsWith('/rest/v1/rpc/reserve_ai')) {              // serverový limit v DB: členství + tarif + počty (zde zjednodušeně)
    calls.reserve.push({ uid, cid: JSON.parse(opts.body).cid });
    if (reserveMode === 'down') throw new Error('síť');
    if (reserveMode === 'missing') return J({ code: 'PGRST202', message: 'Could not find the function public.reserve_ai' }, 404);
    if (reserveMode === 'limit') return J({ code: 'P0001', message: 'Denní limit AI platformy byl vyčerpán' }, 400);
    if (reserveMode === 'perminute') return J({ code: 'P0001', message: 'Zkuste AI znovu za minutu' }, 400);
    return new Response(null, { status: 204 });
  }
  if (url.endsWith('/rest/v1/rpc/reserve_help_chat')) { calls.help.push({ tok, body: JSON.parse(opts.body) }); return J(helpCap); }
  const q = new URL(url).searchParams;
  if (url.includes('/rest/v1/company_members')) {
    const c = (q.get('company_id') || '').replace('eq.', ''), u = (q.get('user_id') || '').replace('eq.', '');
    return J(members.filter((m) => (!c || m.c === c) && m.u === u && u === uid).map((m) => ({ company_id: m.c, role: m.r })));   // RLS: vidí jen své řádky
  }
  if (url.includes('/rest/v1/subscriptions')) {
    const c = (q.get('company_id') || '').replace('eq.', '');
    const visible = members.some((m) => m.c === c && m.u === uid);                                      // RLS: člen firmy
    return J(visible && subs[c] ? [subs[c]] : []);
  }
  if (calls.lenient && url.includes('/rest/v1/')) return J([]);   // ostatní čtení přehledu (digest): prázdná data
  throw new Error('neočekávané volání ' + url);
};
const env = { GEMINI_API_KEY: 'test-neplatny-klic' };
const req = (body, token) => new Request('https://x.test/api/x', { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify(body) });
const bodies = {
  advisor: (cid) => ({ cid, messages: [{ role: 'user', content: 'Co mám řešit?' }], summary: { zakazniku: 3 } }),
  webai: (cid) => ({ cid, name: 'Autoservis Konina', description: 'Autoservis a výměna výfuků v okolí Prahy, rychle a férově.' }),
  marketing: (cid) => ({ cid, kind: 'social', tone: 'friendly', topic: 'Zimní pneumatiky a přezutí', name: 'Konina' }),
  accountant: (cid) => ({ cid, mode: 'ask', messages: [{ role: 'user', content: 'Jaké mám výdaje?' }], summary: { vydaje: 10 } }),
};
const EP = { advisor, webai, marketing, accountant };
let n = 0; const t = async (name, fn) => { reset(); await fn(); n++; console.log('OK   ' + name); };
const call = (ep, body, tok) => { GEMINI_TEXT = ep === 'webai' ? WEB_JSON : 'Odpověď asistenta.'; return EP[ep].onRequest({ request: req(body, tok), env }); };

for (const ep of Object.keys(EP)) {
  await t(ep + ': bez přihlášení 401, Gemini se nevolá', async () => { const r = await call(ep, bodies[ep](C1), null); assert.equal(r.status, 401); assert.equal(calls.gemini, 0); });
  await t(ep + ': neplatný token 401', async () => { const r = await call(ep, bodies[ep](C1), 'cizi'); assert.equal(r.status, 401); assert.equal(calls.gemini, 0); });
  await t(ep + ': bez cid nebo s cizím řetězcem 400', async () => {
    for (const cid of [undefined, '', 'abc', C1 + 'x', "x' or '1'='1", 5, null]) { const r = await call(ep, bodies[ep](cid), 'owner'); assert.equal(r.status, 400, String(cid)); }
    assert.equal(calls.gemini, 0);
  });
  await t(ep + ': přechodné pravidlo pro staré stránky: bez cid projde jen správce právě jedné firmy', async () => {
    const noCid = (b) => { const { cid, ...rest } = b; return rest; };
    let r = await call(ep, noCid(bodies[ep](C1)), 'adm'); assert.equal(r.status, 200, await r.clone().text()); assert.equal(calls.gemini, 1);   // správce jediné firmy (C2)
    reset(); r = await call(ep, noCid(bodies[ep](C1)), 'owner'); assert.equal(r.status, 400); assert.equal(calls.gemini, 0);                      // majitel dvou firem: nejednoznačné
    r = await call(ep, noCid(bodies[ep](C1)), 'emp'); assert.equal(r.status, 403); assert.equal(calls.gemini, 0);                                  // jen zaměstnanec
    r = await call(ep, noCid(bodies[ep](C1)), 'out'); assert.equal(r.status, 403); assert.equal(calls.gemini, 0);                                  // bez členství
    subs[C2] = { plan: 'start', status: 'active', trial_end: null }; r = await call(ep, noCid(bodies[ep](C1)), 'adm'); assert.equal(r.status, 403); assert.equal((await r.json()).error, 'plan'); assert.equal(calls.gemini, 0);   // tarif se kontroluje i tady
  });
  await t(ep + ': zaměstnanec firmy 403 (role), Gemini se nevolá', async () => { const r = await call(ep, bodies[ep](C1), 'emp'); assert.equal(r.status, 403); assert.equal((await r.json()).error, 'forbidden'); assert.equal(calls.gemini, 0); });
  await t(ep + ': cizí uživatel a podvržené cid cizí firmy 403', async () => { const r = await call(ep, bodies[ep](C1), 'out'); assert.equal(r.status, 403); assert.equal(calls.gemini, 0); });
  await t(ep + ': majitel firmy A s cid firmy B (kde není členem) 403', async () => { const r = await call(ep, bodies[ep](C2), 'owner'); assert.equal(r.status, 403); assert.equal(calls.gemini, 0); });
  await t(ep + ': tarif START je odmítnut (403 plan), i když je majitel', async () => { const r = await call(ep, bodies[ep](C3), 'owner'); assert.equal(r.status, 403); assert.equal((await r.json()).error, 'plan'); assert.equal(calls.gemini, 0); });
  await t(ep + ': prošlá zkušební doba a expired/canceled = 403 plan', async () => {
    subs[C1] = { plan: 'pro', status: 'trial', trial_end: past }; assert.equal((await call(ep, bodies[ep](C1), 'owner')).status, 403);
    for (const st of ['expired', 'canceled']) { subs[C1] = { plan: 'pro', status: st, trial_end: future }; assert.equal((await call(ep, bodies[ep](C1), 'owner')).status, 403, st); }
    assert.equal(calls.gemini, 0);
  });
  await t(ep + ': majitel s platným tarifem projde a poskytovatel se zavolá právě jednou', async () => { const r = await call(ep, bodies[ep](C1), 'owner'); assert.equal(r.status, 200, await r.clone().text()); assert.equal(calls.gemini, 1); });
  await t(ep + ': správce pobočky (tarif pobočky) projde', async () => { const r = await call(ep, bodies[ep](C2), 'adm'); assert.equal(r.status, 200, await r.clone().text()); assert.equal(calls.gemini, 1); });
}
await t('tarif AI Účetní smí jen AI Účetní endpoint, AI CEO, web a marketing ne', async () => {
  subs[C1] = { plan: 'accountant', status: 'active', trial_end: null };
  assert.equal((await call('accountant', bodies.accountant(C1), 'owner')).status, 200);
  for (const ep of ['advisor', 'webai', 'marketing']) assert.equal((await call(ep, bodies[ep](C1), 'owner')).status, 403, ep);
});
await t('kontrola nepoužívá servisní klíč, jen token uživatele, a dotazy jsou vázané na cid a uživatele', async () => {
  await call('advisor', bodies.advisor(C1), 'owner');
  const sb = calls.urls.map((u, i) => [u, calls.headers[i]]).filter(([u]) => u.includes('supabase.co'));
  assert.ok(sb.length >= 3 && sb.every(([, h]) => h.authorization === 'Bearer owner'), 'všechna volání Supabase s tokenem uživatele');
  assert.ok(sb.some(([u]) => u.includes('company_members') && u.includes('company_id=eq.' + C1) && u.includes('user_id=eq.' + U_OWNER)), 'členství se ověřuje pro cid i uživatele');
  assert.ok(sb.some(([u]) => u.includes('subscriptions') && u.includes('company_id=eq.' + C1)), 'tarif se čte pro tutéž firmu (ne „první řádek“)');
  assert.ok(!sb.some(([u]) => /subscriptions\?select=plan,status,trial_end&limit=1$/.test(u)), 'žádný dotaz na tarif bez určení firmy');
});
await t('guardAi přímo: poškozená odpověď databáze = odepřeno, ne povoleno', async () => {
  const bad = async () => new Response('nejde json', { status: 200 });
  const r = await guard.guardAi({ fetchFn: bad, sbUrl: 'https://x', sbKey: 'k', token: 't', cid: C1, plans: ['pro'] });
  assert.equal(r.ok, false);
  const down = async () => { throw new Error('síť'); };
  assert.equal((await guard.guardAi({ fetchFn: down, sbUrl: 'https://x', sbKey: 'k', token: 't', cid: C1, plans: ['pro'] })).ok, false);
});

// ---------- serverový limit AI (reserve_ai v databázi) ----------
for (const ep of Object.keys(EP)) {
  await t(ep + ': před voláním AI se rezervuje v DB limitu pro správnou firmu a s tokenem uživatele', async () => {
    const r = await call(ep, bodies[ep](C1), 'owner'); assert.equal(r.status, 200);
    assert.deepEqual(calls.reserve, [{ uid: U_OWNER, cid: C1 }]);
    const iRes = calls.urls.findIndex((u) => u.endsWith('/rpc/reserve_ai')), iAi = calls.urls.findIndex((u) => u.includes('generativelanguage'));
    assert.ok(iRes >= 0 && iRes < iAi, 'rezervace musí předcházet volání AI');
    assert.equal(calls.headers[iRes].authorization, 'Bearer owner');
  });
  await t(ep + ': vyčerpaný limit (platforma, firma, minuta) = 429 a AI se nezavolá', async () => {
    for (const m of ['limit', 'perminute']) { reserveMode = m; const r = await call(ep, bodies[ep](C1), 'owner'); assert.equal(r.status, 429, m); assert.equal((await r.json()).error, 'limit'); }
    assert.equal(calls.gemini, 0);
  });
  await t(ep + ': nedostupná DB nebo chybějící funkce limitu = 503, AI se nezavolá (fail closed)', async () => {
    for (const m of ['down', 'missing']) { reserveMode = m; const r = await call(ep, bodies[ep](C1), 'owner'); assert.equal(r.status, 503, m); }
    assert.equal(calls.gemini, 0);
  });
  await t(ep + ': odmítnutý volající limit vůbec nečerpá', async () => {
    await call(ep, bodies[ep](C1), 'emp'); await call(ep, bodies[ep](C2), 'owner'); await call(ep, bodies[ep](C3), 'owner');
    assert.equal(calls.reserve.length, 0);
  });
}
await t('marketing: neplatné zadání nečerpá limit', async () => {
  const r = await call('marketing', { cid: C1, kind: 'social', topic: 'x' }, 'owner'); assert.equal(r.status, 400); assert.equal(calls.reserve.length, 0);
});
await t('AI Účetní v tarifu accountant: reserve_ai se nevolá (funkce ho nezná), platí měsíční limit dokladů', async () => {
  subs[C1] = { plan: 'accountant', status: 'active', trial_end: null };
  const r = await call('accountant', bodies.accountant(C1), 'owner'); assert.equal(r.status, 200); assert.equal(calls.reserve.length, 0); assert.equal(calls.gemini, 1);
});

// ---------- veřejný chat ----------
const chatReq = (ip = '203.0.113.7') => new Request('https://x.test/api/chat', { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip }, body: JSON.stringify({ messages: [{ role: 'user', content: 'Kolik stojí PRO?' }] }) });
await t('chat: bez servisního klíče (nelze hlídat limit) = 503 a AI se nezavolá', async () => {
  const r = await chat.onRequest({ request: chatReq('203.0.113.1'), env: { GEMINI_API_KEY: 'k' } }); assert.equal(r.status, 503); assert.equal(calls.gemini, 0);
});
await t('chat: vyčerpaný limit platformy = 429, AI se nezavolá', async () => {
  helpCap = false; const r = await chat.onRequest({ request: chatReq('203.0.113.2'), env: { GEMINI_API_KEY: 'k', SUPABASE_SERVICE_KEY: 'svc' } }); assert.equal(r.status, 429); assert.equal(calls.gemini, 0);
});
await t('chat: s limitem projde; do DB jde jen otisk návštěvníka, ne IP', async () => {
  const r = await chat.onRequest({ request: chatReq('203.0.113.3'), env: { GEMINI_API_KEY: 'k', SUPABASE_SERVICE_KEY: 'svc' } }); assert.equal(r.status, 200); assert.equal(calls.gemini, 1);
  assert.equal(calls.help.length, 1); assert.match(calls.help[0].body.p_actor, /^[0-9a-f]{64}$/); assert.ok(!JSON.stringify(calls.help[0].body).includes('203.0.113.3'));
});

// ---------- přehled e-mailem (digest) ----------
const digReq = (body, tok) => new Request('https://x.test/api/digest', { method: 'POST', headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) }, body: JSON.stringify(body) });
await t('digest: přehled firmy jde jen na e-mail přihlášeného, ne na adresu z požadavku', async () => {
  calls.lenient = true;
  const r = await digest.onRequest({ request: digReq({ cid: C1, email: 'utocnik@example.com' }, 'owner'), env: { RESEND_API_KEY: 'r' } });
  assert.equal(r.status, 200); assert.equal(calls.mail.length, 1); assert.deepEqual(calls.mail[0].to, ['owner@firma.example']);
  assert.ok(!JSON.stringify(calls.mail).includes('utocnik@example.com'));
});
await t('digest: cizí firma 403, nic se neodešle', async () => {
  calls.lenient = true;
  const r = await digest.onRequest({ request: digReq({ cid: C2 }, 'owner'), env: { RESEND_API_KEY: 'r' } }); assert.equal(r.status, 403); assert.equal(calls.mail.length, 0);
});
await t('digest: AI shrnutí jen po rezervaci limitu; vyčerpaný limit = přehled bez AI', async () => {
  calls.lenient = true; reserveMode = 'limit';
  const r = await digest.onRequest({ request: digReq({ cid: C1 }, 'owner'), env: { RESEND_API_KEY: 'r', GEMINI_API_KEY: 'k' } });
  assert.equal(r.status, 200); assert.equal(calls.gemini, 0); assert.equal(calls.reserve.length, 1); assert.equal(calls.mail.length, 1);
});
await t('digest: chyba poskytovatele e-mailu se klientovi nevrací', async () => {
  calls.lenient = true; resend = { status: 422, text: 'interní detail účtu xyz@provozovatel.cz' };
  const r = await digest.onRequest({ request: digReq({ cid: C1 }, 'owner'), env: { RESEND_API_KEY: 'r' } }); const b = await r.text();
  assert.ok(!b.includes('provozovatel.cz') && b.includes('"mail":"failed"'), b);
});

// ---------- veřejný formulář ----------
await t('subscribe: odpověď návštěvníkovi neprozrazuje adresu provozovatele ani text chyby', async () => {
  calls.lenient = true; resend = { status: 403, text: 'You can only send testing emails to your own email address (majitel@provozovatel.cz)' };
  const r = await subscribe.onRequest({ request: new Request('https://x.test/api/subscribe', { method: 'POST', headers: { 'content-type': 'application/json', 'cf-connecting-ip': '198.51.100.9' }, body: JSON.stringify({ email: 'a@b.cz', name: 'Test', consent: true }) }), env: { RESEND_API_KEY: 'r', NOTIFY_EMAIL: 'tajny@provozovatel.cz' }, });
  const b = await r.text(); assert.ok(!/provozovatel|tajny|majitel/.test(b), b);
});
console.log('\nVŠECH ' + n + ' TESTŮ PROŠLO (žádné skutečné volání AI)');
