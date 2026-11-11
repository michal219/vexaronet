"""UI test AI týmu v prohlížeči: přehled, šest sekcí, zadání úkolu, schvalování s otiskem, dílčí úlohy AI CEO, chat, plány, limity,
AI Účetní (doklady, duplicita, oprava, DPH, export, bankovní výpis a párování), opakování požadavku, role, ukázka a mobil.
Mock napodobuje DB funkce a endpoint /api/ai-worker; skutečné vynucení ověřují tests/db/run_ai_tym_local.sh a tests/ai_worker_e2e.test.mjs.
Spuštění: python3 tests/ai_team_ui.py"""
import functools, http.server, json, os, socketserver, sys, threading
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CID = '11111111-1111-1111-1111-111111111111'
KINDS = [['marketing', 'plan_7', 'Plán obsahu na 7 dní', True], ['marketing', 'ad_copy', 'Reklamní texty', False], ['obchodnik', 'next_steps', 'Další obchodní kroky a úkoly', True],
         ['obchodnik', 'quote_draft', 'Návrh obchodní nabídky', False], ['ceo', 'orchestrate', 'Komplexní zadání rozdělené mezi AI pracovníky', False], ['ceo', 'weekly_report', 'Týdenní report', True],
         ['ucetnictvi', 'records_review', 'Kontrola evidence příjmů a výdajů', True], ['weby_eshopy', 'seo_tips', 'SEO doporučení', False], ['automatizace', 'ops_digest', 'Provozní přehled a úkoly', True]]
