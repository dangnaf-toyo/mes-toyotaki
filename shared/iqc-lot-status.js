/* Inspection progress and quality conclusions are separate. */
const IqcLotStatus = (() => {
  function describe(lot, totals) {
    const quality=lot.method==='hoa_hoc' ? lot.result : lot.result || lot.multiConclusion;
    if(quality==='NG')return {text:'NG',color:'red'};
    if(lot.multiPaused)return {text:'CHỜ XỬ LÝ',color:'orange'};
    if(quality==='OK')return {text:'PASS',color:'green'};
    if(lot.method==='hoa_hoc')return {text:!lot.chemical&&!lot.inspectionDate?'CHƯA KIỂM':'CHƯA KẾT LUẬN',color:'gray'};
    if(!totals||totals.checked===null)return {text:'CHƯA XÁC ĐỊNH',color:'gray'};
    if(totals.checked===0)return {text:'CHƯA KIỂM',color:'gray'};
    if(lot.inspectionType==='Kiểm tra AQL' && lot.multiPlan && totals.checked===Number(lot.multiPlan.mau_yeu_cau))return {text:'ĐỦ MẪU · CHƯA KẾT LUẬN',color:'yellow'};
    if(totals.remaining===0)return {text:'ĐÃ KIỂM HẾT · CHƯA KẾT LUẬN',color:'yellow'};
    return {text:'ĐANG KIỂM',color:'yellow'};
  }
  return {describe};
})();
if(typeof module!=='undefined')module.exports=IqcLotStatus;
