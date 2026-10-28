// Přihláška k novinkám: uloží do Supabase a pošle majiteli e-mail (Resend).
// Tajné klíče jsou jen v Cloudflare: RESEND_API_KEY, NOTIFY_EMAIL (volitelně NOTIFY_FROM).

let SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
let SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';

const hits = new Map();
function limited(ip) {
  const now = Date.now();
  const a = (hits.get(ip) || []).filter((t) => now - t < 600_000);
  a.push(now);
  hits.set(ip, a);
  if (hits.size > 5000) hits.clear();
  return a.length > 6;
}
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const clip = (v, n) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, n) : null);
const esc = (s) => String(s ?? '–').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);

export const onRequest = async ({ request: req, env, ...context }) => {
  context.ip = req.headers.get('cf-connecting-ip');
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const ip = context?.ip || req.headers.get('x-nf-client-connection-ip') || 'unknown';
  if (limited(ip)) return json({ error: 'rate' }, 429);

  let b;
  try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  if (b?.hp) return json({ ok: true }); // honeypot
  const email = clip(b?.email, 200)?.toLowerCase();
  const name = clip(b?.name, 120);
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !name || b?.consent !== true) return json({ error: 'bad_request' }, 400);
  const row = {
    email, name, consent: true,
    company: clip(b.company, 160), business_type: clip(b.business_type, 80),
    interested_plan: clip(b.interested_plan, 40), message: clip(b.message, 1000),
  };

  const r = await fetch(`${SB_URL}/rest/v1/newsletter_subscribers`, {
    method: 'POST',
    headers: { apikey: SB_KEY, authorization: `Bearer ${SB_KEY}`, 'content-type': 'application/json', prefer: 'return=minimal' },
    body: JSON.stringify(row),
  });
  const inquiry = b?.inquiry === true;
  if (r.status === 409 && !inquiry) return json({ ok: true, duplicate: true });
  if (!r.ok && r.status !== 409) { console.error('Supabase', r.status, await r.text()); return json({ error: 'db' }, 502); }

  const key = env.RESEND_API_KEY, to = env.NOTIFY_EMAIL;
  let mail = 'not_configured';
  if (key && to) {
    try {
      const m = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          from: env.NOTIFY_FROM || 'Vexaronet <onboarding@resend.dev>',
          to: [to],
          subject: inquiry ? `Poptávka: systém na míru – ${row.name}` : `Nová přihláška k novinkám: ${row.name}`,
          html: `<h2>${inquiry ? 'Poptávka: systém na míru (od 20 000 Kč)' : 'Nová přihláška k novinkám Vexaronet'}</h2><p><b>Jméno:</b> ${esc(row.name)}<br><b>E-mail:</b> ${esc(row.email)}<br><b>Firma:</b> ${esc(row.company)}<br><b>Obor:</b> ${esc(row.business_type)}<br><b>Tarif:</b> ${esc(row.interested_plan)}<br><b>Zpráva:</b> ${esc(row.message)}</p><p>Všechny přihlášky najdeš v Supabase, Table Editor, newsletter_subscribers.</p>`,
        }),
      });
      if (m.ok) mail = 'sent';
      else { const t = await m.text(); console.error('Resend', m.status, t); mail = `failed ${m.status}: ${t.slice(0, 160)}`; }
    } catch (e) { console.error('Resend', e); mail = 'error ' + String(e).slice(0, 100); }
  } else console.warn('E-mailové upozornění není nastaveno (RESEND_API_KEY, NOTIFY_EMAIL).');
  return json({ ok: true, mail });
};

