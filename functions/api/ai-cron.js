// Běh AI úloh na pozadí (bez prohlížeče): spouští plánovač (pg_cron + pg_net) s hlavičkou x-cron-secret = AI_CRON_SECRET.
// Zakládá úlohy jen pro plány, které schválil člověk (vlastník nebo správce), a provádí je na jeho účet v limitech firmy.
// Výsledky jsou návrhy: změny dat dál schvaluje člověk v aplikaci. Viz docs/AI_TYM.md.
import VXGUARD from '../../src/ai_guard.js';
import VXWORK from '../../src/ai_worker_core.js';

const SB_URL = 'https://micymdbqgzeckiqyvvkn.supabase.co';
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
const same = (a, b) => { if (a.length !== b.length) return false; let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i); return d === 0; };

export const onRequest = async ({ request: req, env }) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const secret = String(env.AI_CRON_SECRET || ''), got = String(req.headers.get('x-cron-secret') || '');
  if (secret.length < 24 || !same(secret, got)) return json({ error: 'auth' }, 401);
  const SK = VXGUARD.cleanKey(env.SUPABASE_SERVICE_KEY);
  if (!env.GEMINI_API_KEY || !SK) return json({ error: 'not_configured' }, 503);
  const svc = async (name, args) => {
    const r = await fetch(`${SB_URL}/rest/v1/rpc/${name}`, { method: 'POST', headers: { apikey: SK, 'content-type': 'application/json' }, body: JSON.stringify(args) });
    let d = null; try { d = await r.json(); } catch { d = null; }
    return { ok: r.ok, status: r.status, data: d };
  };
  await svc('autopilot_expire_stale', {});
  const tick = await svc('ai_schedule_tick', { p_limit: 3 });
  if (!tick.ok) return json({ error: 'unavailable' }, 503);
  const out = [];
  for (const id of (tick.data?.jobs || []).slice(0, 3)) {
    const cl = await svc('ai_job_claim', { p_job: id });
    if (!cl.ok || !cl.data) { out.push({ id, status: 'skipped' }); continue; }
    const r = await VXWORK.runJob({ job: cl.data, rpc: svc, fetchFn: fetch, apiKey: env.GEMINI_API_KEY, model: env.GEMINI_MODEL || VXWORK.MODEL });
    out.push({ id, status: r.ok ? 'done' : 'failed', error: r.ok ? undefined : r.error });
  }
  return json({ ok: true, created: tick.data?.created || 0, processed: out });
};
