/* Full filtered dataset, independent of the five-row history page. */
(function(root){
 'use strict';
 function aggregate(rows,unit='day',name=d=>d.label||d.code||'Lỗi khác'){
  const defects=new Map(),periods=new Map();let total=0,ng=0;
  for(const r of rows){const checked=Number(r.ok_qty||0)+Number(r.ng_qty||0);total+=checked;ng+=Number(r.ng_qty||0);
   let day=String(r.inspection_date).slice(0,10);if(unit==='week'){const d=new Date(day+'T00:00:00Z');d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7));day=d.toISOString().slice(0,10);}
   const p=periods.get(day)||{date:day,total:0,ng:0,occurrences:0};p.total+=checked;p.ng+=Number(r.ng_qty||0);
   for(const d of r.defects||[]){const qty=Number(d.qty||0);if(qty<=0)continue;const label=name(d);defects.set(label,(defects.get(label)||0)+qty);p.occurrences+=qty;}
   periods.set(day,p);
  }
  return {total,ng,rate:total?ng/total*100:null,defects:[...defects].map(([name,qty])=>({name,qty,rate:total?qty/total*100:null})).sort((a,b)=>b.qty-a.qty||a.name.localeCompare(b.name)),trend:[...periods.values()].sort((a,b)=>a.date.localeCompare(b.date)).map(p=>({...p,rate:p.total?p.ng/p.total*100:null}))};
 }
 function render(target,rows,unit='day',name,options={}){
  const a=aggregate(rows,unit,name),el=(tag,t)=>{const n=document.createElement(tag);n.textContent=t??'';return n;},fmt=n=>n==null?'Chưa đủ dữ liệu':Number(n).toLocaleString('vi-VN',{maximumFractionDigits:2});target.replaceChildren();
  target.append(el('p',options.pcs?`PCS NG / PCS đã kiểm: ${fmt(a.ng)} / ${fmt(a.total)} = ${fmt(a.rate)}%. Từng loại lỗi: số PCS mắc lỗi / tổng PCS đã kiểm. Một PCS có nhiều lỗi chỉ tính một PCS NG; tổng các loại là lượt lỗi, có thể lớn hơn PCS NG.`:`PCS NG / PCS đã kiểm: ${fmt(a.ng)} / ${fmt(a.total)} = ${fmt(a.rate)}%. Biểu đồ loại lỗi thống kê lượt lỗi; một PCS có thể có nhiều lỗi. Tỷ lệ từng loại = lượt lỗi / PCS đã kiểm, không phải tỷ lệ PCS NG.`));
  if(!rows.length){target.append(el('p','Không có dữ liệu trong bộ lọc.'));return a;}
  const ns='http://www.w3.org/2000/svg',svgNode=(tag,attrs,text)=>{const n=document.createElementNS(ns,tag);for(const [k,v]of Object.entries(attrs))n.setAttribute(k,v);if(text!=null)n.textContent=text;return n;};
  const top=a.defects.slice(0,10),max=Math.max(1,...top.map(x=>x.qty)),svg=svgNode('svg',{viewBox:`0 0 900 ${Math.max(55,top.length*46+30)}`,role:'img','aria-label':'Top lỗi theo lượt lỗi và tỷ lệ trên PCS đã kiểm',style:'width:100%;min-width:600px'});
  top.forEach((d,i)=>{const y=i*46+20;svg.append(svgNode('text',{x:0,y:y+12,'font-size':13,fill:'currentColor'},d.name.length>30?d.name.slice(0,29)+'…':d.name),svgNode('rect',{x:250,y,width:400*d.qty/max,height:24,fill:'#2563eb',rx:3}),svgNode('text',{x:665,y:y+16,'font-size':13,fill:'currentColor'},`${fmt(d.qty)} ${options.pcs?'PCS mắc lỗi':'lượt'} · ${fmt(d.rate)}%`));});
  const wrap=el('div');wrap.style.overflowX='auto';wrap.append(svg);target.append(el('h4',options.pcs?'Top lỗi · PCS mắc từng loại lỗi trong khoảng ngày đang xem':'Top 10 lỗi trong khoảng ngày đang xem'),wrap);
  for(const [field,label,color]of [['ng','Số PCS NG','#dc2626'],['rate','Tỷ lệ PCS NG / PCS đã kiểm (%)','#2563eb']]){
   const trend=a.trend,high=Math.max(1,...trend.map(x=>Number(x[field]||0))),chart=svgNode('svg',{viewBox:'0 0 900 200',role:'img','aria-label':label,style:'width:100%;min-width:500px'}),x=i=>45+i*810/Math.max(1,trend.length-1),y=v=>155-130*v/high;
   chart.append(svgNode('path',{d:'M45 20V155H870',fill:'none',stroke:'#94a3b8'}),svgNode('text',{x:0,y:20,fill:'currentColor','font-size':12},fmt(high)),svgNode('text',{x:20,y:155,fill:'currentColor','font-size':12},'0'),svgNode('polyline',{points:trend.map((p,i)=>`${x(i)},${y(p[field]||0)}`).join(' '),fill:'none',stroke:color,'stroke-width':3}));
   trend.forEach((p,i)=>{const dot=svgNode('circle',{cx:x(i),cy:y(p[field]||0),r:4,fill:color});dot.append(svgNode('title',{},`${p.date}: ${fmt(p[field])}; ${p.ng} NG / ${p.total} PCS đã kiểm`));chart.append(dot);if(i===0||i===trend.length-1||trend.length<=10)chart.append(svgNode('text',{x:x(i),y:180,'text-anchor':'middle',fill:'currentColor','font-size':11},p.date.slice(5)));});
   const w=el('div');w.style.overflowX='auto';w.append(chart);target.append(el('h4',label+' theo '+(unit==='week'?'tuần (từ thứ Hai)':'ngày')),w);
  }
  const table=el('table'),head=el('tr');for(const title of ['Kỳ','PCS đã kiểm','PCS NG','Tỷ lệ NG','Lượt lỗi'])head.append(el('th',title));table.append(head);for(const p of a.trend){const tr=el('tr');for(const v of [p.date,fmt(p.total),fmt(p.ng),fmt(p.rate)+'%',fmt(p.occurrences)])tr.append(el('td',v));table.append(tr);}target.append(table);return a;
 }
 const api={aggregate,render};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.OqcDefectCharts=api;
})(typeof globalThis!=='undefined'?globalThis:this);
