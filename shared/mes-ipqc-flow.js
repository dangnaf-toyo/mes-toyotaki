/* Current MES production rows are authoritative. No Task/LOT is inferred from a machine. */
const MesIpqcFlow = (() => {
  const activeStatuses=['Chờ duyệt','Đang duyệt','Đã duyệt','Đang có hiệu lực'];
  async function readRows(table,order) {
    const rows=[];
    for(let offset=0;;offset+=500){const r=await sb.from(table).select('*').order(order).range(offset,offset+499);if(r.error)throw new Error(r.error.message);rows.push(...r.data||[]);if(!r.data||r.data.length<500)return rows;}
  }
  function active(rows,reports) {
    const closed=new Set(reports.map(r=>r.ngay+'|'+r.ca)),latest=new Map(),all=new Map(rows.map(r=>[r.id_dong,r])),ids=new Set();
    for(const row of rows)if(row.id_dong&&(!latest.has(row.ma_may)||Number(row.row_seq)>Number(latest.get(row.ma_may).row_seq)))latest.set(row.ma_may,row);
    for(const row of latest.values()){ids.add(row.id_dong);if(row.khuon_kep_voi)ids.add(row.khuon_kep_voi);}
    return [...ids].map(id=>all.get(id)).filter(r=>r&&r.ma_sp&&(r.open_gio_phat_sinh||!closed.has(r.ngay+'|'+r.ca)));
  }
  async function jobs(){const [rows,reports]=await Promise.all([readRows('duc_ca_hien_tai','id_dong'),readRows('duc_bao_cao_ca','id_bao_cao')]);return active(rows,reports);}
  function signature(row){return JSON.stringify([row.id_dong,row.ma_may,row.ma_sp,row.ngay,row.ca,row.sp_start_time||null,row.so_khuon||null,row.cong_doan||null,row.tag_no||row.task_no||null,row.lot||row.lot_no||null]);}
  async function validate(job,checkpointId,warning=false){
    const fresh=(await jobs()).find(r=>r.id_dong===job.id_dong);
    if(!fresh||signature(fresh)!==signature(job))throw new Error('Phiên sản xuất đã thay đổi. Hãy chọn lại công việc đang chạy.');
    let checkpoint=null;
    if(checkpointId){const r=await sb.from('duc_ipqc_checkpoint').select('*').eq('id_checkpoint',checkpointId).maybeSingle();if(r.error)throw new Error(r.error.message);checkpoint=r.data;if(!checkpoint||checkpoint.id_dong!==fresh.id_dong||checkpoint.ma_may!==fresh.ma_may||checkpoint.ma_sp!==fresh.ma_sp||(warning&&!['NG','CANH_BAO'].includes(checkpoint.ket_qua)))throw new Error('Cảnh báo không thuộc đúng phiên hoặc đã đổi kết quả kiểm tra.');}
    return {job:fresh,checkpoint};
  }
  function data(job,checkpoint){return {
    checkpoint_id:checkpoint?.id_checkpoint||null,id_dong:job.id_dong,machine:job.ma_may,process:job.cong_doan||'Đúc',product_code:job.ma_sp,
    lot_no:job.lot||job.lot_no||null,task_no:job.tag_no||job.task_no||null,production_day:job.ngay,production_shift:job.ca,production_started_at:job.sp_start_time||null,
    inspection_by:checkpoint?.nguoi_kiem||null,inspection_at:checkpoint?.thoi_diem_kiem_thuc_te||null,inspection_evidence_urls:checkpoint?.anh_bang_chung_url||[],inspection_checklist:checkpoint?.checklist_json||[]
  };}
  async function createUnlocked(job,checkpointId,details,actor,warning=true){
    const checked=await validate(job,checkpointId,warning);
    if(!checkpointId&&details.client_request_id){const prior=await sb.from('duc_ipqc_continue_audit').select('request_id').eq('action','TẠO YÊU CẦU').contains('detail',{client_request_id:details.client_request_id});if(prior.error)throw new Error(prior.error.message);if(prior.data?.length)return {id:prior.data[0].request_id,existing:true};}
    if(checkpointId){const previous=await sb.from('duc_ipqc_continue_request').select('id,status').eq('checkpoint_id',checkpointId).order('created_at',{ascending:false});if(previous.error)throw new Error(previous.error.message);const existing=(previous.data||[]).find(r=>activeStatuses.includes(r.status));if(existing)return {id:existing.id,existing:true};}
    const payload={...details,...data(checked.job,checked.checkpoint)};
    const result=await sb.rpc('duc_ipqc_create_continue_request',{p_data:payload,p_actor:actor});if(result.error)throw new Error(result.error.message);if(result.data?.ok===false)throw new Error(result.data.error||'Không tạo được yêu cầu.');return {id:result.data,existing:false};
  }
  async function create(job,checkpointId,details,actor,warning=true){
    const send=()=>createUnlocked(job,checkpointId,details,actor,warning);
    // Coordinate tabs on the same browser; existing SQL still enforces server permissions.
    return navigator.locks?.request?navigator.locks.request('mes-ipqc-request:'+(checkpointId||details.client_request_id||job.id_dong),send):send();
  }
  function reason(values){
    const type=values.reason_type;
    if(!String(values.reason_detail||'').trim())throw new Error('Nhập lý do đề nghị chi tiết.');
    if(type==='TIME'&&!values.allowed_until&&!(Number(values.allowed_hours)>0))throw new Error('Nhập thời hạn hoặc số giờ được chạy thêm.');
    if(['PLAN_QTY','DOWNSTREAM_REWORK'].includes(type)&&!(Number(values.allowed_qty)>0))throw new Error('Nhập số lượng được đề nghị chạy thêm.');
    if(type==='DOWNSTREAM_REWORK'&&(!values.repair_department||!values.treatment_content||!values.treatment_deadline))throw new Error('Nhập bộ phận sửa, nội dung xử lý và thời hạn.');
    if(values.allowed_until&&new Date(values.allowed_until)<=new Date())throw new Error('Thời hạn đề nghị phải ở tương lai.');
    return values;
  }
  const stepRoles={1:['qc_manager'],2:['ke_hoach','qlsx_truong_phong'],3:['quan_ly_bo_phan','truong_ca'],4:['giam_doc_sx']};
  function canDecide(role,step,override=false){return role==='admin'||(override?role==='giam_doc_sx':(stepRoles[step]||[]).includes(role));}
  return {jobs,active,signature,validate,data,create,reason,canDecide};
})();
