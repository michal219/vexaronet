// Propojení sociálních sítí: Facebook stránky a Instagram profesionální účty (Meta Graph API, Facebook Login for Business).
// Viz docs/SOCIALNI_SITE.md. Ověřeno proti dokumentaci Meta 2026-11-12 (Graph API v27.0).
//   POST {op:'begin', cid}                       – vlastník/správce zahájí propojení; vrátí adresu přihlášení u Meta
//   GET  ?code=…&state=…                         – návrat z Meta (OAuth callback); uloží zašifrované tokeny stránek
//   POST {op:'publish', cid, post, account, image_url?} – zveřejní SCHVÁLENÝ příspěvek na propojený účet
// Zásady:
//  * token nikdy neopouští server; do databáze jde jen zašifrovaný (AES-GCM, klíč SOCIAL_TOKEN_KEY je jen v prostředí)
//  * publikaci zahajuje člověk svým tokenem (social_publish_begin kontroluje roli a otisk schválení); server jen dokončuje
//  * nejasný výsledek (vypršení času) se NEopakuje automaticky – označí se „unknown“ a rozhodne člověk
//  * bez nastavení (META_APP_ID, META_APP_SECRET, SOCIAL_TOKEN_KEY, SUPABASE_SERVICE_KEY) vrací 503 not_configured
import VXGUARD from '../../src/ai_guard.js';

const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const SB_KEY = 'sb_publishable_Owl1zZ5ZoGJVPxkjRVAOJw_8O6mLDwW';
const GRAPH = 'https://graph.facebook.com/v27.0';
const DIALOG = 'https://www.facebook.com/v27.0/dialog/oauth';
// oprávnění: seznam stránek, publikace na stránku, základ Instagramu a publikace na Instagram
export const SCOPES = ['pages_show_list', 'pages_read_engagement', 'pages_manage_posts', 'instagram_basic', 'instagram_content_publish'];
const COOKIE = 'vx_soc';
const json = (o, s = 200, h = {}) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...h } });
const cut = (s, n) => String(s ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
const enc = new TextEncoder(), dec = new TextDecoder();
const b64 = (u8) => btoa(String.fromCharCode(...u8)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64 = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const sha256hex = async (s) => hex(await crypto.subtle.digest('SHA-256', enc.encode(s)));

async function rpc(name, args, key, token) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: key, 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(args) });
  let d = null; try { d = await r.json(); } catch { d = null; }
  return { ok: r.ok, status: r.status, data: d };
}

// ---- šifrování tokenů (AES-256-GCM; klíč = SHA-256 tajemství z prostředí; AAD váže šifru na konkrétní účet) ----
async function aesKey(secret) { return crypto.subtle.importKey('raw', await crypto.subtle.digest('SHA-256', enc.encode(secret)), 'AES-GCM', false, ['encrypt', 'decrypt']); }
export async function sealToken(secret, token, aad) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: enc.encode(aad) }, await aesKey(secret), enc.encode(token));
  return `v1.${b64(iv)}.${b64(new Uint8Array(ct))}`;
}
export async function openToken(secret, sealed, aad) {
  const p = String(sealed || '').split('.'); if (p.length !== 3 || p[0] !== 'v1') throw new Error('bad_token');
  return dec.decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(p[1]), additionalData: enc.encode(aad) }, await aesKey(secret), unb64(p[2])));
}
async function proof(token, appSecret) {
  const k = await crypto.subtle.importKey('raw', enc.encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', k, enc.encode(token)));
}

// ---- volání Graph API: token jen v hlavičce (ne v adrese), pevný časový limit ----
// Vrací {ok, data} | {ok:false, timeout:true} | {ok:false, code, message}
async function graph(method, path, params, token, appSecret) {
  const p = new URLSearchParams(params || {});
  if (token && appSecret) p.set('appsecret_proof', await proof(token, appSecret));
  const url = `${GRAPH}${path}${method === 'GET' && [...p].length ? `?${p}` : ''}`;
  let r;
  try {
    r = await fetch(url, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(method === 'POST' ? { 'content-type': 'application/x-www-form-urlencoded' } : {}) },
      body: method === 'POST' ? p.toString() : undefined, signal: AbortSignal.timeout(20000) });
  } catch { return { ok: false, timeout: true }; }
  let d = null; try { d = await r.json(); } catch { d = null; }
  if (!r.ok || d?.error) return { ok: false, status: r.status, code: Number(d?.error?.code) || 0, message: cut(d?.error?.message, 200) || `http_${r.status}` };
  return { ok: true, data: d || {} };
}
const cfg = (env) => {
  const c = { id: String(env.META_APP_ID || '').trim(), secret: String(env.META_APP_SECRET || '').trim(), key: String(env.SOCIAL_TOKEN_KEY || '').trim(), sk: VXGUARD.cleanKey(env.SUPABASE_SERVICE_KEY) };
  return /^[0-9]{5,30}$/.test(c.id) && c.secret.length >= 16 && c.key.length >= 32 && c.sk ? c : null;
};
const redirectUri = (req) => `${new URL(req.url).origin}/api/social`;
const back = (req, q) => new Response(null, { status: 302, headers: { location: `${new URL(req.url).origin}/?social=${q}`, 'cache-control': 'no-store',
  'set-cookie': `${COOKIE}=; Path=/api/social; Max-Age=0; HttpOnly; Secure; SameSite=Lax` } });
