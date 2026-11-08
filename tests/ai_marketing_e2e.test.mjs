// End-to-end: SKUTEČNÝ endpoint functions/api/ai-marketing.js proti SKUTEČNÉ lokální PostgreSQL (profil, limity Autopilota, AI Marketing).
// Volání PostgREST se převádějí na SQL pod rolí podle tokenu (RLS i práva funkcí platí jako v Supabase). Simulovaný je jen poskytovatel AI (Gemini).
//   PSQL="runuser -u postgres -- psql" node tests/ai_marketing_e2e.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as ep from '../functions/api/ai-marketing.js';

const SB = 'https://micymdbqgzeckiqyvvkn.supabase.co', PSQL = (process.env.PSQL || 'psql').split(' '), DB = 'vx_ai_mkt_e2e', SVC = 'test-service-key';
const sh = (args) => execFileSync(PSQL[0], [...PSQL.slice(1), ...args], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
const sql = (q) => sh(['-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-c', q]).trim();
const lit = (v) => (v === null || v === undefined ? 'NULL' : `'${String(typeof v === 'object' ? JSON.stringify(v) : v).replace(/'/g, "''")}'`);
sh(['-X', '-q', '-d', 'postgres', '-c', `drop database if exists ${DB}`, '-c', `create database ${DB}`]);
for (const f of ['db/test/00_local_supabase_shim.sql', 'db/test/01_base_stub.sql', 'db/migrations/20261107120000_profil_firmy.sql', 'db/migrations/20261108110000_autopilot_limity.sql',
  'db/test/05_marketing_prestate.sql', 'db/migrations/20261112100000_ai_marketing.sql']) sh(['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', DB, '-f', f]);
const O = '00000000-0000-0000-0000-00000000d001', E = '00000000-0000-0000-0000-00000000d002', X = '00000000-0000-0000-0000-00000000d003', Y = '00000000-0000-0000-0000-00000000d004';
const A = '00000000-0000-0000-0000-00000000aa01', B = '00000000-0000-0000-0000-00000000bb01', C = '00000000-0000-0000-0000-00000000cc01';
const PROFILE = { shared: { identity: { displayName: 'Autoservis Konina', activity: 'Opravy aut, výměna výfuků a pneuservis v Konině' }, audience: { description: 'Řidiči z Koniny a okolí' },
  brand: { tone: 'přátelský', forbidden: ['nejlevnější'] }, channels: [{ channel: 'Facebook' }] }, local: { geography: { city: 'Konina' } } };
sql(`insert into auth.users (id,email,email_confirmed_at) values ('${O}','o@a.test',now()),('${E}','e@a.test',now()),('${X}','x@b.test',now()),('${Y}','y@c.test',now());
 insert into public.companies (id,owner_id,name) values ('${A}','${O}','Autoservis Konina'),('${B}','${X}','Firma bez profilu'),('${C}','${Y}','Firma START');
 insert into public.company_members (company_id,user_id,role) values ('${A}','${O}','owner'),('${A}','${E}','employee'),('${B}','${X}','owner'),('${C}','${Y}','owner');
 insert into public.subscriptions (company_id,plan,status,trial_end) values ('${A}','pro','trial',now()+interval '20 days'),('${B}','pro','trial',now()+interval '20 days'),('${C}','start','active',null);
 insert into private.company_profile_versions (id,company_id,version,schema_version,data,content_hash,source_revision,confirmed_by) values ('00000000-0000-0000-0000-0000000000f9','${A}',1,1,${lit(PROFILE)},repeat('b',64),1,'${O}');
 insert into private.company_active_profile values ('${A}','00000000-0000-0000-0000-0000000000f9');`);

// ---- převodník PostgREST -> SQL ----
const roleOf = (h) => { const k = h.apikey, t = String(h.authorization || '').replace(/^Bearer\s+/i, ''); if (k === SVC || t === SVC) return { role: 'service_role' }; if (t.startsWith('user:')) return { role: 'authenticated', sub: t.slice(5) }; return { role: 'anon' }; };
function asRole(r, q) {
  const claims = JSON.stringify(r.sub ? { sub: r.sub, role: r.role } : { role: r.role });
  return sql(`begin; select set_config('request.jwt.claims', ${lit(claims)}, true); set local role ${r.role}; ${q}; commit;`).split('\n').filter((x) => !['BEGIN', 'COMMIT', 'SET', ''].includes(x) && !x.startsWith('set_config')).pop();
}
const J = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
let gem = { calls: 0, bodies: [], mode: 'ok', posts: null };
globalThis.fetch = async (url, opts = {}) => {
  url = String(url); const h = opts.headers || {};
  if (url.startsWith('https://generativelanguage.googleapis.com/')) {
    gem.calls++; const body = JSON.parse(opts.body); gem.bodies.push(body);
    if (gem.mode === 'http500') return J({ error: 'x' }, 500);
    const isPosts = body.contents[0].parts[0].text.includes('příspěvků');
    const out = gem.mode === 'garbage' ? 'toto není JSON' : JSON.stringify(isPosts ? { posts: gem.posts } : {
      goal: { metric: 'poptavky', target: 15, days: 30 }, audience: 'Řidiči z Koniny a okolí, kteří potřebují rychlou opravu',
      positioning: 'Rychlý a férový autoservis s online rezervací', tone: 'přátelský',
      channels: [{ channel: 'Facebook', why: 'místní komunita' }, { channel: 'Web nebo blog', why: 'vlastní web' }, { channel: 'TikTok', why: 'mimo povolené' }],
      themes: [{ title: 'Přezutí pneumatik', angle: 'sezóna' }, { title: 'Výměna výfuku', angle: 'bezpečnost' }], cadence_per_week: 2 });
    return J({ candidates: [{ content: { parts: [{ text: out }] } }], usageMetadata: { promptTokenCount: 900, candidatesTokenCount: 400 } });
  }
  if (url === SB + '/auth/v1/user') { const r = roleOf(h); return r.sub ? J({ id: r.sub }) : J({}, 401); }
  if (url.startsWith(SB + '/rest/v1/rpc/')) {
    const fn = url.slice((SB + '/rest/v1/rpc/').length), args = JSON.parse(opts.body || '{}');
    try { return J(JSON.parse(asRole(roleOf(h), `select coalesce(to_jsonb(public.${fn}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')}))::text, 'null')`))); }
    catch (e) { const m = String(e.stderr || e.message); const msg = /ERROR:\s+([^\n]*)/.exec(m)?.[1] || m; return J({ message: msg, code: /permission denied|forbidden/.test(msg) ? '42501' : 'P0001' }, 400); }
  }
  if (url.startsWith(SB + '/rest/v1/company_members') || url.startsWith(SB + '/rest/v1/subscriptions')) {
    const u = new URL(url), t = u.pathname.split('/').pop(), q = u.searchParams, w = [];
    for (const [k, v] of q) if (v.startsWith('eq.')) w.push(`${k} = ${lit(v.slice(3))}`);
    const cols = q.get('select') || '*';
    return J(JSON.parse(asRole(roleOf(h), `select coalesce(json_agg(x),'[]')::text from (select ${cols} from public.${t} ${w.length ? 'where ' + w.join(' and ') : ''} limit 5) x`)));
  }
  throw new Error('neočekávané volání ' + url);
};
const ENV = { GEMINI_API_KEY: 'test', SUPABASE_SERVICE_KEY: SVC };
const call = (body, user = O, env = ENV) => ep.onRequest({ request: new Request('https://vexaronet.com/api/ai-marketing', { method: 'POST', headers: { 'content-type': 'application/json', ...(user ? { authorization: 'Bearer user:' + user } : {}) }, body: JSON.stringify(body) }), env });
const runs = () => JSON.parse(sql(`select coalesce(json_agg(json_build_object('status',status,'actual',actual_nusd,'in',tokens_in,'out',tokens_out) order by created_at),'[]') from private.autopilot_runs`));
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log('OK   ' + name); };

