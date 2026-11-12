// End-to-end: SKUTEČNÝ endpoint functions/api/social.js proti SKUTEČNÉ lokální PostgreSQL (role, schvalování, evidence publikací).
// Simulovaná je jen Meta (Graph API). Žádné skutečné volání ven.
//   PSQL="runuser -u postgres -- psql" node tests/social_e2e.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as ep from '../functions/api/social.js';

const SB = 'https://micymdbqgzeckiqyvvkn.supabase.co', PSQL = (process.env.PSQL || 'psql').split(' '), DB = 'vx_social_e2e', SVC = 'sb_secret_TESTONLY000000000000';
const sh = (args) => execFileSync(PSQL[0], [...PSQL.slice(1), ...args], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
const sql = (q) => sh(['-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-c', q]).trim();
const lit = (v) => (v === null || v === undefined ? 'NULL' : `'${String(typeof v === 'object' ? JSON.stringify(v) : v).replace(/'/g, "''")}'`);
sh(['-X', '-q', '-d', 'postgres', '-c', `drop database if exists ${DB}`, '-c', `create database ${DB}`]);
for (const f of ['db/test/00_local_supabase_shim.sql', 'db/test/01_base_stub.sql', 'db/migrations/20261107120000_profil_firmy.sql', 'db/migrations/20261108110000_autopilot_limity.sql',
  'db/test/05_marketing_prestate.sql', 'db/migrations/20261112100000_ai_marketing.sql', 'db/migrations/20261116100000_social_ucty.sql']) sh(['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-f', f]);
const O = '00000000-0000-0000-0000-00000000d001', E = '00000000-0000-0000-0000-00000000d002', X = '00000000-0000-0000-0000-00000000d003', Y = '00000000-0000-0000-0000-00000000d004';
const A = '00000000-0000-0000-0000-00000000aa01', B = '00000000-0000-0000-0000-00000000bb01', C = '00000000-0000-0000-0000-00000000cc01';
const P1 = '00000000-0000-0000-0000-0000000000a1', P2 = '00000000-0000-0000-0000-0000000000a2', P3 = '00000000-0000-0000-0000-0000000000a3';
sql(`insert into auth.users (id,email,email_confirmed_at) values ('${O}','o@a.test',now()),('${E}','e@a.test',now()),('${X}','x@b.test',now()),('${Y}','y@c.test',now());
 insert into public.companies (id,owner_id,name) values ('${A}','${O}','Autoservis Konina'),('${B}','${X}','Jiná firma'),('${C}','${Y}','Firma START');
 insert into public.company_members (company_id,user_id,role) values ('${A}','${O}','owner'),('${A}','${E}','employee'),('${B}','${X}','owner'),('${C}','${Y}','owner');
 insert into public.subscriptions (company_id,plan,status,trial_end) values ('${A}','pro','trial',now()+interval '20 days'),('${B}','pro','trial',now()+interval '20 days'),('${C}','start','active',null);
 insert into public.marketing_posts (id,company_id,title,body,channel,status) values ('${P1}','${A}','Přezutí','Přezujeme na počkání. Objednejte se online.','Facebook','draft'),
  ('${P2}','${A}','Neschválený','Tento text nikdo neschválil.','Facebook','draft'),('${P3}','${A}','Instagram','Zimní prohlídka vozu.','Instagram','draft');`);

const roleOf = (h) => { const k = h.apikey, t = String(h.authorization || '').replace(/^Bearer\s+/i, ''); if (k === SVC) return { role: 'service_role' }; if (t.startsWith('user:')) return { role: 'authenticated', sub: t.slice(5) }; return { role: 'anon' }; };
function asRole(r, q) {
  const claims = JSON.stringify(r.sub ? { sub: r.sub, role: r.role } : { role: r.role });
  return sql(`begin; select set_config('request.jwt.claims', ${lit(claims)}, true); set local role ${r.role}; ${q}; commit;`).split('\n').filter((x) => !['BEGIN', 'COMMIT', 'SET', ''].includes(x) && !x.startsWith('set_config')).pop();
}
const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
const meta = { calls: [], mode: 'ok', pages: null };
const PAGE_TOKEN = 'EAAG-page-token-SECRET-111', USER_TOKEN = 'EAAG-user-token-SECRET-222';
globalThis.fetch = async (url, opts = {}) => {
  url = String(url); const h = opts.headers || {};
  if (url.startsWith('https://graph.facebook.com/')) {
    const u = new URL(url), path = u.pathname.replace('/v27.0', ''), body = new URLSearchParams(opts.body || ''), auth = String(h.authorization || '');
    meta.calls.push({ method: opts.method, path, q: Object.fromEntries(u.searchParams), body: Object.fromEntries(body), auth, url });
    if (meta.mode === 'timeout' && opts.method === 'POST') throw new Error('timeout');
    if (meta.mode === 'expired' && opts.method === 'POST') return J({ error: { code: 190, message: 'Error validating access token' } }, 400);
    if (meta.mode === 'reject' && opts.method === 'POST') return J({ error: { code: 100, message: 'Invalid parameter' } }, 400);
    if (path === '/oauth/access_token') return u.searchParams.get('code') === 'bad' ? J({ error: { code: 100, message: 'bad code' } }, 400) : J({ access_token: USER_TOKEN });
    if (path === '/me/accounts') return J({ data: meta.pages });
    if (path === '/111/feed') return J({ id: '111_900' });
    if (path === '/111_900') return J({ permalink_url: 'https://www.facebook.com/111/posts/900' });
    if (path === '/222/media') return J({ id: 'c1' });
    if (path === '/c1') return J({ status_code: 'FINISHED' });
    if (path === '/222/media_publish') return J({ id: '777' });
    if (path === '/777') return J({ permalink: 'https://www.instagram.com/p/abc/' });
    return J({ error: { code: 1, message: 'neznámá cesta ' + path } }, 400);
  }
  if (url === SB + '/auth/v1/user') { const r = roleOf(h); return r.sub ? J({ id: r.sub }) : J({}, 401); }
  if (url.startsWith(SB + '/rest/v1/rpc/')) {
    const fn = url.slice((SB + '/rest/v1/rpc/').length), args = JSON.parse(opts.body || '{}');
    assert.ok(!(h.apikey === SVC && h.authorization), 'servisní klíč smí jít jen v hlavičce apikey');
    try { return J(JSON.parse(asRole(roleOf(h), `select coalesce(to_jsonb(public.${fn}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')}))::text, 'null')`))); }
    catch (e) { const m = String(e.stderr || e.message); const msg = /ERROR:\s+([^\n]*)/.exec(m)?.[1] || m; return J({ message: msg, code: /permission denied|forbidden/.test(msg) ? '42501' : 'P0001' }, 400); }
  }
  if (url.startsWith(SB + '/rest/v1/company_members') || url.startsWith(SB + '/rest/v1/subscriptions')) {
    const u = new URL(url), t = u.pathname.split('/').pop(), q = u.searchParams, w = [];
    for (const [k, v] of q) if (v.startsWith('eq.')) w.push(`${k} = ${lit(v.slice(3))}`);
    return J(JSON.parse(asRole(roleOf(h), `select coalesce(json_agg(x),'[]')::text from (select ${q.get('select') || '*'} from public.${t} ${w.length ? 'where ' + w.join(' and ') : ''} limit 5) x`)));
  }
  throw new Error('neočekávané volání ' + url);
};
const ENV = { META_APP_ID: '1234567890', META_APP_SECRET: 'app-secret-0123456789abcdef', SOCIAL_TOKEN_KEY: 'k'.repeat(40), SUPABASE_SERVICE_KEY: SVC };
const post = (body, user = O, env = ENV) => ep.onRequest({ request: new Request('https://vexaronet.com/api/social', { method: 'POST', headers: { 'content-type': 'application/json', ...(user ? { authorization: 'Bearer user:' + user } : {}) }, body: JSON.stringify(body) }), env });
const cb = (q, cookie, env = ENV) => ep.onRequest({ request: new Request('https://vexaronet.com/api/social?' + new URLSearchParams(q), { headers: cookie ? { cookie } : {} }), env });
const asUser = (uid, q) => asRole({ role: 'authenticated', sub: uid }, q);
const approve = (pid) => asUser(O, `select public.mkt_post_approve('${A}','${pid}','${sql(`select private.mkt_hash(title, body, channel) from public.marketing_posts where id='${pid}'`)}')`);
const pubs = () => JSON.parse(sql(`select coalesce(json_agg(json_build_object('post',post_id,'status',status,'error',error,'link',permalink) order by requested_at),'[]') from private.social_publications`));
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log('OK   ' + name); };
const begin = async (user = O, cid = A) => { const r = await post({ op: 'begin', cid }, user); const d = await r.json(); return { r, d, state: d.url ? new URL(d.url).searchParams.get('state') : null, cookie: (r.headers.get('set-cookie') || '').split(';')[0] }; };

