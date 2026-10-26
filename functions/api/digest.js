// Ranni prehled firmy do e-mailu (cte se i na mobilu).
// 1) Prihlaseny uzivatel: POST {cid} s tokenem -> posle zkusebni prehled hned.
// 2) Planovac (Supabase pg_cron -> pg_net) kazdou hodinu: POST s hlavickou x-cron-secret = DIGEST_SECRET.
//    Posle prehled uzivatelum, kterym prave zacina jejich hodina (digest_settings.send_hour, cesky cas).
// Nastaveni Cloudflare: RESEND_API_KEY, DIGEST_SECRET, SUPABASE_SERVICE_KEY (tajny klic, jen zde), volitelne GEMINI_API_KEY, INVITE_FROM.

const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';
const SITE = 'https://vexaronet.com';
const DONE = /done|hotov|dokon|complet|closed|cancel|zruš|zaplac|paid/i;

const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const kc = (n, cur) => `${Math.round(Number(n) || 0).toLocaleString('cs-CZ').replace(/ /g, ' ')} ${cur && cur !== 'CZK' ? cur : 'Kč'}`;

const hits = new Map();
function limited(id) {
  const now = Date.now();
  const a = (hits.get(id) || []).filter((t) => now - t < 600_000);
  a.push(now);
  hits.set(id, a);
  if (hits.size > 5000) hits.clear();
  return a.length > 6;
}