const dbErr = (r) => {
  const m = String(r.data?.message || ''), known = ['not_approved', 'account_not_found', 'image_required', 'invalid_image_url', 'text_too_long', 'already_published', 'in_progress', 'unknown_outcome', 'not_found', 'too_many_attempts', 'read_only'];
  const k = known.find((x) => m.includes(x));
  if (k) return json({ error: k }, k === 'not_approved' ? 412 : ['already_published', 'in_progress', 'unknown_outcome'].includes(k) ? 409 : k === 'too_many_attempts' ? 429 : k === 'read_only' ? 403 : k.includes('not_found') ? 404 : 422);
  if (m.includes('forbidden') || r.data?.code === '42501') return json({ error: 'forbidden' }, 403);
  if (r.status === 404 || r.data?.code === 'PGRST202') return json({ error: 'not_deployed', message: 'Propojení sítí ještě není v databázi nasazené.' }, 503);
  return json({ error: 'unavailable' }, 503);
};

// ---- návrat z Meta ----
async function callback(req, env) {
  const u = new URL(req.url), state = u.searchParams.get('state') || '', code = u.searchParams.get('code') || '';
  const c = cfg(env); if (!c) return back(req, 'not_configured');
  const ck = (req.headers.get('cookie') || '').split(/;\s*/).map((x) => x.split('=')).find((x) => x[0] === COOKIE)?.[1] || '';
  // stav musí přijít ze stejného prohlížeče, který propojení zahájil (ochrana proti podvržení cizího propojení)
  if (!/^[A-Za-z0-9_-]{40,80}$/.test(state) || ck !== state) return back(req, 'state');
  const sh = await sha256hex(state);
  if (!code) { await rpc('social_oauth_finish', { p_state_hash: sh, p_accounts: [] }, c.sk).catch(() => null); return back(req, 'denied'); }
  const t1 = await graph('GET', '/oauth/access_token', { client_id: c.id, client_secret: c.secret, redirect_uri: redirectUri(req), code });
  if (!t1.ok || !t1.data.access_token) return back(req, 'exchange');
  // dlouhodobý uživatelský token -> tokeny stránek z něj časem nevyprší
  const t2 = await graph('GET', '/oauth/access_token', { grant_type: 'fb_exchange_token', client_id: c.id, client_secret: c.secret, fb_exchange_token: t1.data.access_token });
  const userToken = t2.ok && t2.data.access_token ? t2.data.access_token : null;
  if (!userToken) return back(req, 'exchange');
  const pg = await graph('GET', '/me/accounts', { fields: 'id,name,access_token,tasks,instagram_business_account{id,username,name}', limit: '100' }, userToken, c.secret);
  if (!pg.ok) return back(req, 'pages');
  const accounts = [];
  for (const p of (Array.isArray(pg.data.data) ? pg.data.data : []).slice(0, 25)) {
    if (!p?.access_token || !/^[0-9]{1,40}$/.test(String(p.id)) || !(p.tasks || []).includes('CREATE_CONTENT')) continue;
    accounts.push({ provider: 'facebook', external_id: String(p.id), name: cut(p.name, 200) || 'Facebook stránka', username: '', token_enc: await sealToken(c.key, p.access_token, `facebook:${p.id}`) });
    const ig = p.instagram_business_account;
    if (ig && /^[0-9]{1,40}$/.test(String(ig.id))) accounts.push({ provider: 'instagram', external_id: String(ig.id), name: cut(ig.name || ig.username, 200) || 'Instagram', username: cut(ig.username, 200),
      token_enc: await sealToken(c.key, p.access_token, `instagram:${ig.id}`) });
  }
  const fin = await rpc('social_oauth_finish', { p_state_hash: sh, p_accounts: accounts }, c.sk);
  if (!fin.ok) return back(req, 'state');
  return back(req, accounts.length ? 'connected' : 'no_pages');
}

