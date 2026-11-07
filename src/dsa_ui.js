/* ===== DSA: odkaz „Nahlásit obsah“ na veřejných stránkách firem a přehled oznámení pro správce platformy =====
   Viz docs/PRAVNI_SOULAD.md, oblast 6. Odkaz se ukazuje jen návštěvníkům zveřejněného webu (?w=), obchodu (?s=) a rezervací (?r=),
   ne v náhledu majitele. Správce platformy (private.platform_admins) vidí v Nastavení přehled oznámení a zapisuje rozhodnutí;
   rozhodnutí obsah samo nemění. */
var VXDSA=(function(){
 function pubParam(){try{var q=new URLSearchParams(location.search);return q.get('w')?'w':q.get('s')?'s':q.get('r')?'r':''}catch(e){return ''}}
 function sync(){var on=pubParam()&&(document.getElementById('vxsite')||document.getElementById('vxbook')),l=document.getElementById('vxRep');
  if(on&&!l){l=document.createElement('a');l.id='vxRep';l.href='/nahlasit/?u='+encodeURIComponent(location.origin+location.pathname+location.search);l.target='_blank';l.rel='noopener';
   l.textContent='Nahlásit obsah';l.setAttribute('style','position:fixed;left:12px;bottom:12px;z-index:2500;font:13px/1.3 system-ui,sans-serif;padding:7px 11px;border-radius:999px;background:rgba(10,14,36,.85);color:#fff;text-decoration:underline;border:1px solid rgba(255,255,255,.3)');
   document.body.appendChild(l)}
  else if(!on&&l)l.remove()}
 if(typeof MutationObserver!=='undefined'&&typeof document!=='undefined'){var start=function(){new MutationObserver(sync).observe(document.body,{childList:true});sync()};if(document.body)start();else document.addEventListener('DOMContentLoaded',start)}
 /* ---- správce platformy ---- */
 var DEC=[['bez_opatreni','Bez opatření','neodpovida'],['odstraneni','Odstranění obsahu','nezakonny_obsah'],['znepristupneni','Znepřístupnění obsahu','nezakonny_obsah'],['omezeni_viditelnosti','Omezení viditelnosti','nezakonny_obsah'],['pozastaveni_sluzby','Pozastavení služby','smluvni_podminky'],['predano_organum','Předání orgánům','nezakonny_obsah']];
 var ST={received:'Přijato',in_review:'V posouzení',decided:'Rozhodnuto'};
 function e(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
 async function mount(){if(typeof DEMO!=='undefined'&&DEMO)return;var c=typeof getSb==='function'&&getSb();if(!c)return;var host=document.getElementById('appMain');if(!host)return;
  var r=await c.rpc('dsa_admin_list',{p_status:null});if(r.error||!Array.isArray(r.data))return;   /* není správce platformy nebo DB bez migrace: nic nezobrazit */
  var old=document.getElementById('dsaAdm');if(old)old.remove();var sec=document.createElement('section');sec.className='card2';sec.id='dsaAdm';
  sec.innerHTML='<h3>Oznámení obsahu (DSA) – správce platformy</h3><p class="mut">Rozhoduje člověk. Zápis rozhodnutí obsah nemění: omezení proveďte ručně u dotčeného webu, obchodu nebo rezervací. Oznamovatel a firma dostanou vyrozumění e-mailem.</p>'
   +(r.data.length?r.data.map(function(n){return '<details style="border-top:1px solid var(--line);padding:8px 0"><summary><b>'+e(n.ref)+'</b> · '+e(ST[n.status]||n.status)+' · '+e(n.category)+' · '+e(new Date(n.created_at).toLocaleString('cs-CZ'))+'</summary>'
    +'<p><b>Obsah:</b> '+(n.content_urls||[]).map(function(u){return e(u)}).join('<br>')+(n.location_details?'<br><b>Kde:</b> '+e(n.location_details):'')+'</p><p><b>Vysvětlení:</b> '+e(n.explanation)+'</p>'
    +'<p class="mut">Oznamovatel: '+e(n.notifier_name||'anonymně')+' '+e(n.notifier_email||'')+' · Cíl: '+e(n.target_kind||'')+' '+e(n.target_slug||'')+'</p>'
    +(n.status==='decided'?'<p><b>Rozhodnutí:</b> '+e(n.decision)+' ('+e(n.decision_ground)+') – '+e(n.decision_reason)+'</p>'
     :'<form data-dsa="'+e(n.id)+'"><label>Rozhodnutí <select name="d">'+DEC.map(function(d){return '<option value="'+d[0]+'" data-g="'+d[2]+'">'+d[1]+'</option>'}).join('')+'</select></label> '
      +'<label>Důvod <select name="g"><option value="neodpovida">Oznámení nedůvodné</option><option value="nezakonny_obsah">Nezákonný obsah</option><option value="smluvni_podminky">Rozpor s podmínkami</option></select></label>'
      +'<label style="display:block">Odůvodnění (skutečnosti, právní základ, min. 20 znaků)<textarea name="r" rows="3" style="width:100%" required minlength="20"></textarea></label><button type="submit" class="btn btn-ghost btn-sm">Zapsat rozhodnutí a vyrozumět</button> <span class="st" role="status"></span></form>')+'</details>'}).join('')
    :'<p class="mut">Žádná oznámení.</p>');
  host.appendChild(sec)}
 if(typeof document!=='undefined')document.addEventListener('submit',async function(ev){var f=ev.target.closest&&ev.target.closest('form[data-dsa]');if(!f)return;ev.preventDefault();var st=f.querySelector('.st');
  var ses=(await getSb().auth.getSession()).data.session;var r=await fetch('/api/dsa-admin',{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+(ses?ses.access_token:'')},
   body:JSON.stringify({action:'decide',id:f.getAttribute('data-dsa'),decision:f.d.value,ground:f.g.value,reason:f.r.value})});var j=await r.json().catch(function(){return {}});
  st.textContent=r.ok?'Zapsáno. Vyrozumění: oznamovatel '+j.notifier+', firma '+j.uploader+'.':'Nepodařilo se zapsat ('+(j.error||r.status)+').';if(r.ok)setTimeout(mount,800)});
 return {sync:sync,mount:mount}
})();
