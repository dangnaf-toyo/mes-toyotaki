/* Creates the continuation request from the existing IPQC inspection screen. */
const MesIpqcWarning = (() => {
  let pending=null,busy=false;
  const el=id=>document.getElementById(id),value=id=>el(id).value.trim();
  function changed(){
    const type=value('warningReasonType');
    el('warningTimeFields').hidden=type!=='TIME';el('warningQtyFields').hidden=!['PLAN_QTY','DOWNSTREAM_REWORK'].includes(type);el('warningRepairFields').hidden=type!=='DOWNSTREAM_REWORK';
    el('warningMeasurements').hidden=value('warningDefectType')!=='dimension';
  }
  async function open(){
    if(busy)return;
    if(pending?.saved){const dialog=el('warningRequestDialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');return;}
    const checkpoint=state.current;if(!checkpoint)return;
    try{
      const job=(await MesIpqcFlow.jobs()).find(r=>r.id_dong===checkpoint.id_dong);
      if(!job||job.ma_may!==checkpoint.ma_may||job.ma_sp!==checkpoint.ma_sp)throw new Error('Không xác minh được phiên máy đang kiểm tra.');
      pending={checkpoint:{...checkpoint},job,saved:false,actor:await MesAuth.getCurrentUserIdentity()};
      el('warningJobInfo').textContent=job.ma_may+' / '+job.ma_sp+' / '+(job.cong_doan||'Đúc')+' · Phiên '+job.id_dong+' · Task/LOT: '+(job.tag_no||job.task_no||'Chưa có liên kết xác minh');
      el('warningStatus').textContent='';el('warningRequestForm').reset();changed();
      const dialog=el('warningRequestDialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','');
    }catch(error){showToast(error.message,true);}
  }
  function details(){
    const type=value('warningReasonType'),dimension=value('warningDefectType')==='dimension';
    if(dimension&&!value('warningActual'))throw new Error('Nhập giá trị thực tế của lỗi kích thước.');
    const qty=value('warningDefectQty');if(qty&&(!Number.isInteger(Number(qty))||Number(qty)<0))throw new Error('Số lượng lỗi phải là số nguyên, không âm.');
    return MesIpqcFlow.reason({warning_level:'RISK',warning_content:el('ck-ghi-chu').value.trim(),reason_type:type,reason_detail:value('warningReason'),
      defect_type:dimension?'dimension':'appearance',defect_qty:qty?Number(qty):null,actual_value:dimension?value('warningActual'):'',standard_min:dimension?value('warningMin'):'',standard_max:dimension?value('warningMax'):'',
      allowed_until:type==='TIME'&&value('warningUntil')?new Date(value('warningUntil')).toISOString():null,allowed_hours:type==='TIME'&&value('warningHours')?Number(value('warningHours')):null,allowed_qty:['PLAN_QTY','DOWNSTREAM_REWORK'].includes(type)?Number(value('warningAllowedQty')):null,
      produced_current:pending.job.tt_ca||0,repair_department:type==='DOWNSTREAM_REWORK'?value('warningRepairDepartment'):null,treatment_content:type==='DOWNSTREAM_REWORK'?value('warningTreatment'):null,treatment_deadline:type==='DOWNSTREAM_REWORK'&&value('warningDeadline')?new Date(value('warningDeadline')).toISOString():null});
  }
  async function send(event){
    event.preventDefault();if(!pending||busy)return;
    busy=true;el('warningSend').disabled=true;el('warningClose').disabled=true;
    try{
      const request=details();
      if(!pending.saved){
        if(state.current?.id_checkpoint!==pending.checkpoint.id_checkpoint)throw new Error('Phiên kiểm tra đã thay đổi.');
        await MesIpqcFlow.validate(pending.job,pending.checkpoint.id_checkpoint,false);
        const result=await submitCheck('CANH_BAO');if(!result?.ok)return;
        pending.saved=true;pending.savedNote=request.warning_content;
      }
      request.warning_content=pending.savedNote;
      el('warningStatus').textContent='Cảnh báo đã lưu. Đang tạo yêu cầu duyệt…';
      const result=await MesIpqcFlow.create(pending.job,pending.checkpoint.id_checkpoint,request,pending.actor,true);
      el('warningStatus').textContent=(result.existing?'Phiếu đã tồn tại':'Đã tạo phiếu')+' — chưa được phép tiếp tục khi chưa duyệt hợp lệ.';
      showToast(el('warningStatus').textContent);pending=null;
      const dialog=el('warningRequestDialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');
    }catch(error){el('warningStatus').textContent=error.message+(pending?.saved?' Cảnh báo đã lưu; bấm Gửi lại để kiểm tra phiếu, không nộp lại lần kiểm.':'');}
    finally{busy=false;el('warningSend').disabled=false;el('warningClose').disabled=false;}
  }
  el('warningRequestForm').addEventListener('submit',send);
  for(const id of ['warningReasonType','warningDefectType'])el(id).addEventListener('change',changed);
  el('warningClose').onclick=()=>{if(busy)return;const dialog=el('warningRequestDialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');};
  el('warningRequestDialog').addEventListener('cancel',event=>{if(busy)event.preventDefault();});
  return {open,send};
})();