// ---- publikace ----
async function publishTo(provider, id, text, imageUrl, token, secret) {
  if (provider === 'facebook') {
    const r = await graph('POST', `/${id}/feed`, { message: text }, token, secret);
    if (!r.ok) return r;
    const l = await graph('GET', `/${r.data.id}`, { fields: 'permalink_url' }, token, secret);
    return { ok: true, id: String(r.data.id || ''), permalink: l.ok ? l.data.permalink_url : null };
  }
  const c1 = await graph('POST', `/${id}/media`, { image_url: imageUrl, caption: text }, token, secret);
  if (!c1.ok) return c1;                                            // kontejner se nezveřejňuje; chyba zde = nic nevyšlo
  for (let i = 0; i < 5; i++) {                                     // obrázek musí Meta nejdřív stáhnout a zpracovat
    const s = await graph('GET', `/${c1.data.id}`, { fields: 'status_code' }, token, secret);
    if (s.ok && s.data.status_code === 'ERROR') return { ok: false, code: 0, message: 'Instagram obrázek nepřijal (formát nebo dostupnost adresy).' };
    if (!s.ok || s.data.status_code === 'FINISHED' || !s.data.status_code) break;
    await new Promise((res) => setTimeout(res, 1500));
  }
  const r = await graph('POST', `/${id}/media_publish`, { creation_id: c1.data.id }, token, secret);
  if (!r.ok) return r;
  const l = await graph('GET', `/${r.data.id}`, { fields: 'permalink' }, token, secret);
  return { ok: true, id: String(r.data.id || ''), permalink: l.ok ? l.data.permalink : null };
}

export const onRequest = async ({ request: req, env }) => {
  if (req.method === 'GET') return callback(req, env);
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'auth' }, 401);
  let b; try { b = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  if (!['begin', 'publish'].includes(b?.op)) return json({ error: 'bad_request' }, 400);
  const g = await VXGUARD.guardAi({ fetchFn: fetch, sbUrl: SB_URL, sbKey: SB_KEY, token, cid: b?.cid, plans: ['pro', 'business', 'enterprise'] });
  if (!g.ok) return json({ error: g.error }, g.status);
  const c = cfg(env);
  if (!c) return json({ error: 'not_configured', message: 'Propojení se sítěmi Meta zatím není provozovatelem nastavené.' }, 503);

  if (b.op === 'begin') {
    const state = b64(crypto.getRandomValues(new Uint8Array(32)));
    const r = await rpc('social_oauth_begin', { cid: g.cid, p_state_hash: await sha256hex(state) }, SB_KEY, token);
    if (!r.ok) return dbErr(r);
    const q = new URLSearchParams({ client_id: c.id, redirect_uri: redirectUri(req), state, response_type: 'code', scope: SCOPES.join(',') });
    return json({ url: `${DIALOG}?${q}` }, 200, { 'set-cookie': `${COOKIE}=${state}; Path=/api/social; Max-Age=600; HttpOnly; Secure; SameSite=Lax` });
  }

  // publish
  if (!VXGUARD.UUID.test(String(b.post)) || !VXGUARD.UUID.test(String(b.account))) return json({ error: 'bad_request' }, 400);
  const img = b.image_url ? String(b.image_url).trim() : null;
  const bg = await rpc('social_publish_begin', { cid: g.cid, p_post: b.post, p_account: b.account, p_image_url: img }, SB_KEY, token);
  if (!bg.ok) return dbErr(bg);
  const pub = bg.data, fin = (st, a = {}) => rpc('social_publish_finish', { p_pub: pub.publication_id, p_status: st, ...a }, c.sk).catch(() => null);
  const tk = await rpc('social_publish_token', { p_pub: pub.publication_id }, c.sk);
  let access;
  try { access = await openToken(c.key, tk.data?.token_enc, `${pub.provider}:${pub.external_id}`); }
  catch { await fin('failed', { p_error: 'token_unreadable', p_reauth: true }); return json({ error: 'reauth', message: 'Účet je potřeba propojit znovu.' }, 409); }
  const r = await publishTo(pub.provider, pub.external_id, String(pub.text || ''), pub.image_url, access, c.secret);
  if (r.ok) {
    const f = await fin('published', { p_external_id: r.id, p_permalink: r.permalink || null });
    return json({ ok: true, status: 'published', permalink: /^https:\/\//.test(String(r.permalink || '')) ? r.permalink : null, recorded: !!f?.ok });
  }
  if (r.timeout) { await fin('unknown', { p_error: 'timeout' }); return json({ error: 'unknown_outcome', message: 'Síť neodpověděla včas. Zkontrolujte na síti, zda příspěvek vyšel, než to zkusíte znovu.' }, 504); }
  const reauth = r.code === 190 || r.code === 102;                  // neplatný nebo odvolaný token
  await fin('failed', { p_error: `${r.code || 'http'}: ${r.message}`, p_reauth: reauth });
  return json({ error: reauth ? 'reauth' : 'provider_error', message: reauth ? 'Přístup k účtu vypršel nebo byl odvolán. Propojte účet znovu.' : r.message }, reauth ? 409 : 502);
};
