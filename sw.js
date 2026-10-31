/* Vexaronet: jednoduchý service worker. Síť má vždy přednost, offline se zobrazí poslední načtená stránka.
   Požadavky na databázi a API se nikdy neukládají. */
var C='vexaronet-v1';
self.addEventListener('install',function(e){self.skipWaiting()});
self.addEventListener('activate',function(e){e.waitUntil(caches.keys().then(function(k){return Promise.all(k.filter(function(x){return x!==C}).map(function(x){return caches.delete(x)}))}).then(function(){return self.clients.claim()}))});
self.addEventListener('fetch',function(e){
 var r=e.request,u=new URL(r.url);
 if(r.method!=='GET'||u.origin!==location.origin||u.pathname.indexOf('/api/')===0)return;
 e.respondWith(fetch(r).then(function(res){if(res&&res.ok){var cp=res.clone();caches.open(C).then(function(c){c.put(r,cp)})}return res}).catch(function(){return caches.match(r).then(function(m){return m||(r.mode==='navigate'?caches.match('/'):Response.error())})}))});
