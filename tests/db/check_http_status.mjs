// Ověří na SKUTEČNÉM Supabase (PostgREST), že chyby databázových funkcí profile_* se mapují na správné HTTP stavy.
// Lokální PostgreSQL to ověřit neumí, proto je tento skript součástí postupu v docs/TESTOVACI_PROSTREDI.md.
// Hodnoty zadejte jen ve SVÉM terminálu (heslo nikam do chatu):
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<publishable klíč> \
//   TEST_EMAIL=... TEST_PASSWORD=... TEST_COMPANY_ID=<z 20_http_fixture.sql> node tests/db/check_http_status.mjs
const { SUPABASE_URL, SUPABASE_ANON_KEY, TEST_EMAIL, TEST_PASSWORD, TEST_COMPANY_ID } = process.env;
if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !TEST_EMAIL || !TEST_PASSWORD || !TEST_COMPANY_ID) { console.error('Chybí proměnné prostředí (viz komentář na začátku souboru).'); process.exit(2); }
let fails = 0;
const check = (c, m) => { console.log((c ? 'OK   ' : 'FAIL ') + m); if (!c) fails++; };
async function call(name, body, token) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: SUPABASE_ANON_KEY, authorization: 'Bearer ' + (token || SUPABASE_ANON_KEY), 'content-type': 'application/json' }, body: JSON.stringify(body) });
  let j = null; try { j = await r.json(); } catch {}
  return { status: r.status, body: j };
}
const lg = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: SUPABASE_ANON_KEY, 'content-type': 'application/json' }, body: JSON.stringify({ email: TEST_EMAIL, password: TEST_PASSWORD }) });
const tok = (await lg.json()).access_token;
check(!!tok, 'přihlášení testovacího uživatele');
if (!tok) process.exit(1);

const si = await call('profile_schema_info', {}, tok);
check(si.status === 200 && si.body.version >= 1, 'profile_schema_info → 200 (verze ' + (si.body && si.body.version) + ')');
const ver = si.body.version, cid = TEST_COMPANY_ID, doc = { shared: {}, local: {} };

let r = await call('profile_get', { cid }, tok);
check(r.status === 200, 'profile_get → 200');
const rev0 = r.body && r.body.draft ? r.body.draft.revision : 0;
r = await call('profile_save_draft', { cid, expected_revision: rev0, schema_version: ver, doc: { shared: { identity: { displayName: 'HTTP test' } }, local: {} } }, tok);
check(r.status === 200 && r.body.revision === rev0 + 1, 'uložení se správnou revizí → 200');

r = await call('profile_save_draft', { cid, expected_revision: rev0, schema_version: ver, doc }, tok);
check(r.status === 409, 'zastaralá revize → HTTP 409 (je ' + r.status + ')');
check(r.body && r.body.code === 'PT409' && String(r.body.details || '').includes('current_revision'), 'tělo odpovědi nese kód PT409 a current_revision: ' + JSON.stringify(r.body));

r = await call('profile_save_draft', { cid, expected_revision: rev0 + 1, schema_version: 999, doc }, tok);
check(r.status === 412 && r.body.code === 'PT412', 'jiná verze schématu → HTTP 412 (je ' + r.status + ')');

r = await call('profile_save_draft', { cid, expected_revision: rev0 + 1, schema_version: ver, doc: { shared: { identity: { displayName: 'x' } }, local: {} } }, tok);
check(r.status === 422 && r.body.code === 'PT422' && String(r.body.details).includes('displayName:minLength'), 'neplatná data → HTTP 422 se seznamem chyb (je ' + r.status + ')');

r = await call('profile_confirm', { cid, expected_revision: rev0 + 1, expected_hash: 'x' }, tok);
check(r.status === 409, 'potvrzení s jiným otiskem → HTTP 409 (je ' + r.status + ')');

r = await call('profile_get', { cid: '00000000-0000-0000-0000-00000000dead' }, tok);
check(r.status === 403, 'cizí firma → HTTP 403 (je ' + r.status + ')');

r = await call('profile_get', { cid }, null);
check(r.status === 401 || r.status === 403, 'bez přihlášení (jen veřejný klíč) → 401/403 (je ' + r.status + ')');

console.log(fails ? '\nSELHALO: ' + fails : '\nVŠE V POŘÁDKU');
process.exit(fails ? 1 : 0);
