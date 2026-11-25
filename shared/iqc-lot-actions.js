/* Shared, audited LOT metadata edit used by the list and dashboard. */
const IqcLotActions = (() => {
  async function edit(id) {
    try {
      const fresh=await IqcApi.getLot(id), amount=prompt('Tổng số lượng LOT:',fresh.lotQty);
      if(amount===null)return;
      const supplier=prompt('Nhà cung cấp:',fresh.supplier);if(supplier===null)return;
      const note=prompt('Ghi chú LOT:',fresh.note||'');if(note===null)return;
      const r=await sb.rpc('iqc_sua_thong_tin_lot',{p_id:fresh.id,p_updated_at:fresh.updatedAt,p_lot:{lot_qty:Number(amount),supplier,note,location:fresh.location}});
      if(r.error)throw r.error;
      await loadDashboard();
    }catch(e){alert(e.message||e);}
  }
  return {edit};
})();
