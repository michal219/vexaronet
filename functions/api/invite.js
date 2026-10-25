// Pozvanka clena tymu: overi prihlaseneho uzivatele, vytvori pozvanku v databazi
// (pres funkci invite_member, ktera hlida opravneni a limity tarifu) a odesle e-mail pres Resend.
// Tajny klic RESEND_API_KEY je jen v nastaveni Cloudflare. Volitelne INVITE_FROM.

let SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
let SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';
const SITE = 'https://vexaronet.com';

const hits = new Map();
function limited(id) {
  const now = Date.now();
  const a = (hits.get(id) || []).filter((t) => now - t < 600_000);
  a.push(now);
  hits.set(id, a);
  if (hits.size > 5000) hits.clear();
  return a.length > 20;
}
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'auth' }, 401);

  let b;
  try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const cid = String(b?.cid || ''), email = String(b?.email || '').trim().toLowerCase(), role = b?.role === 'admin' ? 'admin' : 'employee';
  if (!/^[0-9a-f-]{36}$/i.test(cid) || email.length > 200) return json({ error: 'bad_request' }, 400);

  const H = { apikey: SB_KEY, authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  let user;
  try {
    const u = await fetch(`${SB_URL}/auth/v1/user`, { headers: H });
    if (!u.ok) return json({ error: 'auth' }, 401);
    user = await u.json();
  } catch { return json({ error: 'auth' }, 401); }
  if (limited(user.id)) return json({ error: 'rate' }, 429);

  // 1) pozvanka v databazi (kontroluje opravneni, roli, limit tarifu)
  const r = await fetch(`${SB_URL}/rest/v1/rpc/invite_member`, {
    method: 'POST', headers: H, body: JSON.stringify({ cid, invite_email: email, invite_role: role }),
  });
  const rd = await r.json().catch(() => null);
  if (!r.ok) return json({ error: 'invite', message: rd?.message || 'Pozvanku se nepodarilo vytvorit.' }, 400);

  // 2) e-mail
  let mail = 'not_configured';
  const key = env.RESEND_API_KEY;
  if (key) {
    try {
      let company = 'vasi firmy';
      const cr = await fetch(`${SB_URL}/rest/v1/companies?id=eq.${cid}&select=name&limit=1`, { headers: H });
      const cd = await cr.json().catch(() => []);
      if (cd?.[0]?.name) company = cd[0].name;
      const who = user.user_metadata?.full_name || user.email;
      const subject = `Pozvánka do firmy ${company} ve Vexaronetu`;
      const text = `Dobrý den,\n${who} Vás zve do firmy ${company} ve Vexaronetu.\n\n1. Otevřete ${SITE} a klikněte na Přihlášení, pak na Registrace.\n2. Zaškrtněte, že jste pozvaný/á do firmy zaměstnavatele.\n3. Registrujte se přesně tímto e-mailem: ${email}\n4. Potvrďte e-mail (přijde Vám odkaz) a přihlaste se.\n\nPo přihlášení uvidíte firmu ${company}.\n\nVexaronet`;
      const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#1a1d2e"><h2 style="margin:0 0 12px">Pozvánka do firmy ${esc(company)}</h2><p>${esc(who)} Vás zve do firmy <b>${esc(company)}</b> ve Vexaronetu.</p><ol style="line-height:1.6"><li>Otevřete <a href="${SITE}">${SITE.replace('https://', '')}</a> a klikněte na <b>Přihlášení</b>, pak na <b>Registrace</b>.</li><li>Zaškrtněte, že jste pozvaný/á do firmy zaměstnavatele.</li><li>Registrujte se přesně tímto e-mailem: <b>${esc(email)}</b></li><li>Potvrďte e-mail (přijde Vám odkaz) a přihlaste se.</li></ol><p>Po přihlášení uvidíte firmu ${esc(company)}.</p><p style="margin:24px 0"><a href="${SITE}" style="background:#6d5cff;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:bold">Otevřít Vexaronet</a></p><p style="color:#7b8199;font-size:12px">Pokud jste pozvánku nečekali, e-mail ignorujte.</p></div>`;
      const m = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
        body: JSON.stringify({ from: env.INVITE_FROM || 'Vexaronet <info@vexaronet.com>', to: [email], reply_to: user.email, subject, html, text }),
      });
      mail = m.ok ? 'sent' : `failed ${m.status}: ${(await m.text()).slice(0, 160)}`;
    } catch (e) { mail = `error ${String(e).slice(0, 100)}`; }
  }
  return json({ ok: true, mail });
};