MOCK = r'''
(function(){var C=window.__cfg||{};window.__log=[];
var S=window.__S={kinds:C.kinds.map(function(k){return {module:k[0],kind:k[1],title:k[2],schedulable:k[3]}}),
 limits:{monthly_nusd:250000000,per_user_nusd:null,per_run_nusd:10000000,plan_cap_nusd:2000000000,spent_nusd:12500000,paid_runs_enabled:true,by_module:{ceo:7500000,obchodnik:5000000}},
 jobs:[{id:'j0',module:'ceo',kind:'weekly_report',title:'Týdenní report <img src=x onerror=window.__xss=1>',brief:'',status:'done',source:'schedule',parent_id:null,error:null,created_at:'2026-11-10T08:00:00Z',output:{summary:'Vše v pořádku.',sections:[{title:'Priority',items:['Pohledávky']}]},cost_nusd:1050000}],
 actions:[],schedules:[],goals:[{id:'g1',title:'Tržby 20 tisíc',metric:'trzby',target:20000,value:5000,starts_on:'2026-11-01',due_on:'2026-12-01',status:'active'}]};
var ACC={settings:{regime:'neurceno',vat_payer:false},documents:[
 {id:'d1',status:'extracted',mime:'application/pdf',doc:{document_type:'received_invoice',supplier_name:'Dodavatel s.r.o.',document_number:'FV-15',total_amount:1210,vat_amount:210,vat_rate:21,issue_date:'2026-11-03',category:'material'},doc_hash:'hd1',duplicate_of:null},
 {id:'d2',status:'extracted',mime:'image/jpeg',doc:{document_type:'received_invoice',supplier_name:'Dodavatel s.r.o.',document_number:'FV-15',total_amount:1210,issue_date:'2026-11-03'},doc_hash:'hd2',duplicate_of:'d1'}],invoices:{unpaid:1,overdue:0,unpaid_amount:2420},bank_unmatched:0};
ACC.documents.forEach(function(d){d.ai_doc=JSON.parse(JSON.stringify(d.doc))});
var BANK={rows:[],counts:{all:0,unmatched:0,matched:0,ignored:0},imports:[]};
var D={companies:C.companies,company_members:C.members,subscriptions:[{plan:'pro',status:'trial',trial_end:new Date(Date.now()+20*864e5).toISOString()}]};
function qb(t){var o={_op:'sel',select(){return o},eq(){return o},limit(){return o},is(){return o},order(){return o},gte(){return o},lte(){return o},in(){return o},insert(){return Promise.resolve({error:null})},update(){o._op='u';return o},delete(){o._op='d';return o},upsert(){return Promise.resolve({error:null})},then(f){return Promise.resolve({data:o._op==='sel'?(D[t]||[]):null,error:null}).then(f)}};return o}
function ok(d){return Promise.resolve({data:d,error:null})}function err(m){return Promise.resolve({data:null,error:{message:m,code:'P0001'}})}
function rpc(n,a){a=JSON.parse(JSON.stringify(a||{}));window.__log.push([n,a]);
 if(n==='ai_team_state'){if(C.noDb)return err('Could not find the function public.ai_team_state(cid) in the schema cache');return ok(JSON.parse(JSON.stringify(S)))}
 if(n==='ai_action_decide'){var x=S.actions.filter(function(q){return q.id===a.p_action})[0];if(!x||x.payload_hash!==a.p_expected_hash)return err('stale');x.status=a.p_approve?'applied':'rejected';var j=S.jobs.filter(function(q){return q.id===x.job_id})[0];if(j&&!S.actions.some(function(q){return q.job_id===j.id&&q.status==='proposed'}))j.status='done';return ok({id:x.id})}
 if(n==='ai_schedule_save'){var s=S.schedules.filter(function(q){return q.module===a.p_module&&q.kind===a.p_kind&&q.cadence===a.p_cadence})[0];if(s)s.enabled=a.p_enabled;else S.schedules.push({id:'s'+S.schedules.length,module:a.p_module,kind:a.p_kind,title:(S.kinds.filter(function(k){return k.kind===a.p_kind})[0]||{}).title,cadence:a.p_cadence,brief:'',enabled:true,next_run_at:'2026-11-18T08:00:00Z',last_status:null});return ok({id:'s'})}
 if(n==='ai_schedule_stop_all'){S.schedules.forEach(function(q){q.enabled=false});return ok({schedules_stopped:1})}
 if(n==='ai_job_cancel'){S.jobs.filter(function(q){return q.id===a.p_job})[0].status='cancelled';return ok({})}
 if(n==='autopilot_set_limits'){S.limits.per_user_nusd=a.p_per_user_nusd;if(a.p_per_run_nusd!=null)S.limits.per_run_nusd=a.p_per_run_nusd;return ok({})}
 if(n==='ai_chat_history')return ok([{role:'user',content:'Starší dotaz'},{role:'assistant',content:'Starší odpověď'}]);
 if(n==='acc_state')return ok(JSON.parse(JSON.stringify(ACC)));
 if(n==='acc_settings_save'){ACC.settings={regime:a.p_regime,vat_payer:a.p_vat_payer};return ok({})}
 if(n==='acc_document_decide'){var d=ACC.documents.filter(function(q){return q.id===a.p_id})[0];if(d.doc_hash!==a.p_expected_hash)return err('stale');if(a.p_approve&&d.duplicate_of&&!a.p_allow_duplicate)return err('duplicate');d.status=a.p_approve?'approved':'rejected';return ok({})}
 if(n==='acc_document_update'){var d2=ACC.documents.filter(function(q){return q.id===a.p_id})[0];if(d2.doc_hash!==a.p_expected_hash)return err('stale');d2.doc=a.p_doc;d2.doc_hash='hx';d2.duplicate_of=null;return ok({})}
 if(n==='acc_vat_summary')return ok({from:a.p_from,to:a.p_to,output:[{rate:21,base:2000,vat:420}],input:[{rate:21,base:1000,vat:210,documents:1}],documents_without_vat:1,note:'Orientační přehled z údajů ve Vexaronetu. Není to daňové přiznání.'});
 if(n==='acc_export')return ok({entries:[{date:'2026-11-03',kind:'expense',title:'Nákup; materiál',amount:1210}],documents:[],invoices:[{number:'20260001',issued_on:'2026-11-05',customer:'Novák',total:2420,currency:'CZK',paid_at:null}]});
 if(n==='bank_reconciliation'){if(a.op==='list')return ok(JSON.parse(JSON.stringify(BANK)));
  if(a.op==='import'){if(!a.doc.confirmed)return err('Potvrďte výpis');a.doc.rows.forEach(function(r,i){BANK.rows.push({id:'t'+i,status:'unmatched',amount_cents:Number(r.amount_cents),currency:r.currency,booked_on:r.booked_on,variable_symbol:r.variable_symbol,description:r.description,candidates:r.variable_symbol==='20260001'?[{id:'inv1',number:'20260001',customer:'Novák',total:2420}]:[]})});BANK.counts.all=BANK.rows.length;BANK.counts.unmatched=BANK.rows.length;return ok({inserted:a.doc.rows.length,duplicates:0})}
  if(a.op==='match'){var t=BANK.rows.filter(function(q){return q.id===a.doc.id})[0];t.status='matched';t.invoice_number='20260001';BANK.counts.unmatched--;BANK.counts.matched++;return ok({matched:true})}
  return ok({saved:true})}
 if(n==='autopilot_status')return ok({root_id:a.cid,is_root:true,plan_allowed:true,platform_paid_runs_enabled:true,monthly_limit_nusd:250000000,spent_nusd:0,open_reserved_nusd:0,remaining_nusd:250000000,runs_this_month:0,month_start:new Date().toISOString(),paid_runs_possible:true,models:[]});
 if(n==='profile_get')return ok({company_id:a.cid,is_root:true,active:{version:1},draft:null,versions:[],can_write:true,schema_version:1});
 if(n==='mkt_state')return ok({profile:{confirmed:true,version:1},strategy:null,approved:null,progress:null,items:[]});if(n==='mkt_results')return ok([]);
 if(n==='company_team')return ok([]);if(n==='accept_company_invites')return ok(0);
 return ok({income:0,expenses:0,customers:0,active_jobs:0,reservations_today:0})}
window.supabase={createClient:function(){return{from:qb,rpc:rpc,auth:{getSession:()=>Promise.resolve({data:{session:{access_token:'t'}}}),getUser:()=>Promise.resolve({data:{user:{id:'u1',email:'a@b.cz',user_metadata:{full_name:'Jan Konina'}}}}),onAuthStateChange(){},updateUser:(x)=>Promise.resolve({data:{user:{user_metadata:x.data}},error:null}),signOut(){}}}}};
})();
'''
CO = [{'id': CID, 'name': 'Autoservis Konina', 'industry': 'Autoservis', 'parent_company_id': None, 'created_at': '2026-10-01T00:00:00Z'}]
def members(role='owner'): return [{'company_id': CID, 'role': role, 'companies': CO[0]}]
fails = []
def check(c, m):
    print(('OK   ' if c else 'FAIL ') + m)
    if not c: fails.append(m)
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(s, *a): pass
srv = socketserver.TCPServer(('127.0.0.1', 0), functools.partial(Q, directory=ROOT + '/public')); BASE = 'http://127.0.0.1:%d/index.html' % srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
API = {'calls': [], 'mode': []}
def api(pg):
    def h(route):
        b = json.loads(route.request.post_data or '{}'); API['calls'].append(b); mode = API['mode'].pop(0) if API['mode'] else 'ok'
        if mode == 'abort': return route.abort()
        if mode == 'disabled': return route.fulfill(status=403, content_type='application/json', body=json.dumps({'error': 'paid_runs_disabled', 'message': 'Placené AI běhy zatím nejsou zapnuté provozovatelem. Nic se neúčtovalo.'}))
        if b['op'] == 'chat': return route.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True, 'reply': 'Tržby jsou 12 000 Kč. <b>tučně</b>'}))
        if b['op'] == 'run':
            pg.evaluate("""b=>{var S=window.__S,id='j'+S.jobs.length;
              if(b.kind==='orchestrate'){S.jobs.unshift({id:id,module:'ceo',kind:'orchestrate',title:'Komplexní zadání',brief:b.brief,status:'done',source:'user',parent_id:null,created_at:new Date().toISOString(),output:{summary:'Plán na růst tržeb.',sections:[]},cost_nusd:2000000});
                S.jobs.push({id:'c1',module:'marketing',kind:'plan_7',title:'Plán obsahu na 7 dní',brief:'Kampaň na servis',status:'queued',source:'ceo',parent_id:id,created_at:new Date().toISOString(),output:null});
                S.jobs.push({id:'c2',module:'obchodnik',kind:'next_steps',title:'Další obchodní kroky a úkoly',brief:'Oslovit firmy',status:'queued',source:'ceo',parent_id:id,created_at:new Date().toISOString(),output:null})}
              else{S.jobs.unshift({id:id,module:b.module,kind:b.kind,title:'Další obchodní kroky a úkoly',brief:b.brief,status:'awaiting_approval',source:'user',parent_id:null,created_at:new Date().toISOString(),output:{summary:'Tři kroky na tento týden.',sections:[{title:'Priority',items:['Zavolat Dopravě Novák']}],dropped_actions:1},cost_nusd:1050000});
                S.actions.push({id:'a1',job_id:id,module:b.module,type:'task',payload:{title:'Zavolat Dopravě Novák',due_in_days:2},payload_hash:'ha1',status:'proposed'},
                               {id:'a2',job_id:id,module:b.module,type:'quote_draft',payload:{title:'Servisní balíček',items:[{name:'Výměna oleje',qty:1,price:1500}],total:1500},payload_hash:'ha2',status:'proposed'})}}""", b)
        else:
            pg.evaluate("id=>{var j=window.__S.jobs.filter(function(q){return q.id===id})[0];j.status='done';j.output={summary:'Dílčí úloha hotová.',sections:[]}}", b['job_id'])
        route.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True}))
    return h
