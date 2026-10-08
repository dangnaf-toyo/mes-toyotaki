/* QC selectors read the personnel/product masters; auth/roles remain MesAuth's responsibility. */
const Qc02Data = (() => {
  let directoryRequest = null;
  async function readAll(table) {
    const rows = [];
    for (let offset = 0; ; offset += 500) {
      const sort = table === 'master_products' ? 'ma_sp' : table === 'user_roles' ? 'user_id' : 'ten_nhan_vien';
      const columns = table === 'user_roles' ? 'user_id,username,full_name,role,bo_phan_phu_trach' : '*';
      const { data, error } = await sb.from(table).select(columns).order(sort).range(offset, offset + 499);
      if (error) throw error;
      rows.push(...(data || []));
      if (!data || data.length < 500) return rows;
    }
  }
  function employeeText(row) {
    return row.ma_nv ? row.ma_nv + '_' + row.ten_nhan_vien : row.ten_nhan_vien;
  }
  // One read-only directory for QC. Never infer auth identity from a selected name.
  async function readDirectory() {
    const master = await readAll('master_employees');
    const byCode = new Map();
    const active = r => r.is_active !== false && r.active !== false && r.trang_thai !== 'inactive';
    for (const r of master.filter(active)) {
      const code = String(r.ma_nv || r.ten_nhan_vien || '').trim();
      if (code) byCode.set(code.toLowerCase(), { ...r, code, name:r.ten_nhan_vien, roles:[String(r.vai_tro || '').toLowerCase()], departments:r.bo_phan ? [r.bo_phan] : [] });
    }
    // Existing RLS may expose only the current account to non-admins.
    // Accessible account rows supplement the master; no privileged RPC is used.
    let accounts = [];
    try { accounts = await readAll('user_roles'); }
    catch (e) { console.warn('Không đọc được tài khoản; dùng danh mục nhân sự hiện có:', e.message); }
    for (const r of accounts.filter(active)) {
      const code = String(r.username || r.user_id || '').trim();
      if (!code) continue;
      const old = byCode.get(code.toLowerCase());
      const role = String(r.role || '').toLowerCase();
      byCode.set(code.toLowerCase(), { ...old, code, name:r.full_name || old?.name || code, roles:[...new Set([...(old?.roles || []),role==='nhan_vien_oqc'?'oqc':role])], departments:[...new Set([...(old?.departments || []),...(r.bo_phan_phu_trach || [])])] });
    }
    return [...byCode.values()].sort((a,b)=>a.name.localeCompare(b.name,'vi'));
  }
  async function employees(role, department) {
    // Share simultaneous reads; do not retain data after completion. Focus re-reads new staff.
    if (!directoryRequest) directoryRequest = readDirectory().finally(()=>{directoryRequest=null;});
    const rows = await directoryRequest;
    return rows.filter(r => (!role || r.roles?.includes(role.toLowerCase())) && (!department || r.departments?.includes(department)));
  }
  function populate(list, rows, value, label) {
    list.replaceChildren();
    rows.forEach(row => {
      const option = document.createElement('option'); option.value = value(row); option.label = label(row); list.append(option);
    });
  }
  function attachEmployees(ids) {
    const list = document.createElement('datalist'); list.id = 'qc02-employees'; document.body.append(list);
    let request = 0;
    async function refresh() {
      const current = ++request;
      try { const rows=await employees(); if(current===request)populate(list, rows, r => r.code + '_' + r.name, r => r.name); }
      catch (e) { console.error('Không tải được danh mục nhân sự QC', e); }
    }
    ids.forEach(id => {
      const input = document.getElementById(id);
      if (input) input.setAttribute('list', list.id);
    });
    document.addEventListener('focusin', e => { if (e.target.getAttribute('list') === list.id) refresh(); });
    return refresh();
  }
  async function products(codeId, nameId) {
    const input = document.getElementById(codeId), name = document.getElementById(nameId);
    const list = document.createElement('datalist'); list.id = 'qc02-products'; input.setAttribute('list', list.id); document.body.append(list);
    let rows = [];
    async function refresh() {
      rows = await readAll('master_products');
      populate(list, rows, r => r.ma_sp, r => r.ma_sp + ' — ' + (r.ten_sp || ''));
    }
    input.addEventListener('change', () => { const found = rows.find(r => r.ma_sp === input.value); if (found && name) name.value = found.ten_sp || ''; });
    input.addEventListener('focus', () => refresh().catch(e => console.error('Không tải được danh mục model', e)));
    return refresh();
  }
  async function standard(code, target) {
    if (!target) return;
    const request = String(Number(target.dataset.standardRequest || 0) + 1);
    target.dataset.standardRequest = request;
    target.hidden = true; target.replaceChildren();
    if (!code) return;

    const { data, error } = await sb.from('duc_ipqc_tieuchuan').select('file_pdf_url').eq('ma_sp', code).maybeSingle();
    if (!target.isConnected || target.dataset.standardRequest !== request) return;
    if (error) { target.textContent = 'Không tải được tiêu chuẩn: ' + error.message; return; }
    target.replaceChildren();
    if (!data || !Qc02View.safeUrl(data.file_pdf_url)) return;
    target.hidden = false;
    const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Xem tiêu chuẩn';
    button.onclick = () => Qc02View.pdf(data.file_pdf_url); target.append(button);
  }
  function lotDetails(row, target) {
    const labels = { id:'Mã hồ sơ', supplier:'NCC', product_code:'Mã sản phẩm', product_name:'Tên / model', lot_no:'Số LOT',
      lot_qty:'Số lượng LOT', received_at:'Ngày nhận', pickup_at:'Ngày bắt đầu kiểm', completed_at:'Ngày hoàn thành',
      inspection_type:'Tiêu chuẩn kiểm', aql:'AQL', sample_qty:'Rút kiểm', result:'Kết quả', ok_qty:'OK', ng_qty:'NG',
      ok_pct:'% OK', ng_pct:'% NG', inspector:'Người kiểm', note:'Ghi chú', status:'Trạng thái', location:'Vị trí',
      inspection_minutes:'Thời gian kiểm (phút)', created_at:'Ngày tạo', updated_at:'Ngày cập nhật', created_by:'Người tạo' };
    if (target) Qc02View.table(target, ['Thông tin', 'Nội dung'], Object.entries(row || {}).map(([k,v]) => [labels[k] || k.replace(/_/g,' '), v ?? '—']));
  }
  return { readAll, employees, employeeText, attachEmployees, products, standard, lotDetails };
})();
