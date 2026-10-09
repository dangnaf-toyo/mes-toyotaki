/* MES-backed creation controls; SQL remains the authority for all approval decisions. */
const MesIpqcApproval = (() => {
  let available=[],selected=null,checkpoint=null,account=null,role='',turn=0,busy=false,token='',proposalWarningId='',inbox=[],loadingWarnings=false,queuedWarnings=false;
  const el=id=>document.getElementById(id),val=id=>el(id).value.trim();
  function options(){
    const text=val('runningSearch').toLocaleLowerCase();el('runningJob').replaceChildren(new Option('Chọn công việc đang chạy',''));
    for(const job of available.filter(r=>[r.ma_may,r.ma_sp,r.id_dong].join(' ').toLocaleLowerCase().includes(text)))el('runningJob').add(new Option(job.ma_may+' / '+job.ma_sp+' / '+job.ca+' / '+job.id_dong,job.id_dong));
    if(selected)el('runningJob').value=selected.id_dong;
  }
  async function refresh(){available=await MesIpqcFlow.jobs();options();}
  function preview(){
    const source=MesIpqcFlow.data(selected,checkpoint);
    el('proposalWarningFaults').textContent=checkpoint?'Loại lỗi đã ghi nhận: '+MesIpqcFlow.defects(checkpoint).join(' / '):'';
    for(const id of ['approvalDefectType','approvalDefectQty','actualValue','standardMin','standardMax','warningLevel'])el(id).closest('.field').hidden=!!checkpoint;
    el('checkpointId').value=source.checkpoint_id||'';el('machine').value=source.machine||'';el('process').value=source.process||'';el('productCode').value=source.product_code||'';el('lotNo').value=source.lot_no||'';el('taskNo').value=source.task_no||'';
    el('jobInfo').textContent='Phiên '+selected.id_dong+' · '+selected.ngay+' · '+selected.ca+' · Người đề nghị: '+identity+(source.inspection_by?' · Người kiểm: '+source.inspection_by:'')+(source.inspection_at?' · Kiểm lúc: '+new Date(source.inspection_at).toLocaleString('vi-VN',{hour12:false}):'');
    const target=el('warningEvidence');target.replaceChildren();
    const urls=Array.isArray(source.inspection_evidence_urls)?source.inspection_evidence_urls:[];
    for(const url of urls){const safe=Qc02View.safeUrl(url,true);if(!safe)continue;const button=document.createElement('button');button.type='button';button.className='btn secondary';const img=document.createElement('img');img.src=safe;img.alt='Ảnh lỗi từ lần kiểm IPQC';img.style.cssText='width:90px;height:65px;object-fit:contain';button.append(img);button.onclick=()=>Qc02View.photo(safe,urls);target.append(button);}
  }
  async function choose(id,requestedCheckpoint=''){
    const request=++turn;selected=null;checkpoint=null;token=crypto.randomUUID();
    el('checkpointId').value='';el('jobInfo').textContent='';el('warningEvidence').replaceChildren();
    const job=available.find(r=>r.id_dong===id);if(!job)return;
    const response=await sb.from('duc_ipqc_checkpoint').select('*').eq('id_dong',job.id_dong).order('thoi_diem_tao',{ascending:false}).limit(200);
    if(response.error)throw new Error(response.error.message);if(request!==turn)return;
    const warnings=(response.data||[]).filter(r=>['NG','CANH_BAO'].includes(r.ket_qua));
    el('warningCheckpoint').replaceChildren(new Option('Phiếu trực tiếp cho phiên đang chọn',''));
    for(const row of warnings)el('warningCheckpoint').add(new Option(row.id_checkpoint+' · '+(row.ghi_chu||row.ket_qua),row.id_checkpoint));
    if(requestedCheckpoint){checkpoint=warnings.find(r=>r.id_checkpoint===requestedCheckpoint);if(!checkpoint)throw new Error('Không tìm thấy cảnh báo của đúng phiên đang chạy.');}
    else if(warnings.length===1)checkpoint=warnings[0];
    selected=job;el('warningCheckpoint').value=checkpoint?.id_checkpoint||'';
    el('warningCheckpoint').onchange=()=>{checkpoint=warnings.find(r=>r.id_checkpoint===val('warningCheckpoint'))||null;token=crypto.randomUUID();if(checkpoint)el('warningContent').value=checkpoint.ghi_chu||'';preview();};
    if(checkpoint)el('warningContent').value=checkpoint.ghi_chu||'';
    el('producedCurrent').value=job.tt_ca??0;preview();
  }
  async function send(event){
    event.preventDefault();event.stopImmediatePropagation();if(busy)return;
    busy=true;el('createBtn').disabled=true;el('runningJob').disabled=true;el('warningCheckpoint').disabled=true;
    try{
      if(!MesIpqcFlow.canPropose(role))throw new Error('Chỉ bộ phận Sản xuất được lập đề nghị chạy tiếp.');
      if(!selected)throw new Error('Chọn đúng công việc đang sản xuất.');
      if(proposalWarningId&&checkpoint?.id_checkpoint!==proposalWarningId)throw new Error('Đề nghị không thuộc đúng cảnh báo đã mở.');
      if(!val('reasonDetail')||!val('proposalCountermeasure')||!val('proposalDepartment'))throw new Error('Nhập đối sách tạm thời và bộ phận đề nghị.');
      const dimension=!checkpoint&&val('approvalDefectType')==='dimension',type=val('reasonType');
      if(proposalWarningId&&type==='EARLY_WARNING')throw new Error('Chọn giới hạn thời gian hoặc số lượng chạy thêm cho đề nghị.');
      if(dimension&&!val('actualValue'))throw new Error('Nhập giá trị thực tế của lỗi kích thước.');
      if(!val('warningContent'))throw new Error('Nhập nội dung cảnh báo.');
      const qty=val('approvalDefectQty');if(qty&&(!Number.isInteger(Number(qty))||Number(qty)<0))throw new Error('Số lượng lỗi không hợp lệ.');
      const details=MesIpqcFlow.reason({client_request_id:token,warning_content:val('warningContent'),warning_level:checkpoint?(checkpoint.ket_qua==='NG'?'NG':'RISK'):val('warningLevel'),reason_type:type,reason_detail:val('reasonDetail')+'\nĐối sách tạm thời: '+val('proposalCountermeasure')+'\nBộ phận đề nghị: '+val('proposalDepartment')+(val('proposalNote')?'\nGhi chú: '+val('proposalNote'):''),requester_department:val('proposalDepartment'),temporary_countermeasure:val('proposalCountermeasure'),requester_note:val('proposalNote'),defect_type:checkpoint?'inspection_checklist':dimension?'dimension':'appearance',inspection_defect_items:checkpoint?MesIpqcFlow.defects(checkpoint):[],defect_qty:checkpoint?null:qty?Number(qty):null,
        actual_value:dimension?val('actualValue'):'',standard_min:dimension?val('standardMin'):'',standard_max:dimension?val('standardMax'):'',
        allowed_until:type==='TIME'&&val('timeMode')==='until'?iso('allowedUntil'):null,allowed_hours:type==='TIME'&&val('timeMode')==='hours'?val('allowedHours'):null,allowed_qty:['PLAN_QTY','DOWNSTREAM_REWORK'].includes(type)?val('allowedQty'):null,produced_current:val('producedCurrent')||0,
        repair_department:type==='DOWNSTREAM_REWORK'?val('repairDepartment'):null,treatment_content:type==='DOWNSTREAM_REWORK'?val('treatmentContent'):null,treatment_deadline:type==='DOWNSTREAM_REWORK'?iso('treatmentDeadline'):null});
      const result=await MesIpqcFlow.create(selected,checkpoint?.id_checkpoint||'',details,identity,!!checkpoint);
      alert((result.existing?'Phiếu đã tồn tại.':'Đã gửi yêu cầu.')+' Chưa được phép tiếp tục sản xuất khi chưa có phê duyệt hợp lệ.');resetForm();proposalWarningId='';await Promise.all([loadRequests(),loadWarnings()]);
    }catch(error){alert(error.message);}
    finally{busy=false;el('createBtn').disabled=false;el('runningJob').disabled=!!proposalWarningId;el('warningCheckpoint').disabled=!!proposalWarningId;}
  }
  async function init(session){
    account=session;
    const user=await sb.from('user_roles').select('role,bo_phan_phu_trach').eq('user_id',session.user.id).maybeSingle();role=user.error?'':user.data?.role||'';
    el('directProposal').hidden=!MesIpqcFlow.canPropose(role);el('proposalRequester').value=identity;
    if(typeof sb.channel==='function'){
      const update=()=>{loadWarnings();loadRequests();};
      sb.channel('mes-ipqc-warning-inbox').on('broadcast',{event:'changed'},update).on('postgres_changes',{event:'*',schema:'public',table:'duc_ipqc_checkpoint'},update).on('postgres_changes',{event:'*',schema:'public',table:'duc_ipqc_continue_request'},update).subscribe();
    }
    await loadWarnings();
    const previousRender=render,previousDecide=decide;
    render=function(){
      const all=rows;const visible=el('onlyMyRequests').checked?all.filter(r=>r.requester_id===account.user.id):all;
      rows=visible;previousRender();rows=all;
      [...el('requests').children].forEach((tr,index)=>{const row=visible[index];if(!row)return;if(!MesIpqcFlow.canDecide(role,row.current_step))tr.querySelectorAll('.approve,.reject').forEach(button=>button.remove());if(!MesIpqcFlow.canDecide(role,row.current_step,true))tr.querySelectorAll('.override').forEach(button=>button.remove());});
      el('myRequestsCount').textContent='Yêu cầu của tôi: '+all.filter(r=>r.requester_id===account.user.id).length;
    };
    decide=async function(id,decision){const row=rows.find(r=>r.id===id);if(!row||!MesIpqcFlow.canDecide(role,row.current_step,decision==='Phê duyệt trực tiếp'))return alert('Tài khoản không có quyền duyệt bước này.');return previousDecide(id,decision);};
    try{await refresh();}catch(error){el('jobInfo').textContent='Không tải được danh sách công việc: '+error.message;return;}
    const q=new URLSearchParams(location.search);let jobId=q.get('jobId'),cp=q.get('checkpointId');
    if(cp&&!jobId){const r=await sb.from('duc_ipqc_checkpoint').select('id_dong').eq('id_checkpoint',cp).maybeSingle();if(r.error)throw new Error(r.error.message);jobId=r.data?.id_dong;}
    if(jobId&&MesIpqcFlow.canPropose(role)){el('runningJob').value=jobId;await choose(jobId,cp||'');el('proposalPanel').classList.remove('hidden');el('proposalRequester').value=identity;proposalWarningId=cp||'';el('runningJob').disabled=!!proposalWarningId;el('warningCheckpoint').disabled=!!proposalWarningId;}
  }
  el('requestForm').addEventListener('submit',send,true);
  el('runningSearch').oninput=options;
  el('runningJob').onchange=()=>{if(busy)return;el('warningContent').value='';choose(val('runningJob')).catch(error=>alert(error.message));};
  el('refreshRunning').onclick=()=>refresh().catch(error=>alert(error.message));
  el('onlyMyRequests').onchange=()=>render();
  el('requestForm').addEventListener('reset',()=>{++turn;selected=null;checkpoint=null;token='';proposalWarningId='';el('runningJob').disabled=false;el('warningCheckpoint').disabled=false;el('warningContent').readOnly=false;el('proposalWarningFaults').textContent='';for(const id of ['approvalDefectType','approvalDefectQty','actualValue','standardMin','standardMax','warningLevel'])el(id).closest('.field').hidden=false;el('warningEvidence').replaceChildren();el('jobInfo').textContent='';el('checkpointId').value='';el('warningCheckpoint').replaceChildren(new Option('Chọn phiên sản xuất trước',''));});
  async function loadWarnings(){
    if(loadingWarnings){queuedWarnings=true;return;}loadingWarnings=true;
    try{
      inbox=await MesIpqcFlow.warnings();
      el('warningInboxStatus').textContent=inbox.length+' cảnh báo chưa có đề nghị. Tự cập nhật khi có cảnh báo; kiểm tra lại mỗi 15 giây.';
      const tbody=el('warningInbox');tbody.replaceChildren();
      for(const item of inbox){
        const cp=item.checkpoint,source=MesIpqcFlow.data(item.job||{id_dong:cp.id_dong,ma_may:cp.ma_may,ma_sp:cp.ma_sp,cong_doan:cp.cong_doan},cp),tr=document.createElement('tr');
        const cell=text=>{const td=document.createElement('td');td.style.whiteSpace='pre-line';td.textContent=text;tr.append(td);return td;};
        cell(cp.id_checkpoint+'\nCÓ CẢNH BÁO - CHƯA CÓ ĐỀ NGHỊ TIẾP TỤC SX');
        cell([source.machine,source.product_code,source.process,'Task/tem: '+(source.task_no||'Chưa có liên kết xác minh'),'LOT: '+(source.lot_no||'Chưa có liên kết xác minh')].join('\n'));
        const fault=cell(MesIpqcFlow.defects(cp).join(' / ')+'\n'+(cp.ghi_chu||''));photos(fault,cp);
        cell((cp.nguoi_kiem||'Chưa có dữ liệu')+'\n'+(cp.thoi_diem_kiem_thuc_te?new Date(cp.thoi_diem_kiem_thuc_te).toLocaleString('vi-VN',{hour12:false}):'Chưa có thời gian cảnh báo'));
        const actions=cell(''),open=document.createElement('button');open.type='button';open.className='btn secondary';open.textContent='Xem cảnh báo';open.onclick=()=>detail(item);actions.append(open);
        if(MesIpqcFlow.canPropose(role)){const propose=document.createElement('button');propose.type='button';propose.className='btn primary';propose.textContent='ĐỀ NGHỊ TIẾP TỤC SẢN XUẤT';propose.onclick=()=>startProposal(item).catch(error=>alert(error.message));actions.append(propose);}
        tbody.append(tr);
      }
      if(!inbox.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=5;td.textContent='Chưa có cảnh báo chưa xử lý.';tr.append(td);tbody.append(tr);}
    }catch(error){el('warningInboxStatus').textContent='Không tải được cảnh báo: '+error.message;el('warningInbox').replaceChildren();}
    finally{loadingWarnings=false;}
  }
  function photos(target,cp){
    const urls=Array.isArray(cp.anh_bang_chung_url)?cp.anh_bang_chung_url:[];
    for(const url of urls){const safe=Qc02View.safeUrl(url,true);if(!safe)continue;const button=document.createElement('button');button.type='button';button.className='btn secondary';const image=document.createElement('img');image.src=safe;image.alt='Ảnh cảnh báo IPQC';image.style.cssText='width:90px;height:65px;object-fit:contain';button.append(image);button.onclick=()=>Qc02View.photo(safe,urls);target.append(button);}
  }
  function detail(item){
    const target=el('warningDetailBody');target.replaceChildren();const cp=item.checkpoint;
    for(const [label,text]of [['Cảnh báo',cp.id_checkpoint],['Máy / model',cp.ma_may+' / '+cp.ma_sp],['Công đoạn',item.job?.cong_doan||cp.cong_doan||'Đúc'],['Task / tem / LOT',item.job?.tag_no||item.job?.task_no||item.job?.lot||item.job?.lot_no||'Chưa có liên kết xác minh'],['Loại lỗi',MesIpqcFlow.defects(cp).join(' / ')||'Chưa có dữ liệu'],['Nội dung',cp.ghi_chu||''],['Người IPQC',cp.nguoi_kiem||''],['Thời gian',cp.thoi_diem_kiem_thuc_te?new Date(cp.thoi_diem_kiem_thuc_te).toLocaleString('vi-VN',{hour12:false}):'Chưa có dữ liệu']]){const p=document.createElement('p');p.textContent=label+': '+text;target.append(p);}
    photos(target,cp);const dialog=el('warningDetailDialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');
  }
  async function startProposal(item){
    if(busy)return;if(!MesIpqcFlow.canPropose(role))throw new Error('Chỉ bộ phận Sản xuất được lập đề nghị.');
    await refresh();const job=available.find(r=>r.id_dong===item.checkpoint.id_dong&&r.ma_may===item.checkpoint.ma_may&&r.ma_sp===item.checkpoint.ma_sp);
    if(!job)throw new Error('Phiên của cảnh báo không còn chạy; không chuyển cảnh báo sang máy/model khác.');
    resetForm();await choose(job.id_dong,item.checkpoint.id_checkpoint);proposalWarningId=item.checkpoint.id_checkpoint;
    el('runningJob').value=job.id_dong;el('runningJob').disabled=true;el('warningCheckpoint').disabled=true;
    el('proposalRequester').value=identity;el('warningContent').readOnly=true;el('reasonType').value='TIME';reasonChanged();
    el('proposalPanel').classList.remove('hidden');el('proposalPanel').scrollIntoView({behavior:'smooth'});
    const dialog=el('warningDetailDialog');if(dialog.open){if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');}
  }
  el('refreshWarnings').onclick=()=>loadWarnings();
  el('warningDetailClose').onclick=()=>{const dialog=el('warningDetailDialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');};
  el('directProposal').onclick=()=>{if(!MesIpqcFlow.canPropose(role))return;resetForm();proposalWarningId='';el('runningJob').disabled=false;el('warningCheckpoint').disabled=false;el('warningContent').readOnly=false;el('proposalRequester').value=identity;el('proposalPanel').classList.remove('hidden');};
  return {init,refresh,loadWarnings};
})();
