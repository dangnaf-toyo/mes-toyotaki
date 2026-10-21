/* OQC dashboard policy only. Existing QC 80%/variable-hours reports stay unchanged. */
(function(root){
 'use strict';const HOURS=7,TARGET=.9;
 const positive=n=>n!==null&&n!==undefined&&n!==''&&Number.isFinite(Number(n))&&Number(n)>0;
 function capa(steps){if(!Array.isArray(steps)||!steps.length)return {error:'Chưa có CAPA'};let seconds=0;for(const s of steps){if(!String(s.name||'').trim()||s.seconds===''||s.seconds==null||!Number.isFinite(Number(s.seconds))||Number(s.seconds)<0)return {error:'Tên công đoạn và giây/PCS không âm là bắt buộc'};seconds+=Number(s.seconds);}if(!positive(seconds))return {error:'Tổng thời gian phải lớn hơn 0'};return {seconds,hourly:3600/seconds,daily:3600/seconds*HOURS*TARGET};}
 function staffing(plans){if(!plans.length)return {fte:null,people:null,missing:0,error:'Ngoài kế hoạch'};let fte=0,missing=0;const days=new Map();for(const p of plans){if(!positive(p.seconds_per_piece)){missing++;continue;}const v=Number(p.quantity)*Number(p.seconds_per_piece)/(HOURS*3600*TARGET);fte+=v;days.set(p.date,(days.get(p.date)||0)+v);}if(missing)return {fte:null,people:null,missing,error:'Chưa tính đủ: '+missing+' dòng kế hoạch chưa có CAPA'};return {fte,people:Math.ceil(Math.max(0,fte-1e-10)),days:[...days].map(([date,value])=>({date,fte:value,people:Math.ceil(Math.max(0,value-1e-10))})),missing:0};}
 function summary(records,plans){let checked=0,ok=0,ng=0,hours=0,earned=0,missingHours=0,missingCapa=0;const people=new Set();for(const r of records){ok+=Number(r.ok_qty||0);ng+=Number(r.ng_qty||0);const qty=Number(r.ok_qty||0)+Number(r.ng_qty||0);checked+=qty;const work=r.work;
   if(r.inspector_code)people.add(String(r.inspector_code).toLocaleLowerCase());
   const labor=work?.labor||[];if(!labor.length)missingHours++;else for(const l of labor){if(positive(l.hours)){hours+=Number(l.hours);people.add(String(l.employee_code).toLocaleLowerCase());}else missingHours++;}
   const sec=work?.seconds_per_piece??r.context?.seconds_per_piece;
   if(r.context?.inspection_scope!=='FULL_POST_MACHINING'||!positive(sec))missingCapa++;else earned+=qty*Number(sec)/3600;
  }
  const planned=plans.reduce((n,p)=>n+Number(p.quantity||0),0),comparable=records.every(r=>r.context?.inspection_scope==='FULL_POST_MACHINING');
  return {checked,ok,ng,ngRate:checked?ng/checked*100:null,planned,completion:planned>0&&comparable?checked/planned*100:null,hours:missingHours?null:hours,knownHours:hours,people:people.size,standardHours:missingCapa?null:earned,efficiency:missingHours||missingCapa||hours<=0?null:earned/hours*100,missingHours,missingCapa,staff:staffing(plans),comparable};
 }
 function group(records,plans){const codes=new Set([...records.map(r=>r.product_code),...plans.map(p=>p.product_code)]);return [...codes].sort().map(code=>({code,...summary(records.filter(r=>r.product_code===code),plans.filter(p=>p.product_code===code))}));}
 const api={HOURS,TARGET,positive,capa,staffing,summary,group};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.OqcDashboardMath=api;
})(typeof globalThis!=='undefined'?globalThis:this);