await t('bez přihlášení 401, zaměstnanec 403, tarif START 403 – AI se nevolá', async () => {
  assert.equal((await call({ action: 'strategy', cid: A, key: 'k-0000001' }, null)).status, 401);
  assert.equal((await call({ action: 'strategy', cid: A, key: 'k-0000001' }, E)).status, 403);
  assert.equal((await call({ action: 'strategy', cid: C, key: 'k-0000001' }, Y)).status, 403);
  assert.equal(gem.calls, 0);
});
await t('placené běhy vypnuté provozovatelem (výchozí stav) = 403 a AI se nevolá', async () => {
  const r = await call({ action: 'strategy', cid: A, key: 'k-0000002' }); assert.equal(r.status, 403); assert.equal((await r.json()).error, 'paid_runs_disabled'); assert.equal(gem.calls, 0);
});
sql(`update private.autopilot_platform set paid_runs_enabled = true`);
await t('bez nastaveného limitu firmy = 402 a AI se nevolá', async () => {
  const r = await call({ action: 'strategy', cid: A, key: 'k-0000003' }); assert.equal(r.status, 402); assert.equal((await r.json()).error, 'budget_not_set'); assert.equal(gem.calls, 0);
});
sql(`begin; select set_config('request.jwt.claims', '{"sub":"${O}","role":"authenticated"}', true); set local role authenticated; select public.autopilot_set_budget('${A}', 250000000); commit;`);
sql(`begin; select set_config('request.jwt.claims', '{"sub":"${X}","role":"authenticated"}', true); set local role authenticated; select public.autopilot_set_budget('${B}', 250000000); commit;`);
await t('firma bez potvrzeného profilu = 412 dřív, než se cokoli rezervuje', async () => {
  const r = await call({ action: 'strategy', cid: B, key: 'k-0000004' }, X); assert.equal(r.status, 412); assert.equal(gem.calls, 0); assert.equal(runs().length, 0);
});
await t('návrh strategie: výzva obsahuje údaje z potvrzeného profilu (ne z požadavku), výsledek se uloží jako koncept a spotřeba se vypořádá', async () => {
  const r = await call({ action: 'strategy', cid: A, key: 'k-strategie-1', profile: { activity: 'PODVRŽENO' } }); const j = await r.json();
  assert.equal(r.status, 200, JSON.stringify(j)); assert.equal(gem.calls, 1);
  const prompt = gem.bodies[0].contents[0].parts[0].text; assert.ok(prompt.includes('výměna výfuků') && !prompt.includes('PODVRŽENO') && prompt.includes('nejlevnější'));
  assert.equal(gem.bodies[0].generationConfig.maxOutputTokens, 1800);
  const st = JSON.parse(sql(`select json_build_object('status',status,'source',source,'channels',doc->'channels','run',run_id is not null,'pv',profile_version) from private.mkt_strategies`));
  assert.deepEqual([st.status, st.source, st.run, st.pv], ['draft', 'ai', true, 1]); assert.ok(!JSON.stringify(st.channels).includes('TikTok'), 'nepovolený kanál AI se vyřadí');
  const rr = runs(); assert.equal(rr.length, 1); assert.equal(rr[0].status, 'succeeded'); assert.equal(rr[0].in, 900); assert.equal(rr[0].out, 400);
  assert.equal(Number(rr[0].actual), 900 * 300 + 400 * 2500); assert.equal(j.cost_nusd, 900 * 300 + 400 * 2500);
});
await t('opakovaný požadavek (stejný klíč, obnovení stránky) AI znovu nevolá a nic nezdvojí', async () => {
  const r = await call({ action: 'strategy', cid: A, key: 'k-strategie-1' }); const j = await r.json();
  assert.equal(r.status, 200); assert.equal(j.reused, true); assert.equal(gem.calls, 1); assert.equal(sql('select count(*) from private.mkt_strategies'), '1'); assert.equal(runs().length, 1);
});
await t('běžící požadavek se stejným klíčem = 409 in_progress (žádné druhé volání AI)', async () => {
  sql(`begin; select set_config('request.jwt.claims', '{"sub":"${O}","role":"authenticated"}', true); set local role authenticated; select public.autopilot_reserve('${A}','marketing','gemini-3.5-flash-lite',100,100,'strategy:k-bezi-0001'); commit;`);
  const r = await call({ action: 'strategy', cid: A, key: 'k-bezi-0001' }); assert.equal(r.status, 409); assert.equal((await r.json()).error, 'in_progress'); assert.equal(gem.calls, 1);
  sql(`update private.autopilot_runs set status='failed', actual_nusd=0, finished_at=now() where idempotency_key='strategy:k-bezi-0001'`);
});
await t('neplatný výstup AI: nic se neuloží, běh je neúspěšný a zaplacené tokeny se započítají', async () => {
  gem.mode = 'garbage'; const r = await call({ action: 'strategy', cid: A, key: 'k-strategie-2' }); gem.mode = 'ok';
  assert.equal(r.status, 502); assert.equal(sql('select count(*) from private.mkt_strategies'), '1');
  const last = runs().pop(); assert.equal(last.status, 'failed'); assert.equal(Number(last.actual), 900 * 300 + 400 * 2500);
});
await t('chyba poskytovatele: běh neúspěšný bez nákladů, opakování stejným klíčem AI nevolá', async () => {
  gem.mode = 'http500'; const r = await call({ action: 'strategy', cid: A, key: 'k-strategie-3' }); gem.mode = 'ok';
  assert.equal(r.status, 502); const last = runs().pop(); assert.equal(last.status, 'failed'); assert.equal(Number(last.actual), 0);
  const c0 = gem.calls; const r2 = await call({ action: 'strategy', cid: A, key: 'k-strategie-3' }); assert.equal(r2.status, 409); assert.equal(gem.calls, c0);
});
await t('příspěvky jen ze SCHVÁLENÉ strategie (412 dřív, než se cokoli rezervuje)', async () => {
  const before = runs().length; const r = await call({ action: 'posts', cid: A, key: 'k-posts-0001' }); assert.equal(r.status, 412); assert.equal(runs().length, before);
});
const hash = sql(`select doc_hash from private.mkt_strategies`), sid = sql(`select id from private.mkt_strategies`);
sql(`begin; select set_config('request.jwt.claims', '{"sub":"${O}","role":"authenticated"}', true); set local role authenticated; select public.mkt_strategy_approve('${A}','${sid}','${hash}'); commit;`);
await t('dávka příspěvků ze schválené strategie: koncepty s autorem-člověkem, kanály a data v povolených mezích', async () => {
  const today = new Date().toISOString().slice(0, 10);
  gem.posts = [{ title: 'Přezujte včas', channel: 'Facebook', planned_on: today, body: 'Zimní pneumatiky přezujeme rychle, termín si vyberete online na našem webu.' },
    { title: 'Tichý výfuk', channel: 'TikTok', planned_on: '2020-01-01', body: 'Hlučný výfuk vyměníme za férovou cenu, objednejte se online na našem webu.' }];
  const r = await call({ action: 'posts', cid: A, key: 'k-posts-0002', count: 2 }); const j = await r.json();
  assert.equal(r.status, 200, JSON.stringify(j));
  const ps = JSON.parse(sql(`select json_agg(json_build_object('ch',channel,'st',status,'on',planned_on,'by',created_by) order by title) from public.marketing_posts`));
  assert.equal(ps.length, 2); assert.ok(ps.every((p) => p.st === 'draft' && p.by === O && p.on >= today && ['Facebook', 'Web nebo blog'].includes(p.ch)), JSON.stringify(ps));
  assert.equal(sql(`select count(*) from private.mkt_items where run_id is not null`), '2');
});
await t('příspěvek, který neprojde kontrolou (krátký text), nic neuloží a běh je neúspěšný', async () => {
  gem.posts = [{ title: 'X', channel: 'Facebook', planned_on: new Date().toISOString().slice(0, 10), body: 'krátké' }];
  const r = await call({ action: 'posts', cid: A, key: 'k-posts-0003' }); assert.equal(r.status, 502);
  assert.equal(sql('select count(*) from public.marketing_posts'), '2'); assert.equal(runs().pop().status, 'failed');
});
await t('vyčerpaný měsíční limit = 402 a AI se nevolá', async () => {
  sql(`update private.autopilot_budgets set monthly_limit_nusd = 1500000`);
  const c0 = gem.calls; const r = await call({ action: 'strategy', cid: A, key: 'k-strategie-4' });
  assert.equal(r.status, 402); assert.equal((await r.json()).error, 'budget_exceeded'); assert.equal(gem.calls, c0);
});
console.log(`\nVŠECH ${n} TESTŮ PROŠLO (skutečná PostgreSQL; simulovaný jen poskytovatel AI)`);
