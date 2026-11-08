// Interní cesty repozitáře (docs/, db/, src/, build.py…) nejsou ve veřejném výstupu public/. Cloudflare Pages ale na hlavní
// doméně ještě vracel jejich dříve uložené kopie z interní mezipaměti statických souborů (cf-cache-status: DYNAMIC,
// s-maxage=604800), kterou nevymaže ani Purge Everything. Tento middleware běží PŘED servírováním statických souborů
// a pro tyto cesty vrátí 404 bez mezipaměti. Volá se jen pro cesty v public/_routes.json (generuje build.py),
// ostatní statické soubory funkce vůbec nevolají. API (/api/*) propouští dál.
export const onRequest = async ({ request, next, env }) => {
  const path = new URL(request.url).pathname;
  if (path === '/api' || path.startsWith('/api/')) return next();
  let body = 'Stránka nenalezena';
  try { const r = await env.ASSETS.fetch(new URL('/404.html', request.url)); if (r.ok) body = await r.text(); } catch { /* jednoduchý text */ }
  return new Response(body, { status: 404, headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-robots-tag': 'noindex' } });
};
