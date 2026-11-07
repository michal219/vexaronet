// Testy čisté logiky profilu firmy. Importuje moduly tak, jak je bude importovat Cloudflare (ES modul + JSON),
// takže zároveň ověřuje, že tytéž soubory fungují mimo prohlížeč.   node tests/profile_core.test.mjs
import assert from 'node:assert/strict';
import core from '../src/profile_core.js';
import J from '../src/jsonschema_mini.js';
import schema from '../src/onboarding_schema.json' with { type: 'json' };

let n = 0;
const t = (name, fn) => { fn(); n++; console.log('OK   ' + name); };
const A = '11111111-1111-1111-1111-111111111111', B = '22222222-2222-2222-2222-222222222222', C = '33333333-3333-3333-3333-333333333333';
const row = (id, role, parent, at) => ({ company_id: id, role, companies: { id, name: id, parent_company_id: parent, created_at: at } });

t('schéma používá jen podporovaná klíčová slova a má celočíselnou verzi', () => {
  assert.ok(Number.isInteger(schema.version) && schema.version >= 1);
  J.validate(schema.shared, {}, '$'); J.validate(schema.local, {}, '$');          // vyhodí výjimku při neznámém klíčovém slově
  const walk = (s) => { for (const k of Object.keys(s)) if (!['type','enum','minLength','maxLength','minimum','maximum','minItems','maxItems','items','properties','required','additionalProperties','format','title','version'].includes(k)) throw new Error('klíč ' + k); Object.values(s.properties || {}).forEach(walk); if (s.items) walk(s.items); };
  walk(schema.shared); walk(schema.local);
});

t('pickCompany: výsledek nezávisí na pořadí řádků z databáze', () => {
  const rows = [row(B, 'owner', A, '2026-10-05'), row(A, 'owner', null, '2026-10-01'), row(C, 'admin', null, '2026-09-01')];
  const perms = [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]];
  for (const p of perms) assert.equal(core.pickCompany(p.map((i) => rows[i]), null), A);   // hlavní firma, kde je majitelem
});
t('pickCompany: platná uložená volba má přednost, neplatná se ignoruje', () => {
  const rows = [row(A, 'owner', null, '2026-10-01'), row(B, 'owner', A, '2026-10-05')];
  assert.equal(core.pickCompany(rows, B), B);
  assert.equal(core.pickCompany(rows, '99999999-9999-9999-9999-999999999999'), A);
  assert.equal(core.pickCompany(rows, ''), A);
});
t('pickCompany: bez majitelství bere nejstarší hlavní firmu, pak nejstarší členství; při shodě rozhodne id', () => {
  assert.equal(core.pickCompany([row(B, 'admin', A, '2026-10-05'), row(C, 'admin', null, '2026-10-02')], null), C);
  assert.equal(core.pickCompany([row(B, 'admin', A, '2026-10-05'), row(C, 'employee', A, '2026-10-02')], null), C);
  assert.equal(core.pickCompany([row(C, 'admin', null, '2026-10-01'), row(A, 'admin', null, '2026-10-01')], null), A);
  assert.equal(core.pickCompany([{ company_id: B, role: 'owner' }, { company_id: A, role: 'owner' }], null), A);   // bez připojené firmy (záloha)
  assert.equal(core.pickCompany([], null), null);
  assert.equal(core.pickCompany(null, null), null);
});

t('mapRpcError: konflikt revize se pozná explicitně z kódu PT409, ze stavu 409 i z textu', () => {
  for (const e of [{ code: 'PT409' }, { status: 409 }, { message: 'revision_conflict' }, { code: 'PT409', status: 409, message: 'x' }])
    assert.equal(core.mapRpcError(e).kind, 'conflict');
  assert.equal(core.mapRpcError({ code: 'PT409', details: '{"current_revision": 7}' }).current, 7);
  assert.equal(core.mapRpcError({ code: 'PT409', details: 'ne-json' }).current, null);
  assert.equal(core.mapRpcError({ code: 'PT409', details: { current_revision: 3 } }).current, 3);
});
t('mapRpcError: ostatní druhy chyb', () => {
  assert.equal(core.mapRpcError({ code: 'PT412' }).kind, 'schema');
  assert.equal(core.mapRpcError({ message: 'schema_mismatch' }).kind, 'schema');
  const v = core.mapRpcError({ code: 'PT422', details: '["$.shared.identity.displayName:minLength"]' });
  assert.equal(v.kind, 'validation'); assert.deepEqual(v.errors, ['$.shared.identity.displayName:minLength']);
  assert.equal(core.mapRpcError({ code: '42501' }).kind, 'forbidden');
  assert.equal(core.mapRpcError({ status: 401 }).kind, 'forbidden');
  assert.equal(core.mapRpcError({ message: 'síť' }).kind, 'other');
  assert.equal(core.mapRpcError(null).kind, 'other');
});

