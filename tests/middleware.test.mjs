// functions/_middleware.js + public/_routes.json: interní cesty vrací 404 bez mezipaměti, /api/* jde dál, statické soubory funkci nevolají.
//   node tests/middleware.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { onRequest } from '../functions/_middleware.js';
const routes = JSON.parse(readFileSync(new URL('../public/_routes.json', import.meta.url)));
const env = { ASSETS: { fetch: async (u) => new Response(String(u).endsWith('/404.html') ? '<h1>404 stránka</h1>' : 'x') } };
let nextCalled = 0; const next = async () => { nextCalled++; return new Response('api'); };
const call = (p) => onRequest({ request: new Request('https://vexaronet.com' + p), next, env });
const matches = (p) => routes.include.some((r) => (r.endsWith('/*') ? p.startsWith(r.slice(0, -1)) : p === r));
for (const p of ['/docs/SECURITY_STATUS.md', '/db/migrations/20261112100000_ai_marketing.sql', '/src/ai_guard.js', '/build.py', '/tests/public_dir.py', '/functions/api/chat.js', '/schema.sql', '/README.md', '/public/index.html']) {
  assert.ok(matches(p), 'cesta je v _routes.json: ' + p);
  const r = await call(p);
  assert.equal(r.status, 404, p); assert.equal(r.headers.get('cache-control'), 'no-store'); assert.match(await r.text(), /404 stránka/);
}
console.log('OK   interní cesty (včetně 4 dříve uložených v mezipaměti) jsou v _routes.json a middleware vrací 404 bez mezipaměti');
const r = await call('/api/chat'); assert.equal(await r.text(), 'api'); assert.equal(nextCalled, 1);
console.log('OK   /api/* jde dál na serverové funkce');
for (const p of ['/', '/index.html', '/assets/vendor/supabase-js-2.45.4/supabase.js', '/podminky/', '/nahlasit/', '/sw.js', '/manifest.webmanifest', '/robots.txt'])
  assert.ok(!matches(p), 'veřejná cesta nesmí volat funkci: ' + p);
console.log('OK   veřejné stránky a prostředky funkci nevolají (statické servírování beze změny)');
assert.ok(routes.include.length <= 100 && routes.version === 1);
console.log('VŠECHNY KONTROLY PROŠLY');
