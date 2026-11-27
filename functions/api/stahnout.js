// Stažení aplikace a zdrojového kódu: soubor se vydá až po zadání e-mailu a souhlasech.
// E-mail se uloží do seznamu odběratelů novinek (newsletter_subscribers) a teprve potom se vrátí zip.
// Samotné zipy leží ve public/stazeni/, ale přímý přístup na /stazeni/* blokuje functions/_middleware.js (404).

const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';
const FILES = { lokalni: 'Vexaronet-lokalni.zip', zdroj: 'Vexaronet-zdrojovy-kod.zip' };

const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const a = (hits.get(ip) || []).filter((t) => now - t < 600_000);
  a.push(now);
  hits.set(ip, a);
  if (hits.size > 5000) hits.clear();
  return a.length > 10;
}
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const ip = req.headers.get('cf-connecting-ip') || 'unknown';
  if (limited(ip)) return json({ error: 'rate' }, 429);
  let b;
  try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  if (b?.hp) return json({ error: 'bad_request' }, 400);
  const email = typeof b?.email === 'string' ? b.email.trim().toLowerCase().slice(0, 200) : '';
  const file = FILES[b?.file];
  if (!file || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || b?.consent !== true || b?.license !== true || b?.age !== true) return json({ error: 'bad_request' }, 400);

  const r = await fetch(`${SB_URL}/rest/v1/newsletter_subscribers`, {
    method: 'POST',
    headers: { apikey: SB_KEY, 'content-type': 'application/json', prefer: 'return=minimal' },
    body: JSON.stringify({ email, name: '(stažení)', consent: true, interested_plan: 'stažení zdarma' }),
  });
  if (!r.ok && r.status !== 409) { console.error('stahnout Supabase', r.status); return json({ error: 'db' }, 502); }

  const a = await env.ASSETS.fetch(new URL('/stazeni/' + file, req.url));
  if (!a.ok) { console.error('stahnout asset', a.status); return json({ error: 'asset' }, 502); }
  return new Response(a.body, { status: 200, headers: {
    'content-type': 'application/zip', 'content-disposition': `attachment; filename="${file}"`,
    'cache-control': 'no-store', 'x-robots-tag': 'noindex',
  } });
};
