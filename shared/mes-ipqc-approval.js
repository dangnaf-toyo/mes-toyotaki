/* MES-backed creation controls; SQL remains the authority for all approval decisions. */
const MesIpqcApproval = (() => {
  let available=[],selected=null,checkpoint=null,account=null,role='',turn=0,busy=false,token='';
  const el=id=>document.getElementById(id),val=id=>el(id).value.trim();
  function options(){
    const text=val('runningSearch').toLocaleLowerCase();el('runningJob').replaceChildren(new Option('Chọn công việc đang chạy',''));
    for(const job of available.filter(r=>[r.ma_may,r.ma_sp,r.id_dong].join(' ').toLocaleLowerCase().includes(text)))el('runningJob').add(new Option(job.ma_may+' / '+job.ma_sp+' / '+job.ca+' / '+job.id_dong,job.id_dong));
    if(selected)el('runningJob').value=selected.id_dong;
  }
  async function refresh(){available=await MesIpqcFlow.jobs();options();}
  function preview(){
    const source=MesIpqcFlow.data(selected,checkpoint);
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
      if(!selected)throw new Error('Chọn đúng công việc đang sản xuất.');
      const dimension=val('approvalDefectType')==='dimension',type=val('reasonType');
      if(dimension&&!val('actualValue'))throw new Error('Nhập giá trị thực tế của lỗi kích thước.');
      if(!val('warningContent'))throw new Error('Nhập nội dung cảnh báo.');
      const qty=val('approvalDefectQty');if(qty&&(!Number.isInteger(Number(qty))||Number(qty)<0))throw new Error('Số lượng lỗi không hợp lệ.');
      const details=MesIpqcFlow.reason({client_request_id:token,warning_content:val('warningContent'),warning_level:val('warningLevel'),reason_type:type,reason_detail:val('reasonDetail'),defect_type:dimension?'dimension':'appearance',defect_qty:qty?Number(qty):null,
        actual_value:dimension?val('actualValue'):'',standard_min:dimension?val('standardMin'):'',standard_max:dimension?val('standardMax'):'',
        allowed_until:type==='TIME'&&val('timeMode')==='until'?iso('allowedUntil'):null,allowed_hours:type==='TIME'&&val('timeMode')==='hours'?val('allowedHours'):null,allowed_qty:['PLAN_QTY','DOWNSTREAM_REWORK'].includes(type)?val('allowedQty'):null,produced_current:val('producedCurrent')||0,
        repair_department:type==='DOWNSTREAM_REWORK'?val('repairDepartment'):null,treatment_content:type==='DOWNSTREAM_REWORK'?val('treatmentContent'):null,treatment_deadline:type==='DOWNSTREAM_REWORK'?iso('treatmentDeadline'):null});
      const result=await MesIpqcFlow.create(selected,checkpoint?.id_checkpoint||'',details,identity,!!checkpoint);
      alert((result.existing?'Phiếu đã tồn tại.':'Đã gửi yêu cầu.')+' Chưa được phép tiếp tục sản xuất khi chưa có phê duyệt hợp lệ.');resetForm();await loadRequests();
    }catch(error){alert(error.message);}
    finally{busy=false;el('createBtn').disabled=false;el('runningJob').disabled=false;el('warningCheckpoint').disabled=false;}
  }
  async function init(session){
    account=session;
    const user=await sb.from('user_roles').select('role').eq('user_id',session.user.id).maybeSingle();role=user.error?'':user.data?.role||'';
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
    if(jobId){el('runningJob').value=jobId;await choose(jobId,cp||'');}
  }
  el('requestForm').addEventListener('submit',send,true);
  el('runningSearch').oninput=options;
  el('runningJob').onchange=()=>{if(busy)return;el('warningContent').value='';choose(val('runningJob')).catch(error=>alert(error.message));};
  el('refreshRunning').onclick=()=>refresh().catch(error=>alert(error.message));
  el('onlyMyRequests').onchange=()=>render();
  el('requestForm').addEventListener('reset',()=>{++turn;selected=null;checkpoint=null;token='';el('warningEvidence').replaceChildren();el('jobInfo').textContent='';el('checkpointId').value='';el('warningCheckpoint').replaceChildren(new Option('Chọn phiên sản xuất trước',''));});
  return {init,refresh};
})();
