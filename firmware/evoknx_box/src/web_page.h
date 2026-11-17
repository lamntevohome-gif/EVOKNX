// The web page of the box (everything in one file). It only shows information, and only to the home network (the box refuses reads
// from other networks). The timers are made on the phone, the settings in the Editor.
#pragma once
#include <Arduino.h>

static const char kPage[] PROGMEM = R"HTML(<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EvoKNX Box</title>
<style>
:root{--bg:#f4f5f4;--panel:#fff;--ink:#1d2321;--muted:#68726e;--line:#dde1df;--acc:#1e7f57;--bad:#d4452a;--warn:#b35c00}
@media(prefers-color-scheme:dark){:root{--bg:#161a18;--panel:#1f2523;--ink:#e8ecea;--muted:#98a39e;--line:#323a37;--acc:#3bb27f;--bad:#f47560;--warn:#e8a33d}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,Segoe UI,Roboto,sans-serif}
header{padding:14px 16px;background:var(--panel);border-bottom:1px solid var(--line);display:flex;gap:10px;align-items:center}
header b{font-size:17px}header span{color:var(--muted)}
main{max-width:920px;margin:0 auto;padding:16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px;margin-bottom:12px}
.card h3{margin:0 0 8px;font-size:15px}
.row{display:flex;justify-content:space-between;gap:12px;padding:5px 0;border-top:1px solid var(--line)}.row:first-of-type{border-top:0}
.row span:first-child{color:var(--muted)}
nav{display:flex;gap:6px;margin-bottom:12px;flex-wrap:wrap}
nav button,.btn{border:1px solid var(--line);background:var(--panel);color:var(--ink);padding:7px 12px;border-radius:6px;font:inherit;cursor:pointer}
nav button.on,.btn.pri{background:var(--acc);border-color:var(--acc);color:#fff}
input{font:inherit;padding:7px 9px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--ink);min-width:0}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:var(--bad)}.dot.ok{background:#14ae5c}
.muted{color:var(--muted)}.bad{color:var(--bad)}.warn{color:var(--warn)}
table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:7px 6px;border-top:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:500;font-size:13px;border-top:0}
.tag{display:inline-block;padding:1px 7px;border-radius:10px;border:1px solid var(--line);font-size:12px;color:var(--muted)}
.day{font-weight:600;margin:14px 0 4px}
.log{display:grid;grid-template-columns:62px 1fr;gap:2px 10px;font-size:14px}.log i{font-style:normal;color:var(--muted)}
.hide{display:none}.msg{margin-top:8px;font-size:13px}
</style></head><body>
<header><b>EvoKNX Box</b><span id="name"></span></header>
<main>
<div id="app">
<nav id="nav"></nav>
<section id="s-over"></section>
<section id="s-timers" class="hide"></section>
<section id="s-log" class="hide"></section>
</div></main>
<script>
let TZ=0,TAB='over',TIMER=0;
async function api(path){
 const r=await fetch(path,{cache:'no-store'});
 const j=await r.json().catch(()=>({}));
 if(r.status===403)throw new Error('Open this page from the home network.');
 if(!r.ok)throw new Error(j.error||('Error '+r.status));return j}
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const TABS=[['over','Overview'],['timers','Timers'],['log','Log (7 days)']];
function start(){$('nav').innerHTML=TABS.map(t=>`<button id="b-${t[0]}" onclick="show('${t[0]}')">${t[1]}</button>`).join('');show('over');clearInterval(TIMER);TIMER=setInterval(()=>{if(TAB!=='log')load()},5000)}
function show(t){TAB=t;TABS.forEach(x=>{$('s-'+x[0]).classList.toggle('hide',x[0]!==t);$('b-'+x[0]).classList.toggle('on',x[0]===t)});load()}
function ago(s){if(s<0)return 'never';if(s<60)return s+' s ago';if(s<3600)return Math.floor(s/60)+' min ago';return Math.floor(s/3600)+' h ago'}
function up(s){const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return (d?d+' d ':'')+h+' h '+m+' min'}
const row=(a,b)=>`<div class="row"><span>${a}</span><span>${b}</span></div>`;
const dot=ok=>`<span class="dot ${ok?'ok':''}"></span>`;
const ga=g=>((g>>11)&31)+'/'+((g>>8)&7)+'/'+(g&255);
function val(a,s){if(s)return a==='01'?'On':a==='00'?'Off':'value '+parseInt(a,16);return '0x'+a}
function days(d){const n=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];if(d===127)return 'Every day';if(d===31)return 'Mon–Fri';if(d===96)return 'Sat, Sun';return n.filter((_,i)=>d&(1<<i)).join(', ')}
function dur(s){if(s%3600===0)return s/3600+' h';if(s%60===0)return s/60+' min';return s+' s'}
function clock(m){return String(Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0')}
function left(s){return Math.floor(s/60)+':'+String(s%60).padStart(2,'0')}
async function load(){try{
 const s=await api('/api/status');TZ=s.tz;$('name').textContent=s.name;
 if(TAB==='over')$('s-over').innerHTML=`<div class="card"><h3>Time</h3>${row('Box time',s.timeOk?esc(s.time):'<span class="warn">not set yet</span>')}${row('Time zone','UTC'+(s.tz<0?'-':'+')+String(Math.floor(Math.abs(s.tz)/60)).padStart(2,'0')+':'+String(Math.abs(s.tz)%60).padStart(2,'0')+' <span class="muted">(set in the Editor)</span>')}${row('Internet time (NTP)',(s.ntpSynced?dot(true)+'synchronised':dot(false)+'not synchronised')+' <span class="muted">('+esc(s.ntp)+')</span>')}</div>
 <div class="card"><h3>KNX bus</h3>${row('Connection',(s.busUp?dot(true)+'connected':dot(false)+'not connected')+' <span class="muted">('+(s.mode==='tunnel'?'tunneling, KNX IP Interface':'routing, KNX IP Router')+')</span>')}${s.busErr?row('Problem','<span class="bad">'+esc(s.busErr)+'</span>'):''}${row('Last telegram received',ago(s.rxAgo))}${row('Last telegram sent',ago(s.txAgo))}</div>
 <div class="card"><h3>Box</h3>${row('Timers',s.count+(s.running.length?' ('+s.running.length+' counting down)':''))}${row('Address',esc(s.ip))}${row('Firmware',esc(s.fw))}${row('Running for',up(s.uptime))}${row('Settings version',esc(s.rev||'none'))}</div>`;
 if(TAB==='timers'){const c=await api('/api/config');const run={};s.running.forEach(r=>run[r.id]=r.left);
  const t=c.timers||[];$('s-timers').innerHTML=`<div class="card"><h3>Timers</h3>${t.length?`<table><tr><th>Name</th><th>When</th><th>Writes</th></tr>`+t.map(x=>x.k==='s'
  ?`<tr><td>${esc(x.n||'Schedule')}</td><td>${clock(x.m)}, ${days(x.d)}</td><td>${ga(x.g)} ${esc(x.gn)} = ${val(x.a,x.as)}</td></tr>`
  :`<tr><td>${esc(x.n||'Countdown')}<br><span class="tag">countdown</span></td><td>${ga(x.w)} ${esc(x.wn)} becomes ${val(x.v,x.vs)}, then wait ${dur(x.s)}${run[x.id]!==undefined?'<br><b>counting down: '+left(run[x.id])+' left</b>':''}${x.r?'':'<br><span class="muted">does not restart</span>'}</td><td>${ga(x.g)} ${esc(x.gn)} = ${val(x.a,x.as)}</td></tr>`).join('')+'</table>':'<p class="muted">No timers yet. Make them in the EvoKNX App (Settings, Schedulers).</p>'}</div><p class="muted">Timers are made and changed in the EvoKNX App (Settings, Schedulers). Timers that are switched off are not listed here.</p>`}
 if(TAB==='log')await loadLog();
}catch(e){$('s-'+TAB).innerHTML='<div class="card bad">'+esc(e.message)+'</div>'}}
const KIND={S:'Schedule',C:'Countdown started',X:'Countdown cancelled',R:'Countdown wrote',E:'Error',M:'Run by hand',U:'KNX connected',D:'KNX disconnected',B:'Box started',P:'Timers or settings received',T:'Time set'};
async function loadLog(){const l=await api('/api/log');const ev=l.events||[];let h='',day='';
 for(let i=ev.length-1;i>=0;i--){const e=ev[i];let d='',tm='--:--';if(e.t){const x=new Date((e.t+TZ*60)*1000).toISOString();d=x.slice(0,10);tm=x.slice(11,16)}else d='Time not set';
  if(d!==day){if(day)h+='</div>';h+=`<div class="day">${d}</div><div class="log">`;day=d}
  h+=`<i>${tm}</i><span class="${e.k==='E'?'bad':''}"><b>${KIND[e.k]||e.k}</b> ${esc(e.x)}</span>`}
 if(day)h+='</div>';$('s-log').innerHTML=`<div class="card"><h3>What the box did in the last 7 days</h3>${h||'<p class="muted">Nothing yet.</p>'}</div>`}
start();
</script></body></html>)HTML";
