// Testy čisté logiky Autopilota.   node tests/autopilot_core.test.mjs
import assert from 'node:assert/strict';
import ap from '../src/autopilot_core.js';
let n = 0; const t = (m, f) => { f(); n++; console.log('OK   ' + m); };

t('0,25 USD = 250 000 000 nUSD bez desetinných čísel', () => {
  assert.equal(ap.usdToNusd('0,25'), '250000000'); assert.equal(ap.usdToNusd('0.25'), '250000000');
  assert.equal(ap.usdToNusd(' 0,25 '), '250000000'); assert.equal(ap.usdToNusd('1'), '1000000000');
  assert.equal(ap.usdToNusd('0,000000001'), '1'); assert.equal(ap.usdToNusd('0'), '0');
});
t('zaokrouhlovací pasti desetinných čísel se neprojeví (0,1 + 0,2, 1,005, 0,29)', () => {
  assert.equal(ap.usdToNusd('0,3'), '300000000'); assert.equal(ap.usdToNusd('1,005'), '1005000000'); assert.equal(ap.usdToNusd('0,29'), '290000000');
});
t('neplatné vstupy a nad 50 USD se odmítnou', () => {
  for (const s of ['', 'abc', '-1', '0,2500000001', '1e3', '1,2,3', '50,000000001', '51', '999', '1000', ',5', '5,']) assert.equal(ap.usdToNusd(s), null, s);
  assert.equal(ap.usdToNusd('50'), '50000000000'); assert.equal(ap.usdToNusd(null), null);
});
t('cena za 1 M tokenů: 300 a 2 500 nUSD za token = 0,30 a 2,50 USD', () => {
  assert.equal(ap.perMillionUsd(300), 0.3); assert.equal(ap.perMillionUsd(2500), 2.5);
});
t('formát USD', () => { assert.match(ap.fmtUsd(250000000).replace(/\s/g, ' '), /^0,25 USD$/); assert.equal(ap.fmtUsd(null), '–'); assert.match(ap.fmtUsd(6200000).replace(/\s/g, ' '), /^0,0062 USD$/); });
t('přepínač má přesně požadovaných šest režimů ve správném pořadí', () => {
  assert.deepEqual(ap.MODES.map((m) => m.name), ['AI Marketing', 'AI Obchodník', 'AI CEO', 'AI Účetnictví', 'AI Weby a e-shopy', 'AI Automatizace']);
  assert.equal(new Set(ap.MODES.map((m) => m.id)).size, 6);
});
t('záložky společné více režimům zůstanou v naposledy zvoleném režimu', () => {
  assert.equal(ap.modeOfTab('finance', 'ucetnictvi'), 'ucetnictvi'); assert.equal(ap.modeOfTab('finance', 'ceo'), 'ceo');
  assert.equal(ap.modeOfTab('finance'), 'ceo'); assert.equal(ap.modeOfTab('finance', 'marketing'), 'ceo');       // marketing finance neobsahuje
  assert.equal(ap.modeOfTab('zakaznici', 'obchodnik'), 'obchodnik'); assert.equal(ap.modeOfTab('zakaznici', 'marketing'), 'marketing');
  assert.equal(ap.modeOfTab('autopilot', 'ceo'), 'home'); assert.equal(ap.modeOfTab('profil', 'ceo'), null);
  assert.equal(ap.modeOfTab('pripady'), 'obchodnik'); assert.equal(ap.modeOfTab('ucetni'), 'ucetnictvi');
});
t('hlavní záložka každého režimu patří právě tomuto režimu', () => { for (const m of ap.MODES) assert.equal(ap.modeOfTab(m.tab), m.id, m.id); });
t('stav režimů odpovídá skutečnosti: obchodník ještě není, ostatní jen omezeně', () => {
  assert.equal(ap.MODES.find((m) => m.id === 'obchodnik').state, 'soon');
  assert.ok(ap.MODES.filter((m) => m.id !== 'obchodnik').every((m) => m.state === 'lim'));
  assert.ok(ap.MODES.every((m) => m.state !== 'on'), 'žádný režim se nesmí tvářit jako plně hotový');
});
t('připravenost: placené běhy jsou možné jen když platí všechny čtyři body', () => {
  const ok = { plan_allowed: true, monthly_limit_nusd: 250000000, platform_paid_runs_enabled: true };
  assert.ok(ap.readiness(ok, true).every((r) => r.ok));
  for (const k of [{ plan_allowed: false }, { monthly_limit_nusd: null }, { monthly_limit_nusd: 0 }, { platform_paid_runs_enabled: false }])
    assert.ok(ap.readiness({ ...ok, ...k }, true).some((r) => !r.ok));
  assert.ok(ap.readiness(ok, false).some((r) => !r.ok)); assert.ok(ap.readiness(ok, null).some((r) => !r.ok));
});
console.log('\nVŠECH ' + n + ' TESTŮ PROŠLO');