// ---- cesky cas ----
function partsIn(d) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
      .formatToParts(d).map((x) => [x.type, x.value]),
  );
  return p;
}
function offsetMs(d) {
  const p = partsIn(d);
  return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute) - Math.floor(d.getTime() / 60000) * 60000;
}
function pragueNow(now = new Date()) {
  const p = partsIn(now);
  return { ymd: `${p.year}-${p.month}-${p.day}`, hour: +p.hour };
}
function dayStartUtc(ymd) {
  const g = Date.parse(`${ymd}T00:00:00Z`);
  let s = g - offsetMs(new Date(g));
  s = g - offsetMs(new Date(s));
  return new Date(s);
}
function addDays(ymd, n) {
  const d = new Date(Date.parse(`${ymd}T12:00:00Z`) + n * 864e5);
  return d.toISOString().slice(0, 10);
}
const hm = (iso) => new Intl.DateTimeFormat('cs-CZ', { timeZone: 'Europe/Prague', hour: '2-digit', minute: '2-digit' }).format(new Date(iso));
const dm = (iso) => new Intl.DateTimeFormat('cs-CZ', { timeZone: 'Europe/Prague', day: 'numeric', month: 'numeric' }).format(new Date(iso));
const dateLong = (ymd) => new Intl.DateTimeFormat('cs-CZ', { timeZone: 'UTC', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(`${ymd}T12:00:00Z`));

// ---- data ----
async function buildDigest(H, cid, ymd) {
  const start = dayStartUtc(ymd), end = dayStartUtc(addDays(ymd, 1));
  const S = start.toISOString(), E = end.toISOString();
  const get = async (path) => {
    try {
      const r = await fetch(`${SB_URL}/rest/v1/${path}`, { headers: H });
      return r.ok ? await r.json() : [];
    } catch { return []; }
  };
  const q = (t, extra) => get(`${t}?company_id=eq.${cid}&${extra}&limit=1000`);
  const [co, tasks, res, jobs, inv, shifts, prods, moves, locs] = await Promise.all([
    get(`companies?id=eq.${cid}&select=name&limit=1`),
    q('tasks', `completed=eq.false&due_at=lt.${encodeURIComponent(E)}&select=title,due_at`),
    q('reservations', `canceled=eq.false&starts_at=gte.${encodeURIComponent(S)}&starts_at=lt.${encodeURIComponent(E)}&select=title,starts_at,location_id&order=starts_at`),
    q('jobs', `due_at=lt.${encodeURIComponent(E)}&select=title,status,due_at,location_id`),
    q('invoices', `paid_at=is.null&select=number,total,currency,due_on,customer_snapshot`),
    q('shifts', `starts_at=gte.${encodeURIComponent(S)}&starts_at=lt.${encodeURIComponent(E)}&select=person,starts_at,ends_at&order=starts_at`),
    q('products', `active=eq.true&select=id,name,unit,min_qty`),
    q('stock_moves', `select=product_id,qty,kind`),
    q('locations', `select=id,name`),
  ]);
  const lm = {};
  (locs || []).forEach((l) => { lm[l.id] = l.name; });
  const inDay = (iso) => iso && new Date(iso) >= start;
  const tToday = [], tLate = [];
  (tasks || []).forEach((t) => (inDay(t.due_at) ? tToday : tLate).push(t.title));
  const jToday = [], jLate = [];
  (jobs || []).filter((j) => j.due_at && !DONE.test(j.status || '')).forEach((j) => (inDay(j.due_at) ? jToday : jLate).push(j.title + (j.location_id && lm[j.location_id] ? ` (${lm[j.location_id]})` : '')));
  const today0 = ymd;
  const late = (inv || []).filter((i) => i.due_on && i.due_on < today0);
  const stock = {};
  (moves || []).forEach((m) => { stock[m.product_id] = (stock[m.product_id] || 0) + (Number(m.qty) || 0); });
  const low = (prods || []).filter((p) => Number(p.min_qty) > 0 && (stock[p.id] || 0) <= Number(p.min_qty)).map((p) => p.name);
  const d = {
    company: co?.[0]?.name || 'vaše firma',
    ymd,
    tasksToday: tToday, tasksLate: tLate,
    reservations: (res || []).map((r) => `${hm(r.starts_at)} ${r.title || 'Rezervace'}${r.location_id && lm[r.location_id] ? ` (${lm[r.location_id]})` : ''}`),
    jobsToday: jToday, jobsLate: jLate,
    shifts: (shifts || []).map((s) => `${s.person}: ${hm(s.starts_at)}–${hm(s.ends_at)}`),
    invLateCount: late.length,
    invLateSum: late.reduce((s, i) => s + (Number(i.total) || 0), 0),
    invLate: late.slice(0, 3).map((i) => `${i.number || ''} ${i.customer_snapshot?.name || ''} ${kc(i.total, i.currency)} (splatnost ${dm(i.due_on)})`.trim()),
    invOpenCount: (inv || []).length,
    invOpenSum: (inv || []).reduce((s, i) => s + (Number(i.total) || 0), 0),
    lowStock: low.slice(0, 8),
  };
  d.n = d.tasksToday.length + d.tasksLate.length + d.reservations.length + d.jobsToday.length + d.jobsLate.length + d.invLateCount;
  return d;
}

async function aiLine(env, d) {
  const key = env.GEMINI_API_KEY;
  if (!key || !d.n) return '';
  const model = env.GEMINI_MODEL || 'gemini-3.5-flash-lite';
  const data = { ukoly_dnes: d.tasksToday, ukoly_po_terminu: d.tasksLate, rezervace_dnes: d.reservations, zakazky_dnes: d.jobsToday, zakazky_po_terminu: d.jobsLate, faktury_po_splatnosti: d.invLate, faktury_po_splatnosti_pocet: d.invLateCount, sklad_pod_minimem: d.lowStock };
  try {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: 'Jsi AI asistent v aplikaci Vexaronet. Napiš majiteli malé české firmy 2 až 4 krátké věty prostým textem, na co se má dnes ráno soustředit nejdřív a proč. Vycházej POUZE z dat níže, nic si nevymýšlej, neslibuj, že něco uděláš. Žádný markdown, žádné pozdravy.' }] },
        contents: [{ role: 'user', parts: [{ text: JSON.stringify(data) }] }],
        generationConfig: { maxOutputTokens: 300, temperature: 0.3 },
      }),
    });
    if (!r.ok) return '';
    const j = await r.json();
    return (j?.candidates?.[0]?.content?.parts || []).map((p) => p.text || '').join('').trim().slice(0, 700);
  } catch { return ''; }
}