def open_page(b, cfg, vp=None):
    ctx = b.new_context(viewport=vp or {'width': 1400, 'height': 1000}, accept_downloads=True); pg = ctx.new_page(); pg.errs = []
    pg.on('pageerror', lambda e: pg.errs.append(str(e))); pg.on('dialog', lambda d: d.accept('vlastní převod') if d.type == 'prompt' else d.accept())
    pg.add_init_script('window.__cfg=' + json.dumps(dict(cfg, companies=CO, kinds=KINDS)) + ';'); pg.add_init_script(MOCK)
    pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.route('**/api/registration', lambda r: r.fulfill(status=503, body='{}', content_type='application/json'))
    pg.route('**/api/ai-worker', api(pg)); pg.goto(BASE); pg.wait_for_timeout(500)
    pg.evaluate("document.getElementById('acc').click()"); pg.wait_for_selector('#vxapp .kpi'); pg.wait_for_timeout(400); return pg
def tab(pg, t): pg.click('#ait [data-ait-tab=%s]' % t); pg.wait_for_timeout(500)
def log(pg, n): return pg.evaluate("window.__log.filter(function(x){return x[0]==='%s'}).map(function(x){return x[1]})" % n)
def toast(pg): return pg.inner_text('#appToast')

with sync_playwright() as p:
    b = p.chromium.launch()
    pg = open_page(b, {'members': members()})
    check('AI tým (přehled)' in pg.inner_text('#vxside .ad-sub'), 'v menu AI Autopilot je položka AI tým')
    pg.click('#vxside [data-tab=aitym]'); pg.wait_for_selector('#ait .ait-tabs'); pg.wait_for_timeout(500)
    check([x.strip() for x in pg.locator('#ait .ait-tabs button').all_inner_texts()] == ['Přehled', 'AI Marketing', 'AI Obchodník', 'AI CEO', 'AI Účetní', 'AI Weby a e-shopy', 'AI Automatizace'], 'horní přepínač: přehled a šest AI pracovníků')
    t = pg.inner_text('#ait')
    check('0,0125 USD' in t and '0,25 USD' in t and '5 %' in t and 'AI CEO: 0,0075 USD' in t, 'přehled: spotřeba 0,0125 z 0,25 USD (5 %) a rozpad po modulech')
    check('Limit na jednu operaci: 0,01 USD' in t and 'strop tarifu: 2,00 USD' in t, 'přehled: limit na operaci a strop tarifu')
    check('Tržby 20 tisíc' in t and '5 000 z 20 000' in t.replace('\u00a0', ' '), 'měřitelný cíl s plněním ze skutečných dat')
    check(pg.evaluate('window.__xss') is None and '<img' in pg.inner_text('#ait'), 'názvy úloh jsou escapované (žádné spuštění skriptu)')
    # limity
    pg.click('#aitLim >> xpath=ancestor::details/summary'); pg.fill('#ait_lu', '0,10'); pg.fill('#ait_lr', 'abc'); pg.click('#aitLim button[type=submit]'); pg.wait_for_timeout(200)
    check(len(log(pg, 'autopilot_set_limits')) == 0, 'neplatná částka limitu se neodešle')
    pg.fill('#ait_lr', '0,005'); pg.click('#aitLim button[type=submit]'); pg.wait_for_timeout(500)
    L = log(pg, 'autopilot_set_limits')
    check(len(L) == 1 and L[0]['p_per_user_nusd'] == 100000000 and L[0]['p_per_run_nusd'] == 5000000 and L[0]['cid'] == CID, 'limity na uživatele a operaci se uloží v nanodolarech pro aktivní firmu')
    # zadání úkolu: nejdřív vypnuté placené běhy, pak přerušené spojení a opakování se stejným klíčem
    tab(pg, 'obchodnik')
    check(pg.locator('#ait_kind option').count() == 2 and 'Odesílání e-mailů zákazníkům' in pg.inner_text('#ait') and 'Nepřipojeno' in pg.inner_text('#ait'), 'sekce AI Obchodník: jeho úlohy a poctivý stav externího propojení')
    pg.fill('#ait_brief', 'Zaměř se na servisní smlouvy'); API['mode'] = ['disabled']; pg.click('#aitRun button[type=submit]'); pg.wait_for_timeout(600)
    check('nejsou zapnuté' in toast(pg), 'vypnuté placené běhy: srozumitelná hláška')
    API['mode'] = ['abort']; pg.click('#aitRun button[type=submit]'); pg.wait_for_timeout(600)
    k_abort = API['calls'][-1]['key']; check('přerušilo' in toast(pg) and pg.input_value('#ait_brief') != '', 'přerušené spojení: zadání zůstane a hláška říká, že se neplatí dvakrát')
    pg.click('#aitRun button[type=submit]'); pg.wait_for_timeout(900)
    c = API['calls'][-1]
    check(c['key'] == k_abort and c['op'] == 'run' and c['module'] == 'obchodnik' and c['kind'] == 'next_steps' and c['brief'] == 'Zaměř se na servisní smlouvy' and c['cid'] == CID, 'opakování po výpadku posílá stejný idempotenční klíč')
    t = pg.inner_text('#ait')
    check('Tři kroky na tento týden.' in t and 'čeká na schválení' in t and '1 návrhů AI neprošlo kontrolou' in t, 'výsledek úlohy se zobrazí včetně informace o zahozených návrzích')
    check(pg.locator('#ait .ait-act').count() == 2 and 'Celkem' in t and 'Servisní balíček' in t, 'návrhy akcí jsou čitelné (úkol, koncept nabídky s položkami)')
    pg.click('#ait [data-ait=act-ok][data-id=a1]'); pg.wait_for_timeout(600)
    d = log(pg, 'ai_action_decide')
    check(len(d) == 1 and d[0] == {'cid': CID, 'p_action': 'a1', 'p_expected_hash': 'ha1', 'p_approve': True} and 'provedeno' in pg.inner_text('#ait'), 'schválení posílá otisk zobrazeného obsahu')
    pg.click('#ait [data-ait=act-no][data-id=a2]'); pg.wait_for_timeout(600)
    check(log(pg, 'ai_action_decide')[-1]['p_approve'] is False and 'zamítnuto' in pg.inner_text('#ait'), 'zamítnutí návrhu')
    # plán
    pg.select_option('#ait_sc', 'daily'); pg.click('#aitSch button[type=submit]'); pg.wait_for_timeout(500)
    s = log(pg, 'ai_schedule_save')
    check(len(s) == 1 and s[0]['p_module'] == 'obchodnik' and s[0]['p_kind'] == 'next_steps' and s[0]['p_cadence'] == 'daily' and s[0]['p_enabled'] is True and 'zapnuto' in pg.inner_text('#ait'), 'pravidelný plán se uloží a zobrazí')
    pg.click('#ait [data-ait=sch-stop]'); pg.wait_for_timeout(500)
    check(len(log(pg, 'ai_schedule_stop_all')) == 1 and 'vypnuto' in pg.inner_text('#ait'), 'automatizaci lze zastavit jedním tlačítkem')
    # AI CEO: komplexní zadání, dílčí úlohy, chat
    tab(pg, 'ceo'); pg.select_option('#ait_kind', 'orchestrate'); pg.fill('#ait_brief', 'Chci zvýšit tržby o 20 %'); pg.click('#aitRun button[type=submit]'); pg.wait_for_timeout(900)
    t = pg.inner_text('#ait')
    check('Dílčí úlohy pro AI pracovníky (2)' in t and 'zadal AI CEO' in t and pg.locator('#ait [data-ait=job-run]').count() == 2, 'AI CEO rozdělí zadání na dílčí úlohy pro další pracovníky')
    pg.click('#ait [data-ait=job-run][data-id=c1]'); pg.wait_for_timeout(900)
    check(API['calls'][-1]['op'] == 'run_job' and API['calls'][-1]['job_id'] == 'c1' and pg.locator('#ait [data-ait=job-run]').count() == 1, 'dílčí úlohu spustí člověk a její stav se sleduje')
    check('Starší odpověď' in pg.inner_text('#aitChat'), 'chat načte uloženou historii')
    pg.fill('#ait_msg', 'Jak jsme na tom?'); pg.click('#aitChatF button[type=submit]'); pg.wait_for_timeout(700)
    c = API['calls'][-1]
    check(c['op'] == 'chat' and c['module'] == 'ceo' and c['message'] == 'Jak jsme na tom?' and 'Tržby jsou 12 000 Kč.' in pg.inner_text('#aitChat') and pg.locator('#aitChat b').count() == 0, 'chat: odpověď se zobrazí jako text (bez HTML)')
    # AI Účetní
    tab(pg, 'ucetnictvi'); pg.wait_for_timeout(400); t = pg.inner_text('#ait')
    check('AI Účetní připravuje podklady, nerozhoduje' in t and 'možná duplicita' in t and 'Bankovní účet není propojený' in t, 'AI Účetní: upozornění, příznak duplicity a poctivý stav banky')
    pg.select_option('#ait_reg', 'danova_evidence'); pg.check('#ait_vat'); pg.click('#aitReg button[type=submit]'); pg.wait_for_timeout(500)
    check(log(pg, 'acc_settings_save')[-1] == {'cid': CID, 'p_regime': 'danova_evidence', 'p_vat_payer': True}, 'režim evidence (daňová evidence, plátce DPH) se uloží')
    pg.click('#ait [data-ait=doc-ok][data-id=d1]'); pg.wait_for_timeout(600)
    check(log(pg, 'acc_document_decide')[-1] == {'cid': CID, 'p_id': 'd1', 'p_expected_hash': 'hd1', 'p_approve': True, 'p_allow_duplicate': False}, 'schválení dokladu posílá otisk')
    pg.click('#ait [data-ait=doc-edit][data-id=d2]'); pg.wait_for_selector('#aitDocF'); pg.fill('#aitd_document_number', 'FV-16'); pg.fill('#aitd_total_amount', '605'); pg.click('#aitDocF button[type=submit]'); pg.wait_for_timeout(600)
    u = log(pg, 'acc_document_update')
    check(len(u) == 1 and u[0]['p_expected_hash'] == 'hd2' and u[0]['p_doc']['document_number'] == 'FV-16' and u[0]['p_doc']['total_amount'] == 605 and 'upraveno člověkem' in pg.inner_text('#ait'), 'oprava údajů dokladu člověkem')
    pg.click('#aitVat button[type=submit]'); pg.wait_for_timeout(500); t = pg.inner_text('#ait')
    check('orientačně' in t and '210' in t and 'Není to daňové přiznání' in t and '1 dokladů nemá uvedenou částku DPH' in t, 'přehled DPH: výstup, vstup, rozdíl a upozornění')
    with pg.expect_download() as dl: pg.click('#ait [data-ait=acc-export]')
    csv = open(dl.value.path(), encoding='utf-8-sig').read()
    check(csv.startswith('typ;datum') and '"Nákup; materiál";-1210' in csv and 'vystavena faktura;2026-11-05;20260001' in csv, 'export CSV: záznamy a faktury, středník v textu je v uvozovkách')
    pg.set_input_files('#ait_bf', {'name': 'vypis.csv', 'mimeType': 'text/csv', 'buffer': 'ID pohybu;Datum;Objem;Měna;VS;Zpráva pro příjemce\n1;05.11.2026;2420,00;CZK;20260001;Faktura\n2;06.11.2026;-350,50;CZK;;Nákup\n'.encode('utf-8')}); pg.wait_for_timeout(400)
    check('Načteno 2 pohybů' in pg.inner_text('#ait'), 'bankovní výpis CSV se načte')
    pg.fill('#ait_ba', 'Fio CZK'); pg.click('#aitCsv button[type=submit]'); pg.wait_for_timeout(300)
    check(not any(x['op'] == 'import' for x in log(pg, 'bank_reconciliation')) and 'Potvrďte' in toast(pg), 'bez potvrzení skutečného výpisu se nic nenahraje')
    pg.check('#ait_bc'); pg.click('#aitCsv button[type=submit]'); pg.wait_for_timeout(700)
    im = [x for x in log(pg, 'bank_reconciliation') if x['op'] == 'import']
    check(len(im) == 1 and im[0]['doc']['account_key'] == 'Fio CZK' and im[0]['doc']['confirmed'] is True and im[0]['doc']['rows'][0] == {'external_id': '1', 'booked_on': '2026-11-05', 'amount_cents': '242000', 'currency': 'CZK', 'variable_symbol': '20260001', 'description': 'Faktura'}, 'import posílá převedené pohyby stávající funkci bank_reconciliation')
    check('Odpovídá faktuře 20260001' in pg.inner_text('#ait') and 'Odchozí platba' in pg.inner_text('#ait'), 'pohyb se shodným VS a částkou nabídne fakturu ke spárování')
    pg.click('#ait [data-ait=bank-match]'); pg.wait_for_timeout(700)
    mt = [x for x in log(pg, 'bank_reconciliation') if x['op'] == 'match']
    check(len(mt) == 1 and mt[0]['doc'] == {'id': 't0', 'invoice_id': 'inv1', 'confirmed': True} and 'spárováno' in pg.inner_text('#ait'), 'úhradu faktury potvrzuje člověk')
    check(not pg.errs, 'bez chyb JS: %s' % pg.errs); pg.context.close()

    pg = open_page(b, {'members': members(), 'noDb': True}); pg.click('#vxside [data-tab=aitym]'); pg.wait_for_timeout(600)
    check('ještě není v databázi nasazená' in pg.inner_text('#ait') and pg.locator('#aitRun').count() == 0, 'bez migrace: srozumitelná hláška, žádné tlačítko AI'); pg.context.close()
    pg = open_page(b, {'members': members('employee')})
    check(pg.locator('#vxside [data-tab=aitym]').count() == 0 and len(log(pg, 'ai_team_state')) == 0, 'zaměstnanec AI tým nevidí a stav nenačítá'); pg.context.close()
    pg = open_page(b, {'members': members()}, vp={'width': 390, 'height': 800}); pg.evaluate("var x=document.createElement('button');x.dataset.tab='aitym';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_selector('#ait .ait-tabs'); pg.wait_for_timeout(500)
    pg.click('#ait [data-ait-tab=ucetnictvi]'); pg.wait_for_timeout(600)
    w = pg.evaluate("[document.documentElement.scrollWidth, innerWidth, document.getElementById('appMain').scrollWidth, document.getElementById('appMain').clientWidth]")
    check(w[0] <= w[1] + 1 and w[2] <= w[3] + 1, 'mobil 390 px: AI tým i účetní sekce bez vodorovného posouvání %s' % w); pg.context.close()
    ctx = b.new_context(); pg = ctx.new_page(); pg.route('**/supabase.js', lambda r: r.fulfill(body='', content_type='text/javascript')); pg.route('**/api/registration', lambda r: r.fulfill(status=503, body='{}', content_type='application/json'))
    pg.goto(BASE); pg.wait_for_timeout(400); pg.click('#top .cta [data-demo]'); pg.wait_for_selector('#vxapp .kpi')
    pg.evaluate("var x=document.createElement('button');x.dataset.tab='aitym';document.querySelector('#vxapp').appendChild(x);x.click()"); pg.wait_for_timeout(400)
    check('V ukázce se AI tým nespouští' in pg.inner_text('#appMain'), 'ukázka: AI tým se nespouští'); ctx.close()
    b.close()
srv.shutdown()
print('\nSELHALO: %d' % len(fails) if fails else '\nVšechny kontroly prošly.')
sys.exit(1 if fails else 0)