t('cíl: 146 000 Kč + 35 % = 197 100 Kč (v haléřích), rozdíl 51 100 Kč', () => {
  assert.equal(core.goalTarget(14600000, 3500), 19710000);
  assert.equal(core.goalTarget(14600000, 3500) - 14600000, 5110000);
  assert.equal(core.goalTarget(999999999999, 100000), 10999999999989);               // přes 2^53 by Number selhal
});
t('applyDerived přepíše klientský cíl výpočtem a nemění vstup', () => {
  const doc = { shared: { goals: [{ metric: 'revenue', baselineMinor: 14600000, growthBp: 3500, targetMinor: 1 }] } };
  const copy = JSON.stringify(doc), out = core.applyDerived(doc);
  assert.equal(out.shared.goals[0].targetMinor, 19710000); assert.equal(out.shared.goals[0].targetSource, 'calc'); assert.equal(JSON.stringify(doc), copy);
});

t('validateDoc: pobočka nesmí mít společné údaje; neznámá sekce se odmítne', () => {
  assert.deepEqual(core.validateDoc(schema, { local: { geography: { city: 'Beroun' } } }, false), []);
  assert.deepEqual(core.validateDoc(schema, { shared: { identity: { displayName: 'Xx' } } }, false), ['$.shared:branch_not_allowed']);
  assert.deepEqual(core.validateDoc(schema, { x: 1 }, true), ['$.x:additional']);
});
t('validateDoc: web s přihlašovacími údaji a datum 30. 2. se odmítnou', () => {
  assert.deepEqual(core.validateDoc(schema, { shared: { identity: { website: 'https://u:p@x.cz' } } }, true), ['$.shared.identity.website:format']);
  assert.deepEqual(core.validateDoc(schema, { shared: { goals: [{ metric: 'jobs', dueDate: '2026-02-30' }] } }, true), ['$.shared.goals[0].dueDate:format']);
});
t('incomplete: prázdný profil a úplný profil', () => {
  assert.ok(core.incomplete({}, true).includes('shared.identity.displayName:required'));
  assert.deepEqual(core.incomplete({ local: {} }, false), ['local.geography:required']);
  assert.deepEqual(core.incomplete({ shared: { identity: { displayName: 'A1' }, services: { items: [{ name: 'Sl' }] }, audience: { description: 'Z' } }, local: { geography: { city: 'P' } } }, true), []);
});
t('částky: nula je skutečná nula a vyžaduje měnu, prázdná hodnota ne', () => {
  const base = { shared: { identity: { displayName: 'A1' }, services: { items: [{ name: 'Sl' }] }, audience: { description: 'Z' } }, local: { geography: { city: 'P' } } };
  const z = JSON.parse(JSON.stringify(base)); z.shared.financialContext = { revenueMinor: 0 };
  assert.ok(core.incomplete(z, true).includes('shared.financialContext.revenueCurrency:required'));
  const nl = JSON.parse(JSON.stringify(base)); nl.shared.financialContext = { revenueMinor: null };
  assert.deepEqual(core.incomplete(nl, true), []);
});
t('trimDeep: ořezává jen mezery, tab a nové řádky, klíče nechá', () => {
  assert.deepEqual(core.trimDeep({ ' k ': ' v\n', a: ['\t x '] }), { ' k ': 'v', a: ['x'] });
  assert.equal(core.trimDeep(' x '), ' x ');
});

console.log('\nVŠECH ' + n + ' TESTŮ PROŠLO');
