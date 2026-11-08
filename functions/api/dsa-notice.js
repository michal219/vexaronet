// Oznámení nezákonného obsahu podle čl. 16 DSA (veřejný formulář /nahlasit/). Viz docs/PRAVNI_SOULAD.md, oblast 6.
// Uloží oznámení (DB ověří povinné údaje), pošle oznamovateli potvrzení o přijetí s referenčním číslem a NIC NEODSTRAŇUJE:
// o obsahu rozhoduje člověk (správce platformy) přes /api/dsa-admin.
import L from '../../src/legal_server.js';

const CATS = ['csam', 'terorismus', 'nenavist', 'podvod', 'dusevni_vlastnictvi', 'osobni_udaje', 'nebezpecne_zbozi', 'spotrebitel', 'jine'];
const clip = (v, n) => (typeof v === 'string' ? v.trim().slice(0, n) : '');

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return L.json({ error: 'method' }, 405);
  let b; try { b = await req.json(); } catch { return L.json({ error: 'bad_request' }, 400); }
  if (b?.hp) return L.json({ error: 'bad_request' }, 400);                       // skryté pole proti robotům
  const urls = (Array.isArray(b?.urls) ? b.urls : [b?.urls]).map((u) => clip(u, 2000)).filter(Boolean).slice(0, 10);
  const doc = { urls, details: clip(b?.details, 2000), category: CATS.includes(b?.category) ? b.category : '', explanation: clip(b?.explanation, 5000),
    name: clip(b?.name, 200), email: clip(b?.email, 254), good_faith: b?.good_faith === true };
  const errs = [];
  if (!urls.length || urls.some((u) => !/^https?:\/\/\S+$/i.test(u))) errs.push('urls');
  if (!doc.category) errs.push('category');
  if (doc.explanation.length < 30) errs.push('explanation');
  if (doc.category !== 'csam' && (doc.name.length < 2 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(doc.email))) errs.push('identity');
  if (doc.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(doc.email)) errs.push('identity');
  if (!doc.good_faith) errs.push('good_faith');
  if (errs.length) return L.json({ error: 'invalid', fields: [...new Set(errs)] }, 400);
  const SK = String(env.SUPABASE_SERVICE_KEY || '').replace(/[\s\u200B-\u200D\u2060\uFEFF]+/g, '');
  if (!SK) return L.json({ error: 'not_configured', contact: L.dsaContact(env) }, 503);
  const r = await L.rpc(fetch, 'dsa_submit', { doc, p_ip_hash: await L.ipHash(req, SK) }, SK).catch(() => null);
  if (!r || !r.ok) {
    const m = String(r?.data?.message || '');
    if (m.includes('too_many')) return L.json({ error: 'too_many' }, 429);
    if (r && r.status === 400) return L.json({ error: 'invalid' }, 400);
    return L.json({ error: 'unavailable', contact: L.dsaContact(env) }, 503);
  }
  const { id, ref } = r.data;
  let ack = 'no_email';
  if (doc.email) {
    const text = `Dobrý den,\n\npotvrzujeme přijetí vašeho oznámení obsahu, který považujete za nezákonný.\n\nReferenční číslo: ${ref}\nOznačený obsah: ${urls.join(', ')}\n\n`
      + `Oznámení posoudí člověk z našeho týmu. Obsah neodstraňujeme automaticky jen na základě oznámení. O rozhodnutí vás budeme informovat e-mailem, včetně možností nápravy.\n`
      + `Při vyřizování nepoužíváme automatizované rozhodování.\n\nKontaktní místo: ${L.dsaContact(env)}\nVexaronet`;
    const s = await L.sendMail(env, fetch, { to: doc.email, subject: `Potvrzení přijetí oznámení ${ref}`, text });
    ack = s.ok ? 'sent' : 'failed';
    if (s.ok) await L.rpc(fetch, 'dsa_mark', { p_id: id, p_event: 'potvrzeni_odeslano' }, SK).catch(() => null);
  }
  return L.json({ ok: true, ref, ack });
};
