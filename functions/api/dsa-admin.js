// Vyřizování oznámení DSA správcem platformy (čl. 16 odst. 5 a 6, čl. 17). Viz docs/PRAVNI_SOULAD.md, oblast 6.
//  POST {action:'list', status?} | {action:'review', id} | {action:'decide', id, decision, ground, reason}
// Oprávnění ověřuje databáze (private.platform_admins) podle tokenu přihlášeného uživatele.
// Rozhodnutí obsah NEMĚNÍ: omezení (odstranění, znepřístupnění…) provede správce ručně v aplikaci podle zapsaného rozhodnutí.
// Po rozhodnutí se pošle vyrozumění oznamovateli a u omezení odůvodnění provozovateli dotčeného obsahu (vlastníkům firmy).
import L from '../../src/legal_server.js';

const DEC = { bez_opatreni: 'bez opatření (obsah zůstává dostupný)', odstraneni: 'odstranění obsahu', znepristupneni: 'znepřístupnění obsahu',
  omezeni_viditelnosti: 'omezení viditelnosti obsahu', pozastaveni_sluzby: 'pozastavení poskytování služby', predano_organum: 'předání příslušným orgánům' };
const GROUND = { nezakonny_obsah: 'obsah je podle našeho posouzení nezákonný', smluvni_podminky: 'obsah je v rozporu s obchodními podmínkami', neodpovida: 'oznámení nebylo shledáno důvodným' };

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return L.json({ error: 'method' }, 405);
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return L.json({ error: 'auth' }, 401);
  let b; try { b = await req.json(); } catch { return L.json({ error: 'bad_request' }, 400); }
  const call = (fn, args) => L.rpc(fetch, fn, args, L.SB_KEY, token);
  const deny = (r) => L.json({ error: r.status === 401 ? 'auth' : String(r.data?.message || '').includes('forbidden') || r.data?.code === '42501' ? 'forbidden' : 'failed', message: String(r.data?.message || '').slice(0, 120) }, r.status === 401 ? 401 : 403);
  if (b?.action === 'list') { const r = await call('dsa_admin_list', { p_status: b.status || null }); return r.ok ? L.json({ ok: true, notices: r.data }) : deny(r); }
  if (b?.action === 'review') { const r = await call('dsa_admin_review', { p_id: b.id }); return r.ok ? L.json({ ok: true }) : deny(r); }
  if (b?.action !== 'decide') return L.json({ error: 'bad_request' }, 400);
  if (!DEC[b.decision] || !GROUND[b.ground]) return L.json({ error: 'bad_request' }, 400);
  const r = await call('dsa_admin_decide', { p_id: b.id, p_decision: b.decision, p_ground: b.ground, p_reason: String(b.reason || '') });
  if (!r.ok) return deny(r);
  const d = r.data, contact = L.dsaContact(env), out = { ok: true, ref: d.ref, notifier: 'none', uploader: 'none' };
  // vyrozumění oznamovatele (čl. 16 odst. 5)
  if (d.notifier_email) {
    const s = await L.sendMail(env, fetch, { to: d.notifier_email, subject: `Rozhodnutí o oznámení ${d.ref}`,
      text: `Dobrý den,\n\nk vašemu oznámení ${d.ref} (${(d.urls || []).join(', ')}) jsme rozhodli: ${DEC[d.decision]}.\nDůvod: ${GROUND[d.ground]}. ${d.reason}\n\n`
        + `Rozhodnutí přijal člověk, bez automatizovaného rozhodování. Pokud s ním nesouhlasíte, odpovězte na ${contact} a uveďte referenční číslo; rozhodnutí znovu posoudíme. `
        + `Máte také právo obrátit se na soud nebo na koordinátora digitálních služeb (dozorový orgán podle nařízení o digitálních službách).\n\nVexaronet` });
    out.notifier = s.ok ? 'sent' : 'failed';
    if (s.ok) await call('dsa_mark', { p_id: b.id, p_event: 'oznamovatel_vyrozumen' }).catch(() => null);
  }
  // odůvodnění dotčenému provozovateli obsahu (čl. 17) – jen u omezení a jen když je firma známá
  if (d.decision !== 'bez_opatreni' && d.target_company_id && env.SUPABASE_SERVICE_KEY) {
    const SK = String(env.SUPABASE_SERVICE_KEY || '').replace(/[\s\u200B-\u200D\u2060\uFEFF]+/g, ''), H = { apikey: SK };
    const own = await fetch(`${L.SB_URL}/rest/v1/company_members?company_id=eq.${d.target_company_id}&role=eq.owner&select=user_id`, { headers: H }).then((x) => (x.ok ? x.json() : [])).catch(() => []);
    let sentAny = false;
    for (const o of own.slice(0, 3)) {
      const u = await fetch(`${L.SB_URL}/auth/v1/admin/users/${o.user_id}`, { headers: H }).then((x) => (x.ok ? x.json() : null)).catch(() => null);
      if (!u?.email) continue;
      const s = await L.sendMail(env, fetch, { to: u.email, subject: `Odůvodnění omezení obsahu (${d.ref})`,
        text: `Dobrý den,\n\nna základě oznámení podaného podle čl. 16 nařízení (EU) 2022/2065 jsme u obsahu ${(d.urls || []).join(', ')} rozhodli: ${DEC[d.decision]}.\n`
          + `Důvod: ${GROUND[d.ground]}.\nSkutečnosti a odůvodnění: ${d.reason}\nRozhodnutí přijal člověk, bez automatizovaného rozhodování.\n\n`
          + `Možnosti nápravy: odpovězte na ${contact} s referenčním číslem ${d.ref} a doložte, proč obsah nezákonný není; rozhodnutí znovu posoudíme. `
          + `Můžete se také obrátit na soud nebo na koordinátora digitálních služeb (dozorový orgán podle nařízení o digitálních službách).\n\nVexaronet` });
      sentAny = sentAny || s.ok;
    }
    out.uploader = sentAny ? 'sent' : 'failed';
    if (sentAny) await call('dsa_mark', { p_id: b.id, p_event: 'poskytovatel_obsahu_vyrozumen' }).catch(() => null);
  }
  return L.json(out);
};
