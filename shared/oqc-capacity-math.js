/* Shared formulas. All stored seconds are snapshots, never current-master lookups. */
(function(root){
 'use strict';
 const EFFICIENCY=.8;
 const positive=v=>v!==null&&v!==''&&v!==undefined&&Number.isFinite(Number(v))&&Number(v)>0;
 const nearInteger=v=>Math.abs(v-Math.round(v))<1e-10?Math.round(v):v;
 function seconds(steps){
   if(!Array.isArray(steps)||!steps.length)return {value:null,error:'Chưa có định mức: cần ít nhất một bước kiểm.'};
   if(steps.some(s=>!String(s.name||'').trim()||!positive(s.seconds)))return {value:null,error:'Mỗi bước cần tên và số giây/PCS lớn hơn 0.'};
   const total=steps.reduce((n,s)=>n+Number(s.seconds),0);
   return Number.isFinite(total)&&total>0?{value:total,error:null}:{value:null,error:'Tổng thời gian kiểm không hợp lệ.'};
 }
 function capacity(sec,hours){
   if(!positive(sec))return {value:null,error:'Chưa có định mức hoặc tổng giây/PCS không lớn hơn 0.'};
   if(!positive(hours)||Number(hours)>24)return {value:null,error:'Nhập số giờ/người trước hiệu suất, lớn hơn 0 và không quá 24 giờ.'};
   const value=Math.floor(nearInteger(Number(hours)*3600*EFFICIENCY/Number(sec)));
   return value>0?{value,error:null}:{value:null,error:'Thời gian làm việc chưa đủ để kiểm 1 PCS theo định mức.'};
 }
 function manpower(rows,hours){
   if(!positive(hours)||Number(hours)>24)return {fte:null,people:null,error:'Chưa có số giờ kế hoạch hợp lệ.'};
   if(!rows.length)return {fte:null,people:null,error:'Chưa có kế hoạch kiểm.'};
   if(rows.some(r=>!positive(r.planned_qty)||!positive(r.seconds_per_piece)))return {fte:null,people:null,error:'Kế hoạch thiếu số lượng hoặc phiên bản định mức.'};
   const workload=rows.reduce((n,r)=>n+Number(r.planned_qty)*Number(r.seconds_per_piece),0),fte=workload/(Number(hours)*3600*EFFICIENCY);
   return {workload,fte,people:Math.ceil(nearInteger(fte)),error:null};
 }
 function report(data){
   const plans=data.plans||[],results=data.results||[],plannedQty=plans.reduce((n,r)=>n+Number(r.planned_qty),0),plannedCodes=new Set(plans.map(p=>p.product_code));
   const checked=results.reduce((n,r)=>n+Number(r.checked_qty),0),checkedInPlan=results.filter(r=>plannedCodes.has(r.product_code)).reduce((n,r)=>n+Number(r.checked_qty),0);
   const unrated=results.reduce((n,r)=>n+Number(r.unrated_records||0),0),earned=results.reduce((n,r)=>n+Number(r.earned_seconds||0),0);
   const labor=data.labor?.labor_seconds,efficiency=unrated||!positive(labor)?null:earned/Number(labor)*100;
   return {plannedQty,checked,checkedInPlan,completion:plannedQty>0?checkedInPlan/plannedQty*100:null,earned,unrated,efficiency,staffing:manpower(plans,data.day?.hours_per_person)};
 }
 const api={EFFICIENCY,positive,seconds,capacity,manpower,report};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.OqcCapacityMath=api;
})(typeof globalThis!=='undefined'?globalThis:this);
