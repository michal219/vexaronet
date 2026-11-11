// Převod bankovního výpisu CSV (src/bank_csv.js).   node tests/bank_csv.test.mjs
import assert from 'node:assert/strict';
import B from '../src/bank_csv.js';
let n = 0; const t = (name, fn) => { fn(); n++; console.log('OK   ' + name); };
t('částky: 1 234,50 / -99.90 / 1.234,5 / +15 a odmítnutí nesmyslu', () => {
  assert.equal(B.toCents('1 234,50'), 123450); assert.equal(B.toCents('-99.90'), -9990); assert.equal(B.toCents('1.234,5'), 123450); assert.equal(B.toCents('+15'), 1500);
  assert.equal(B.toCents('0,07'), 7); assert.equal(B.toCents('12,345.67'), 1234567); assert.equal(B.toCents('abc'), null); assert.equal(B.toCents('1,2,3'), null);
});
t('výpis ve stylu Fio (úvodní řádky, středník, uvozovky, ID pohybu)', () => {
  const csv = '﻿"Výpis č. 11/2026";"";""\n"Majitel účtu: Test"\n\n"ID pohybu";"Datum";"Objem";"Měna";"Protiúčet";"VS";"Zpráva pro příjemce"\n'
    + '"26001";"05.11.2026";"2420,00";"CZK";"123/0100";"0020260001";"Faktura; servis"\n"26002";"06.11.2026";"-350,50";"CZK";"";"";"Nákup"\n';
  const r = B.parse(csv); assert.equal(r.errors.length, 0);
  assert.deepEqual(r.rows[0], { external_id: '26001', booked_on: '2026-11-05', amount_cents: '242000', currency: 'CZK', variable_symbol: '20260001', description: 'Faktura; servis' });
  assert.equal(r.rows[1].amount_cents, '-35050'); assert.equal(r.rows[1].variable_symbol, '');
});
t('výpis bez ID: stabilní ID i pro dva shodné pohyby, čárka jako oddělovač, ISO datum', () => {
  const csv = 'date,amount,currency,variable symbol,description\n2026-11-05,100.00,CZK,123,a\n2026-11-05,100.00,CZK,123,b\n2026-11-06,50,EUR,,c\n';
  const a = B.parse(csv), b = B.parse(csv);
  assert.deepEqual(a.rows.map((x) => x.external_id), ['r:2026-11-05:10000:123:1', 'r:2026-11-05:10000:123:2', 'r:2026-11-06:5000::1']); assert.deepEqual(a.rows, b.rows);
});
t('nečitelné řádky, nulové pohyby a nepodporovaná měna se přeskočí a ohlásí', () => {
  const r = B.parse('Datum;Částka;Měna\n1.11.2026;abc;CZK\n2.11.2026;0;CZK\n3.11.2026;10;USD\n4.11.2026;10;CZK\n');
  assert.equal(r.rows.length, 1); assert.equal(r.skipped, 3); assert.equal(r.errors.length, 2);
});
t('soubor bez hlavičky s datem a částkou se odmítne', () => { assert.equal(B.parse('a;b\n1;2\n').rows.length, 0); assert.ok(B.parse('a;b\n1;2\n').errors[0].includes('nenašli')); });
console.log(`VŠECH ${n} TESTŮ PROŠLO`);