function render(d, ai) {
  const sec = (title, items, color) => (items.length
    ? `<h3 style="margin:18px 0 6px;font-size:15px;color:${color || '#1a1d2e'}">${esc(title)}</h3><ul style="margin:0;padding-left:18px;line-height:1.6">${items.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>`
    : '');
  const tx = (title, items) => (items.length ? `\n${title}\n${items.map((x) => `- ${x}`).join('\n')}\n` : '');
  const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#1a1d2e;font-size:15px">
<h2 style="margin:0 0 4px">Dobré ráno, ${esc(d.company)}</h2><p style="margin:0 0 14px;color:#7b8199">${esc(dateLong(d.ymd))}</p>
${ai ? `<div style="background:#f1efff;border-left:4px solid #6d5cff;padding:10px 14px;border-radius:8px;margin-bottom:6px">${esc(ai)}</div><p style="margin:0 0 6px;color:#7b8199;font-size:12px">Shrnutí vytvořila AI z vašich dat v aplikaci.</p>` : ''}
${d.n ? '' : '<p>Na dnešek nemáte v aplikaci nic naplánováno ani po termínu.</p>'}
${sec('Rezervace dnes', d.reservations)}${sec('Úkoly na dnes', d.tasksToday)}${sec('Úkoly po termínu', d.tasksLate, '#c0392b')}${sec('Zakázky s termínem dnes', d.jobsToday)}${sec('Zakázky po termínu', d.jobsLate, '#c0392b')}${sec('Směny dnes', d.shifts)}
${d.invLateCount ? sec(`Faktury po splatnosti (${d.invLateCount}, celkem ${kc(d.invLateSum)})`, d.invLate, '#c0392b') : ''}
${sec('Sklad pod minimem', d.lowStock, '#b9770e')}
<p style="margin:18px 0 0"><b>Přehled financí:</b> neuhrazeno ${d.invOpenCount} ${d.invOpenCount === 1 ? 'faktura' : d.invOpenCount < 5 ? 'faktury' : 'faktur'} za ${kc(d.invOpenSum)}.</p>
<p style="margin:22px 0"><a href="${SITE}" style="background:#6d5cff;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:bold">Otevřít Vexaronet</a></p>
<p style="color:#7b8199;font-size:12px">Ranní přehled můžete vypnout nebo změnit hodinu v aplikaci na stránce Přehled.</p></div>`;
  const text = `Dobré ráno, ${d.company}\n${dateLong(d.ymd)}\n${ai ? `\n${ai}\n(Shrnutí vytvořila AI z vašich dat.)\n` : ''}${d.n ? '' : '\nNa dnešek nemáte nic naplánováno ani po termínu.\n'}${tx('Rezervace dnes', d.reservations)}${tx('Úkoly na dnes', d.tasksToday)}${tx('Úkoly po termínu', d.tasksLate)}${tx('Zakázky s termínem dnes', d.jobsToday)}${tx('Zakázky po termínu', d.jobsLate)}${tx('Směny dnes', d.shifts)}${tx(`Faktury po splatnosti (${d.invLateCount}, celkem ${kc(d.invLateSum)})`, d.invLateCount ? d.invLate : [])}${tx('Sklad pod minimem', d.lowStock)}\nNeuhrazeno: ${d.invOpenCount} ${d.invOpenCount === 1 ? 'faktura' : d.invOpenCount < 5 ? 'faktury' : 'faktur'} za ${kc(d.invOpenSum)}.\n\n${SITE}`;
  const subject = d.n ? `Dnes ve firmě ${d.company}: ${d.n} ${d.n === 1 ? 'věc' : d.n < 5 ? 'věci' : 'věcí'} k řešení` : `Dnes ve firmě ${d.company}: klidný den`;
  return { html, text, subject };
}

async function send(env, to, d, ai, replyTo) {
  const key = env.RESEND_API_KEY;
  if (!key) return 'not_configured';
  const m = render(d, ai);
  try {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
      body: JSON.stringify({ from: env.INVITE_FROM || 'Vexaronet <info@vexaronet.com>', to: [to], subject: m.subject, html: m.html, text: m.text, ...(replyTo ? { reply_to: replyTo } : {}) }),
    });
    return r.ok ? 'sent' : `failed ${r.status}: ${(await r.text()).slice(0, 160)}`;
  } catch (e) { return `error ${String(e).slice(0, 100)}`; }
}

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  // ---- planovac ----
  const secret = req.headers.get('x-cron-secret');
  if (secret) {
    if (!env.DIGEST_SECRET || secret !== env.DIGEST_SECRET) return json({ error: 'auth' }, 401);
    const SK = env.SUPABASE_SERVICE_KEY;
    if (!SK) return json({ error: 'not_configured', message: 'Chybi SUPABASE_SERVICE_KEY.' }, 503);
    const H = { apikey: SK, authorization: `Bearer ${SK}` };
    const { ymd, hour } = pragueNow();
    let rows = [];
    try {
      const r = await fetch(`${SB_URL}/rest/v1/digest_settings?enabled=eq.true&send_hour=eq.${hour}&or=(last_sent_on.is.null,last_sent_on.lt.${ymd})&select=company_id,user_id,email&limit=200`, { headers: H });
      rows = r.ok ? await r.json() : [];
    } catch { /* nic */ }
    const cache = new Map();
    let sent = 0, failed = 0;
    for (const s of rows) {
      try {
        let to = s.email;
        if (!to) {
          const u = await fetch(`${SB_URL}/auth/v1/admin/users/${s.user_id}`, { headers: H });
          to = u.ok ? (await u.json()).email : '';
        }
        if (!to) { failed++; continue; }
        let c = cache.get(s.company_id);
        if (!c) {
          const d = await buildDigest(H, s.company_id, ymd);
          let ai = '';
          try {
            const sr = await fetch(`${SB_URL}/rest/v1/subscriptions?company_id=eq.${s.company_id}&select=plan,status&limit=1`, { headers: H });
            const sub = sr.ok ? (await sr.json())[0] : null;
            if (sub && ['pro', 'business', 'enterprise'].includes(String(sub.plan).toLowerCase())) ai = await aiLine(env, d);
          } catch { /* bez AI */ }
          c = { d, ai };
          cache.set(s.company_id, c);
        }
        const res = await send(env, to, c.d, c.ai);
        if (res === 'sent') {
          sent++;
          await fetch(`${SB_URL}/rest/v1/digest_settings?company_id=eq.${s.company_id}&user_id=eq.${s.user_id}`, {
            method: 'PATCH', headers: { ...H, 'content-type': 'application/json' }, body: JSON.stringify({ last_sent_on: ymd }),
          });
        } else failed++;
      } catch { failed++; }
    }
    return json({ ok: true, hour, due: rows.length, sent, failed });
  }

  // ---- zkusebni odeslani prihlasenym uzivatelem ----
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'auth' }, 401);
  let b;
  try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const cid = String(b?.cid || '');
  if (!/^[0-9a-f-]{36}$/i.test(cid)) return json({ error: 'bad_request' }, 400);
  const H = { apikey: SB_KEY, authorization: `Bearer ${token}` };
  let user;
  try {
    const u = await fetch(`${SB_URL}/auth/v1/user`, { headers: H });
    if (!u.ok) return json({ error: 'auth' }, 401);
    user = await u.json();
  } catch { return json({ error: 'auth' }, 401); }
  if (limited(user.id)) return json({ error: 'rate' }, 429);
  const own = await fetch(`${SB_URL}/rest/v1/company_members?company_id=eq.${cid}&user_id=eq.${user.id}&select=role&limit=1`, { headers: H }).then((r) => (r.ok ? r.json() : [])).catch(() => []);
  if (!own?.length) return json({ error: 'forbidden' }, 403);
  let to = String(b?.email || '').trim();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(to) || to.length > 200) to = user.email;
  const { ymd } = pragueNow();
  const d = await buildDigest(H, cid, ymd);
  let ai = '';
  try {
    const sr = await fetch(`${SB_URL}/rest/v1/subscriptions?company_id=eq.${cid}&select=plan&limit=1`, { headers: H });
    const sub = sr.ok ? (await sr.json())[0] : null;
    if (sub && ['pro', 'business', 'enterprise'].includes(String(sub.plan).toLowerCase())) ai = await aiLine(env, d);
  } catch { /* bez AI */ }
  const mail = await send(env, to, d, ai);
  return json({ ok: mail === 'sent', mail, to, n: d.n });
};
