// End-to-end: SKUTEČNÉ Cloudflare endpointy (functions/api/*) proti SKUTEČNÉ lokální PostgreSQL s migracemi 20261110100000 a 20261110110000.
// Volání PostgREST (/rest/v1/rpc/*) se převádějí na SQL pod rolí anon / authenticated / service_role (jako v Supabase).
// Simulovaný je jen poskytovatel e-mailu (Resend): zachytáváme, co by se odeslalo.
//   PSQL="runuser -u postgres -- psql" node tests/legal_e2e.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as unsub from '../functions/api/unsubscribe.js';
import * as newsletter from '../functions/api/newsletter.js';
import * as dsaNotice from '../functions/api/dsa-notice.js';
import * as dsaAdmin from '../functions/api/dsa-admin.js';
import L from '../src/legal_server.js';

const PSQL = (process.env.PSQL || 'psql').split(' '), DB = 'vx_legal_e2e', SVC = 'test-service-key';
const sh = (args, input) => execFileSync(PSQL[0], [...PSQL.slice(1), ...args], { input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
const sql = (q) => sh(['-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-c', q]).trim();
const lit = (v) => (v === null || v === undefined ? 'NULL' : `'${String(typeof v === 'object' ? JSON.stringify(v) : v).replace(/'/g, "''")}'`);
// databáze
sh(['-X', '-q', '-d', 'postgres', '-c', `drop database if exists ${DB}`, '-c', `create database ${DB}`]);
for (const f of ['db/test/00_local_supabase_shim.sql', 'db/test/01_base_stub.sql', 'db/test/04_legal_prestate.sql', 'db/migrations/20261110100000_marketing_odhlaseni.sql', 'db/migrations/20261110110000_dsa_oznameni.sql'])
  sh(['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-f', f]);
const ADM = '00000000-0000-0000-0000-0000000000a1', USR = '00000000-0000-0000-0000-0000000000a2', OWN = '00000000-0000-0000-0000-0000000000a3', CO = '00000000-0000-0000-0000-0000000000c1';
sql(`insert into auth.users (id,email,email_confirmed_at) values ('${ADM}','spravce@vexaronet.test',now()),('${USR}','bezny@vexaronet.test',now()),('${OWN}','majitel@firma.test',now());
 insert into private.platform_admins values ('${ADM}');
 insert into public.companies (id,owner_id,name) values ('${CO}','${OWN}','Firma s webem'); insert into public.company_members (company_id,user_id,role) values ('${CO}','${OWN}','owner');
 insert into public.sites (company_id,slug,enabled) values ('${CO}','demo-web',true);
 insert into public.newsletter_subscribers (email,consent) values ('anna@priklad.test',true),('bob@priklad.test',true),('cyril@priklad.test',false);`);

// převodník PostgREST -> SQL (role podle klíče a tokenu jako v Supabase)
const mails = [];
function roleOf(h) {
  const key = h.apikey, tok = String(h.authorization || '').replace(/^Bearer\s+/i, '');
  if (key === SVC || tok === SVC) return { role: 'service_role', sub: null };
  if (tok.startsWith('user:')) return { role: 'authenticated', sub: tok.slice(5) };
  return { role: 'anon', sub: null };
}
function asRole(r, q) {
  const claims = JSON.stringify(r.sub ? { sub: r.sub, role: r.role } : { role: r.role });
  return sql(`begin; select set_config('request.jwt.claims', ${lit(claims)}, true); set local role ${r.role}; ${q}; commit;`).split('\n').filter((x) => x !== 'BEGIN' && x !== 'COMMIT' && x !== 'SET' && x !== '' && !x.startsWith('set_config') ).pop();
}
const J = (o, s = 200) => new Response(o === undefined ? null : JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
globalThis.fetch = async (url, opts = {}) => {
  url = String(url); const h = opts.headers || {};
  if (url.startsWith('https://api.resend.com/')) { mails.push(JSON.parse(opts.body)); return J({ id: 'msg-' + mails.length }); }
  if (url.startsWith(L.SB_URL + '/rest/v1/rpc/')) {
    const fn = url.slice((L.SB_URL + '/rest/v1/rpc/').length), args = JSON.parse(opts.body || '{}');
    const call = `select coalesce(to_jsonb(public.${fn}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')}))::text, 'null')`;
    try { const out = asRole(roleOf(h), call); return J(JSON.parse(out)); }
    catch (e) { const m = String(e.stderr || e.message); const code = /ERROR:\s+([^\n]*)/.exec(m)?.[1] || m; return J({ message: code, code: /permission denied|forbidden/.test(code) ? '42501' : 'P0001' }, /permission denied|forbidden/.test(code) ? 403 : 400); }
  }
  if (url.startsWith(L.SB_URL + '/rest/v1/company_members')) {
    if (roleOf(h).role !== 'service_role') return J([]);
    const q = new URL(url).searchParams, cid = q.get('company_id').replace('eq.', ''), role = q.get('role').replace('eq.', '');
    return J(JSON.parse(sql(`select coalesce(json_agg(json_build_object('user_id',user_id)),'[]') from public.company_members where company_id=${lit(cid)} and role=${lit(role)}`)));
  }
  if (url.startsWith(L.SB_URL + '/auth/v1/admin/users/')) {
    if (roleOf(h).role !== 'service_role') return J({}, 401);
    return J({ email: sql(`select email from auth.users where id=${lit(url.split('/').pop())}`) });
  }
  throw new Error('neočekávané volání ' + url);
};
const ENV = { SUPABASE_SERVICE_KEY: SVC, RESEND_API_KEY: 'test-resend', MARKETING_DISPATCH_SECRET: 'tajne-dispatch', OPERATOR_NAME: 'Provozovatel s.r.o. (testovací údaj)', OPERATOR_ADDRESS: 'Testovací 1, Praha (testovací údaj)' };
const post = (ep, body, headers = {}, env = ENV, url = 'https://vexaronet.com/api/x') => ep.onRequest({ request: new Request(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) }), env });
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log('OK   ' + name); };

