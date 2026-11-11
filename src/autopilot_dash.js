/* ===== AI Marketing Autopilot: dashboard podle vizuální reference =====
   Zobrazuje jen skutečná data z evidence firmy (příspěvky, úkoly, zákazníci, obchodní případy, finanční záznamy).
   Co nemá zdroj dat (zobrazení, prokliky, ROAS, zisk z kampaní, propojené účty), ukazuje jako „Nepřipojeno“ nebo „–“.
   AI běhy (strategie, dávka příspěvků), schválení s otiskem obsahu, publikace a výsledky řeší src/ai_marketing_ui.js přes server (/api/ai-marketing, RPC mkt_*). */
var APD={tab:'prehled',week:0,menu:null,st:null};
var APD_TABS=[['prehled','Přehled','strat0'],['strategie','Strategie','strat'],['obsah','Obsah','img'],['kampane','Kampaně','mega'],['kalendar','Kalendář','kalendar'],['analyza','Analýza','bars'],['finance','Finance & ROI','coins'],['integrace','Integrace','link']];
IC.strat0='M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z';
IC.strat='M12 21a9 9 0 119-9M12 16a4 4 0 114-4M12 12l7-7M17 5h2v2';
IC.img='M4 5h16v14H4zM4 15l4-4 4 4 3-3 5 5M9 9.5a1 1 0 100-.01';
IC.mega='M4 14v-4l11-5v14zM15 9a3 3 0 010 6M6 14l1 5h2l-1-5';
IC.bars='M5 20v-6M11 20V6M17 20v-10M3 20h18';
IC.coins='M12 5c4 0 7 1 7 2.5S16 10 12 10 5 9 5 7.5 8 5 12 5zM5 7.5v4C5 13 8 14 12 14s7-1 7-2.5v-4M5 11.5v4C5 17 8 18 12 18s7-1 7-2.5v-4';
IC.link='M10 14a4 4 0 005.7 0l3-3a4 4 0 00-5.7-5.7l-1 1M14 10a4 4 0 00-5.7 0l-3 3a4 4 0 005.7 5.7l1-1';
IC.eye='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12zM12 15a3 3 0 100-6 3 3 0 000 6z';
IC.tick='M5 12l4 4 10-10';
IC.usr='M12 12a4 4 0 100-8 4 4 0 000 8zM4 21c0-4 4-6 8-6s8 2 8 6';
IC.usrs='M9 11a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM2 20c0-3.5 3-5.5 7-5.5s7 2 7 5.5M17 11a3 3 0 100-6M18 14.5c2.5.4 4 2 4 5';
IC.bag='M9 3h6l-1.5 3h-3zM7 9c-2 2-3 4-3 7 0 3 3 5 8 5s8-2 8-5c0-3-1-5-3-7-1 .7-3 1-5 1s-4-.3-5-1zM12 13v5';
IC.edit='M4 20l4-1 11-11-3-3L5 16zM14 6l3 3';
IC.chev='M6 9l6 6 6-6';
IC.chevl='M15 6l-6 6 6 6';
IC.chevr='M9 6l6 6-6 6';
IC.arr='M5 12h14M13 6l6 6-6 6';
IC.up='M12 19V5M6 11l6-6 6 6';
IC.down='M12 5v14M6 13l6 6 6-6';
IC.dots='M5 12h.01M12 12h.01M19 12h.01';
IC.sparkle='M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18 15l.8 2.2L21 18l-2.2.8L18 21l-.8-2.2L15 18l2.2-.8z';
function apdCss(){if(document.getElementById('apdCss'))return;var s=document.createElement('style');s.id='apdCss';s.textContent=
'.apd{--pv:#8b6cff;--pv2:#a78bfa;--ok:#35d49a;--bad:#ff6b81;--cardbg:linear-gradient(160deg,rgba(38,44,120,.46),rgba(16,20,60,.62));font-size:.92rem;color:var(--text);max-width:1280px;margin:0 auto}'
+'.apd *{box-sizing:border-box}.apd button{font:inherit;color:inherit}'
+'.apd .ad-card{border:1px solid var(--line);border-radius:16px;background:var(--cardbg);padding:11px 14px;min-width:0;box-shadow:inset 0 1px 0 rgba(255,255,255,.04)}'
+'[data-theme=light] .apd{--cardbg:linear-gradient(160deg,#fff,#f1f2ff)}'
+'.apd h2,.apd h3{margin:0;font-weight:700;letter-spacing:.01em}.apd h3{font-size:1.1rem}.apd .mut{color:var(--mut)}'
+'.apd .ad-hd{display:grid;grid-template-columns:auto minmax(0,1fr) auto auto auto;gap:12px 16px;align-items:center;margin:0 0 8px}'
+'.apd .ad-robot{width:140px;height:122px;margin:-6px 0 -10px -6px;filter:drop-shadow(0 8px 18px rgba(120,90,255,.45))}'
+'.apd .ad-ttl h2{font-size:1.75rem;line-height:1.1}.apd .ad-ttl p{margin:6px 0 0;font-size:1.05rem}'
+'.apd .ad-pill{display:inline-flex;align-items:center;gap:8px;padding:7px 16px;border-radius:999px;border:1px solid rgba(139,108,255,.6);background:rgba(139,108,255,.12);font-weight:600;white-space:nowrap}'
+'.apd .ad-pill i{width:9px;height:9px;border-radius:50%;background:#9aa0c8}.apd .ad-pill.ad-on{border-color:rgba(53,212,154,.7);background:rgba(53,212,154,.1);color:var(--ok)}.apd .ad-pill.ad-on i{background:var(--ok)}.apd .ad-pill.ad-warn{border-color:rgba(255,190,80,.6);background:rgba(255,190,80,.1);color:#ffcf7a}.apd .ad-pill.ad-warn i{background:#ffbe50}'
+'.apd .ad-acc,.apd .ad-fin{display:flex;align-items:center;gap:12px;padding:10px 16px}.apd .ad-acc small,.apd .ad-fin small{display:block}.apd .ad-acc .ad-ic{display:flex;gap:12px;margin-top:6px;align-items:center}'
+'.apd .ad-soc{width:26px;height:26px;border-radius:8px;display:grid;place-items:center;font-size:.72rem;font-weight:800;color:#fff;opacity:.45;filter:grayscale(.7)}'
+'.apd .ad-tabs{display:flex;gap:6px;overflow-x:auto;padding:6px;margin:0 0 10px;border:1px solid var(--line);border-radius:16px;background:var(--cardbg);scrollbar-width:none;-webkit-overflow-scrolling:touch}.apd .ad-tabs::-webkit-scrollbar{display:none}'
+'.apd .ad-tabs button{flex:1 0 auto;display:inline-flex;align-items:center;justify-content:center;gap:9px;padding:10px 16px;border-radius:12px;border:1px solid transparent;background:none;cursor:pointer;white-space:nowrap;font-size:1rem;color:var(--text)}'
+'.apd .ad-tabs button:hover{background:rgba(139,108,255,.14)}.apd .ad-tabs button[aria-current=page]{background:linear-gradient(135deg,#6a52ee,#5a43d6);border-color:rgba(167,139,250,.9);color:#fff;font-weight:700;box-shadow:0 0 0 1px rgba(139,108,255,.4),0 6px 20px rgba(100,70,240,.4)}'
+'.apd .ad-tabs button:focus-visible,.apd .ad-btn2:focus-visible,.apd .row button:focus-visible,.apd .ad-cal button:focus-visible{outline:2px solid var(--pv2);outline-offset:2px}'
+'.apd .ad-kpis{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px;margin-bottom:10px}'
+'.apd .ad-kpi{display:flex;align-items:center;gap:10px;padding:9px 12px}.apd .ad-kpi .ad-ki{flex:none;width:44px;height:44px;color:var(--pv2);display:grid;place-items:center}.apd .ad-kpi b{display:block;font-size:1.45rem;line-height:1.05;font-weight:700}.apd .ad-kpi span{display:block;color:var(--mut);font-size:.92rem;margin-top:3px}.apd .ad-kpi em{display:block;font-style:normal;font-size:.74rem;color:var(--mut);margin-top:2px}.apd .ad-kpi .ad-ar{margin-left:auto;align-self:center;color:var(--ok)}.apd .ad-kpi .ad-ar.ad-dn{color:var(--bad)}.apd .ad-kpi .ad-na{font-size:1.25rem;color:var(--mut)}'
+'.apd .ad-g2{display:grid;gap:10px;margin-bottom:10px}.apd .ad-g-a{grid-template-columns:minmax(0,5fr) minmax(0,8fr)}.apd .ad-g-b{grid-template-columns:minmax(0,13fr) minmax(0,8fr)}.apd .ad-g-c{grid-template-columns:minmax(0,1.45fr) minmax(0,1fr)}'
+'.apd .ad-ch{display:flex;align-items:center;gap:10px;margin-bottom:6px;flex-wrap:wrap}.apd .ad-ch .ad-ci{color:var(--pv2);display:grid;place-items:center}.apd .ad-ch .ad-sp{margin-left:auto}'
+'.apd .ad-badge{display:inline-flex;padding:4px 12px;border-radius:999px;border:1px solid rgba(139,108,255,.6);background:rgba(139,108,255,.14);font-size:.8rem;white-space:nowrap}'
+'.apd .ad-plan{list-style:none;margin:0;padding:0;position:relative}.apd .ad-plan li{display:grid;grid-template-columns:18px 48px minmax(0,1fr) 22px;gap:10px;align-items:center;padding:5px 8px;border-radius:10px;min-height:34px}.apd .ad-plan li .ad-dot{width:11px;height:11px;border-radius:50%;background:#3a4170;border:2px solid #5560a0}.apd .ad-plan li.ad-now{background:rgba(139,108,255,.2)}.apd .ad-plan li.ad-now .ad-dot{background:var(--pv);border-color:#cbbcff;box-shadow:0 0 0 4px rgba(139,108,255,.3)}.apd .ad-plan time{color:var(--mut)}.apd .ad-plan .ad-st{width:20px;height:20px;border-radius:50%;border:2px solid #4a5290;display:grid;place-items:center}.apd .ad-plan .ad-st.ad-ok{background:var(--ok);border-color:var(--ok);color:#06241a}'
+'.apd .ad-tk{list-style:none;margin:0;padding:0;display:grid;gap:8px}.apd .ad-tk li{display:grid;grid-template-columns:72px minmax(0,1fr) auto auto auto auto;gap:10px;align-items:center}.apd .ad-tk .ad-th{width:72px;height:50px;border-radius:8px;display:grid;place-items:center;background:linear-gradient(135deg,#3a2f9a,#7a4fd8 60%,#d06fb0);color:#fff}.apd .ad-tk .ad-tt{min-width:0}.apd .ad-tk .ad-tt b{display:block;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.apd .ad-tk .ad-tt small{color:var(--mut)}'
+'.apd .ad-tag{padding:3px 12px;border-radius:8px;background:rgba(80,110,255,.28);color:#b9c6ff;font-size:.78rem;white-space:nowrap}'
+'.apd .ad-btn2{display:inline-flex;align-items:center;gap:7px;padding:8px 14px;border-radius:9px;border:1px solid var(--line);background:rgba(255,255,255,.04);cursor:pointer;white-space:nowrap;min-height:38px}.apd .ad-btn2:hover{background:rgba(139,108,255,.18)}.apd .ad-btn2.ad-go{background:linear-gradient(135deg,#1fc07a,#18a868);border-color:transparent;color:#04261a;font-weight:700}.apd .ad-btn2.ad-go:hover{filter:brightness(1.1)}.apd .ad-btn2.ad-pr{border-color:rgba(139,108,255,.7);color:#cfc3ff}.apd .ad-btn2[disabled]{opacity:.5;cursor:not-allowed}.apd .ad-more{width:34px;justify-content:center;padding:6px;border:0;background:none}'
+'.apd .ad-empty{display:flex;align-items:center;gap:12px;padding:14px;border:1px dashed var(--line);border-radius:12px;color:var(--mut);line-height:1.4}.apd .ad-empty b{color:var(--text)}'
+'.apd .ad-cal{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:6px}.apd .ad-cal .ad-day{border:1px solid var(--line);border-radius:10px;padding:7px 4px;text-align:center;min-height:70px;display:flex;flex-direction:column;align-items:center;gap:4px;background:rgba(255,255,255,.02)}.apd .ad-cal .ad-day.ad-today{border-color:var(--pv2);box-shadow:0 0 0 1px rgba(167,139,250,.5)}.apd .ad-cal .ad-day small{color:var(--text);font-size:.82rem}.apd .ad-cal .ad-it{display:flex;gap:3px;align-items:center;justify-content:center;flex-wrap:wrap;background:none;border:0;cursor:pointer;padding:2px}.apd .ad-cal .ad-add{width:28px;height:28px;border-radius:8px;border:1px solid var(--line);background:none;cursor:pointer;color:var(--mut);display:grid;place-items:center}'
+'.apd .ad-nav3{display:flex;align-items:center;border:1px solid var(--line);border-radius:10px;overflow:hidden}.apd .ad-nav3 button{background:none;border:0;padding:8px 12px;cursor:pointer;min-height:36px}.apd .ad-nav3 span{padding:0 18px;white-space:nowrap}'
+'.apd .ad-chn{width:26px;height:26px;border-radius:8px;display:grid;place-items:center;color:#fff;flex:none}'
+'.apd .ad-bar{height:10px;border-radius:999px;background:rgba(128,128,170,.25);overflow:hidden;flex:1}.apd .ad-bar i{display:block;height:100%;background:linear-gradient(90deg,#3bb6ff,#8b6cff,#c06cff)}'
+'.apd .ad-chart{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,.9fr);gap:14px;align-items:stretch}.apd .ad-chart svg.ad-cs{width:100%;height:auto;display:block;overflow:visible}.apd .ad-tiles{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;align-content:start}.apd .ad-tile{border:1px solid var(--line);border-radius:12px;padding:10px;background:rgba(255,255,255,.03);min-width:0}.apd .ad-tile b{display:block;font-size:1.1rem}.apd .ad-tile b.ad-na{font-size:.74rem;line-height:1.2;margin:2px 0}.apd .ad-tile span{color:var(--mut);font-size:.82rem}.apd .ad-tile .ad-ti{color:var(--pv2);margin-bottom:2px}'
+'.apd .ad-kv{display:grid;gap:0}.apd .ad-kv>div{display:flex;justify-content:space-between;gap:12px;padding:7px 4px;border-bottom:1px solid rgba(130,150,255,.1)}.apd .ad-kv>div:last-child{border:0}.apd .ad-kv b{font-weight:600;text-align:right}.apd .ad-na{color:var(--mut)}'
+'.apd .ad-finw{display:grid;grid-template-columns:minmax(0,1fr) 150px;gap:10px;align-items:center}.apd .ad-ring{width:140px;height:140px;margin:0 auto;display:block}'
+'.apd .ad-tabbody{display:grid;gap:14px}.apd .ad-tabbody>.ad-card{margin:0}.apd .ad-lst{list-style:none;padding:0;margin:0;display:grid;gap:8px}.apd .ad-lst li{display:flex;gap:12px;align-items:center;padding:10px 12px;border:1px solid var(--line);border-radius:12px}.apd .ad-lst li>div{min-width:0;flex:1}.apd .ad-lst small{display:block}'
+'.apd .ad-demo{display:inline-block;margin-left:8px;padding:2px 9px;border-radius:999px;background:rgba(255,190,80,.2);color:#ffd387;font-size:.72rem;vertical-align:middle}'
+'.apd .ap .card2{background:var(--cardbg)}'
+'.apdm{position:fixed;inset:0;z-index:2000;background:rgba(4,6,24,.7);display:grid;place-items:center;padding:16px}.apdm>div{width:min(560px,100%);max-height:86vh;overflow:auto;border-radius:16px;border:1px solid var(--line);background:#12173f;color:#eaf0ff;padding:18px}.apdm pre{white-space:pre-wrap;word-break:break-word;font:inherit;margin:10px 0}'
+'.vxapp aside .apg{display:flex;flex-direction:column;gap:2px}.vxapp aside .apg>button.ad-hdr{background:linear-gradient(135deg,#5b45e0,#4a3bc4);color:#fff;font-weight:700;box-shadow:0 6px 18px rgba(90,70,220,.35)}.vxapp aside .apg>button.ad-hdr .ad-chv{margin-left:auto;transition:transform .2s}.vxapp aside .apg.ad-open>button.ad-hdr .ad-chv{transform:rotate(180deg)}.vxapp aside .apg .ad-sub{display:none;flex-direction:column;gap:1px;margin:2px 0 4px 10px;padding-left:6px;border-left:1px solid var(--line)}.vxapp aside .apg.ad-open .ad-sub{display:flex}.vxapp aside .apg .ad-sub button{min-height:34px;padding:5px 10px;font-size:.88rem;gap:10px}'
+'@media(max-width:1180px){.apd .ad-hd{grid-template-columns:auto minmax(0,1fr) auto}.apd .ad-hd .ad-acc,.apd .ad-hd .ad-fin{grid-column:span 3}.apd .ad-kpis{grid-template-columns:repeat(3,minmax(0,1fr))}.apd .ad-g-a,.apd .ad-g-b,.apd .ad-g-c{grid-template-columns:minmax(0,1fr)}}'
+'@media(max-width:700px){.apd .ad-kpi .ad-ki{display:none}.apd .ad-kpi b{font-size:1.3rem}.apd .ad-kpi{padding:10px 12px}.apd .ad-tiles{grid-template-columns:repeat(2,minmax(0,1fr))}.apd .ad-hd{grid-template-columns:auto minmax(0,1fr)}.apd .ad-hd .ad-pill{grid-column:1/-1;justify-self:start}.apd .ad-hd .ad-acc,.apd .ad-hd .ad-fin{grid-column:1/-1}.apd .ad-robot{width:84px;height:76px}.apd .ad-ttl h2{font-size:1.3rem}.apd .ad-ttl p{font-size:.9rem}.apd .ad-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.apd .ad-kpi:last-child{grid-column:1/-1}.apd .ad-tk li{grid-template-columns:56px minmax(0,1fr) auto;row-gap:8px}.apd .ad-tk .ad-th{width:56px;height:42px}.apd .ad-tk li .ad-tag{display:none}.apd .ad-tk li .ad-btn2{grid-column:span 1}.apd .ad-chart,.apd .ad-finw{grid-template-columns:minmax(0,1fr)}.apd .ad-cal{gap:4px}.apd .ad-cal .ad-day{min-height:70px;padding:5px 2px}.apd .ad-tabs button{padding:9px 12px}}'
;document.head.appendChild(s)}
/* ---------- pomocné ---------- */
function apdD0(o){var d=new Date();d.setHours(0,0,0,0);d.setDate(d.getDate()+(o||0));return d}
function apdIso(d){return d.getFullYear()+'-'+('0'+(d.getMonth()+1)).slice(-2)+'-'+('0'+d.getDate()).slice(-2)}
function apdRows(k){var x=APP.d&&APP.d[k];return x&&x.rows?x.rows:[]}
function apdErr(k){var x=APP.d&&APP.d[k];return x&&x.err?x.err:null}
function apdInRange(v,a,b){if(!v)return false;var t=new Date(v).getTime();return t>=a.getTime()&&t<b.getTime()}
function apdPct(cur,prev){return prev>0?Math.round((cur-prev)/prev*100):null}
function apdKc(n){return Math.round(Number(n)||0).toLocaleString('cs-CZ')+' Kč'}
var APD_MKT=/marketing|reklam|inzer|facebook|instagram|meta ads|google ads|tiktok|sklik|ppc/i;
function apdStats(){
 var t0=apdD0(0),a30=apdD0(-29),b=apdD0(1),a60=apdD0(-59),cu=apdRows('customers'),dl=apdRows('deals'),fe=apdRows('fe'),
  nc=cu.filter(function(r){return apdInRange(r.created_at,a30,b)}).length,pc=cu.filter(function(r){return apdInRange(r.created_at,a60,a30)}).length,
  nd=dl.filter(function(r){return apdInRange(r.created_at,a30,b)}).length,pd=dl.filter(function(r){return apdInRange(r.created_at,a60,a30)}).length,
  isM=function(r){return r.kind==='expense'&&APD_MKT.test(String(r.title||''))},
  cost30=fe.filter(function(r){return isM(r)&&apdInRange(r.entry_date,a30,b)}).reduce(function(s,r){return s+Number(r.amount||0)},0),
  ms=new Date(t0.getFullYear(),t0.getMonth(),1),
  costM=fe.filter(function(r){return isM(r)&&apdInRange(r.entry_date,ms,b)}).reduce(function(s,r){return s+Number(r.amount||0)},0);
 return {nc:nc,pc:pc,nd:nd,pd:pd,cost30:cost30,costM:costM,hasFe:fe.length>0,custOk:!apdErr('customers'),dealsOk:!apdErr('deals')}}
