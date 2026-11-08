// Odhlášení z marketingových e-mailů („Novinky Vexaronet“) bez přihlášení. Viz docs/PRAVNI_SOULAD.md, oblast 4.
// GET  /api/unsubscribe?t=TOKEN  -> přesměruje na stránku /odhlasit/ (GET nic nemění: náhledy odkazů v poště ho volají samy)
// POST /api/unsubscribe          -> {token} (JSON) nebo jedním klikem z pošty (RFC 8058: List-Unsubscribe=One-Click, token v ?t=)
// Token je náhodný, v DB je jen jeho otisk. V odkazu ani v odpovědi není e-mailová adresa.
import L from '../../src/legal_server.js';

export const onRequest = async ({ request: req }) => {
  const url = new URL(req.url);
  if (req.method === 'GET') {
    const t = url.searchParams.get('t') || '';
    return new Response(null, { status: 303, headers: { location: '/odhlasit/' + (/^[0-9a-f]{64}$/.test(t) ? '?t=' + t : ''), 'cache-control': 'no-store', 'referrer-policy': 'no-referrer' } });
  }
  if (req.method !== 'POST') return L.json({ error: 'method' }, 405);
  let token = url.searchParams.get('t') || '';
  const ct = req.headers.get('content-type') || '';
  if (ct.includes('application/json')) { try { const b = await req.json(); if (b && typeof b.token === 'string') token = b.token; } catch { return L.json({ error: 'bad_request' }, 400); } }
  if (!/^[0-9a-f]{64}$/.test(token)) return L.json({ ok: false, error: 'invalid' }, 400);
  let r;
  try { r = await L.rpc(fetch, 'marketing_unsubscribe', { p_token: token }, L.SB_KEY); } catch { return L.json({ ok: false, error: 'unavailable' }, 503); }
  if (!r.ok) return L.json({ ok: false, error: 'unavailable' }, 503);
  if (!r.data || r.data.ok !== true) return L.json({ ok: false, error: 'invalid' }, 404);
  return L.json({ ok: true, list: r.data.list || 'Novinky Vexaronet' });
};