// ===================== marketing =====================
await t('naplánovat zprávu smí jen správce platformy (DB to ověří podle tokenu)', async () => {
  assert.equal((await post(newsletter, { action: 'queue', subject: 'Novinky', body: 'Text novinek pro test.' }, { authorization: `Bearer user:${USR}` })).status, 403);
  const r = await post(newsletter, { action: 'queue', subject: 'Listopadové novinky', body: 'Přidali jsme profil firmy a přehled Autopilota.' }, { authorization: `Bearer user:${ADM}` });
  assert.equal(r.status, 200, await r.clone().text());
  const r2 = await post(newsletter, { action: 'queue', subject: 'Prosincové novinky', body: 'Naplánovaná zpráva na později.', scheduled_at: new Date(Date.now() + 3600e3).toISOString() }, { authorization: `Bearer user:${ADM}` });
  assert.equal(r2.status, 200);
});
await t('bez identifikace odesílatele se nic neodešle (§ 7 odst. 4 písm. b) zák. 480/2004 Sb.)', async () => {
  const { OPERATOR_NAME, ...env } = ENV;
  const r = await post(newsletter, { action: 'dispatch' }, { 'x-dispatch-secret': 'tajne-dispatch' }, env);
  assert.equal(r.status, 503); assert.deepEqual((await r.json()).missing, ['OPERATOR_NAME']); assert.equal(mails.length, 0);
});
await t('odeslání bez tajemství plánovače je odmítnuto', async () => { assert.equal((await post(newsletter, { action: 'dispatch' }, { 'x-dispatch-secret': 'spatne' })).status, 401); });
let tokAnna;
await t('dávka jde jen adresátům se souhlasem; zpráva je označená, s odesílatelem a odhlášením jedním klikem', async () => {
  const r = await post(newsletter, { action: 'dispatch' }, { 'x-dispatch-secret': 'tajne-dispatch' });
  const j = await r.json(); assert.equal(r.status, 200); assert.equal(j.sent, 2);
  assert.deepEqual(mails.map((m) => m.to[0]).sort(), ['anna@priklad.test', 'bob@priklad.test']);
  const a = mails.find((m) => m.to[0] === 'anna@priklad.test');
  assert.match(a.text, /^Obchodní sdělení/); assert.match(a.text, /Provozovatel s\.r\.o\./); assert.match(a.text, /odhlasit\/\?t=[0-9a-f]{64}/);
  assert.match(a.headers['List-Unsubscribe'], /^<https:\/\/vexaronet\.com\/api\/unsubscribe\?t=[0-9a-f]{64}>$/); assert.equal(a.headers['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
  assert.ok(!a.headers['List-Unsubscribe'].includes('anna') && !/odhlasit\/\?t=[^\s]*anna/.test(a.text), 'adresa příjemce není v odkazu');
  tokAnna = /\?t=([0-9a-f]{64})/.exec(a.headers['List-Unsubscribe'])[1];
});
await t('GET odkazu (náhled v poště) nic neodhlásí, jen přesměruje na stránku s tlačítkem', async () => {
  const r = await unsub.onRequest({ request: new Request(`https://vexaronet.com/api/unsubscribe?t=${tokAnna}`), env: ENV });
  assert.equal(r.status, 303); assert.equal(r.headers.get('location'), `/odhlasit/?t=${tokAnna}`);
  assert.equal(sql(`select count(*) from private.marketing_suppressions`), '0');
});
await t('odhlášení jedním klikem z pošty (RFC 8058) funguje bez přihlášení a neprozradí adresu', async () => {
  const r = await post(unsub, 'List-Unsubscribe=One-Click', { 'content-type': 'application/x-www-form-urlencoded' }, ENV, `https://vexaronet.com/api/unsubscribe?t=${tokAnna}`);
  const body = await r.text(); assert.equal(r.status, 200, body); assert.ok(!body.includes('anna'));
  assert.equal(sql(`select email_norm from private.marketing_suppressions`), 'anna@priklad.test');
});
await t('neplatný nebo smyšlený token nic neodhlásí', async () => {
  assert.equal((await post(unsub, { token: 'a'.repeat(64) })).status, 404);
  assert.equal((await post(unsub, { token: 'anna@priklad.test' })).status, 400);
});
await t('naplánovaná zpráva (zadaná před odhlášením) už odhlášené adrese nepřijde', async () => {
  mails.length = 0;
  sql(`update private.marketing_messages set status='sent' where subject='Listopadové novinky'; update private.marketing_messages set scheduled_at=now()-interval '1 second' where subject='Prosincové novinky'`);
  const j = await (await post(newsletter, { action: 'dispatch' }, { 'x-dispatch-secret': 'tajne-dispatch' })).json();
  assert.equal(j.sent, 1); assert.deepEqual(mails.map((m) => m.to[0]), ['bob@priklad.test']);
});
await t('ani nová přihláška stejné adresy odhlášení neobejde', async () => {
  mails.length = 0;
  sql(`insert into public.newsletter_subscribers (email,consent) values ('Anna@Priklad.test',true); update private.marketing_messages set status='sent'`);
  await post(newsletter, { action: 'queue', subject: 'Další novinky', body: 'Ještě jedna zpráva pro test.' }, { authorization: `Bearer user:${ADM}` });
  await post(newsletter, { action: 'dispatch' }, { 'x-dispatch-secret': 'tajne-dispatch' });
  assert.ok(!mails.some((m) => m.to[0].toLowerCase().startsWith('anna')), JSON.stringify(mails.map((m) => m.to)));
});

// ===================== DSA =====================
const notice = (o = {}) => ({ urls: ['https://vexaronet.com/?w=demo-web'], details: 'Sekce Služby', category: 'podvod', explanation: 'Web vybírá zálohy za služby, které nikdy nedodá; je to podvod.', name: 'Jana Oznamovatelka', email: 'jana@priklad.test', good_faith: true, ...o });
let ref;
await t('DSA: oznámení se přijme, má referenční číslo a oznamovatel dostane potvrzení přijetí', async () => {
  mails.length = 0;
  const r = await post(dsaNotice, notice(), { 'cf-connecting-ip': '198.51.100.7' }); const j = await r.json();
  assert.equal(r.status, 200, JSON.stringify(j)); assert.match(j.ref, /^DSA-\d{8}-[0-9A-F]{8}$/); assert.equal(j.ack, 'sent'); ref = j.ref;
  assert.equal(mails.length, 1); assert.equal(mails[0].to[0], 'jana@priklad.test'); assert.ok(mails[0].text.includes(j.ref) && /neodstraňujeme automaticky/.test(mails[0].text));
  assert.equal(sql(`select target_kind||':'||target_company_id||':'||(ack_sent_at is not null) from private.dsa_notices where ref='${j.ref}'`), `web:${CO}:true`);
  assert.ok(!sql(`select ip_hash from private.dsa_notices where ref='${j.ref}'`).includes('198.51.100.7'), 'IP se neukládá, jen otisk');
});
await t('DSA: neúplné oznámení (bez vysvětlení, bez prohlášení, bez kontaktu) se odmítne a nic se neuloží', async () => {
  const before = sql('select count(*) from private.dsa_notices');
  for (const bad of [notice({ explanation: 'krátké' }), notice({ good_faith: false }), notice({ email: '' }), notice({ urls: ['javascript:alert(1)'] })])
    assert.equal((await post(dsaNotice, bad, { 'cf-connecting-ip': '198.51.100.8' })).status, 400);
  assert.equal(sql('select count(*) from private.dsa_notices'), before);
});
await t('DSA: oznámení zneužívání dětí lze podat bez jména a e-mailu', async () => {
  const r = await post(dsaNotice, notice({ category: 'csam', name: '', email: '' }), { 'cf-connecting-ip': '198.51.100.9' }); const j = await r.json();
  assert.equal(r.status, 200); assert.equal(j.ack, 'no_email');
});
await t('DSA: ochrana proti zahlcení z jedné adresy', async () => {
  let last; for (let i = 0; i < 11; i++) last = await post(dsaNotice, notice(), { 'cf-connecting-ip': '203.0.113.50' });
  assert.equal(last.status, 429);
});
await t('DSA: běžný uživatel oznámení nevidí ani nerozhoduje', async () => {
  assert.equal((await post(dsaAdmin, { action: 'list' }, { authorization: `Bearer user:${USR}` })).status, 403);
  const id = sql(`select id from private.dsa_notices where ref='${ref}'`);
  assert.equal((await post(dsaAdmin, { action: 'decide', id, decision: 'odstraneni', ground: 'nezakonny_obsah', reason: 'Pokus běžného uživatele rozhodnout.' }, { authorization: `Bearer user:${USR}` })).status, 403);
  assert.equal(sql(`select status from private.dsa_notices where ref='${ref}'`), 'received');
});
await t('DSA: rozhodnutí správce vyrozumí oznamovatele i firmu (odůvodnění podle čl. 17) a obsah samo nemění', async () => {
  mails.length = 0;
  const id = sql(`select id from private.dsa_notices where ref='${ref}'`);
  const r = await post(dsaAdmin, { action: 'decide', id, decision: 'znepristupneni', ground: 'nezakonny_obsah', reason: 'Web vybírá zálohy za neexistující služby (podvod).' }, { authorization: `Bearer user:${ADM}` });
  const j = await r.json(); assert.equal(r.status, 200, JSON.stringify(j)); assert.equal(j.notifier, 'sent'); assert.equal(j.uploader, 'sent');
  const toN = mails.find((m) => m.to[0] === 'jana@priklad.test'), toU = mails.find((m) => m.to[0] === 'majitel@firma.test');
  assert.ok(toN && /Rozhodnutí o oznámení/.test(toN.subject)); assert.ok(toU && /Odůvodnění omezení obsahu/.test(toU.subject));
  assert.ok(/Možnosti nápravy/.test(toU.text) && /bez automatizovaného rozhodování/.test(toU.text) && toU.text.includes(ref));
  assert.equal(sql(`select enabled from public.sites where slug='demo-web'`), 't', 'web zůstal zapnutý: omezení provádí člověk ručně');
  assert.equal(sql(`select string_agg(e.event, ',' order by e.id) from private.dsa_events e join private.dsa_notices n on n.id=e.notice_id where n.ref='${ref}'`),
    'prijato,potvrzeni_odeslano,rozhodnuto,oznamovatel_vyrozumen,poskytovatel_obsahu_vyrozumen');
});
console.log(`\nVŠECH ${n} TESTŮ PROŠLO (skutečná PostgreSQL, simulovaný jen poskytovatel e-mailu)`);
