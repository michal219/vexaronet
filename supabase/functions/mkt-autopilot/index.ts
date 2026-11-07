// AI Marketing Autopilot – serverová funkce (Supabase Edge Function).
// 1) Plánovač (pg_cron -> pg_net) volá {action:'dispatch'} s hlavičkou x-vexaronet-dispatch (tajemství ve Vaultu).
// 2) Aplikace volá {action:'run'|'status', company_id} s přihlašovacím tokenem uživatele.
// Klíče (GEMINI_API_KEY, service role) jsou jen tady na serveru, nikdy v prohlížeči.
import { createClient } from 'npm:@supabase/supabase-js@2.115.0';
import { runQueue, TaskError } from './worker.js';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const db = createClient(URL_, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
const ORIGINS = [/^https:\/\/(www\.)?vexaronet\.com$/, /^https:\/\/[a-z0-9-]+\.vexaronet\.pages\.dev$/];
const uuid = (v: unknown) => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);

function cors(req: Request): Record<string, string> {
  const o = req.headers.get('origin') || '';
  return ORIGINS.some((r) => r.test(o)) ? { 'Access-Control-Allow-Origin': o, 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', Vary: 'Origin' } : {};
}

// ---------- AI (Gemini) ----------
let MODEL: string | null = null;
async function pickModel(key: string) {
  if (MODEL) return MODEL;
  const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000', { headers: { 'x-goog-api-key': key }, signal: AbortSignal.timeout(10000) });
  if (!r.ok) throw new TaskError(`AI služba nepovolila načíst modely (HTTP ${r.status}).`, r.status >= 500 || r.status === 429);
  const names = ((await r.json()).models || []).filter((m: any) => m.supportedGenerationMethods?.includes('generateContent')).map((m: any) => m.name);
  const pref = (Deno.env.get('MKT_GEMINI_MODEL') ? [Deno.env.get('MKT_GEMINI_MODEL')!] : []).concat(['gemini-3.5-flash-lite', 'gemini-3.1-flash-lite', 'gemini-2.5-flash-lite', 'gemini-2.5-flash']);
  MODEL = pref.map((n) => 'models/' + n).find((n) => names.includes(n)) || null;
  if (!MODEL) throw new TaskError('Žádný podporovaný model Gemini není pro projekt dostupný.', false);
  return MODEL;
}
const ai = {
  async generate({ system, user, schema }: { system: string; user: string; schema: unknown }) {
    const key = Deno.env.get('GEMINI_API_KEY');
    if (!key) throw new TaskError('AI služba není na serveru nastavená (chybí GEMINI_API_KEY v Supabase).', false);
    const model = await pickModel(key);
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/${model}:generateContent`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': key }, signal: AbortSignal.timeout(60000),
      body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: user }] }],
        generationConfig: { maxOutputTokens: 6000, temperature: 0.6, responseMimeType: 'application/json', responseSchema: schema } }),
    });
    if (!r.ok) {
      await r.body?.cancel();
      const retry = r.status === 429 || r.status >= 500;
      throw new TaskError(r.status === 429 ? 'AI služba je dočasně přetížená nebo vyčerpala kvótu.' : `AI služba odmítla požadavek (HTTP ${r.status}).`, retry);
    }
    const d = await r.json();
    const raw = (d?.candidates?.[0]?.content?.parts || []).filter((p: any) => !p.thought).map((p: any) => p.text || '').join('');
    let json = null; try { json = JSON.parse(raw); } catch { /* neplatný JSON */ }
    const u = d?.usageMetadata || {};
    return { json, model: model.replace(/^models\//, ''), usage: { in: u.promptTokenCount || 0, out: (u.candidatesTokenCount || 0) + (u.thoughtsTokenCount || 0) } };
  },
};

// ---------- databáze ----------
const must = <T>(r: { data: T; error: any }) => { if (r.error) throw new TaskError('Databáze: ' + r.error.message, true); return r.data; };
const pragueYmd = (d = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Prague', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
const repo = {
  async claim(cid: string | null) { const d = must(await db.rpc('mkt_worker_claim', { p_company: cid })) as any[]; return d?.[0] || null; },
  async finish(t: any, r: any) { must(await db.rpc('mkt_worker_finish', { p_task: t.id, p_lease: t.lease_token, p_ok: r.ok, p_result: r.ok ? r.result : null, p_error: r.ok ? null : r.error, p_final: !!r.final })); },
  async budget(cid: string) { return must(await db.rpc('mkt_worker_budget', { p_company: cid })) as any; },
  async insert(table: string, row: any) { return (must(await db.from(table).insert(row).select('id').single()) as any).id; },
  async insertMany(table: string, rows: any[]) { return (must(await db.from(table).insert(rows).select('id')) as any[]).map((x) => x.id); },
  async enqueue(t: any) {
    const q = t.idem_key ? db.from('mkt_tasks').upsert(t, { onConflict: 'company_id,idem_key', ignoreDuplicates: true }).select('id') : db.from('mkt_tasks').insert(t).select('id');
    const d = must(await q) as any[]; return d?.[0]?.id || null;
  },
  async log(cid: string, e: any) { await db.from('mkt_activity').insert({ company_id: cid, ...e }); },
  async chatHistory(cid: string, n: number) { const d = must(await db.from('mkt_chat').select('id,role,body,created_at').eq('company_id', cid).order('created_at', { ascending: false }).limit(n)) as any[]; return d.reverse(); },
  async context(cid: string) {
    const now = new Date(), d90 = new Date(now.getTime() - 90 * 864e5).toISOString(), d60 = new Date(now.getTime() - 60 * 864e5).toISOString().slice(0, 10), d30 = new Date(now.getTime() - 30 * 864e5).toISOString(), in14 = new Date(now.getTime() + 14 * 864e5).toISOString(), today = pragueYmd(now);
    const [prof, cust, deals, jobs, res, inv, met, upc, appr, rep, tt] = await Promise.all([
      db.from('mkt_profiles').select('business_name,industry,offer,location,audience,competitors,website,budget_monthly,goals,tone,channels,completed').eq('company_id', cid).maybeSingle(),
      db.from('customers').select('created_at', { count: 'exact' }).eq('company_id', cid).eq('archived', false).gte('created_at', d90),
      db.from('deals').select('stage,value,created_at,updated_at').eq('company_id', cid).gte('created_at', d90).limit(500),
      db.from('jobs').select('id', { count: 'exact', head: true }).eq('company_id', cid).not('status', 'in', '(done,canceled)'),
      db.from('reservations').select('id', { count: 'exact', head: true }).eq('company_id', cid).eq('canceled', false).gte('starts_at', d30),
      db.from('invoices').select('total,paid_at').eq('company_id', cid).gte('paid_at', d30).limit(500),
      db.from('mkt_metrics').select('metric,channel,value').eq('company_id', cid).gte('metric_date', d60).limit(2000),
      db.from('mkt_content').select('channel,status').eq('company_id', cid).in('status', ['pending_approval', 'approved']).gte('planned_at', now.toISOString()).lte('planned_at', in14),
      db.from('mkt_approvals').select('entity').eq('company_id', cid).eq('status', 'pending'),
      db.from('mkt_reports').select('kind,title,created_at').eq('company_id', cid).order('created_at', { ascending: false }).limit(3),
      db.from('mkt_tasks').select('title,status,kind').eq('company_id', cid).gte('created_at', new Date(now.getTime() - 24 * 36e5).toISOString()).limit(50),
    ]);
    const weeks = Array(8).fill(0); for (const c of (cust.data || []) as any[]) { const w = Math.floor((now.getTime() - Date.parse(c.created_at)) / (7 * 864e5)); if (w < 8) weeks[w]++; }
    const dl = (deals.data || []) as any[]; const won = dl.filter((d) => d.stage === 'won' && Date.parse(d.updated_at || d.created_at) > Date.parse(d30));
    const agg: Record<string, number> = {}; for (const m of (met.data || []) as any[]) { const k = `${m.metric}:${m.channel}`; agg[k] = (agg[k] || 0) + Number(m.value || 0); }
    const up: Record<string, number> = {}; for (const c of (upc.data || []) as any[]) up[c.channel] = (up[c.channel] || 0) + 1;
    const pa: Record<string, number> = {}; for (const a of (appr.data || []) as any[]) pa[a.entity] = (pa[a.entity] || 0) + 1;
    return {
      today, profile: prof.data || null,
      crm: { novi_zakaznici_90_dni: cust.count ?? null, novi_zakaznici_po_tydnech_od_nejnovejsiho: weeks, obchodni_pripady_90_dni: dl.length, vyhrane_pripady_30_dni: won.length,
        hodnota_vyhranych_30_dni_kc: won.reduce((a, d) => a + Number(d.value || 0), 0), aktivni_zakazky: jobs.count ?? null, rezervace_30_dni: res.count ?? null,
        zaplacene_faktury_30_dni_kc: ((inv.data || []) as any[]).reduce((a, i) => a + Number(i.total || 0), 0), chybi_tabulky: [cust, deals, jobs, res, inv].filter((x: any) => x.error).length },
      metrics: Object.keys(agg).length ? agg : 'Žádné marketingové metriky zatím nejsou zadané ani propojené.',
      upcoming: Object.entries(up).map(([channel, count]) => ({ channel, count })), pending: pa,
      reports: rep.data || [], today_tasks: tt.data || [],
    };
  },
};

const renderStatus = () => 'Automatický render videa (záběry, hlas, střih) zatím není připojený, proto vzniká kompletní podklad k ruční výrobě.';
const deps = { repo, ai, now: () => new Date(), renderStatus };

async function userFrom(req: Request) {
  const tok = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!tok) return null;
  const { data, error } = await db.auth.getUser(tok);
  return error || !data?.user ? null : data.user;
}

Deno.serve(async (req: Request) => {
  const h = cors(req);
  const json = (o: unknown, status = 200) => Response.json(o, { status, headers: { ...h, 'Cache-Control': 'no-store' } });
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: h });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  let b: any; try { const t = await req.text(); if (t.length > 2000) return json({ error: 'Příliš velký požadavek.' }, 413); b = JSON.parse(t || '{}'); } catch { return json({ error: 'Neplatný požadavek.' }, 400); }
  try {
    if (b.action === 'dispatch') {
      const tok = req.headers.get('x-vexaronet-dispatch') || '';
      if (!/^[a-f0-9]{64}$/.test(tok)) return json({ error: 'Unauthorized' }, 401);
      const ok = await db.rpc('mkt_worker_dispatch_ok', { p_token: tok });
      if (ok.error || ok.data !== true) return json({ error: 'Unauthorized' }, 401);
      return json(await runQueue(deps, null, Date.now() + 100_000));
    }
    const user = await userFrom(req);
    if (!user) return json({ error: 'Přihlaste se.' }, 401);
    if (!uuid(b.company_id)) return json({ error: 'Neplatná firma.' }, 400);
    const m = await db.from('company_members').select('role').eq('company_id', b.company_id).eq('user_id', user.id).maybeSingle();
    if (m.error || !m.data) return json({ error: 'K této firmě nemáte přístup.' }, 403);
    if (b.action === 'status') {
      const bud = await db.rpc('mkt_worker_budget', { p_company: b.company_id });
      return json({ ai_configured: !!Deno.env.get('GEMINI_API_KEY'), render_configured: false, publishing: { meta: false, tiktok: false, youtube: false, google_ads: false }, budget: bud.data || null });
    }
    if (b.action === 'run') {
      if (!['owner', 'admin'].includes(m.data.role)) return json({ error: 'Spouštět úlohy může vlastník nebo správce.' }, 403);
      return json(await runQueue(deps, b.company_id, Date.now() + 100_000));
    }
    return json({ error: 'Neznámá akce.' }, 400);
  } catch (e) {
    console.error('mkt-autopilot', e instanceof Error ? e.message : e);
    return json({ error: 'Požadavek se nepodařilo zpracovat. Zkuste to později.' }, 503);
  }
});