function apdChanIcon(ch,sz){sz=sz||26;var c=String(ch||'');
 var m={'Instagram':['linear-gradient(135deg,#f9a03f,#e1306c 55%,#7a3ff2)','M4 4h16v16H4zM12 16a4 4 0 100-8 4 4 0 000 8zM17 7.5v.01'],'Facebook':['#1877f2','M14 20v-7h2.5l.5-3h-3V8.5c0-.9.4-1.5 1.6-1.5H17V4.3C16.600 4.200 15.700 4 14.800 4 12.500 4 11 5.400 11 7.800V10H8.500v3H11v7z'],'E-mail':['#5a6ad8','M4 6h16v12H4zM4 7l8 6 8-6'],'Web nebo blog':['#2a9d8f','M12 3a9 9 0 100 18 9 9 0 000-18zM3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18'],'Reklama':['#d9822b','M4 14v-4l11-5v14zM15 9a3 3 0 010 6']}[c]||['#6b73a8','M5 12h.01M12 12h.01M19 12h.01'];
 return '<span class="ad-chn" style="width:'+sz+'px;height:'+sz+'px;background:'+m[0]+'" title="'+esc(c||'bez kanálu')+'"><svg viewBox="0 0 24 24" width="'+Math.round(sz*.62)+'" height="'+Math.round(sz*.62)+'" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+m[1]+'"/></svg></span>'}
function apdRobot(){return '<svg class="ad-robot" viewBox="0 0 128 112" role="img" aria-label="Ilustrace AI asistenta"><defs><linearGradient id="rbG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9a86ff"/><stop offset="1" stop-color="#4b3bd0"/></linearGradient><linearGradient id="rbV" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b1f5a"/><stop offset="1" stop-color="#0a0c2e"/></linearGradient><radialGradient id="rbE"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#8fa8ff"/></radialGradient></defs>'
 +'<path d="M20 112c2-22 20-30 44-30s42 8 44 30z" fill="url(#rbG)"/><path d="M52 84l12 10 12-10" fill="none" stroke="#cfc6ff" stroke-width="3" stroke-linecap="round"/>'
 +'<rect x="30" y="12" width="68" height="64" rx="28" fill="url(#rbG)"/><rect x="38" y="26" width="52" height="36" rx="17" fill="url(#rbV)" stroke="#b6a8ff" stroke-width="2"/>'
 +'<ellipse cx="53" cy="44" rx="7" ry="8" fill="url(#rbE)"/><ellipse cx="75" cy="44" rx="7" ry="8" fill="url(#rbE)"/>'
 +'<rect x="20" y="34" width="12" height="26" rx="6" fill="#6f5cf0"/><rect x="96" y="34" width="12" height="26" rx="6" fill="#6f5cf0"/><path d="M26 34c0-26 76-26 76 0" fill="none" stroke="#b6a8ff" stroke-width="4" stroke-linecap="round"/><path d="M102 58c0 10-10 14-22 14" fill="none" stroke="#b6a8ff" stroke-width="3" stroke-linecap="round"/><circle cx="78" cy="72" r="3.5" fill="#cfc6ff"/></svg>'}
/* ---------- bloky Přehledu ---------- */
/* Stav AI: „Aktivní“ jen když platí tarif, je nastaven limit a provozovatel povolil placené běhy (stav z databáze). */
function apdPillHtml(s){if(!s)return '<span class="ad-pill"><i></i>AI neběží</span>';var r=VXAP.readiness(s,null);
 if(r[0].ok&&r[2].ok&&r[3].ok)return '<span class="ad-pill ad-on"><i></i>Aktivní</span>';
 if(r[0].ok&&r[2].ok)return '<span class="ad-pill ad-warn"><i></i>Připraveno, AI zatím vypnutá</span>';
 return '<span class="ad-pill"><i></i>AI neběží</span>'}
function apdHeader(){
 var s=APD.st,pill=apdPillHtml(s),
  fe=apdRows('fe'),fl=fe.length?'Finance: z vaší evidence':'Finance: bez záznamů';
 return '<div class="ad-hd">'+apdRobot()+'<div class="ad-ttl"><h2>AI Marketing Autopilot'+(DEMO?'<span class="ad-demo">Ukázková data</span>':'')+'</h2><p class="mut">Váš marketingový pomocník. Navrhuje, schvalujete vy.</p></div>'
  +'<div id="apdPill">'+pill+'</div>'
  +'<div class="ad-card ad-acc"><div><b>Propojené účty</b><div class="ad-ic" aria-label="Žádný účet není propojený"><span class="ad-soc" style="background:#0a7cff">∞</span><span class="ad-soc" style="background:linear-gradient(135deg,#f9a03f,#e1306c)">IG</span><span class="ad-soc" style="background:#1877f2">f</span><span class="ad-soc" style="background:#111">♪</span><span class="ad-soc" style="background:#e62117">▶</span></div></div><div><small class="mut">Nepřipojeno</small><button type="button" class="ad-btn2 ad-pr" data-apd-act="connect" style="margin-top:6px">Připojit</button></div></div>'
  +'<div class="ad-card ad-fin"><svg viewBox="0 0 24 24" width="34" height="34" fill="none" stroke="var(--pv2)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="'+IC.coins+'"/></svg><div><b>'+esc(fl)+'</b><small class="mut">Náklady a výnosy ze záložky Finance</small></div></div></div>'}
function apdTabs(){return '<nav class="ad-tabs" aria-label="Sekce AI Marketing Autopilota">'+APD_TABS.map(function(t){return '<button type="button" data-apd="'+t[0]+'"'+(APD.tab===t[0]?' aria-current="page"':'')+'>'+ico(t[2],20)+'<span>'+esc(t[1])+'</span></button>'}).join('')+'</nav>'}
function apdKpis(){var S=apdStats();
 function card(ic,val,lab,sub,ar){return '<div class="ad-card ad-kpi"><span class="ad-ki">'+ico(ic,34)+'</span><div><b>'+val+'</b><span>'+esc(lab)+'</span>'+(sub?'<em>'+esc(sub)+'</em>':'')+'</div>'+(ar||'')+'</div>'}
 function arrow(p){return p==null?'':'<span class="ad-ar'+(p<0?' ad-dn':'')+'" title="Změna oproti předchozím 30 dnům: '+(p>0?'+':'')+p+' %">'+ico(p<0?'down':'up',20)+'</span>'}
 var dp=apdPct(S.nd,S.pd),cp=apdPct(S.nc,S.pc);
 return '<div class="ad-kpis">'
  +card('usr',S.dealsOk?String(S.nd):'–','Poptávky (30 dní)',S.dealsOk?(dp==null?'nové obchodní případy':(dp>0?'+':'')+dp+' % oproti předchozím 30 dnům'):'data nejsou k dispozici',arrow(dp))
  +card('usrs',S.custOk?String(S.nc):'–','Noví zákazníci',S.custOk?(cp==null?'za posledních 30 dní':(cp>0?'+':'')+cp+' % oproti předchozím 30 dnům'):'data nejsou k dispozici',arrow(cp))
  +card('coins',S.hasFe?apdKc(S.cost30):'–','Náklady na marketing',S.hasFe?'výdaje s popisem marketing/reklama':'zatím žádné finanční záznamy')
  +card('bars','<span class="ad-na">–</span>','Návratnost (ROAS)','chybí tržby přiřazené kampaním')
  +card('bag','<span class="ad-na">–</span>','Zisk z marketingu','nelze určit bez výnosů z kampaní')+'</div>'}
function apdPlan(){
 var t0=apdD0(0),t1=apdD0(1),td=apdIso(t0),items=[];
 apdRows('marketing_posts').forEach(function(p){if(p.planned_on===td&&p.status!=='draft')items.push({t:'',n:'Příspěvek: '+p.title,ok:p.status==='done'})});
 apdRows('tasks').forEach(function(x){if(x.due_at&&apdInRange(x.due_at,t0,t1)){var d=new Date(x.due_at);items.push({t:('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2),n:x.title,ok:!!x.completed})}});
 var T=(typeof AIT!=='undefined'&&AIT.st&&AIT.cid===APP.cid)?AIT.st:null;
 if(T){(T.schedules||[]).forEach(function(q){if(q.enabled&&q.next_run_at&&apdInRange(q.next_run_at,t0,t1)){var d=new Date(q.next_run_at);items.push({t:('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2),n:'AI: '+q.title,ok:false})}});
  (T.jobs||[]).forEach(function(j){if(apdInRange(j.created_at,t0,t1)&&j.status!=='cancelled'){var d=new Date(j.created_at);items.push({t:('0'+d.getHours()).slice(-2)+':'+('0'+d.getMinutes()).slice(-2),n:'AI: '+j.title+(j.status==='awaiting_approval'?' (čeká na schválení)':j.status==='failed'?' (nepovedlo se)':''),ok:j.status==='done'})}})}
 items.sort(function(a,b){return a.t<b.t?-1:a.t>b.t?1:0});
 var nowT=('0'+new Date().getHours()).slice(-2)+':00',cur=-1;items.forEach(function(it,i){if(cur<0&&!it.ok&&(it.t===''||it.t>=nowT))cur=i});
 return '<section class="ad-card" id="apdPlanBox"><div class="ad-ch"><span class="ad-ci">'+ico('kalendar',24)+'</span><h3>Dnešní plán AI</h3></div>'
  +(items.length?'<ul class="ad-plan">'+items.slice(0,6).map(function(it,i){return '<li'+(i===cur?' class="ad-now"':'')+'><span class="ad-dot"></span><time>'+(it.t||'celý den')+'</time><span>'+esc(it.n)+'</span><span class="ad-st'+(it.ok?' ad-ok':'')+'" role="img" aria-label="'+(it.ok?'hotovo':'čeká')+'">'+(it.ok?ico('tick',13):'')+'</span></li>'}).join('')+'</ul>'
   :'<div class="ad-empty"><span>Na dnes není nic naplánováno. Pravidelné úlohy AI nastavíte v <button type="button" class="lnkb" data-tab="aitym">AI týmu</button>.</span></div>')
  +'<p class="mut" style="margin:10px 0 0;font-size:.78rem">Skládá se z vašich úkolů, naplánovaných příspěvků a dnešních úloh AI.</p></section>'}
function apdTasks(){
 var dr=apdRows('marketing_posts').filter(function(p){return p.status==='draft'}),err=apdErr('marketing_posts');
 var ai=(typeof AIT!=='undefined'&&AIT.st&&AIT.cid===APP.cid)?(AIT.st.actions||[]).filter(function(a){return a.status==='proposed'}).length:0,nw=dr.length+ai;
 return '<section class="ad-card" id="apdTasksBox"><div class="ad-ch"><span class="ad-ci">'+ico('coins',24)+'</span><h3>Aktuální úkoly</h3>'+(nw?'<span class="ad-badge">'+nw+' '+(nw===1?'čeká':nw<5?'čekají':'čeká')+' na schválení</span>':'')+'</div>'
  +(ai?'<div class="ad-empty" style="margin-bottom:8px"><span><b>'+ai+' '+(ai===1?'návrh':ai<5?'návrhy':'návrhů')+' AI</b> čeká na vaše schválení.</span><button type="button" class="ad-btn2 ad-go" data-tab="aitym">Zobrazit</button></div>':'')
  +(err?'<div class="ad-empty">Příspěvky nelze načíst: '+esc(err)+'</div>':dr.length?'<ul class="ad-tk">'+dr.slice(0,3).map(function(p){var kd=(p.title||'').split(':')[0];
   return '<li><span class="ad-th">'+ico('img',24)+'</span><div class="ad-tt"><b>'+esc(p.title)+'</b><small>'+esc(p.channel||'bez kanálu')+(p.planned_on?' · '+fD(p.planned_on):'')+'</small></div><span class="ad-tag">'+esc(p.channel||'Koncept')+'</span>'
   +'<button type="button" class="ad-btn2" data-apd-act="prev" data-id="'+esc(p.id)+'">'+ico('eye',17)+'Náhled</button><button type="button" class="ad-btn2 ad-go" data-apd-act="appr" data-id="'+esc(p.id)+'">'+ico('tick',17)+'Schválit</button><button type="button" class="ad-btn2 ad-more" data-edit="marketing_posts:'+esc(p.id)+'" aria-label="Upravit příspěvek">'+ico('dots',18)+'</button></li>'}).join('')+'</ul>'
   :'<div class="ad-empty"><span><b>Žádné koncepty ke schválení.</b> V záložce Obsah si nechte navrhnout příspěvek nebo ho přidejte ručně.</span></div>')
  +'<p class="mut" style="margin:10px 0 0;font-size:.78rem">Schválení se uloží na serveru přesně pro zobrazený text; po úpravě je nutné schválit znovu. Nic se samo nepublikuje ani neodesílá.</p></section>'}
function apdWeek(){var t=apdD0(0),dow=(t.getDay()+6)%7,m=apdD0(-dow+APD.week*7);return m}
function apdCal(){
 var m=apdWeek(),days=[],names=['Po','Út','St','Čt','Pá','So','Ne'],P=apdRows('marketing_posts'),td=apdIso(apdD0(0)),e=m,en=new Date(m);en.setDate(en.getDate()+6);
 for(var i=0;i<7;i++){var d=new Date(m);d.setDate(d.getDate()+i);days.push(d)}
 var lab=APD.week===0?'Tento týden':(APD.week===1?'Příští týden':(APD.week===-1?'Minulý týden':m.getDate()+'. '+(m.getMonth()+1)+'. – '+en.getDate()+'. '+(en.getMonth()+1)+'.'));
 return '<section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('kalendar',24)+'</span><h3>Marketingový kalendář</h3><div class="ad-nav3" role="group" aria-label="Týden"><button type="button" data-apd-act="wk" data-d="-1" aria-label="Předchozí týden">'+ico('chevl',16)+'</button><span>'+esc(lab)+'</span><button type="button" data-apd-act="wk" data-d="1" aria-label="Další týden">'+ico('chevr',16)+'</button></div><button type="button" class="ad-btn2 ad-sp" style="border:0;background:none;color:var(--pv2)" data-apd="kalendar">Zobrazit celý kalendář</button></div>'
  +'<div class="ad-cal">'+days.map(function(d,i){var iso=apdIso(d),ps=P.filter(function(p){return p.planned_on===iso});
   return '<div class="ad-day'+(iso===td?' ad-today':'')+'"><small>'+names[i]+' '+d.getDate()+'.'+(d.getMonth()+1)+'.</small>'
    +(ps.length?'<button type="button" class="ad-it" data-edit="marketing_posts:'+esc(ps[0].id)+'" aria-label="'+esc(ps.length+' příspěvků, první: '+ps[0].title)+'">'+ps.slice(0,2).map(function(p){return apdChanIcon(p.channel,24)}).join('')+(ps.length>2?'<small>+'+(ps.length-2)+'</small>':'')+(ps.every(function(p){return p.status==='done'})?'<span class="apok" style="color:var(--ok)">'+ico('tick',15)+'</span>':'')+'</button>'
     :'<button type="button" class="ad-add" data-new="marketing_posts" aria-label="Přidat příspěvek na '+d.getDate()+'. '+(d.getMonth()+1)+'.">'+ico('plus',16)+'</button>')+'</div>'}).join('')+'</div></section>'}
function apdStrategy(){return '<section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('strat',26)+'</span><h3>Marketingová strategie</h3></div>'
 +mkSlot('card')
 +'<button type="button" class="ad-btn2 ad-pr" data-apd="strategie">Zobrazit strategii '+ico('arr',16)+'</button></section>'}
function apdChart(S,big){
 var W=520,H=big?240:150,pl=44,pr=10,pt=10,pb=22,a30=apdD0(-29),days=30,cu=apdRows('customers'),dl=apdRows('deals'),ser=function(rows){var a=[],c=0;for(var i=0;i<days;i++){var d0=new Date(a30);d0.setDate(d0.getDate()+i);var d1=new Date(d0);d1.setDate(d1.getDate()+1);c+=rows.filter(function(r){return apdInRange(r.created_at,d0,d1)}).length;a.push(c)}return a};
 var A1=ser(dl),A2=ser(cu),mx=Math.max(1,A1[days-1],A2[days-1]),step=mx<=5?1:mx<=10?2:mx<=25?5:mx<=60?10:20,top=Math.ceil(mx/step)*step||1,
  x=function(i){return pl+(W-pl-pr)*i/(days-1)},y=function(v){return pt+(H-pt-pb)*(1-v/top)},
  line=function(a,c){return '<polyline fill="none" stroke="'+c+'" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round" points="'+a.map(function(v,i){return x(i).toFixed(1)+','+y(v).toFixed(1)}).join(' ')+'"/>'},
  grid='';for(var g=0;g<=top;g+=step){grid+='<line x1="'+pl+'" x2="'+(W-pr)+'" y1="'+y(g)+'" y2="'+y(g)+'" stroke="rgba(130,150,255,.18)"/><text x="'+(pl-8)+'" y="'+(y(g)+4)+'" text-anchor="end" fill="currentColor" opacity=".7" font-size="13">'+g+'</text>'}
 var none=A1[days-1]+A2[days-1]===0;
 return '<svg class="ad-cs" viewBox="0 0 '+W+' '+H+'" role="img" aria-label="Kumulativní počet nových poptávek a zákazníků za posledních 30 dní">'+grid
  +'<path d="M'+x(0)+','+y(0)+' '+A2.map(function(v,i){return 'L'+x(i).toFixed(1)+','+y(v).toFixed(1)}).join(' ')+' L'+x(days-1)+','+y(0)+'Z" fill="rgba(139,108,255,.22)"/>'+line(A2,'#a78bfa')+line(A1,'#3bb6ff')
  +'<text x="'+pl+'" y="'+(H-4)+'" fill="currentColor" opacity=".7" font-size="11">před 30 dny</text><text x="'+(W-pr)+'" y="'+(H-4)+'" text-anchor="end" fill="currentColor" opacity=".7" font-size="11">dnes</text>'
  +(none?'<text x="'+(W/2)+'" y="'+(H/2-4)+'" text-anchor="middle" fill="currentColor" opacity=".8" font-size="13">Za 30 dní zatím žádné nové poptávky ani zákazníci.</text>':'')+'</svg>'
  +'<div style="display:flex;gap:16px;margin-top:6px;font-size:.8rem" class="mut"><span><i style="display:inline-block;width:14px;height:3px;background:#3bb6ff;vertical-align:middle;margin-right:6px"></i>Poptávky (obchodní případy)</span><span><i style="display:inline-block;width:14px;height:3px;background:#a78bfa;vertical-align:middle;margin-right:6px"></i>Noví zákazníci</span></div>'}
function apdResults(){var S=apdStats();
 return '<section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('bars',24)+'</span><h3>Výsledky marketingu <small class="mut" style="font-weight:400">(30 dní)</small></h3></div><div class="ad-chart"><div>'+apdChart(S)+'</div><div class="ad-tiles" data-mk-slot="tiles">'+mkTilesHtml()+'</div></div></section>'}
function apdRing(txt,sub){return '<svg class="ad-ring" viewBox="0 0 140 140" role="img" aria-label="ROI: '+esc(txt)+'"><defs><linearGradient id="rgG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3bb6ff"/><stop offset="1" stop-color="#c06cff"/></linearGradient></defs><circle cx="70" cy="70" r="58" fill="none" stroke="rgba(130,150,255,.2)" stroke-width="12"/><circle cx="70" cy="70" r="58" fill="none" stroke="url(#rgG)" stroke-width="12" stroke-linecap="round" stroke-dasharray="364" stroke-dashoffset="364" transform="rotate(-90 70 70)" opacity=".0"/><text x="70" y="68" text-anchor="middle" font-size="26" font-weight="700" fill="currentColor">'+esc(txt)+'</text><text x="70" y="88" text-anchor="middle" font-size="12" fill="currentColor" opacity=".7">'+esc(sub)+'</text></svg>'}
function apdFinBox(){var S=apdStats();
 return '<section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('coins',24)+'</span><h3>Marketing & Finance <small class="mut" style="font-weight:400">('+(S.hasFe?'z vaší evidence':'bez dat')+')</small></h3></div><div class="ad-finw"><div class="ad-kv">'
  +'<div><span>Rozpočet (měsíc)</span><b class="ad-na">nenastaven <button type="button" class="ad-btn2 ad-more" data-apd-act="budget" aria-label="Nastavit rozpočet" style="min-height:28px;width:28px;display:inline-grid">'+ico('edit',15)+'</button></b></div>'
  +'<div><span>Utraceno (tento měsíc)</span><b>'+(S.hasFe?apdKc(S.costM):'<span class="ad-na">–</span>')+'</b></div>'
  +'<div><span>Výnosy z marketingu</span><b class="ad-na">Nepřipojeno</b></div>'
  +'<div><span>Čistý zisk (ROI)</span><b class="ad-na">nelze spočítat</b></div></div>'+apdRing('–','ROI')+'</div>'
  +'<div style="text-align:right;margin-top:8px"><button type="button" class="ad-btn2" data-tab="finance" style="font-size:.85rem">Detail ve Financích '+ico('arr',15)+'</button></div></section>'}
function apdOverview(){return apdKpis()+'<div class="ad-g2 ad-g-a">'+apdPlan()+apdTasks()+'</div><div class="ad-g2 ad-g-b">'+apdCal()+apdStrategy()+'</div><div class="ad-g2 ad-g-c">'+apdResults()+apdFinBox()+'</div>'}
/* ---------- ostatní záložky ---------- */
function apdEmpty(t,x){return '<div class="ad-empty"><span><b>'+esc(t)+'</b><br>'+esc(x)+'</span></div>'}
function apdTabStrategy(){return '<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('strat',26)+'</span><h3>Strategie</h3></div>'+mkSlot('strat')+'</section></div>'}
function apdTabContent(){var h='<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('img',24)+'</span><h3>Obsah</h3></div><p class="mut" style="margin:0 0 6px">AI jen navrhuje, nic se samo nepublikuje ani neodesílá.</p></section><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('sparkle',24)+'</span><h3>Návrhy příspěvků ze strategie</h3></div>'+mkSlot('gen')+'</section>';
 var m;try{m=typeof APD_MK==='function'?APD_MK():'<div class="draft">Generátor textů není k dispozici.</div>'}catch(e){m='<div class="draft">Generátor textů se nepodařilo zobrazit: '+esc(e.message)+'</div>'}
 return h+m+'</div>'}
function apdTabCampaigns(){var ad=apdRows('marketing_posts').filter(function(p){return p.channel==='Reklama'});
 return '<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('mega',24)+'</span><h3>Kampaně</h3></div>'
  +apdEmpty('Žádná propojená reklamní kampaň.','Reklamní účty (Meta, Google) nejsou připojené, proto nelze zobrazit výdaje ani výsledky kampaní. Níže jsou vaše reklamní texty z plánu příspěvků.')
  +'<h3 style="margin:16px 0 8px;font-size:1rem">Reklamní texty v plánu</h3>'+(ad.length?'<ul class="ad-lst">'+ad.map(function(p){return '<li>'+apdChanIcon('Reklama',30)+'<div><b>'+esc(p.title)+'</b><small class="mut">'+esc(MKST[p.status]||p.status)+(p.planned_on?' · '+fD(p.planned_on):'')+'</small></div><button type="button" class="ad-btn2" data-edit="marketing_posts:'+esc(p.id)+'">Upravit</button></li>'}).join('')+'</ul>':'<p class="mut">Zatím žádné reklamní texty. Vytvořte je v záložce Obsah.</p>')
  +'<div style="margin-top:12px"><button type="button" class="ad-btn2 ad-pr" data-apd="obsah">Otevřít Obsah</button></div></section></div>'}
function apdTabCalendar(){return '<div class="ad-tabbody">'+apdCal()+'<section class="ad-card"><div class="ad-ch"><h3>Příspěvky v plánu</h3><button type="button" class="ad-btn2 ad-sp ad-go" data-new="marketing_posts">'+ico('plus',16)+'Nový příspěvek</button></div>'
 +(function(){var P=apdRows('marketing_posts').slice().sort(function(a,b){return String(a.planned_on||'9')<String(b.planned_on||'9')?-1:1});return P.length?'<ul class="ad-lst">'+P.map(function(p){return '<li>'+apdChanIcon(p.channel,30)+'<div><b>'+esc(p.title)+'</b><small class="mut">'+esc(p.channel||'bez kanálu')+' · '+esc(MKST[p.status]||p.status)+'</small></div><span class="mut">'+(p.planned_on?fD(p.planned_on):'bez data')+'</span><button type="button" class="ad-btn2" data-apd-act="prev" data-id="'+esc(p.id)+'">'+ico('eye',16)+'Náhled</button><button type="button" class="ad-btn2" data-edit="marketing_posts:'+esc(p.id)+'">Upravit</button></li>'}).join('')+'</ul>':apdEmpty('Zatím žádné příspěvky.','Přidejte první příspěvek tlačítkem výše nebo v záložce Obsah.')})()+'</section></div>'}
function apdTabAnalysis(){var S=apdStats();return '<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('bars',24)+'</span><h3>Analýza <small class="mut" style="font-weight:400">(30 dní)</small></h3></div>'+apdChart(S,1)+'</section>'
 +'<section class="ad-card"><h3 style="margin-bottom:8px">Co je k dispozici</h3><div class="ad-kv"><div><span>Nové obchodní případy</span><b>'+(S.dealsOk?S.nd:'–')+'</b></div><div><span>Noví zákazníci</span><b>'+(S.custOk?S.nc:'–')+'</b></div><div><span>Zhlédnutí a prokliky</span><b class="ad-na">Nepřipojeno</b></div><div><span>Původ zákazníka (kampaň, kanál)</span><b class="ad-na">neevidujeme</b></div></div><p class="mut fine">Dokud neevidujeme původ zákazníků a nepřipojíme reklamní účty, nelze měřit přínos jednotlivých kampaní.</p></section><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('bars',24)+'</span><h3>Výsledky zveřejněných příspěvků</h3></div>'+mkSlot('res')+'</section></div>'}
function apdTabFinance(){var S=apdStats();return '<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('coins',24)+'</span><h3>Finance & ROI</h3></div><div class="ad-finw"><div class="ad-kv">'
 +'<div><span>Výdaje s popisem marketing/reklama (30 dní)</span><b>'+(S.hasFe?apdKc(S.cost30):'<span class="ad-na">–</span>')+'</b></div>'
 +'<div><span>Tento měsíc</span><b>'+(S.hasFe?apdKc(S.costM):'<span class="ad-na">–</span>')+'</b></div>'
 +'<div><span>Výnosy přiřazené kampaním</span><b class="ad-na">Nepřipojeno</b></div><div><span>ROAS</span><b class="ad-na">nelze spočítat</b></div><div><span>ROI</span><b class="ad-na">nelze spočítat</b></div><div><span>Zisk z marketingu</span><b class="ad-na">nelze spočítat</b></div></div>'+apdRing('–','ROI')+'</div></section>'
 +'<section class="ad-card"><h3 style="margin-bottom:8px">Jak se čísla počítají</h3><ul class="ad-lst"><li><div><b>ROAS</b><small class="mut">výnosy z kampaně ÷ výdaje na reklamu. Potřebuje tržby přiřazené konkrétní kampani.</small></div></li><li><div><b>Výnosy</b><small class="mut">tržby, které lze doložit jako výsledek marketingu.</small></div></li><li><div><b>Zisk</b><small class="mut">výnosy minus všechny související náklady (reklama, práce, AI). Bez úplných nákladů i výnosů se nepočítá.</small></div></li><li><div><b>ROI</b><small class="mut">(zisk ÷ náklady). Dokud chybí výnosy nebo zisk, zobrazuje se „–“.</small></div></li></ul><p class="mut fine">Výdaje se rozpoznávají jen podle popisu finančního záznamu (marketing, reklama, Facebook, Instagram…). Je to odhad, ne účetní kategorie.</p></section>'
 +'<section class="ad-card"><div class="ad-ch"><h3>Náklady na AI a limit</h3></div><div class="ap" id="apRoot" data-nomodes="1"><p class="mut">Načítám stav limitu…</p></div></section></div>'}
function apdTabIntegr(){var L=[['Instagram','Instagram'],['Facebook','Facebook'],['TikTok',''],['YouTube',''],['Meta Ads','Reklama'],['Google Ads','Reklama']];
 return '<div class="ad-tabbody"><section class="ad-card"><div class="ad-ch"><span class="ad-ci">'+ico('link',24)+'</span><h3>Integrace</h3></div><ul class="ad-lst">'+L.map(function(x){return '<li>'+(x[1]?apdChanIcon(x[1],30):'<span class="ad-chn" style="width:30px;height:30px;background:#6b73a8">'+esc(x[0].charAt(0))+'</span>')+'<div><b>'+esc(x[0])+'</b><small class="mut">Nepřipojeno</small></div><button type="button" class="ad-btn2" data-apd-act="connect">Připojit</button></li>'}).join('')+'</ul><p class="mut fine">Propojení externích účtů zatím není k dispozici. Až bude, požádáme o souhlas a vždy půjde odpojit.</p></section></div>'}
function apdBody(){switch(APD.tab){case 'strategie':return apdTabStrategy();case 'obsah':return apdTabContent();case 'kampane':return apdTabCampaigns();case 'kalendar':return apdTabCalendar();case 'analyza':return apdTabAnalysis();case 'finance':return apdTabFinance();case 'integrace':return apdTabIntegr();default:return apdOverview()}}
function apdHtml(){apdCss();apStyle();return '<div class="apd" id="apd">'+apdHeader()+apdTabs()+'<div id="apdBody">'+apdBody()+'</div></div>'}
async function apdLoadStatus(){
 if(DEMO||APP.role==='employee')return;
 try{var r=await getSb().rpc('autopilot_status',{cid:APP.cid});if(r.error||!r.data)return;APD.st=r.data;
  var h=A('apdPill');if(h)h.innerHTML=apdPillHtml(APD.st)
 }catch(e){}}
function apdAfter(){if(APD.tab==='finance'&&A('apRoot')&&APP.role!=='employee')apLoad();apdLoadStatus();mkLoad();
 if(typeof aitLoad==='function'&&APP.role!=='employee'&&!DEMO)aitLoad().then(function(){var p=A('apdPlanBox'),t=A('apdTasksBox');if(p)p.outerHTML=apdPlan();if(t)t.outerHTML=apdTasks();apAgentsSync()})}
/* ---------- napojení na aplikaci ---------- */
var APD_MK=VIEWS.marketing;(function(){var st=document.createElement('style');st.textContent='.vxapp aside .ad-agents{display:flex;align-items:center;gap:12px;margin:10px 0 8px;padding:10px 12px;border:1px solid var(--line);border-radius:14px;background:rgba(139,108,255,.08)}.vxapp aside .ad-agents .ad-ai{color:#a78bfa;display:grid;place-items:center}.vxapp aside .ad-agents b{display:block}.vxapp aside .ad-agents small{display:flex;align-items:center;gap:7px}.vxapp aside .ad-agents small i{width:9px;height:9px;border-radius:50%;background:#7a82a8}';document.head.appendChild(st)})();
VIEWS.autopilot=function(){if(APP.role==='employee')return '<div class="card2 soonc"><h2>Autopilot</h2><p>Autopilot spravuje vlastník nebo správce.</p></div>';return apdHtml()};
VIEWS.marketing=function(){if(APP.role==='employee')return APD_MK();APD.tab='obsah';return apdHtml()};
var _apAfterM=AFTER.marketing;
AFTER.autopilot=function(){if(APP.role!=='employee')apdAfter()};
AFTER.marketing=function(){if(_apAfterM)_apAfterM();if(APP.role!=='employee')apdAfter()};
function apdGo(t){APD.tab=t;if(APP.tab!=='autopilot'&&!(APP.tab==='marketing'&&t==='obsah'))appTab(t==='obsah'?'marketing':'autopilot');else appTab(APP.tab==='marketing'&&t!=='obsah'?'autopilot':APP.tab)}
function apdModal(h){var o=document.createElement('div');o.className='apdm';o.setAttribute('role','dialog');o.setAttribute('aria-modal','true');o.innerHTML='<div>'+h+'<div style="text-align:right;margin-top:10px"><button type="button" class="ad-btn2" data-apdm="x" style="background:#222a6a;color:#fff;border:1px solid #4a56b0;border-radius:9px;padding:8px 16px;cursor:pointer">Zavřít</button></div></div>';document.body.appendChild(o);var b=o.querySelector('button');if(b)b.focus();
 function close(){o.remove();window.removeEventListener('keydown',kd,true)}function kd(e){if(e.key==='Escape'){e.stopImmediatePropagation();e.preventDefault();close()}}window.addEventListener('keydown',kd,true);o.addEventListener('click',function(e){if(e.target===o||e.target.getAttribute('data-apdm'))close()})}
if(!window.__apdBound){window.__apdBound=true;
 document.addEventListener('click',function(e){
  var g=e.target.closest&&e.target.closest('#vxapp [data-apgrp]');if(g){APD.menu=!(APD.menu===null?(['autopilot','marketing','ceo','ucetni','weby','automatizace','pripady','nabidky'].indexOf(APP.tab)>=0):APD.menu);renderNav();return}
  var t=e.target.closest&&e.target.closest('#apd [data-apd]');if(t){e.preventDefault();APD.tab=t.getAttribute('data-apd');if(APD.tab==='obsah'){APP.tab!=='marketing'?appTab('marketing'):appTab('marketing')}else{APP.tab!=='autopilot'?appTab('autopilot'):appTab('autopilot')}return}
  var b=e.target.closest&&e.target.closest('#apd [data-apd-act]');if(!b)return;var a=b.getAttribute('data-apd-act'),id=b.getAttribute('data-id');
  if(a==='wk'){APD.week+=Number(b.getAttribute('data-d'));appTab(APP.tab);return}
  if(a==='connect'){apdModal('<h3>Propojení účtů zatím není k dispozici</h3><p>Instagram, Facebook, TikTok, YouTube ani reklamní účty zatím nelze připojit. Proto Vexaronet nezná zhlédnutí, prokliky ani výsledky kampaní a nic za vás nepublikuje.</p>');return}
  if(a==='budget'){apdModal('<h3>Marketingový rozpočet zatím nelze uložit</h3><p>Pole pro měsíční marketingový rozpočet ještě nemá úložiště. Limit nákladů na AI (ne marketingový rozpočet) nastavíte v záložce Finance & ROI.</p>');return}
  if(a.indexOf('mk-')===0){mkAct(a,b,id);return}
  var p=apdRows('marketing_posts').filter(function(x){return String(x.id)===id})[0];
  if(a==='prev'&&p){mkPreview(p);return}
  if(a==='appr'&&p){mkApprovePost(p,b)}})}

function apNavSync(){var g=document.querySelector('#vxside .apg');if(!g)return;var want=APD.menu===null?(APGRP.concat(['pripady','nabidky']).indexOf(APP.tab)>=0):APD.menu;if(g.classList.contains('ad-open')!==!!want)renderNav()}

/* „Aktivní“ AI zaměstnanec = modul, který má zapnutý pravidelný plán nebo za posledních 7 dní dokončil úlohu (stav z databáze). */
function apAgentsCount(){var T=(typeof AIT!=='undefined'&&AIT.st&&AIT.cid===APP.cid)?AIT.st:null,m={};if(!T)return 0;var w=Date.now()-7*864e5;
 (T.schedules||[]).forEach(function(q){if(q.enabled)m[q.module]=1});(T.jobs||[]).forEach(function(j){if((j.status==='done'||j.status==='awaiting_approval')&&new Date(j.created_at).getTime()>=w)m[j.module]=1});return Object.keys(m).length}
function apAgentsSync(){var e=A('apAgentsN');if(e){var n=apAgentsCount();e.innerHTML='<i'+(n?' style="background:var(--ok)"':'')+'></i>'+n+' '+(n===1?'aktivní':n>=2&&n<=4?'aktivní':'aktivních')}}
function apAgentsHtml(){if(APP.role==='employee')return '';var n=apAgentsCount();return '<div class="ad-agents"><span class="ad-ai">'+ico('autopilot',26)+'</span><div><b>AI zaměstnanci</b><small id="apAgentsN"><i'+(n?' style="background:var(--ok)"':'')+'></i>'+n+' '+(n>=1&&n<=4?'aktivní':'aktivních')+'</small></div></div>'}
