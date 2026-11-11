// Veřejný stav vývojové fáze (počet volných míst pro firmy, datum spuštění) přes vlastní doménu:
// prohlížeč tak při načtení úvodní stránky nekontaktuje cizí server. Data: public.registration_status() (jen čtení).
// Limit samotný vynucuje databáze (trigger na public.companies), tento endpoint nic nemění.
const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';
const json = (o, s = 200, cache = 'no-store') => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': cache } });
export const onRequest = async ({ request: req }) => {
  if (req.method !== 'GET') return json({ error: 'method' }, 405);
  try {
    const r = await fetch(`${SB_URL}/rest/v1/rpc/registration_status`, { method: 'POST', headers: { apikey: SB_KEY, 'content-type': 'application/json' }, body: '{}' });
    if (!r.ok) return json({ error: 'unavailable' }, 503);
    const d = await r.json();
    if (!d || typeof d !== 'object') return json({ error: 'unavailable' }, 503);
    const out = { limited: !!d.limited, open: d.open !== false, launch_on: /^\d{4}-\d{2}-\d{2}$/.test(String(d.launch_on)) ? d.launch_on : null };
    if (d.limited) { out.max = Number(d.max) || 0; out.remaining = Math.max(0, Number(d.remaining) || 0); }
    return json(out, 200, 'public, max-age=30');
  } catch { return json({ error: 'unavailable' }, 503); }
};
