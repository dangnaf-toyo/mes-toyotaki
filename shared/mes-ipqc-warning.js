/* One click records the inspection warning. It never creates a production request. */
const MesIpqcWarning = (() => {
  let busy=false;
  const updates=typeof sb.channel==='function'?sb.channel('mes-ipqc-warning-inbox').subscribe():null;
  function publish(){if(updates)Promise.resolve(updates.send({type:'broadcast',event:'changed',payload:{refresh:true}})).catch(()=>{});}
  async function open(){
    if(busy||!state.current)return;
    const cp={...state.current},button=document.getElementById('ipqcWarningButton'),controls=[...document.querySelectorAll('#scr-check button,#scr-check input,#scr-check textarea,#scr-check select')].map(el=>({el,disabled:el.disabled}));
    busy=true;button.disabled=true;for(const {el}of controls)el.disabled=true;
    try{
      const saved=await sb.from('duc_ipqc_checkpoint').select('*').eq('id_checkpoint',cp.id_checkpoint).maybeSingle();
      if(saved.error)throw new Error(saved.error.message);
      if(!saved.data||saved.data.id_dong!==cp.id_dong||saved.data.ma_may!==cp.ma_may||saved.data.ma_sp!==cp.ma_sp)throw new Error('Không xác minh được đúng phiên kiểm tra.');
      if(saved.data.trang_thai==='da_kiem'){
        if(saved.data.ket_qua!=='CANH_BAO')throw new Error('Phiên này đã được lưu với kết quả khác; không ghi đè lịch sử.');
        state.queue=state.queue.filter(r=>r.id_checkpoint!==cp.id_checkpoint);state.current=null;renderQueue();showScreen('scr-queue');
        showToast('Cảnh báo đã được ghi nhận tại Duyệt tiếp tục SX IPQC.');publish();return;
      }
      const job=(await MesIpqcFlow.jobs()).find(r=>r.id_dong===cp.id_dong);
      if(!job||job.ma_may!==cp.ma_may||job.ma_sp!==cp.ma_sp)throw new Error('Phiên sản xuất đã thay đổi; không ghi cảnh báo cho máy/model khác.');
      if(state.current?.id_checkpoint!==cp.id_checkpoint)throw new Error('Phiên kiểm tra đã thay đổi.');
      const result=await submitCheck('CANH_BAO');
      if(result?.ok)publish();
      else{
        const confirmed=await sb.from('duc_ipqc_checkpoint').select('*').eq('id_checkpoint',cp.id_checkpoint).maybeSingle();
        if(!confirmed.error&&confirmed.data?.trang_thai==='da_kiem'&&confirmed.data.ket_qua==='CANH_BAO'&&confirmed.data.id_dong===cp.id_dong&&confirmed.data.ma_may===cp.ma_may&&confirmed.data.ma_sp===cp.ma_sp){
          state.queue=state.queue.filter(r=>r.id_checkpoint!==cp.id_checkpoint);state.current=null;renderQueue();showScreen('scr-queue');
          showToast('Cảnh báo đã được ghi nhận tại Duyệt tiếp tục SX IPQC.');publish();
        }
      }
    }catch(error){showToast(error.message,true);}
    finally{busy=false;for(const {el,disabled}of controls)el.disabled=disabled;button.disabled=false;}
  }
  return {open};
})();
