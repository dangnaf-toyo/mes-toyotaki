/**
 * ============================================================================
 * khuon-ds.js — DANH SÁCH KHUÔN (duc_shot_khuon) dùng chung (T92):
 *   - quan-ly-danh-muc.html tab Khuôn (admin): đủ thao tác — khai báo / sửa /
 *     đổi mã / xoá khuôn (duc_configure_mold, duc_rename_khuon, duc_xoa_khuon),
 *     tình trạng sử dụng (T79 duc_khuon_doi_tinh_trang + log), thứ tự ưu tiên
 *     khuôn cùng mã SP (T86 duc_khuon_dat_uu_tien).
 *   - quan-ly-khuon.html (mọi người): chỉ xem.
 * T92: 5 RPC trên chỉ admin (has_role('admin')) — server chặn, không chỉ ẩn nút.
 *
 *   KhuonDs.mount(el, { admin: bool, userName: string, onLoaded?: ({molds, issues}) => void })
 * Cần `sb` (shared/supabase-client.js). Hộp thoại chỉ để sửa 1 khuôn.
 * ============================================================================
 */
(function () {
  const CSS = `.kds-bar{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px}
.kds-bar input[type=search]{border:1.5px solid var(--border-strong);border-radius:6px;padding:7px 9px;font-family:inherit;font-size:13px;width:240px;max-width:100%}
.kds-bar .sp{flex:1}
.kds-bar .lbl{font-size:10.5px;font-weight:700;color:var(--text-muted);text-transform:uppercase;letter-spacing:.05em;min-width:78px}
.kds .chip{border:1px solid var(--border-strong);background:#fff;border-radius:100px;padding:5px 11px;font-family:inherit;font-size:12px;font-weight:600;cursor:pointer;color:var(--text-muted)}
.kds .chip:hover{background:var(--bg-sunken)}
.kds .chip.on{background:var(--text);color:#fff;border-color:var(--text)}
.kds-wrap{overflow-x:auto}
.kds table{width:100%;border-collapse:collapse;font-size:12.5px}
.kds th{background:var(--bg-sunken);color:var(--text-muted);font-size:10.5px;text-transform:uppercase;letter-spacing:.04em;text-align:left;padding:7px 8px;border-bottom:1px solid var(--border);white-space:nowrap}
.kds td{padding:7px 8px;border-bottom:1px solid var(--border);vertical-align:middle}
.kds th.num,.kds td.num{text-align:right}
.kds td.num{font-family:'JetBrains Mono',monospace;font-size:12px}
.kds td.mk{font-weight:700;white-space:nowrap}
.kds td.act{white-space:nowrap;text-align:right}
.kds .st{font-weight:700;font-size:12px}
.kds .st.ok{color:var(--run-fg)}.kds .st.soon{color:var(--warn-fg)}.kds .st.due{color:var(--alarm-fg)}.kds .st.renew{color:#9F1239}
.kds .bar{height:5px;border-radius:3px;background:var(--bg-sunken);margin-top:3px;overflow:hidden;min-width:70px}
.kds .bar i{display:block;height:100%}
.kds .tt,.kds-dlg .tt{display:inline-block;font-size:11.5px;font-weight:700;padding:3px 9px;border-radius:100px;white-space:nowrap}
.tt.dang_sx{background:var(--run-bg);color:var(--run-fg)}
.tt.moi_chua_sx{background:#E0F2FE;color:#075985}
.tt.dung_het_tuoi_tho{background:#F1F5F9;color:#475569}
.tt.cho_tra_khach{background:#F3E8FF;color:#6B21A8}
.tt.cho_bao_phe{background:var(--alarm-bg);color:var(--alarm-fg)}
.kds .tt-sub{font-size:10.5px;color:var(--text-dim);margin-top:2px;max-width:190px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.kds tr.inactive td{color:var(--text-muted)}
.kds tr.inactive .st,.kds tr.inactive .bar{opacity:.45}
.kds .ut{display:inline-block;font-size:10.5px;font-weight:700;padding:1px 7px;border-radius:100px;background:#FEF3C7;color:#92400E;margin-left:5px;vertical-align:middle}
.kds .iss-tag{display:inline-block;font-size:10.5px;font-weight:700;margin-top:2px}
.kds .empty{padding:16px;text-align:center;color:var(--text-dim)}
.kds button.kb,.kds a.kb,.kds-dlg button.kb{border:none;border-radius:5px;padding:8px 14px;font-family:inherit;font-size:12.5px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;gap:6px;background:var(--accent);color:#fff;text-decoration:none;white-space:nowrap;margin:0}
.kds button.kb:hover,.kds-dlg button.kb:hover{background:var(--accent-hover)}
.kds button.kb:disabled,.kds-dlg button.kb:disabled{opacity:.5;cursor:not-allowed}
.kds .kb.sm{padding:4px 9px;font-size:11.5px}
.kds .kb.ol,.kds-dlg .kb.ol{background:#fff;border:1.5px solid var(--accent);color:var(--accent)}
.kds .kb.ol:hover,.kds-dlg .kb.ol:hover{background:var(--bg-sunken)}
.kds-dlg .kb.dg{background:#FEE2E2;border:1px solid #F87171;color:#B91C1C}
.kds-dlg .kb.dg:hover{background:#FECACA}
.kds-mask{position:fixed;inset:0;background:rgba(15,23,42,.45);display:none;align-items:flex-start;justify-content:center;z-index:950;padding:5vh 10px;overflow-y:auto}
.kds-mask.open{display:flex}
.kds-dlg{background:#fff;border-radius:10px;box-shadow:var(--shadow-lg);width:min(540px,100%)}
.kds-dlg .hd{display:flex;align-items:center;justify-content:space-between;padding:12px 16px;border-bottom:1px solid var(--border);font-weight:700;font-size:14px}
.kds-dlg .hd button{border:none;background:none;font-size:18px;cursor:pointer;color:var(--text-muted);padding:0 4px}
.kds-dlg .bd{padding:14px 16px;display:flex;flex-direction:column;gap:10px}
.kds-dlg .ft{padding:10px 16px;border-top:1px solid var(--border);display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap;align-items:center}
.kds-dlg .ft .hint{margin-right:auto;max-width:260px}
.kds-dlg .hint{font-size:12px;color:var(--text-muted)}
.kds-dlg .fg{display:flex;flex-direction:column;gap:4px}
.kds-dlg .fg label{font-size:10.5px;font-weight:700;color:var(--text-muted);text-transform:uppercase;letter-spacing:.05em;margin:0}
.kds-dlg .fg input,.kds-dlg .fg select,.kds-dlg .fg textarea{border:1.5px solid var(--border-strong);border-radius:6px;padding:8px 9px;font-size:13.5px;font-family:inherit;width:100%;color:var(--text);background:#fff}
.kds-dlg .fg textarea{min-height:60px;resize:vertical}
.kds-dlg .fg .sub{font-size:11px;color:var(--text-muted)}
.kds-dlg .row2{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.kds-dlg .tt-opts,.kds-dlg .ut-list{display:flex;flex-direction:column;gap:6px}
.kds-dlg label.tt-opt{display:flex;gap:10px;align-items:flex-start;border:1.5px solid var(--border);border-radius:8px;padding:8px 10px;cursor:pointer;margin:0;font-weight:400;color:var(--text);font-size:13px}
.kds-dlg .tt-opt:has(input:checked){border-color:var(--accent);background:#F0F7FF}
.kds-dlg .tt-opt input{margin-top:3px;width:auto}
.kds-dlg .tt-opt small{display:block;color:var(--text-muted);font-size:11.5px;margin-top:1px}
.kds-dlg .tt-opt.cur{opacity:.55;cursor:default}
.kds-dlg .ut-row{display:flex;align-items:center;gap:10px;border:1.5px solid var(--border);border-radius:8px;padding:8px 10px}
.kds-dlg .ut-row .no{font-family:'JetBrains Mono',monospace;font-weight:700;font-size:16px;width:26px;text-align:center;color:#92400E}
.kds-dlg .ut-row .mk{font-weight:700;flex:1}
.kds-dlg .ut-row .mk small{display:block;font-weight:400;color:var(--text-muted);font-size:11.5px}
.kds-dlg .ut-row button{border:1px solid var(--border-strong);background:#fff;color:var(--text);border-radius:5px;width:30px;height:28px;padding:0;cursor:pointer;font-size:13px}
.kds-dlg .ut-row button:disabled{opacity:.3;cursor:default}
.kds-dlg .st{font-weight:700}
.kds-dlg .st.ok{color:var(--run-fg)}.kds-dlg .st.soon{color:var(--warn-fg)}.kds-dlg .st.due{color:var(--alarm-fg)}.kds-dlg .st.renew{color:#9F1239}
.kds-dlg .hist div{padding:4px 0;border-bottom:1px solid var(--border);font-size:11.5px}
.kds-msg{position:fixed;left:50%;transform:translateX(-50%);bottom:18px;z-index:1000;max-width:min(560px,92vw);padding:11px 16px;border-radius:8px;font-size:13px;font-weight:600;display:none;box-shadow:var(--shadow-lg)}
.kds-msg.err{background:var(--alarm-bg);color:var(--alarm-fg);border:1px solid #FCA5A5;display:block}
.kds-msg.ok{background:var(--run-bg);color:var(--run-fg);border:1px solid #A7F3D0;display:block}
@media (max-width:640px){.kds-dlg .row2{grid-template-columns:1fr}.kds-bar input[type=search]{flex:1}}
`;
  const MOLD = { MAINTENANCE_SHOT: 10000, REPLACEMENT_SHOT: 100000, WARN_RATIO: 0.8 };   // = CONFIG.MOLD ở duc-dashboard.html
  const ST_CLS = { 'OK': 'ok', 'Sắp bảo dưỡng': 'soon', 'Cần bảo dưỡng': 'due', 'Cần làm mới': 'renew' };
  const ST_PRIO = { 'Cần làm mới': 0, 'Cần bảo dưỡng': 1, 'Sắp bảo dưỡng': 2, 'OK': 3 };
  // Tình trạng sử dụng (T79) — thứ tự = thứ tự hiển thị / sắp xếp.
  const TT = {
    dang_sx:           ['🟢 Đang sản xuất', 'Khuôn đang dùng cho sản xuất'],
    moi_chua_sx:       ['🆕 Mới — chưa vào SX', 'Khuôn mới nhận, chưa đưa vào sản xuất'],
    dung_het_tuoi_tho: ['⛔ Hết tuổi thọ — dừng SX', 'Đã dừng sản xuất, chưa quyết định trả khách hay báo phế'],
    cho_tra_khach:     ['📦 Chờ trả khách hàng', 'Hết tuổi thọ, chờ trả khuôn về khách hàng'],
    cho_bao_phe:       ['🗑 Chờ báo phế', 'Hết tuổi thọ, chờ làm thủ tục báo phế'],
  };
  const TT_KEYS = Object.keys(TT);

  const DLG_HTML = `
<div class="kds-mask" data-dlg="cfg"><div class="kds-dlg">
  <div class="hd"><span>✏ <span data-f="cfg-title">Sửa khuôn</span></span><button type="button" data-close>✕</button></div>
  <div class="bd">
    <div class="hint" style="background:var(--bg-sunken);border-radius:6px;padding:8px 10px">Để trống ô nào thì giữ nguyên giá trị hiện tại của ô đó. Dùng khi cần khai báo baseline hoặc sửa ngưỡng riêng cho khuôn này.</div>
    <div class="fg"><label>Mã khuôn *</label><input data-f="ma-khuon" placeholder="VD: K-DC5-01"><div class="sub" data-f="ma-khuon-hint"></div></div>
    <div class="fg"><label>Mã sản phẩm <span data-f="sp-req">*</span></label><select data-f="ma-sp"></select><div class="sub">Mỗi khuôn đúc đúng 1 mã SP cố định.</div></div>
    <div class="row2">
      <div class="fg"><label>Tổng shot lũy kế</label><input type="number" data-f="tong-shot" min="0" step="1" placeholder="Để trống nếu giữ nguyên"></div>
      <div class="fg"><label>Shot từ lần BD gần nhất</label><input type="number" data-f="shot-since" min="0" step="1" placeholder="Để trống nếu giữ nguyên"></div>
    </div>
    <div class="row2">
      <div class="fg"><label>Ngưỡng bảo dưỡng (shot)</label><input type="number" data-f="nguong-bd" min="0" step="100" placeholder="Để trống nếu giữ nguyên"></div>
      <div class="fg"><label>Ngưỡng làm mới (shot)</label><input type="number" data-f="nguong-lm" min="0" step="1000" placeholder="Để trống nếu giữ nguyên"></div>
    </div>
    <div class="fg"><label>Chu kỳ bảo dưỡng theo thời gian (ngày)</label><input type="number" data-f="chu-ky" min="0" step="1" placeholder="VD: 30 — để trống nếu chỉ theo dõi theo số shot"><div class="sub">Nhập 0 để bỏ chu kỳ theo ngày.</div></div>
    <div class="fg"><label>Ghi chú</label><textarea data-f="ghi-chu" placeholder="VD: Khai báo baseline từ Excel ngày 01/08/2026"></textarea></div>
  </div>
  <div class="ft">
    <span class="hint">Bộ đếm shot tự reset khi check sheet bảo dưỡng hoàn thành ĐẠT.</span>
    <button type="button" class="kb dg" data-act="cfg-del">🗑 Xoá khuôn</button>
    <button type="button" class="kb ol" data-close>Huỷ</button>
    <button type="button" class="kb" data-act="cfg-save">Lưu</button>
  </div>
</div></div>
<div class="kds-mask" data-dlg="ut"><div class="kds-dlg">
  <div class="hd"><span>⇅ Thứ tự ưu tiên khuôn — mã <span data-f="ut-sp"></span></span><button type="button" data-close>✕</button></div>
  <div class="bd">
    <div class="hint">Bảng điều khiển Đúc sẽ tự chọn khuôn ưu tiên 1; nếu khuôn đó đang chạy trên máy khác thì chọn khuôn ưu tiên kế tiếp. Chỉ khuôn <b>Đang sản xuất</b> mới được xếp ưu tiên.</div>
    <div class="ut-list" data-f="ut-list"></div>
  </div>
  <div class="ft">
    <button type="button" class="kb ol" data-close>Huỷ</button>
    <button type="button" class="kb" data-act="ut-save">Lưu thứ tự</button>
  </div>
</div></div>
<div class="kds-mask" data-dlg="tt"><div class="kds-dlg">
  <div class="hd"><span>🏷 Tình trạng khuôn <span data-f="tt-tag"></span></span><button type="button" data-close>✕</button></div>
  <div class="bd">
    <div class="hint" data-f="tt-shot"></div>
    <div class="tt-opts" data-f="tt-opts"></div>
    <div class="fg"><label>Lý do / ghi chú *</label><textarea data-f="tt-ly-do" placeholder="VD: Đạt 100.000 shot, khách yêu cầu trả khuôn theo PO 123..."></textarea></div>
    <div class="fg"><label>Lịch sử tình trạng</label><div class="hist" data-f="tt-history">—</div></div>
  </div>
  <div class="ft">
    <button type="button" class="kb ol" data-close>Huỷ</button>
    <button type="button" class="kb" data-act="tt-save">Lưu tình trạng</button>
  </div>
</div></div>`;

  function injectCss(){
    if (document.getElementById('kds-css')) return;
    const st = document.createElement('style');
    st.id = 'kds-css';
    st.textContent = CSS;
    document.head.appendChild(st);
  }
  function escapeHtml(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function fmtNum(n){ return (Number(n) || 0).toLocaleString('vi-VN'); }
  function pad(n){ return String(n).padStart(2, '0'); }
  function fmtDate(s){ if (!s) return '—'; const d = new Date(String(s).length <= 10 ? s + 'T00:00:00' : s); return pad(d.getDate()) + '/' + pad(d.getMonth() + 1) + '/' + d.getFullYear(); }
  function naturalCompare(a, b){ return String(a).localeCompare(String(b), 'vi', { numeric: true, sensitivity: 'base' }); }
  function numOrNull(v){ return (v === '' || v == null) ? null : Number(v); }

  // _computeMoldStatus (ShotKhuon.js) / duc_compute_mold_status (SQL) — giữ đồng bộ.
  function moldStatus(tong, shotBD, nguongBD, nguongLM){
    if (tong >= nguongLM) return 'Cần làm mới';
    if ((tong - shotBD) >= nguongBD) return 'Cần bảo dưỡng';
    if ((tong - shotBD) >= nguongBD * MOLD.WARN_RATIO) return 'Sắp bảo dưỡng';
    return 'OK';
  }
  function normMold(m){
    const nguongBD = Number(m.nguong_bao_duong) || MOLD.MAINTENANCE_SHOT;
    const nguongLM = Number(m.nguong_lam_moi) || MOLD.REPLACEMENT_SHOT;
    const tong = Number(m.tong_shot_luy_ke) || 0, shotBD = Number(m.shot_tai_lan_bao_duong_gan_nhat) || 0;
    return { ma_khuon: String(m.ma_khuon).trim(), ten_sp_gan_nhat: m.ten_sp_gan_nhat || '', tong_shot_luy_ke: tong,
      nguong_bao_duong: nguongBD, nguong_lam_moi: nguongLM, lan_bao_duong_gan_nhat: m.lan_bao_duong_gan_nhat || null,
      shot_tai_lan_bao_duong_gan_nhat: shotBD, chu_ky_bao_duong_ngay: m.chu_ky_bao_duong_ngay || null,
      shots_since_maintenance: tong - shotBD, trang_thai_khuon: moldStatus(tong, shotBD, nguongBD, nguongLM),
      tinh_trang: TT[m.tinh_trang] ? m.tinh_trang : 'dang_sx', tinh_trang_ly_do: m.tinh_trang_ly_do || '',
      tinh_trang_luc: m.tinh_trang_luc || null, tinh_trang_boi: m.tinh_trang_boi || '',
      uu_tien: m.uu_tien || null, ma_sp: String(m.ten_sp_gan_nhat || '').split(' (')[0].trim() };
  }
  function nextDueLabel(m){
    if (!m.lan_bao_duong_gan_nhat || !m.chu_ky_bao_duong_ngay) return '—';
    const due = new Date(String(m.lan_bao_duong_gan_nhat).slice(0, 10) + 'T00:00:00');
    due.setDate(due.getDate() + Number(m.chu_ky_bao_duong_ngay));
    return fmtDate(due.getFullYear() + '-' + pad(due.getMonth() + 1) + '-' + pad(due.getDate())) +
      (due < new Date() ? ' <span class="st due">(quá hạn)</span>' : '');
  }

  function mount(el, opt){
    injectCss();
    const admin = !!opt.admin;
    let molds = [], issues = [], products = [];
    let kFilter = 'all', ttFilter = 'all', q = '';
    let cur = null, utSp = '', utDs = [];

    el.classList.add('kds');
    el.innerHTML = '<div class="kds-bar"><input type="search" data-k="q" placeholder="Tìm mã khuôn / mã SP..."><span class="sp"></span>' +
      (admin ? '<button type="button" class="kb" data-act="new">＋ Khai báo khuôn mới</button>' : '') + '</div>' +
      '<div class="kds-bar" data-k="ttChips"></div><div class="kds-bar" data-k="kChips"></div>' +
      '<div class="kds-wrap"><table><thead><tr><th>Khuôn</th><th>Tình trạng</th><th>Mã SP</th><th class="num">Tổng shot</th><th class="num">Từ lần BD</th>' +
      '<th class="num">Ngưỡng BD</th><th class="num">Ngưỡng LM</th><th>BD gần nhất</th><th>Hạn BD (theo ngày)</th><th>Trạng thái</th><th></th></tr></thead>' +
      '<tbody data-k="tb"><tr><td colspan="11" class="empty">Đang tải...</td></tr></tbody></table></div>';
    const $ = k => el.querySelector('[data-k="' + k + '"]');

    let host = null, msgEl = document.querySelector('.kds-msg');
    if (!msgEl) { msgEl = document.createElement('div'); msgEl.className = 'kds-msg'; document.body.appendChild(msgEl); }
    let msgTimer = null;
    function showMsg(text, cls, ms){
      msgEl.textContent = text; msgEl.className = 'kds-msg ' + cls;
      clearTimeout(msgTimer);
      msgTimer = setTimeout(() => { msgEl.className = 'kds-msg'; }, ms || 3500);
    }
    if (admin) {
      host = document.createElement('div');
      host.innerHTML = DLG_HTML;
      document.body.appendChild(host);
    }
    const f = k => host.querySelector('[data-f="' + k + '"]');
    function openDlg(k){ host.querySelector('[data-dlg="' + k + '"]').classList.add('open'); }
    function closeDlg(){ if (host) host.querySelectorAll('.kds-mask').forEach(d => d.classList.remove('open')); }

    async function rpcWrite(fn, params){
      const { data, error } = await sb.rpc(fn, params);
      if (error) throw new Error(error.message || String(error));
      if (data && typeof data === 'object' && data.ok === false) throw new Error(data.error || 'Lỗi không xác định');
      return data;
    }

    async function load(){
      const [m, i, p] = await Promise.all([
        sb.from('duc_shot_khuon').select('*'),
        sb.from('duc_van_de_khuon').select('ma_khuon,trang_thai'),
        admin ? sb.from('master_products').select('ma_sp,ten_sp').order('ma_sp') : Promise.resolve({ data: [] }),
      ]);
      if (m.error) return showMsg('Lỗi tải khuôn: ' + m.error.message, 'err', 6000);
      molds = (m.data || []).filter(x => x.ma_khuon).map(normMold).sort((a, b) =>
        (TT_KEYS.indexOf(a.tinh_trang) - TT_KEYS.indexOf(b.tinh_trang)) ||
        (ST_PRIO[a.trang_thai_khuon] - ST_PRIO[b.trang_thai_khuon]) || naturalCompare(a.ma_khuon, b.ma_khuon));
      issues = i.data || [];
      products = (p.data || []).filter(x => x.ma_sp);
      render();
      if (opt.onLoaded) opt.onLoaded({ molds, issues });
    }

    function render(){
      const ttCounts = { all: molds.length };
      molds.forEach(m => { ttCounts[m.tinh_trang] = (ttCounts[m.tinh_trang] || 0) + 1; });
      $('ttChips').innerHTML = '<span class="lbl">Tình trạng</span>' +
        [['all', 'Tất cả'], ...TT_KEYS.map(k => [k, TT[k][0]])].map(([k, l]) =>
          '<button type="button" class="chip' + (ttFilter === k ? ' on' : '') + '" data-ttf="' + k + '">' + escapeHtml(l) + ' ' + (ttCounts[k] || 0) + '</button>').join('');
      // Đếm trạng thái bảo dưỡng trong phạm vi tình trạng đang lọc.
      const scope = molds.filter(m => ttFilter === 'all' || m.tinh_trang === ttFilter);
      const counts = { all: scope.length };
      scope.forEach(m => { counts[m.trang_thai_khuon] = (counts[m.trang_thai_khuon] || 0) + 1; });
      $('kChips').innerHTML = '<span class="lbl">Bảo dưỡng</span>' + [['all', 'Tất cả'], ['Cần làm mới'], ['Cần bảo dưỡng'], ['Sắp bảo dưỡng'], ['OK']]
        .map(([k, l]) => '<button type="button" class="chip' + (kFilter === k ? ' on' : '') + '" data-kf="' + escapeHtml(k) + '">' + escapeHtml(l || k) + ' ' + (counts[k] || 0) + '</button>').join('');
      const iss = {};
      issues.filter(x => x.trang_thai !== 'Đã đóng').forEach(x => { (iss[String(x.ma_khuon).trim()] ||= []).push(x); });
      const spDangSx = {};
      molds.forEach(m => { if (m.tinh_trang === 'dang_sx' && m.ma_sp) spDangSx[m.ma_sp] = (spDangSx[m.ma_sp] || 0) + 1; });
      const list = scope.filter(m => (kFilter === 'all' || m.trang_thai_khuon === kFilter) &&
        (!q || m.ma_khuon.toLowerCase().includes(q) || m.ten_sp_gan_nhat.toLowerCase().includes(q)));
      const tb = $('tb');
      if (!list.length) {
        tb.innerHTML = '<tr><td colspan="11" class="empty">' + (molds.length ? 'Không có khuôn khớp bộ lọc'
          : 'Chưa có khuôn nào' + (admin ? ' — bấm ＋ Khai báo khuôn mới, hoặc khuôn tự xuất hiện sau khi chạy xong 1 ca.' : '.')) + '</td></tr>';
        return;
      }
      tb.innerHTML = list.map(m => {
        const pct = Math.min(100, Math.round(m.shots_since_maintenance / m.nguong_bao_duong * 100));
        const cls = ST_CLS[m.trang_thai_khuon] || '';
        const ii = iss[m.ma_khuon] || [];
        const pending = ii.some(x => x.trang_thai === 'Chờ xác nhận');
        const issTag = ii.length ? '<div><a href="van-de-khuon.html?khuon=' + encodeURIComponent(m.ma_khuon) + '" class="iss-tag" style="color:' + (pending ? 'var(--warn-fg)' : '#C2410C') + '">' +
          (pending ? '❓ Chờ xác nhận' : '⚠ Có vấn đề') + (ii.length > 1 ? ' (' + ii.length + ')' : '') + '</a></div>' : '';
        const ttCell = '<span class="tt ' + m.tinh_trang + '">' + TT[m.tinh_trang][0] + '</span>' +
          (m.tinh_trang_ly_do ? '<div class="tt-sub" title="' + escapeHtml(m.tinh_trang_ly_do + ' — ' + m.tinh_trang_boi + ' ' + fmtDate(m.tinh_trang_luc)) + '">' + escapeHtml(m.tinh_trang_ly_do) + '</div>' : '');
        const nhieuKhuon = m.tinh_trang === 'dang_sx' && m.ma_sp && (spDangSx[m.ma_sp] || 0) >= 2;
        const mk = escapeHtml(m.ma_khuon);
        return '<tr class="' + (m.tinh_trang === 'dang_sx' ? '' : 'inactive') + '"><td class="mk">' + mk +
          (m.uu_tien && m.tinh_trang === 'dang_sx' ? '<span class="ut" title="Thứ tự ưu tiên trong mã ' + escapeHtml(m.ma_sp) + '">ưu tiên ' + m.uu_tien + '</span>' : '') + '</td><td>' + ttCell + '</td><td>' + escapeHtml(m.ten_sp_gan_nhat || '—') + '</td>' +
          '<td class="num">' + fmtNum(m.tong_shot_luy_ke) + '</td>' +
          '<td class="num">' + fmtNum(m.shots_since_maintenance) + '<div class="bar"><i style="width:' + pct + '%;background:' +
            ({ ok: 'var(--run-fg)', soon: 'var(--warn-fg)', due: 'var(--alarm-fg)', renew: '#9F1239' }[cls] || 'var(--text-dim)') + '"></i></div></td>' +
          '<td class="num">' + fmtNum(m.nguong_bao_duong) + '</td><td class="num">' + fmtNum(m.nguong_lam_moi) + '</td>' +
          '<td>' + fmtDate(m.lan_bao_duong_gan_nhat) + '</td><td>' + nextDueLabel(m) + '</td>' +
          '<td><span class="st ' + cls + '">' + escapeHtml(m.trang_thai_khuon) + '</span>' + issTag + '</td>' +
          '<td class="act">' +
            (admin && nhieuKhuon ? '<button type="button" class="kb ol sm" data-ut="' + mk + '" title="Thứ tự ưu tiên các khuôn của mã ' + escapeHtml(m.ma_sp) + '">⇅ Ưu tiên</button> ' : '') +
            (admin ? '<button type="button" class="kb ol sm" data-tt="' + mk + '">🏷 Tình trạng</button> ' : '') +
            '<a class="kb ol sm" href="van-de-khuon.html?khuon=' + encodeURIComponent(m.ma_khuon) + '&tab=lich-su" title="Lịch sử sự cố + IPQC NG của khuôn">🔎 Vấn đề</a> ' +
            (admin ? '<button type="button" class="kb ol sm" data-cfg="' + mk + '">✏ Sửa</button> ' : '') +
            '<a class="kb ol sm" href="quan-ly-khuon.html?tab=mau&khuon=' + encodeURIComponent(m.ma_khuon) + '" data-gomau="' + mk + '">📋 Hạng mục</a></td></tr>';
      }).join('');
    }

    // ── Khai báo / sửa / đổi mã / xoá khuôn ──────────────────────────────────
    function openCfg(maKhuon){
      const m = maKhuon ? molds.find(x => x.ma_khuon === maKhuon) : null;
      cur = m;
      f('cfg-title').textContent = m ? 'Sửa khuôn ' + m.ma_khuon : 'Khai báo khuôn mới';
      f('ma-khuon').value = m ? m.ma_khuon : '';
      f('ma-khuon-hint').textContent = m
        ? 'Đổi mã ở đây = đổi tên khuôn — chỉ áp dụng cho trạm đang chạy và kế hoạch tuần hiện tại/tương lai, không sửa lại lịch sử (log bảo dưỡng, vấn đề khuôn, hàng NG, tem đã in).' : '';
      const sel = f('ma-sp');
      sel.innerHTML = '<option value="">— Chọn mã SP —</option>' + products.map(p => '<option value="' + escapeHtml(p.ma_sp) + '">' + escapeHtml(p.ma_sp + ' — ' + (p.ten_sp || '')) + '</option>').join('');
      sel.value = m ? m.ma_sp : '';
      f('sp-req').hidden = !!m;
      f('tong-shot').value = m ? m.tong_shot_luy_ke : '';
      f('shot-since').value = m ? m.shots_since_maintenance : '';
      f('nguong-bd').value = m ? m.nguong_bao_duong : '';
      f('nguong-lm').value = m ? m.nguong_lam_moi : '';
      f('chu-ky').value = m && m.chu_ky_bao_duong_ngay ? m.chu_ky_bao_duong_ngay : '';
      f('ghi-chu').value = '';
      host.querySelector('[data-act="cfg-del"]').hidden = !m;
      openDlg('cfg');
    }
    async function saveCfg(btn){
      const maMoi = f('ma-khuon').value.trim();
      if (!maMoi) return showMsg('Cần nhập mã khuôn', 'err');
      const maSp = f('ma-sp').value.trim();
      if (!cur && !maSp) return showMsg('Khuôn mới cần khai báo mã sản phẩm', 'err');
      btn.disabled = true;
      try {
        // Đổi tên TRƯỚC nếu mã bị sửa (khuôn mới thì duc_configure_mold tự tạo đúng mã).
        let ma = cur ? cur.ma_khuon : maMoi;
        if (cur && maMoi !== cur.ma_khuon) {
          const r = await rpcWrite('duc_rename_khuon', { p_ma_khuon_cu: cur.ma_khuon, p_ma_khuon_moi: maMoi, p_user: opt.userName });
          ma = r.ma_khuon_moi;
        }
        const d = await rpcWrite('duc_configure_mold', {
          p_ma_khuon: ma, p_ma_sp: maSp || null,
          p_tong_shot_luy_ke: numOrNull(f('tong-shot').value),
          p_shots_since_maintenance: numOrNull(f('shot-since').value),
          p_nguong_bao_duong_moi: numOrNull(f('nguong-bd').value),
          p_nguong_lam_moi_moi: numOrNull(f('nguong-lm').value),
          p_chu_ky_bao_duong_ngay: numOrNull(f('chu-ky').value),
          p_ghi_chu: f('ghi-chu').value.trim() || null,
          p_user: opt.userName,
        });
        closeDlg();
        showMsg('✓ Đã lưu khuôn ' + d.ma_khuon, 'ok');
        await load();
      } catch (e) { showMsg('Lỗi: ' + e.message, 'err', 6000); }
      finally { btn.disabled = false; }
    }
    // Chỉ xoá khỏi danh sách chọn, KHÔNG đụng lịch sử (migration_phase_D36). Bị chặn
    // nếu khuôn đang gán trạm đang chạy / có trong KH tuần hiện tại-tương lai.
    async function deleteCfg(){
      if (!cur) return;
      if (!confirm('Xoá khuôn "' + cur.ma_khuon + '" khỏi danh sách chọn?\n\n' +
        'Chỉ xoá được khuôn không đang gán cho trạm nào và không có trong kế hoạch tuần hiện tại/tương lai.\n' +
        'Lịch sử bảo dưỡng/vấn đề/hàng NG/tem cũ (nếu có) vẫn được giữ nguyên.')) return;
      try {
        await rpcWrite('duc_xoa_khuon', { p_ma_khuon: cur.ma_khuon, p_user: opt.userName });
        closeDlg();
        showMsg('✓ Đã xoá khuôn ' + cur.ma_khuon, 'ok');
        await load();
      } catch (e) { showMsg('Lỗi: ' + e.message, 'err', 6000); }
    }

    // ── Thứ tự ưu tiên khuôn (T86) ───────────────────────────────────────────
    function openUt(maKhuon){
      const m = molds.find(x => x.ma_khuon === maKhuon);
      if (!m) return;
      utSp = m.ma_sp;
      // Khuôn Đang sản xuất của mã, xếp theo ưu tiên (chưa đặt thì xuống cuối).
      utDs = molds.filter(x => x.ma_sp === utSp && x.tinh_trang === 'dang_sx')
        .sort((a, b) => ((a.uu_tien || 1e9) - (b.uu_tien || 1e9)) || naturalCompare(a.ma_khuon, b.ma_khuon)).map(x => x.ma_khuon);
      f('ut-sp').textContent = utSp;
      renderUt();
      openDlg('ut');
    }
    function renderUt(){
      f('ut-list').innerHTML = utDs.map((mk, i) => {
        const m = molds.find(x => x.ma_khuon === mk);
        return '<div class="ut-row"><span class="no">' + (i + 1) + '</span><span class="mk">' + escapeHtml(mk) +
          '<small>' + fmtNum(m.shots_since_maintenance) + ' / ' + fmtNum(m.nguong_bao_duong) + ' shot từ lần BD · tổng ' + fmtNum(m.tong_shot_luy_ke) +
          ' · <span class="st ' + (ST_CLS[m.trang_thai_khuon] || '') + '">' + escapeHtml(m.trang_thai_khuon) + '</span></small></span>' +
          '<button type="button" data-ut-mv="-1" data-i="' + i + '"' + (i === 0 ? ' disabled' : '') + ' title="Lên">▲</button>' +
          '<button type="button" data-ut-mv="1" data-i="' + i + '"' + (i === utDs.length - 1 ? ' disabled' : '') + ' title="Xuống">▼</button></div>';
      }).join('');
    }
    async function saveUt(btn){
      btn.disabled = true;
      try {
        await rpcWrite('duc_khuon_dat_uu_tien', { p_ma_sp: utSp, p_ds_khuon: utDs });
        closeDlg();
        showMsg('✓ Đã lưu thứ tự ưu tiên khuôn mã ' + utSp + ': ' + utDs.join(' → '), 'ok', 4000);
        await load();
      } catch (e) { showMsg('Lỗi: ' + e.message, 'err', 6000); }
      finally { btn.disabled = false; }
    }

    // ── Tình trạng khuôn (T79) ───────────────────────────────────────────────
    async function openTt(maKhuon){
      const m = molds.find(x => x.ma_khuon === maKhuon);
      if (!m) return;
      cur = m;
      f('tt-tag').textContent = m.ma_khuon;
      f('tt-shot').innerHTML = 'Tổng shot <b>' + fmtNum(m.tong_shot_luy_ke) + '</b> / ngưỡng làm mới ' + fmtNum(m.nguong_lam_moi) +
        ' — <span class="st ' + (ST_CLS[m.trang_thai_khuon] || '') + '">' + escapeHtml(m.trang_thai_khuon) + '</span>';
      f('tt-opts').innerHTML = TT_KEYS.map(k => '<label class="tt-opt' + (k === m.tinh_trang ? ' cur' : '') + '">' +
        '<input type="radio" name="kds-tt" value="' + k + '"' + (k === m.tinh_trang ? ' disabled' : '') + '>' +
        '<span><span class="tt ' + k + '">' + TT[k][0] + '</span>' + (k === m.tinh_trang ? ' <b style="font-size:11px">(hiện tại)</b>' : '') +
        '<small>' + TT[k][1] + '</small></span></label>').join('');
      f('tt-ly-do').value = '';
      openDlg('tt');
      const h = f('tt-history');
      h.textContent = 'Đang tải...';
      const { data } = await sb.from('duc_khuon_tinh_trang_log').select('tu,sang,ly_do,nguoi,thoi_diem')
        .eq('ma_khuon', m.ma_khuon).order('thoi_diem', { ascending: false }).limit(10);
      const lb = k => TT[k] ? TT[k][0] : (k || '—');
      h.innerHTML = data && data.length ? data.map(r => '<div><b>' + fmtDate(r.thoi_diem) + '</b> — ' + escapeHtml(lb(r.tu)) + ' → <b>' + escapeHtml(lb(r.sang)) + '</b>' +
        (r.nguoi ? ' — ' + escapeHtml(r.nguoi) : '') + (r.ly_do ? '<div style="color:var(--text-muted);border:none;padding:0">' + escapeHtml(r.ly_do) + '</div>' : '') + '</div>').join('')
        : 'Chưa đổi tình trạng lần nào.';
    }
    async function saveTt(btn){
      if (!cur) return;
      const r = host.querySelector('[data-f="tt-opts"] input[name="kds-tt"]:checked');
      if (!r) return showMsg('Chọn tình trạng mới', 'err');
      const lyDo = f('tt-ly-do').value.trim();
      if (!lyDo) return showMsg('Nhập lý do / ghi chú', 'err');
      btn.disabled = true;
      try {
        await rpcWrite('duc_khuon_doi_tinh_trang', { p_ma_khuon: cur.ma_khuon, p_tinh_trang: r.value, p_ly_do: lyDo });
        closeDlg();
        showMsg('✓ Khuôn ' + cur.ma_khuon + ': ' + TT[r.value][0], 'ok');
        await load();
      } catch (e) { showMsg('Lỗi: ' + e.message, 'err', 6000); }
      finally { btn.disabled = false; }
    }

    // ── Sự kiện ──────────────────────────────────────────────────────────────
    $('q').addEventListener('input', e => { q = e.target.value.trim().toLowerCase(); render(); });
    el.addEventListener('click', e => {
      const t = e.target.closest('[data-kf],[data-ttf],[data-tt],[data-ut],[data-cfg],[data-act="new"]');
      if (!t) return;
      if (t.dataset.kf) { kFilter = t.dataset.kf; return render(); }
      if (t.dataset.ttf) { ttFilter = t.dataset.ttf; return render(); }
      if (!admin) return;
      if (t.dataset.tt) return openTt(t.dataset.tt);
      if (t.dataset.ut) return openUt(t.dataset.ut);
      if (t.dataset.cfg) return openCfg(t.dataset.cfg);
      if (t.dataset.act === 'new') return openCfg(null);
    });
    if (admin) {
      host.addEventListener('click', e => {
        if (e.target.classList.contains('kds-mask') || e.target.closest('[data-close]')) return closeDlg();
        const mv = e.target.closest('button[data-ut-mv]');
        if (mv) {
          const i = Number(mv.dataset.i), j = i + Number(mv.dataset.utMv);
          [utDs[i], utDs[j]] = [utDs[j], utDs[i]];
          return renderUt();
        }
        const b = e.target.closest('[data-act]');
        if (!b) return;
        if (b.dataset.act === 'cfg-save') return saveCfg(b);
        if (b.dataset.act === 'cfg-del') return deleteCfg();
        if (b.dataset.act === 'ut-save') return saveUt(b);
        if (b.dataset.act === 'tt-save') return saveTt(b);
      });
      document.addEventListener('keydown', e => { if (e.key === 'Escape') closeDlg(); });
    }

    load();
    return { reload: load };
  }

  window.KhuonDs = { mount };
})();
