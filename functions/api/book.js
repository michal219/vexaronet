// Verejna online rezervace: zavola databazovou funkci public_book (hlida kapacitu a limity)
// a po uspechu odesle zakaznikovi potvrzeni e-mailem pres Resend (soubor .ics do kalendare).
// E-mail se odesila jen po uspesne rezervaci a jen na adresu zadanou v rezervaci.
// Tajny klic RESEND_API_KEY je jen v nastaveni Cloudflare. Volitelne INVITE_FROM.

const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';

const hits = new Map();
function limited(id) {
  const now = Date.now();
  const a = (hits.get(id) || []).filter((t) => now - t < 600_000);
  a.push(now);
  hits.set(id, a);
  if (hits.size > 5000) hits.clear();
  return a.length > 10;
}
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const icsDate = (d) => new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsText = (s) => String(s ?? '').replace(/[\;,]/g, (c) => '\\' + c).replace(/\r?\n/g, '\\n');
const b64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  let b;
  try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const slug = String(b?.slug || '').toLowerCase(), service = String(b?.service || ''), start = String(b?.start || '');
  const name = String(b?.name || '').trim(), email = String(b?.email || '').trim(), phone = b?.phone ? String(b.phone).trim() : null;
  if (!/^[a-z0-9][a-z0-9-]{2,40}$/.test(slug) || !/^[0-9a-f-]{36}$/i.test(service) || isNaN(new Date(start)) || name.length > 120 || email.length > 200)
    return json({ error: 'bad_request' }, 400);
  const ip = req.headers.get('cf-connecting-ip') || 'x';
  if (limited(ip)) return json({ error: 'too_many' }, 429);

  const H = { apikey: SB_KEY, authorization: `Bearer ${SB_KEY}`, 'content-type': 'application/json' };
  let data;
  try {
    const r = await fetch(`${SB_URL}/rest/v1/rpc/public_book`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ p_slug: slug, p_service: service, p_start: start, p_name: name, p_email: email, p_phone: phone }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok || !j) {
      const m = String(j?.message || '');
      const code = ['slot_taken', 'bad_email', 'bad_name', 'bad_phone', 'too_many', 'not_found'].find((c) => m.includes(c)) || 'failed';
      return json({ error: code }, code === 'failed' ? 502 : 400);
    }
    data = j;
  } catch { return json({ error: 'failed' }, 502); }

  let mail = 'skipped';
  const key = env.RESEND_API_KEY;
  if (key) {
    try {
      let info = {};
      const ir = await fetch(`${SB_URL}/rest/v1/rpc/public_booking_info`, { method: 'POST', headers: H, body: JSON.stringify({ p_slug: slug }) });
      if (ir.ok) info = (await ir.json().catch(() => null)) || {};
      const biz = data.business || info.name || 'provozovna';
      const when = new Date(data.start);
      const day = when.toLocaleDateString('cs-CZ', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Prague' });
      const time = when.toLocaleTimeString('cs-CZ', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Prague' });
      const where = [info.address, info.phone].filter(Boolean).join(' · ');
      const subject = `Potvrzení rezervace: ${data.service}, ${day} v ${time}`;
      const text = `Dobrý den, ${name},\n\nvaše rezervace je uložená.\n\nSlužba: ${data.service}\nTermín: ${day} v ${time}\nKde: ${biz}${where ? ' (' + where + ')' : ''}\n\nPokud nemůžete přijít, dejte provozovně včas vědět${info.phone ? ' na telefonu ' + info.phone : ''}.\n\nTento e-mail byl odeslán přes Vexaronet.`;
      const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#1a1d2e"><h2 style="margin:0 0 12px">Rezervace je uložená</h2><p>Dobrý den, ${esc(name)},</p><table style="border-collapse:collapse;margin:12px 0"><tr><td style="padding:4px 14px 4px 0;color:#7b8199">Služba</td><td><b>${esc(data.service)}</b></td></tr><tr><td style="padding:4px 14px 4px 0;color:#7b8199">Termín</td><td><b>${esc(day)} v ${esc(time)}</b></td></tr><tr><td style="padding:4px 14px 4px 0;color:#7b8199">Kde</td><td>${esc(biz)}${where ? '<br>' + esc(where) : ''}</td></tr></table><p>Pokud nemůžete přijít, dejte provozovně včas vědět${info.phone ? ' na telefonu <b>' + esc(info.phone) + '</b>' : ''}.</p><p style="color:#7b8199;font-size:12px">E-mail byl odeslán přes Vexaronet na základě vaší rezervace. Pokud jste rezervaci nevytvořili, ignorujte ho.</p></div>`;
      const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Vexaronet//CS', 'BEGIN:VEVENT', `UID:${crypto.randomUUID()}@vexaronet.com`, `DTSTAMP:${icsDate(Date.now())}`, `DTSTART:${icsDate(data.start)}`, `DTEND:${icsDate(data.end || data.start)}`, `SUMMARY:${icsText(data.service + ' – ' + biz)}`, `LOCATION:${icsText(info.address || biz)}`, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
      const m = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
        body: JSON.stringify({ from: env.INVITE_FROM || 'Vexaronet <info@vexaronet.com>', to: [email], subject, html, text, attachments: [{ filename: 'rezervace.ics', content: b64(ics) }] }),
      });
      mail = m.ok ? 'sent' : 'failed';
    } catch { mail = 'failed'; }
  }
  return json({ ...data, mail });
};
