// Marketingové e-maily „Novinky Vexaronet“: naplánování (správce platformy) a odeslání dávky (plánovač). Viz docs/PRAVNI_SOULAD.md, oblast 4.
//  POST {action:'queue', subject, body, scheduled_at?}  s tokenem správce platformy -> naplánuje zprávu (DB ověří správce)
//  POST {action:'dispatch'} s hlavičkou x-dispatch-secret = MARKETING_DISPATCH_SECRET -> odešle jednu dávku
// Odhlášení se vynucuje v DB (výběr dávky + kontrola těsně před každým odesláním), takže platí i pro dříve naplánované zprávy.
// Bez identifikace odesílatele (OPERATOR_NAME, OPERATOR_ADDRESS) se nic neodešle (§ 7 odst. 4 písm. b) zák. č. 480/2004 Sb.).
import L from '../../src/legal_server.js';

export function composeMail(env, msg, token) {
  const unsubPage = `${L.SITE}/odhlasit/?t=${token}`, oneClick = `${L.SITE}/api/unsubscribe?t=${token}`;
  const who = `${env.OPERATOR_NAME}, ${env.OPERATOR_ADDRESS}`, contact = L.dsaContact(env);
  const text = `Obchodní sdělení – Novinky Vexaronet\n\n${msg.body_text}\n\n—\nOdesílatel: ${who}. Kontakt: ${contact}.\n`
    + `Tento e-mail dostáváte, protože jste se přihlásili k odběru novinek o vývoji Vexaronetu.\nOdhlásit se můžete jedním kliknutím: ${unsubPage}\n`;
  const html = `<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto;color:#1a1d2e"><p style="font-size:12px;color:#666;margin:0 0 12px">Obchodní sdělení – Novinky Vexaronet</p>`
    + `<div style="white-space:pre-wrap">${L.esc(msg.body_text)}</div><hr style="border:0;border-top:1px solid #ddd;margin:24px 0">`
    + `<p style="font-size:12px;color:#555">Odesílatel: ${L.esc(who)}. Kontakt: ${L.esc(contact)}.<br>Tento e-mail dostáváte, protože jste se přihlásili k odběru novinek o vývoji Vexaronetu.<br>`
    + `<a href="${unsubPage}">Odhlásit se z novinek</a></p></div>`;
  return { subject: `Novinky Vexaronet: ${msg.subject}`, text, html,
    headers: { 'List-Unsubscribe': `<${oneClick}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' } };
}

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return L.json({ error: 'method' }, 405);
  let b; try { b = await req.json(); } catch { return L.json({ error: 'bad_request' }, 400); }

  if (b?.action === 'queue') {
    const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (!token) return L.json({ error: 'auth' }, 401);
    const subject = String(b.subject || '').trim(), body = String(b.body || '').trim();
    if (subject.length < 3 || subject.length > 150 || body.length < 10 || body.length > 20000) return L.json({ error: 'bad_request' }, 400);
    const when = b.scheduled_at && !isNaN(new Date(b.scheduled_at)) ? new Date(b.scheduled_at).toISOString() : new Date().toISOString();
    const r = await L.rpc(fetch, 'marketing_queue', { p_subject: subject, p_body: body, p_scheduled_at: when }, L.SB_KEY, token);
    if (!r.ok) return L.json({ error: r.status === 401 || String(r.data?.message || '').includes('forbidden') ? 'forbidden' : 'failed' }, r.status === 401 ? 401 : 403);
    return L.json({ ok: true, id: r.data, scheduled_at: when });
  }

  if (b?.action === 'dispatch') {
    if (!env.MARKETING_DISPATCH_SECRET || req.headers.get('x-dispatch-secret') !== env.MARKETING_DISPATCH_SECRET) return L.json({ error: 'auth' }, 401);
    const missing = ['SUPABASE_SERVICE_KEY', 'RESEND_API_KEY', 'OPERATOR_NAME', 'OPERATOR_ADDRESS'].filter((k) => !env[k]);
    if (missing.length) return L.json({ error: 'not_configured', missing }, 503);
    const SK = String(env.SUPABASE_SERVICE_KEY || '').replace(/[\s\u200B-\u200D\u2060\uFEFF]+/g, '');
    const c = await L.rpc(fetch, 'marketing_claim', { p_limit: Math.min(50, Math.max(1, Number(b.limit) || 20)) }, SK);
    if (!c.ok) return L.json({ error: 'unavailable' }, 503);
    const msg = c.data?.message, list = Array.isArray(c.data?.recipients) ? c.data.recipients : [];
    if (!msg) return L.json({ ok: true, message: null, sent: 0, skipped: 0 });
    let sent = 0, skipped = 0;
    for (const rc of list) {
      const allowed = await L.rpc(fetch, 'marketing_send_allowed', { p_message: msg.id, p_email: rc.email }, SK);
      if (!allowed.ok || allowed.data !== true) {
        await L.rpc(fetch, 'marketing_finish', { p_message: msg.id, p_email: rc.email, p_provider_id: null, p_skipped: 'odhlaseno_nebo_bez_souhlasu' }, SK); skipped++; continue;
      }
      const m = composeMail(env, msg, rc.token);
      const s = await L.sendMail(env, fetch, { to: rc.email, ...m });
      await L.rpc(fetch, 'marketing_finish', { p_message: msg.id, p_email: rc.email, p_provider_id: s.ok ? (s.id || 'sent') : null, p_skipped: s.ok ? null : 'chyba_odeslani' }, SK);
      if (s.ok) sent++; else skipped++;
    }
    return L.json({ ok: true, message: msg.id, sent, skipped });
  }
  return L.json({ error: 'bad_request' }, 400);
};
