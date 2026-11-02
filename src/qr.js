/* Vexaronet: vlastní generátor QR kódu (bajtový režim, korekce M, verze 1 až 10). Vrací SVG řetězec.
   Žádné externí knihovny. Ověřeno dekódováním v testech (tests/faktury_qr.py). */
var VXQR=(function(){
 var EXP=[],LOG=[];(function(){var x=1,i;for(i=0;i<255;i++){EXP[i]=x;LOG[x]=i;x<<=1;if(x&256)x^=0x11d}for(i=255;i<512;i++)EXP[i]=EXP[i-255]})();
 function gm(a,b){return a&&b?EXP[LOG[a]+LOG[b]]:0}
 function gen(d){var r=[1],i,j,n;for(i=0;i<d;i++){n=[];for(j=0;j<=r.length;j++)n.push(0);for(j=0;j<r.length;j++){n[j]^=r[j];n[j+1]^=gm(r[j],EXP[i])}r=n}return r}
 function rs(data,d){var g=gen(d),res=[],i,j,f;for(i=0;i<d;i++)res.push(0);for(i=0;i<data.length;i++){f=data[i]^res.shift();res.push(0);for(j=0;j<d;j++)res[j]^=gm(g[j+1],f)}return res}
 /* verze: [datové kódová slova, EC na blok, bloky skupiny 1, délka, bloky skupiny 2, délka] pro úroveň M */
 var VT={1:[16,10,1,16,0,0],2:[28,16,1,28,0,0],3:[44,26,1,44,0,0],4:[64,18,2,32,0,0],5:[86,24,2,43,0,0],6:[108,16,4,27,0,0],7:[124,18,4,31,0,0],8:[154,22,2,38,2,39],9:[182,22,3,36,2,37],10:[216,26,4,43,1,44]};
 var AL={1:[],2:[6,18],3:[6,22],4:[6,26],5:[6,30],6:[6,34],7:[6,22,38],8:[6,24,42],9:[6,26,46],10:[6,28,50]};
 function utf8(s){var o=[],i,c;s=unescape(encodeURIComponent(s));for(i=0;i<s.length;i++){c=s.charCodeAt(i);o.push(c)}return o}
 function encode(text){
  var b=utf8(text),v,t,bits=[];
  for(v=1;v<=10;v++){var cb=v<10?8:16;if(4+cb+b.length*8<=VT[v][0]*8)break}
  if(v>10)throw new Error('Text je příliš dlouhý pro QR kód.');
  t=VT[v];
  function put(val,n){for(var i=n-1;i>=0;i--)bits.push((val>>>i)&1)}
  put(4,4);put(b.length,v<10?8:16);b.forEach(function(x){put(x,8)});
  var cap=t[0]*8;put(0,Math.min(4,cap-bits.length));while(bits.length%8)bits.push(0);
  var cw=[],i,j;for(i=0;i<bits.length;i+=8){var x=0;for(j=0;j<8;j++)x=x*2+bits[i+j];cw.push(x)}
  for(i=0;cw.length<t[0];i++)cw.push(i%2?0x11:0xEC);
  var blocks=[],pos=0,k;
  for(k=0;k<t[2];k++){blocks.push(cw.slice(pos,pos+t[3]));pos+=t[3]}
  for(k=0;k<t[4];k++){blocks.push(cw.slice(pos,pos+t[5]));pos+=t[5]}
  var ecs=blocks.map(function(bl){return rs(bl,t[1])}),out=[],mx=Math.max(t[3],t[5]);
  for(i=0;i<mx;i++)blocks.forEach(function(bl){if(i<bl.length)out.push(bl[i])});
  for(i=0;i<t[1];i++)ecs.forEach(function(e){out.push(e[i])});
  return {v:v,cw:out}}
 function build(v,cw){
  var n=17+4*v,M=[],F=[],i,j;for(i=0;i<n;i++){M.push([]);F.push([]);for(j=0;j<n;j++){M[i].push(0);F[i].push(false)}}
  function set(x,y,d){if(x<0||y<0||x>=n||y>=n)return;M[y][x]=d?1:0;F[y][x]=true}
  function finder(cx,cy){for(var dy=-4;dy<=4;dy++)for(var dx=-4;dx<=4;dx++){var d=Math.max(Math.abs(dx),Math.abs(dy));set(cx+dx,cy+dy,d!==4&&d!==2)}}
  finder(3,3);finder(n-4,3);finder(3,n-4);
  for(i=8;i<n-8;i++){set(6,i,i%2===0);set(i,6,i%2===0)}
  var al=AL[v];al.forEach(function(ay){al.forEach(function(ax){if((ax===6&&ay===6)||(ax===6&&ay===al[al.length-1])||(ax===al[al.length-1]&&ay===6))return;for(var dy=-2;dy<=2;dy++)for(var dx=-2;dx<=2;dx++)set(ax+dx,ay+dy,Math.max(Math.abs(dx),Math.abs(dy))!==1)})});
  set(8,n-8,true);
  function fmt(mask){var d=mask,r=d,q;for(q=0;q<10;q++)r=(r<<1)^((r>>>9)*0x537);var bits=((d<<10)|r)^0x5412,g=function(k){return (bits>>>k)&1};
   for(q=0;q<=5;q++)set(8,q,g(q));set(8,7,g(6));set(8,8,g(7));set(7,8,g(8));for(q=9;q<15;q++)set(14-q,8,g(q));
   for(q=0;q<8;q++)set(n-1-q,8,g(q));for(q=8;q<15;q++)set(8,n-15+q,g(q));set(8,n-8,true)}
  fmt(0);
  if(v>=7){var r=v,q;for(q=0;q<12;q++)r=(r<<1)^((r>>>11)*0x1F25);var bits=(v<<12)|r;for(q=0;q<18;q++){var bit=(bits>>>q)&1,a=n-11+(q%3),c=Math.floor(q/3);set(a,c,bit);set(c,a,bit)}}
  var data=[];cw.forEach(function(c){for(var k=7;k>=0;k--)data.push((c>>>k)&1)});
  var idx=0,up=true,x,y,xx;
  for(x=n-1;x>=1;x-=2){if(x===6)x=5;for(var s=0;s<n;s++){y=up?n-1-s:s;for(xx=0;xx<2;xx++){var cx=x-xx;if(!F[y][cx]){M[y][cx]=idx<data.length?data[idx]:0;idx++}}}up=!up}
  return {n:n,M:M,F:F,fmt:fmt}}
 var MASKS=[function(x,y){return (x+y)%2===0},function(x,y){return y%2===0},function(x,y){return x%3===0},function(x,y){return (x+y)%3===0},function(x,y){return (Math.floor(x/3)+Math.floor(y/2))%2===0},function(x,y){return (x*y)%2+(x*y)%3===0},function(x,y){return ((x*y)%2+(x*y)%3)%2===0},function(x,y){return ((x+y)%2+(x*y)%3)%2===0}];
 function penalty(M,n){
  var p=0,x,y,run,c;
  for(y=0;y<n;y++){run=1;for(x=1;x<n;x++){if(M[y][x]===M[y][x-1])run++;else{if(run>=5)p+=run-2;run=1}}if(run>=5)p+=run-2}
  for(x=0;x<n;x++){run=1;for(y=1;y<n;y++){if(M[y][x]===M[y-1][x])run++;else{if(run>=5)p+=run-2;run=1}}if(run>=5)p+=run-2}
  for(y=0;y<n-1;y++)for(x=0;x<n-1;x++){c=M[y][x];if(c===M[y][x+1]&&c===M[y+1][x]&&c===M[y+1][x+1])p+=3}
  var pa=[1,0,1,1,1,0,1,0,0,0,0],pb=[0,0,0,0,1,0,1,1,1,0,1];
  function m(get,k,pt){for(var i=0;i<11;i++)if(get(k+i)!==pt[i])return false;return true}
  for(y=0;y<n;y++)for(x=0;x<=n-11;x++){if(m(function(i){return M[y][i]},x,pa)||m(function(i){return M[y][i]},x,pb))p+=40}
  for(x=0;x<n;x++)for(y=0;y<=n-11;y++){if(m(function(i){return M[i][x]},y,pa)||m(function(i){return M[i][x]},y,pb))p+=40}
  var dark=0;for(y=0;y<n;y++)for(x=0;x<n;x++)dark+=M[y][x];
  var k=Math.ceil(Math.abs(dark*20-n*n*10)/(n*n))-1;p+=Math.max(0,k)*10;return p}
 /* vrací matici (pole řádků 0/1) */
 function matrix(text){
  var e=encode(text),b=build(e.v,e.cw),best=null,bp=1e9,m,x,y;
  for(m=0;m<8;m++){var C=b.M.map(function(r){return r.slice()});
   for(y=0;y<b.n;y++)for(x=0;x<b.n;x++)if(!b.F[y][x]&&MASKS[m](x,y))C[y][x]^=1;
   /* formátové bity dané masky */
   var tmp={M:C};(function(){var n=b.n,d=m,r=d,q;for(q=0;q<10;q++)r=(r<<1)^((r>>>9)*0x537);var bits=((d<<10)|r)^0x5412,g=function(k){return (bits>>>k)&1};
    function st(xx,yy,v){C[yy][xx]=v}
    for(q=0;q<=5;q++)st(8,q,g(q));st(8,7,g(6));st(8,8,g(7));st(7,8,g(8));for(q=9;q<15;q++)st(14-q,8,g(q));
    for(q=0;q<8;q++)st(n-1-q,8,g(q));for(q=8;q<15;q++)st(8,n-15+q,g(q));st(8,n-8,1)})();
   var pn=penalty(C,b.n);if(pn<bp){bp=pn;best=C}}
  return best}
 function svg(text,opt){opt=opt||{};var M=matrix(text),n=M.length,q=4,s=n+q*2,d='',x,y;
  for(y=0;y<n;y++){var x0=-1;for(x=0;x<=n;x++){var on=x<n&&M[y][x]===1;if(on&&x0<0)x0=x;if(!on&&x0>=0){d+='M'+(x0+q)+' '+(y+q)+'h'+(x-x0)+'v1h-'+(x-x0)+'z';x0=-1}}}
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+s+' '+s+'" shape-rendering="crispEdges" role="img" aria-label="'+(opt.label||'QR platba')+'"><rect width="'+s+'" height="'+s+'" fill="#fff"/><path d="'+d+'" fill="#000"/></svg>'}
 return {matrix:matrix,svg:svg}
})();
if(typeof module!=='undefined')module.exports=VXQR;