await t('šifrování tokenu: jiný klíč ani jiný účet ho neotevře', async () => {
  const s = await ep.sealToken('k'.repeat(40), 'tajny-token', 'facebook:111');
  assert.ok(!s.includes('tajny-token')); assert.equal(await ep.openToken('k'.repeat(40), s, 'facebook:111'), 'tajny-token');
  await assert.rejects(ep.openToken('x'.repeat(40), s, 'facebook:111')); await assert.rejects(ep.openToken('k'.repeat(40), s, 'facebook:999'));
});
await t('bez přihlášení 401, zaměstnanec 403, tarif START 403, bez nastavení 503 – Meta se nevolá', async () => {
  assert.equal((await post({ op: 'begin', cid: A }, null)).status, 401);
  assert.equal((await post({ op: 'begin', cid: A }, E)).status, 403);
  assert.equal((await post({ op: 'begin', cid: C }, Y)).status, 403);
  const r = await post({ op: 'begin', cid: A }, O, { ...ENV, META_APP_SECRET: '' }); assert.equal(r.status, 503); assert.equal((await r.json()).error, 'not_configured');
  assert.equal(meta.calls.length, 0);
});
let ACC_FB, ACC_IG;
await t('zahájení: adresa přihlášení u Meta s požadovanými oprávněními; tajemství aplikace v ní není', async () => {
  const b = await begin(); assert.equal(b.r.status, 200);
  const u = new URL(b.d.url); assert.equal(u.origin + u.pathname, 'https://www.facebook.com/v27.0/dialog/oauth');
  assert.equal(u.searchParams.get('redirect_uri'), 'https://vexaronet.com/api/social'); assert.equal(u.searchParams.get('scope'), ep.SCOPES.join(','));
  assert.ok(!b.d.url.includes(ENV.META_APP_SECRET)); assert.match(b.r.headers.get('set-cookie'), /HttpOnly; Secure; SameSite=Lax/);
  assert.equal(sql(`select count(*) from private.social_oauth_states where state_hash='${b.state}'`), '0', 'v databázi je jen otisk stavu');
});
await t('návrat bez cookie nebo s cizím stavem se odmítne a nic se neuloží', async () => {
  const b = await begin();
  assert.match((await cb({ code: 'ok', state: b.state }, null)).headers.get('location'), /social=state$/);
  assert.match((await cb({ code: 'ok', state: 'x'.repeat(43) }, b.cookie)).headers.get('location'), /social=state$/);
  assert.equal(sql('select count(*) from private.social_accounts'), '0');
});
await t('návrat: uloží stránku i navázaný Instagram; stránku bez práva tvořit obsah přeskočí; token je v DB jen zašifrovaný', async () => {
  meta.pages = [{ id: '111', name: 'Autoservis Konina', access_token: PAGE_TOKEN, tasks: ['CREATE_CONTENT', 'MANAGE'], instagram_business_account: { id: '222', username: 'autoservis_konina' } },
    { id: '333', name: 'Cizí stránka jen ke čtení', access_token: 'x', tasks: ['ANALYZE'] }];
  const b = await begin(); const r = await cb({ code: 'ok', state: b.state }, b.cookie);
  assert.equal(r.status, 302); assert.match(r.headers.get('location'), /social=connected$/);
  const rows = JSON.parse(sql(`select json_agg(json_build_object('id',id,'p',provider,'e',external_id,'t',token_enc,'c',company_id,'by',connected_by) order by provider) from private.social_accounts`));
  assert.deepEqual(rows.map((x) => [x.p, x.e]), [['facebook', '111'], ['instagram', '222']]);
  assert.ok(rows.every((x) => x.c === A && x.by === O && x.t.startsWith('v1.') && !x.t.includes(PAGE_TOKEN)));
  [ACC_FB, ACC_IG] = rows.map((x) => x.id);
  assert.ok(meta.calls.filter((c) => c.path === '/me/accounts').every((c) => c.auth === 'Bearer ' + USER_TOKEN && !c.url.includes(USER_TOKEN)), 'token jde v hlavičce, ne v adrese');
  // stejný stav podruhé nejde použít
  assert.match((await cb({ code: 'ok', state: b.state }, b.cookie)).headers.get('location'), /social=state$/);
});
await t('uživatel vidí účty bez tokenů; zaměstnanec ani cizí firma je nevidí', async () => {
  const s = JSON.parse(asUser(O, `select public.social_state('${A}')::text`));
  assert.equal(s.accounts.length, 2); assert.ok(!JSON.stringify(s).includes('token'));
  assert.throws(() => asUser(E, `select public.social_state('${A}')`)); assert.throws(() => asUser(X, `select public.social_state('${A}')`));
  assert.throws(() => asUser(O, `select * from private.social_accounts`));
  assert.throws(() => asUser(O, `select public.social_publish_token('${P1}')`)); assert.throws(() => asUser(O, `select public.social_oauth_finish(repeat('a',64), '[]')`));
});
await t('neschválený příspěvek se nezveřejní (412) a Meta se nevolá', async () => {
  const c0 = meta.calls.length; const r = await post({ op: 'publish', cid: A, post: P2, account: ACC_FB });
  assert.equal(r.status, 412); assert.equal((await r.json()).error, 'not_approved'); assert.equal(meta.calls.length, c0);
});
await t('cizí firma nemůže publikovat na účet jiné firmy ani zaměstnanec za svou firmu', async () => {
  const c0 = meta.calls.length;
  assert.equal((await post({ op: 'publish', cid: B, post: P1, account: ACC_FB }, X)).status, 404);
  assert.equal((await post({ op: 'publish', cid: A, post: P1, account: ACC_FB }, E)).status, 403);
  assert.equal(meta.calls.length, c0);
});
await t('Facebook: schválený text se zveřejní přesně tak, jak byl schválen, a propíše se do evidence příspěvku', async () => {
  approve(P1); const c0 = meta.calls.length; const r = await post({ op: 'publish', cid: A, post: P1, account: ACC_FB }); const d = await r.json();
  assert.equal(r.status, 200); assert.equal(d.permalink, 'https://www.facebook.com/111/posts/900');
  const feed = meta.calls.slice(c0).find((c) => c.path === '/111/feed');
  assert.equal(feed.body.message, 'Přezujeme na počkání. Objednejte se online.'); assert.equal(feed.auth, 'Bearer ' + PAGE_TOKEN); assert.match(feed.body.appsecret_proof, /^[0-9a-f]{64}$/);
  assert.equal(sql(`select published_channel||'|'||published_url||'|'||published_by from private.mkt_items where post_id='${P1}'`), `Facebook|https://www.facebook.com/111/posts/900|${O}`);
  assert.equal(sql(`select status from public.marketing_posts where id='${P1}'`), 'done');
});
await t('opakované kliknutí nic znovu nezveřejní (409 already_published)', async () => {
  const c0 = meta.calls.length; const r = await post({ op: 'publish', cid: A, post: P1, account: ACC_FB });
  assert.equal(r.status, 409); assert.equal((await r.json()).error, 'already_published'); assert.equal(meta.calls.length, c0);
});
await t('Instagram: bez obrázku 422; s obrázkem kontejner → zveřejnění → odkaz', async () => {
  approve(P3);
  assert.equal((await post({ op: 'publish', cid: A, post: P3, account: ACC_IG })).status, 422);
  assert.equal((await post({ op: 'publish', cid: A, post: P3, account: ACC_IG, image_url: 'http://nezabezpecene.test/a.jpg' })).status, 422);
  const c0 = meta.calls.length; const r = await post({ op: 'publish', cid: A, post: P3, account: ACC_IG, image_url: 'https://cdn.test/a.jpg' });
  assert.equal(r.status, 200); assert.equal((await r.json()).permalink, 'https://www.instagram.com/p/abc/');
  const seq = meta.calls.slice(c0).map((c) => c.path); assert.deepEqual(seq, ['/222/media', '/c1', '/222/media_publish', '/777']);
  assert.equal(meta.calls[c0].body.caption, 'Zimní prohlídka vozu.'); assert.equal(meta.calls[c0].body.image_url, 'https://cdn.test/a.jpg');
});
await t('úprava textu po schválení zruší možnost zveřejnit (je nutné schválit znovu)', async () => {
  sql(`insert into public.marketing_posts (id,company_id,title,body,channel,status) values ('00000000-0000-0000-0000-0000000000a4','${A}','Čtvrtý','Původní text.','Facebook','draft')`);
  approve('00000000-0000-0000-0000-0000000000a4'); sql(`update public.marketing_posts set body='Změněný text bez schválení.' where id='00000000-0000-0000-0000-0000000000a4'`);
  assert.equal((await post({ op: 'publish', cid: A, post: '00000000-0000-0000-0000-0000000000a4', account: ACC_FB })).status, 412);
});
const P5 = '00000000-0000-0000-0000-0000000000a5';
await t('odmítnutí sítí: zapíše se chyba, příspěvek zůstane nezveřejněný a jde to zkusit znovu', async () => {
  sql(`insert into public.marketing_posts (id,company_id,title,body,channel,status) values ('${P5}','${A}','Pátý','Text pátého příspěvku.','Facebook','draft')`); approve(P5);
  meta.mode = 'reject'; const r = await post({ op: 'publish', cid: A, post: P5, account: ACC_FB }); meta.mode = 'ok';
  assert.equal(r.status, 502); assert.equal(sql(`select published_at is null from private.mkt_items where post_id='${P5}'`), 't');
  assert.deepEqual(pubs().filter((x) => x.post === P5).map((x) => x.status), ['failed']);
});
await t('síť neodpověděla: výsledek „unknown“, další pokus je zablokovaný, dokud člověk nerozhodne', async () => {
  meta.mode = 'timeout'; const r = await post({ op: 'publish', cid: A, post: P5, account: ACC_FB }); meta.mode = 'ok';
  assert.equal(r.status, 504); assert.equal((await r.json()).error, 'unknown_outcome');
  const c0 = meta.calls.length; const r2 = await post({ op: 'publish', cid: A, post: P5, account: ACC_FB });
  assert.equal(r2.status, 409); assert.equal((await r2.json()).error, 'unknown_outcome'); assert.equal(meta.calls.length, c0);
  const id = sql(`select id from private.social_publications where post_id='${P5}' and status='unknown'`);
  assert.throws(() => asUser(E, `select public.social_publish_resolve('${A}','${id}',false)`));
  asUser(O, `select public.social_publish_resolve('${A}','${id}',false)`);
  assert.equal((await post({ op: 'publish', cid: A, post: P5, account: ACC_FB })).status, 200);
});
await t('vypršelý token: 409 reauth a účet je označen k novému propojení', async () => {
  const P6 = '00000000-0000-0000-0000-0000000000a6';
  sql(`insert into public.marketing_posts (id,company_id,title,body,channel,status) values ('${P6}','${A}','Šestý','Text šestého.','Facebook','draft')`); approve(P6);
  meta.mode = 'expired'; const r = await post({ op: 'publish', cid: A, post: P6, account: ACC_FB }); meta.mode = 'ok';
  assert.equal(r.status, 409); assert.equal((await r.json()).error, 'reauth');
  assert.equal(sql(`select last_error from private.social_accounts where id='${ACC_FB}'`), 'reauth');
});
await t('odpojení smaže token; publikace na odpojený účet nejde; zaměstnanec odpojit nesmí', async () => {
  assert.throws(() => asUser(E, `select public.social_disconnect('${A}','${ACC_IG}')`));
  asUser(O, `select public.social_disconnect('${A}','${ACC_IG}')`);
  assert.equal(sql(`select token_enc='' and disconnected_at is not null from private.social_accounts where id='${ACC_IG}'`), 't');
  assert.equal(JSON.parse(asUser(O, `select public.social_state('${A}')::text`)).accounts.length, 1);
  const P7 = '00000000-0000-0000-0000-0000000000a7';
  sql(`insert into public.marketing_posts (id,company_id,title,body,channel,status) values ('${P7}','${A}','Sedmý','Text sedmého.','Instagram','draft')`); approve(P7);
  assert.equal((await post({ op: 'publish', cid: A, post: P7, account: ACC_IG, image_url: 'https://cdn.test/a.jpg' })).status, 404);
});
await t('uživatel odmítl přístup u Meta: nic se neuloží, stav je spotřebovaný', async () => {
  const b = await begin(); const n0 = sql('select count(*) from private.social_accounts');
  assert.match((await cb({ error: 'access_denied', state: b.state }, b.cookie)).headers.get('location'), /social=denied$/);
  assert.equal(sql('select count(*) from private.social_accounts'), n0);
  assert.match((await cb({ code: 'ok', state: b.state }, b.cookie)).headers.get('location'), /social=state$/);
});
await t('žádný token ani tajemství aplikace není v odpovědích ani v chybách uložených v databázi', async () => {
  const dump = sql(`select coalesce(string_agg(coalesce(error,'')||coalesce(permalink,''),' '),'') from private.social_publications`) + sql(`select coalesce(string_agg(coalesce(last_error,''),' '),'') from private.social_accounts`);
  for (const s of [PAGE_TOKEN, USER_TOKEN, ENV.META_APP_SECRET, ENV.SOCIAL_TOKEN_KEY]) assert.ok(!dump.includes(s));
});
await t('návrat migrace odstraní vše, co přidala', async () => {
  sh(['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-f', 'db/migrations/20261116100000_social_ucty_rollback.sql']);
  assert.equal(sql(`select count(*) from pg_proc where proname like 'social\\_%'`), '0');
  assert.equal(sql(`select count(*) from pg_tables where schemaname='private' and tablename like 'social\\_%'`), '0');
  assert.equal(sql(`select published_channel from private.mkt_items where post_id='${P1}'`), 'Facebook', 'evidence zveřejnění u příspěvku zůstává');
});
sh(['-X', '-q', '-d', 'postgres', '-c', `drop database if exists ${DB}`]);
console.log(`VŠECH ${n} TESTŮ PROŠLO (skutečná PostgreSQL; simulovaná jen Meta)`);
