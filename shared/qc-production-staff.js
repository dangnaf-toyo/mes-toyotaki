/* OQC weekly source only: dashboard policy 7h/90%; legacy saved hours stay untouched. */
const MesQcProduction=(()=>{
 const days=['t2','t3','t4','t5','t6','t7','cn'],M=OqcDashboardMath;
 const fmt=n=>Number(n).toLocaleString('vi-VN',{minimumFractionDigits:1,maximumFractionDigits:2});
 let reports=[],versions=[],bases=[],token=0,modalToken=0;
 const date=(mon,i)=>{const d=new Date(mon+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+i);return d.toISOString().slice(0,10);};
 const output=(id,parent)=>{let e=document.getElementById(id);if(!e){e=document.createElement('output');e.id=id;e.style.cssText='display:block;font-size:12px;white-space:normal;margin-top:6px;line-height:1.5';parent.append(e);}return e;};
 async function all(table,filter){const rows=[];for(let i=0;;i+=500){let q=sb.from(table).select('*').order(table==='oqc_dashboard_plan_basis'?'work_date':'id');if(filter)q=filter(q);const r=await q.range(i,i+499);if(r.error)throw r.error;rows.push(...r.data||[]);if(!r.data||r.data.length<500)return rows;}}
 async function loadWeek(){const mon=fmtDate(weekMonday),[week,v,b]=await Promise.all([Promise.all(days.map(async(_,i)=>{const r=await sb.rpc('oqc_capacity_report',{p_date:date(mon,i)});if(r.error)throw r.error;return r.data||{plans:[]};})),all('oqc_work_standard_version'),all('oqc_dashboard_plan_basis',q=>q.gte('work_date',mon).lte('work_date',date(mon,6)))]);return {week,v,b};}
 function norm(code,i,id){const d=date(fmtDate(weekMonday),i);return bases.find(b=>b.work_date===d&&b.product_code===code)||(reports[i]?.plans||[]).find(p=>p.product_code===code&&(p.oqc_plan_id===id||(p.source_kind==='oqc'&&p.source_plan_id===id)))||versions.filter(v=>v.product_code===code&&v.effective_from<=d).sort((a,b)=>b.effective_from.localeCompare(a.effective_from)||Number(b.id)-Number(a.id))[0];}
 function plan(row,i,quantity=row[days[i]]){return {date:date(fmtDate(weekMonday),i),product_code:row.ma_sp,quantity:Number(quantity),seconds_per_piece:norm(row.ma_sp,i,row.id)?.seconds_per_piece??null};}
 const label=s=>s.error||fmt(s.fte)+' người · bố trí '+s.people+' người';
 async function table(){const turn=++token;if(activeTab!=='OQC'){document.getElementById('qc-week-staff-summary')?.remove();return;}try{const loaded=await loadWeek();if(turn!==token||activeTab!=='OQC')return;reports=loaded.week;versions=loaded.v;bases=loaded.b;
  const trs=[...document.querySelectorAll('#tbodyCd tr')];for(let n=0;n<cdRows.length;n++){const row=cdRows[n],tr=trs[n];if(!tr||tr.children.length<9)continue;days.forEach((_,i)=>{output('qc-staff-'+row.id+'-'+i,tr.children[i+2]).textContent=Number(row[days[i]])>0?'Nhân lực cần: '+label(M.staffing([plan(row,i)])):'';});}
  const panel=output('qc-week-staff-summary',document.getElementById('tbodyCd').closest('table').parentElement);panel.replaceChildren();const h=document.createElement('h4');h.textContent='Tổng nhân lực OQC cần theo ngày · 7 giờ/người · hiệu suất kế hoạch 90%';panel.append(h);
  days.forEach((day,i)=>{const p=document.createElement('p'),s=M.staffing(cdRows.filter(r=>Number(r[day])>0).map(r=>plan(r,i)));p.textContent=date(fmtDate(weekMonday),i)+': '+label(s);panel.append(p);});
  const link=document.createElement('a');link.href='oqc-daily.html';link.textContent='Mở OQC kiểm tra / CAPA';panel.append(link);
 }catch(e){if(turn===token&&activeTab==='OQC')output('qc-week-staff-summary',document.getElementById('tbodyCd').closest('table').parentElement).textContent='Chưa đủ dữ liệu tính nhân lực — '+e.message;}}
 async function modal(){const turn=++modalToken;days.forEach(day=>{document.getElementById('qc-hours-'+day)?.closest('label')?.remove();document.getElementById('qc-draft-'+day)?.remove();});if(activeTab!=='OQC')return;
  try{const loaded=await loadWeek();if(turn!==modalToken||activeTab!=='OQC')return;reports=loaded.week;versions=loaded.v;bases=loaded.b;
   days.forEach(day=>{const parent=document.getElementById('cf-'+day).parentElement,label=document.createElement('label'),input=document.createElement('input');label.textContent='Giờ/người · hiệu suất kế hoạch 90%';input.type='number';input.id='qc-hours-'+day;input.value='7';input.readOnly=true;label.append(input);parent.append(label);output('qc-draft-'+day,parent);});preview();
  }catch(e){showMsg('Chưa đủ dữ liệu tính nhân lực — '+e.message,'err');}
 }
 function preview(){if(activeTab!=='OQC')return;const code=document.getElementById('cf-ma-sp').value;days.forEach((day,i)=>{const out=document.getElementById('qc-draft-'+day);if(!out)return;const existing=cdRows.find(r=>r.id===editingId),row={id:existing?.ma_sp===code?existing.id:null,ma_sp:code},qty=Number(document.getElementById('cf-'+day).value),own=qty>0?[plan(row,i,qty)]:[],others=cdRows.filter(r=>r.id!==editingId&&r.ma_sp!==code&&Number(r[day])>0).map(r=>plan(r,i));out.textContent='Model: '+label(M.staffing(own))+' · Tổng ngày đang chỉnh sửa: '+label(M.staffing([...others,...own]))+' · 7 giờ/người × 90%';});}
 // Weekly quantity saves retain their existing RPC/approval path and historical hours.
 function hours(){return {};}
 const oldRender=renderCdRows;renderCdRows=function(...args){oldRender(...args);table();};
 const oldOpen=openRowModalCd;openRowModalCd=function(...args){oldOpen(...args);modal();};
 const oldModel=onMaSpChangeCd;onMaSpChangeCd=function(...args){oldModel(...args);modal();};
 days.forEach(day=>document.getElementById('cf-'+day).addEventListener('input',preview));
 table();
 return {hours,table,modal};
})();
