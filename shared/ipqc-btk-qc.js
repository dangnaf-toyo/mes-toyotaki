/**
 * ============================================================================
 * ipqc-btk-qc.js — T133: QC Manager
 *   IpqcBtkQc.mountEditor(el)  — tab "Quản lý tiêu chuẩn": lập bảng tuần kiểm
 *       theo mã (phiên bản A/B/..., hạng mục đo số / OK-NG, bản vẽ + vị trí đo,
 *       lịch sử sửa đổi), nhập / xuất Excel.
 *   IpqcBtkQc.mountChart(el)   — tab "Biểu đồ kiểm soát": biểu đồ I-MR / X̄-R,
 *       cảnh báo theo 4 quy tắc, Cp/Cpk, tổng quan hạng mục, đặt lại giới hạn.
 * RPC: ipqc_btk_luu / ipqc_do_du_lieu / ipqc_gioi_han_dat
 *   T163: ipqc_btk_luu chỉ tạo BẢN NHÁP chờ duyệt (NV QC soạn → TP QC kiểm tra → GĐ SX
 *   phê duyệt, ipqc_tc_duyet / ipqc_tc_huy); khoiDuyet/duyet/huy dùng chung cho checklist.
 * (supabase/migration_phase_T133_ipqc_bang_tuan_kiem.sql). Cần ipqc-spc.js,
 * SheetJS (XLSX) cho nhập/xuất Excel.
 * ============================================================================
 */
(function () {
  const S = () => window.IpqcSpc;
  const esc = s => S().esc(s);
  const COT = ['Mã SP', 'Phiên bản', 'Ngày hiệu lực', 'Số mẫu/lần', 'No', 'Hạng mục', 'Kiểu (Đo số / OK-NG)',
    'Danh nghĩa', 'Dung sai +', 'Dung sai −', 'Tiêu chuẩn (OK-NG)', 'Dụng cụ KT', 'Tần suất', 'Nội dung sửa đổi', 'Người phê duyệt'];

  function css() {
    if (document.getElementById('bq-css')) return;
    const st = document.createElement('style'); st.id = 'bq-css';
    st.textContent =
      '.bq{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-start;font-size:13px}' +
      '.bq .side{flex:1 1 240px;max-width:290px;min-width:0;background:#fff;border:1px solid #D9DFE5;border-radius:12px;padding:10px;position:sticky;top:calc(var(--navbar-h,50px) + 8px);align-self:flex-start}' +
      '.bq .side [data-list]{max-height:calc(100vh - var(--navbar-h,50px) - 130px);min-height:200px;overflow-y:auto;overscroll-behavior:contain;padding-right:2px}' +
      '.bq .main{scroll-margin-top:calc(var(--navbar-h,50px) + 8px)}' +
      '@media (max-width:700px){.bq .side{position:static;max-width:none}.bq .side [data-list]{max-height:50vh}}' +
      '.bq .main{flex:999 1 620px;min-width:0;display:flex;flex-direction:column;gap:12px}' +
      '.bq .card{background:#fff;border:1px solid #D9DFE5;border-radius:12px;padding:12px 14px}' +
      '.bq .ttl{font-size:11px;font-weight:700;color:#64748B;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px;display:flex;align-items:center;gap:8px}' +
      '.bq .ttl .sp{flex:1}' +
      '.bq input,.bq select,.bq textarea{font:inherit;padding:6px 8px;border:1.5px solid #B8C1CC;border-radius:7px;background:#fff;box-sizing:border-box;min-width:0}' +
      '.bq label.f{display:flex;flex-direction:column;gap:3px;font-size:11px;font-weight:600;color:#64748B}' +
      '.bq .btn{font:inherit;font-weight:700;padding:7px 12px;border-radius:8px;border:1.5px solid #0F5FA5;background:#fff;color:#0F5FA5;cursor:pointer}' +
      '.bq .btn.p{background:#0F5FA5;color:#fff}.bq .btn.sm{padding:4px 9px;font-size:12px}.bq .btn.d{border-color:#FCA5A5;color:#B91C1C}' +
      '.bq .btn:disabled{opacity:.5;cursor:not-allowed}' +
      '.bq .li{display:flex;align-items:center;gap:8px;padding:7px 8px;border-radius:8px;cursor:pointer;border:1px solid transparent}' +
      '.bq .li:hover{background:#F1F5F9}.bq .li.on{background:#EFF6FF;border-color:#93C5FD}' +
      '.bq .li .m{font-family:"JetBrains Mono",monospace;font-weight:700;font-size:12.5px}.bq .li .t{font-size:11.5px;color:#64748B}' +
      '.bq .tag{font-size:10.5px;font-weight:700;padding:1px 7px;border-radius:10px;white-space:nowrap}' +
      '.bq .tag.ok{background:#DCFCE7;color:#166534}.bq .tag.no{background:#FEF3C7;color:#92400E}.bq .tag.ng{background:#FEE2E2;color:#991B1B}.bq .tag.w{background:#FEF3C7;color:#92400E}' +
      '.bq .flds{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:flex-end}' +
      '.bq table{width:100%;border-collapse:collapse}.bq th{background:#F1F5F9;color:#475569;text-align:left;padding:6px;font-size:12px;white-space:nowrap}' +
      '.bq td{padding:4px 5px;border-top:1px solid #EEF1F5;vertical-align:middle}' +
      '.bq .tbl{overflow-x:auto}.bq .mono{font-family:"JetBrains Mono",monospace}' +
      '.bq .no{display:inline-flex;width:22px;height:22px;border-radius:50%;background:#DC2626;color:#fff;font-weight:800;align-items:center;justify-content:center;font-size:11.5px}' +
      '.bq .bv{position:relative;border:1.5px dashed #B8C1CC;border-radius:10px;background:#F8FAFC;min-height:180px;display:flex;align-items:center;justify-content:center;color:#64748B;text-align:center;overflow:hidden}' +
      '.bq .bv img{display:block;max-width:100%;cursor:crosshair}.bq .bv .b{position:absolute;transform:translate(-50%,-50%);width:24px;height:24px;border-radius:50%;background:#DC2626;color:#fff;font-weight:800;display:flex;align-items:center;justify-content:center;font-size:12px;border:2px solid #fff;pointer-events:none}' +
      '.bq .msg{padding:8px 10px;border-radius:8px;font-weight:600;font-size:12.5px;margin-top:8px}.bq .msg.err{background:#FEF2F2;color:#B91C1C;border:1px solid #FCA5A5}.bq .msg.ok{background:#ECFDF5;color:#047857;border:1px solid #A7E3C6}' +
      '.bq .hint{font-size:11.5px;color:#64748B;margin-top:6px}' +
      '.bq .ro td input,.bq .ro td select{background:#F8FAFC}' +
      '.bq .al{border:1.5px solid #FCD34D;background:#FFFBEB;border-radius:10px;padding:8px 10px;margin-bottom:7px;cursor:pointer}' +
      '.bq .al.ng{border-color:#FCA5A5;background:#FEF2F2}.bq .al .h{display:flex;gap:6px;align-items:center;font-weight:700}.bq .al .s{font-size:11.5px;color:#64748B;margin-top:2px}' +
      '.bq .kpi{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.bq .kpi div{background:#F8FAFC;border-radius:8px;padding:7px 9px}' +
      '.bq .kpi .k{font-size:11px;color:#64748B}.bq .kpi .v{font-family:"JetBrains Mono",monospace;font-weight:800;font-size:17px}' +
      '.bq .lg{display:flex;flex-wrap:wrap;gap:6px 14px;font-size:11.5px;color:#475569;margin-top:4px}' +
      '.bq tr.clk{cursor:pointer}.bq tr.clk:hover td{background:#F8FAFC}.bq tr.sel td{background:#EFF6FF}' +
      '.bq-mask{position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:9000;display:flex;align-items:center;justify-content:center;padding:14px}' +
      '.bq-dlg{background:#fff;border-radius:12px;max-width:760px;width:100%;max-height:90vh;overflow:auto;padding:14px 16px;font-size:13px}' +
      '.bq .tag.no{display:inline-block;width:auto;height:auto;border-radius:10px;background:#FEF3C7;color:#92400E;font-size:10.5px}' +
      '.bq td.doi input,.bq td.doi select{background:#FEF9C3;border-color:#EAB308}.bq tr.moi td:first-child{box-shadow:inset 3px 0 #16A34A}' +
      '.tcd{border:1.5px solid #FCD34D;background:#FFFBEB;border-radius:10px;padding:10px 12px;margin-top:10px;font-size:13px}' +
      '.tcd .bcs{display:flex;flex-wrap:wrap;gap:6px}.tcd .bc{flex:1 1 150px;background:#fff;border:1px solid #E2E8F0;border-radius:8px;padding:6px 9px;display:flex;flex-direction:column;gap:2px;font-size:12px;color:#64748B}' +
      '.tcd .bc b{color:#0F172A}.tcd .bc.x{border-color:#A7E3C6}.tcd .bc.x b::before{content:"✓ ";color:#047857}.tcd .bc.c{border-color:#F59E0B;box-shadow:0 0 0 2px #FEF3C7}' +
      '.tcd .nut{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}' +
      '.tcd .btn{font:inherit;font-size:12.5px;font-weight:700;padding:7px 12px;border-radius:8px;border:1.5px solid #0F5FA5;background:#fff;color:#0F5FA5;cursor:pointer}.tcd .btn.p{background:#0F5FA5;color:#fff}.tcd .btn.d{border-color:#FCA5A5;color:#B91C1C}.tcd .btn:disabled{opacity:.5}' +
      '.tcd .loi{margin-top:8px;padding:7px 10px;border-radius:8px;background:#FEF2F2;color:#B91C1C;border:1px solid #FCA5A5;font-weight:600;font-size:12.5px}';
    document.head.appendChild(st);
  }
  function msg(el, text, kind) { el.innerHTML = text ? '<div class="msg ' + (kind || 'ok') + '">' + esc(text) + '</div>' : ''; }
  async function nguoi() { try { return (await MesAuth.getCurrentUserIdentity()) || ''; } catch (e) { return ''; } }
  function ngayVN(ts) { return ts ? new Date(ts).toLocaleString('vi-VN', { hour12: false, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : ''; }
  function soVN(v) { if (v === null || v === undefined) return ''; const s = String(v).trim().replace(/^[ØøФф⌀]\s*/, '').replace(',', '.'); return s; }

  // ═══════════════════════════ PHÊ DUYỆT TIÊU CHUẨN (T163) ═══════════════════════════
  // Nhân viên QC soạn → Trưởng phòng QC kiểm tra → Giám đốc SX phê duyệt. Dùng chung cho
  // bảng tuần kiểm ('btk') và checklist + PDF ('checklist', qc-manager.html).
  const TT = { cho_kiem_tra: 'Chờ TP QC kiểm tra', cho_phe_duyet: 'Chờ GĐ SX phê duyệt', tra_lai: 'Bị trả lại', da_duyet: 'Đã duyệt' };
  const TT_NGAN = { cho_kiem_tra: 'chờ kiểm tra', cho_phe_duyet: 'chờ phê duyệt', tra_lai: 'bị trả lại' };
  const SOAN = ['ipqc', 'nhan_vien_oqc', 'qc_manager', 'admin'];
  let quyenP = null;
  /** {uid, role, soan, kiemTra, pheDuyet, huyMoi} của người đang đăng nhập (uid null = chưa đăng nhập). */
  function quyen() {
    if (!quyenP) quyenP = (async () => {
      try {
        const s = await MesAuth.getSession();
        if (!s) return { uid: null, role: null };
        const { data } = await sb.from('user_roles').select('role').eq('user_id', s.user.id).maybeSingle();
        const role = data ? data.role : null;
        return { uid: s.user.id, role, soan: SOAN.includes(role), kiemTra: role === 'qc_manager', pheDuyet: role === 'giam_doc_sx', huyMoi: role === 'qc_manager' || role === 'admin' };
      } catch (e) { return { uid: null, role: null }; }
    })();
    return quyenP;
  }
  const DA_XONG = { kiem_tra: 'Đã kiểm tra — chuyển Giám đốc SX phê duyệt.', phe_duyet: 'Đã phê duyệt — có hiệu lực ngay cho IPQC.', tra_lai: 'Đã trả lại cho người soạn.' };
  /** Kiểm tra / phê duyệt / trả lại 1 bản nháp. Trả null nếu người dùng bấm huỷ; ném lỗi nếu không được. */
  async function duyet(loai, id, hanhDong) {
    let lyDo = null;
    if (hanhDong === 'tra_lai') {
      lyDo = prompt('Lý do trả lại (người soạn sẽ thấy):');
      if (lyDo === null) return null;
      if (!lyDo.trim()) throw new Error('Nhập lý do trả lại.');
    }
    if (hanhDong === 'phe_duyet' && !confirm('Phê duyệt? Bản này có hiệu lực ngay cho IPQC, thay bản đang dùng.')) return null;
    const { data, error } = await sb.rpc('ipqc_tc_duyet', { p_loai: loai, p_id: id, p_hanh_dong: hanhDong, p_ly_do: lyDo, p_nguoi: await nguoi() });
    if (error) throw new Error(error.message);
    if (!data || !data.ok) throw new Error((data && data.error) || 'Không thực hiện được');
    return DA_XONG[hanhDong];
  }
  async function huy(loai, id) {
    if (!confirm('Huỷ bản nháp này? Nội dung đã soạn sẽ mất.')) return null;
    const { data, error } = await sb.rpc('ipqc_tc_huy', { p_loai: loai, p_id: id });
    if (error) throw new Error(error.message);
    if (!data || !data.ok) throw new Error((data && data.error) || 'Không huỷ được');
    return 'Đã huỷ bản nháp.';
  }
  /** Khối 3 bước + nút duyệt cho 1 bản nháp r (dòng ipqc_btk / duc_ipqc_tieuchuan_de_xuat). */
  function khoiDuyet(r, q) {
    css();
    const tt = r.trang_thai;
    const buoc = (ten, ai, luc, xong, cho) => '<div class="bc' + (xong ? ' x' : cho ? ' c' : '') + '"><b>' + ten + '</b><span>' +
      (xong ? esc(ai || '') + ' · ' + esc(ngayVN(luc)) : cho ? 'Đang chờ' : '—') + '</span></div>';
    let h = '<div class="tcd"><div class="bcs">' +
      buoc('Soạn', r.nguoi_lap, r.gui_luc || r.tao_luc, true, false) +
      buoc('Trưởng phòng QC kiểm tra', r.nguoi_kiem_tra, r.kiem_tra_luc, tt === 'cho_phe_duyet', tt === 'cho_kiem_tra') +
      buoc('Giám đốc SX phê duyệt', r.nguoi_phe_duyet, r.phe_duyet_luc, false, tt === 'cho_phe_duyet') + '</div>';
    if (tt === 'tra_lai') h += '<div class="loi">Bị trả lại bởi ' + esc(r.nguoi_tra_lai || '') + ' (' + esc(ngayVN(r.tra_lai_luc)) + '): ' + esc(r.ly_do_tra_lai || '') + ' — sửa rồi gửi lại.</div>';
    const nut = [];
    if (tt === 'cho_kiem_tra' && q.kiemTra) nut.push('<button class="btn p" type="button" data-duyet="kiem_tra">✓ Kiểm tra đạt — chuyển GĐ SX</button>', '<button class="btn d" type="button" data-duyet="tra_lai">Trả lại</button>');
    if (tt === 'cho_phe_duyet' && q.pheDuyet) nut.push('<button class="btn p" type="button" data-duyet="phe_duyet">✓ Phê duyệt — áp dụng</button>', '<button class="btn d" type="button" data-duyet="tra_lai">Trả lại</button>');
    if (q.uid && (r.nguoi_lap_uid === q.uid || q.huyMoi)) nut.push('<button class="btn d" type="button" data-huy>Huỷ bản nháp</button>');
    if (nut.length) h += '<div class="nut">' + nut.join('') + '</div>';
    return h + '</div>';
  }

  // ═══════════════════════════ BẢNG TUẦN KIỂM ═══════════════════════════
  // opts.doiTrangThai(): gọi sau mỗi lần gửi duyệt / duyệt / huỷ (để trang làm mới danh sách chờ duyệt).
  async function mountEditor(el, opts) {
    css();
    const q = await quyen();
    const baoDoi = () => { if (opts && opts.doiTrangThai) opts.doiTrangThai(); };
    const st = { products: [], btk: {}, nhap: {}, ma: null, versions: [], xem: null, rows: [], viTri: [], banVe: null, noDat: 1 };
    el.innerHTML = '<div class="bq"><div class="side"><div class="ttl"><span class="sp">Bảng tuần kiểm theo mã</span></div>' +
      '<input type="search" data-tim placeholder="Tìm mã SP…" aria-label="Tìm mã SP" style="width:100%;margin-bottom:8px"><div data-list></div></div>' +
      '<div class="main" data-main><div class="card" style="color:#64748B">Chọn 1 mã SP ở cột trái để xem / soạn bảng tuần kiểm kích thước. ' +
      '<div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap">' + (q.soan ? '<button class="btn" type="button" data-nhap>Nhập từ Excel</button>' : '') + '<button class="btn" type="button" data-mau>Tải file mẫu</button></div></div></div></div>';
    const listEl = el.querySelector('[data-list]'), main = el.querySelector('[data-main]');

    async function taiDanhSach() {
      const [p, b] = await Promise.all([
        sb.from('master_products').select('ma_sp,ten_sp,ten_khach_hang').order('ma_sp'),
        sb.from('ipqc_btk').select('ma_sp,phien_ban,id,dang_dung,trang_thai').or('dang_dung.eq.true,trang_thai.neq.da_duyet'),
      ]);
      st.products = p.data || [];
      st.btk = {}; st.nhap = {};
      (b.data || []).forEach(x => { if (x.dang_dung) st.btk[x.ma_sp] = x; else st.nhap[x.ma_sp] = x; });
      veDanhSach();
    }
    function veDanhSach() {
      const q2 = (el.querySelector('[data-tim]').value || '').trim().toLowerCase();
      const hang = ma => st.nhap[ma] ? 2 : st.btk[ma] ? 1 : 0;
      const ds = st.products.filter(p => !q2 || (p.ma_sp + ' ' + (p.ten_sp || '') + ' ' + (p.ten_khach_hang || '')).toLowerCase().includes(q2))
        .sort((a, b) => hang(b.ma_sp) - hang(a.ma_sp) || a.ma_sp.localeCompare(b.ma_sp));
      listEl.innerHTML = ds.map(p => {
        const nh = st.nhap[p.ma_sp];
        return '<div class="li' + (p.ma_sp === st.ma ? ' on' : '') + '" data-ma="' + esc(p.ma_sp) + '" role="button" tabindex="0">' +
          '<div style="flex:1;min-width:0"><div class="m">' + esc(p.ma_sp) + '</div><div class="t">' + esc(p.ten_sp || '') + '</div></div>' +
          (nh ? '<span class="tag ' + (nh.trang_thai === 'tra_lai' ? 'ng' : 'w') + '" title="' + esc(TT[nh.trang_thai]) + '">' + esc(nh.phien_ban) + ' · ' + (nh.trang_thai === 'tra_lai' ? 'trả lại' : 'chờ') + '</span>' : '') +
          (st.btk[p.ma_sp] ? '<span class="tag ok">' + esc(st.btk[p.ma_sp].phien_ban) + '</span>' : nh ? '' : '<span class="tag no">Chưa có</span>') + '</div>';
      }).join('') || '<div class="hint">Không có mã phù hợp.</div>';
    }

    // idXem: phiên bản muốn mở; mặc định bản nháp đang chờ duyệt (nếu có), không thì bản đang dùng.
    async function chonMa(ma, idXem) {
      st.ma = ma; veDanhSach();
      // Danh sách có thanh trượt riêng: bấm mã ở cuối danh sách thì đưa nội dung bên phải lên đầu màn hình.
      const top = main.getBoundingClientRect().top;
      if (top < 0 || top > window.innerHeight * 0.5) main.scrollIntoView({ block: 'start' });
      const v = await sb.from('ipqc_btk').select('*').eq('ma_sp', ma).order('tao_luc', { ascending: false });
      st.versions = v.data || [];
      const ids = st.versions.map(x => x.id);
      const m = ids.length ? await sb.from('ipqc_btk_muc').select('*').in('id_btk', ids).order('muc_no') : { data: [] };
      st.mucAll = m.data || [];
      const chon = (idXem && st.versions.find(x => x.id === idXem)) || st.versions.find(x => x.trang_thai !== 'da_duyet') || st.versions.find(x => x.dang_dung) || null;
      napPhienBan(chon);
    }
    function napPhienBan(b) {
      st.xem = b;
      st.rows = b ? st.mucAll.filter(x => x.id_btk === b.id).map(x => ({ ...x })) : [{ muc_no: 1, kieu: 'so', hang_muc: 'Kích thước', tan_suat: '2h/lần' }];
      st.viTri = b ? (b.ban_ve_vi_tri || []).map(x => ({ ...x })) : [];
      st.banVe = b ? b.ban_ve_url : null;
      ve();
    }
    function phienBanMoi() {
      const cur = st.versions.find(x => x.dang_dung);
      if (!cur) return 'A';
      return /^[A-Y]$/.test(cur.phien_ban) ? String.fromCharCode(cur.phien_ban.charCodeAt(0) + 1) : cur.phien_ban + '.1';
    }
    // So bản nháp với bản đang dùng: ô đã sửa / hạng mục mới / hạng mục bị bỏ.
    const COT_SS = ['hang_muc', 'kieu', 'danh_nghia', 'dung_sai_tren', 'dung_sai_duoi', 'tieu_chuan', 'dung_cu', 'tan_suat'];
    function giongNhau(a, b) {
      const x = String(a ?? '').trim(), y = String(b ?? '').trim();
      return x === y || (x !== '' && y !== '' && isFinite(+soVN(x)) && isFinite(+soVN(y)) && +soVN(x) === +soVN(y));
    }
    function soSanh(cur) {
      if (!cur) return null;
      const goc = {}; st.mucAll.filter(x => x.id_btk === cur.id).forEach(x => { goc[+x.muc_no] = x; });
      const doi = st.rows.map(r => { const g = goc[+r.muc_no]; return g ? COT_SS.filter(c => !giongNhau(r[c], g[c])) : null; });
      const nos = new Set(st.rows.map(r => +r.muc_no));
      return { cur, doi, bo: Object.values(goc).filter(g => !nos.has(+g.muc_no)) };
    }

    function ve() {
      const p = st.products.find(x => x.ma_sp === st.ma) || {};
      const b = st.xem;
      const cur = st.versions.find(x => x.dang_dung) || null;
      const nhap = st.versions.find(x => x.trang_thai !== 'da_duyet') || null;
      const laNhap = !!(b && b.trang_thai !== 'da_duyet');
      const cu = b && !laNhap && !b.dang_dung;
      const ss = laNhap ? soSanh(cur) : null;
      const dis = q.soan ? '' : ' disabled';
      const tenPb = v => esc(v.phien_ban) + (v.dang_dung ? ' (đang dùng)' : v.trang_thai !== 'da_duyet' ? ' (' + TT_NGAN[v.trang_thai] + ')' : ' (cũ)');
      let canhBao = '';
      if (cu) canhBao = 'Đang xem phiên bản cũ ' + esc(b.phien_ban) + ' (chỉ xem). Gửi duyệt sẽ tạo bản nháp từ nội dung này' + (nhap ? ', ghi đè bản nháp ' + esc(nhap.phien_ban) : '') + '.';
      else if (!laNhap && nhap) canhBao = 'Mã này đang có bản nháp ' + esc(nhap.phien_ban) + ' (' + esc(TT_NGAN[nhap.trang_thai]) + ') — chọn ở ô "Đang xem". Gửi duyệt từ đây sẽ ghi đè bản nháp đó.';
      else if (!cur) canhBao = 'Mã chưa có bảng tuần kiểm được duyệt — IPQC chưa đo theo bảng tuần kiểm cho mã này.';
      main.innerHTML =
        '<div class="card"><div class="flds">' +
          '<div style="flex:1 1 220px"><div style="font-size:11px;color:#64748B;font-weight:600">Biểu kiểm tra tuần kiểm · ' + esc((b && b.ma_bieu) || 'QP-82405-B') + '</div>' +
          '<div style="font-size:19px;font-weight:800">' + esc(st.ma) + ' <span style="font-size:13px;color:#475569;font-weight:600">' + esc(p.ten_sp || '') + '</span></div></div>' +
          '<label class="f">Đang xem<select data-pb>' + (st.versions.length ? st.versions.map(v => '<option value="' + v.id + '"' + (b && v.id === b.id ? ' selected' : '') + '>' + tenPb(v) + ' — ' + esc(v.ngay_hieu_luc || '') + '</option>').join('') : '<option>Chưa có — lập mới</option>') + '</select></label>' +
          (q.soan ? '<button class="btn" type="button" data-nhap>Nhập từ Excel</button>' : '') + '<button class="btn" type="button" data-mau>Tải file mẫu</button>' +
          (b ? '<button class="btn" type="button" data-xuat>Xuất Excel</button>' : '') +
        '</div>' +
        (laNhap ? khoiDuyet(b, q) : '') +
        (canhBao ? '<div class="msg ' + (cu || nhap ? 'err' : 'ok') + '">' + canhBao + '</div>' : '') +
        '<div class="flds" style="margin-top:10px">' +
          '<label class="f">Phiên bản' + (laNhap ? '' : ' mới') + '<input data-f="phien_ban" value="' + esc(nhap ? nhap.phien_ban : phienBanMoi()) + '" style="width:70px"' + dis + '></label>' +
          '<label class="f">Ngày hiệu lực<input type="date" data-f="ngay_hieu_luc" value="' + esc(laNhap && b.ngay_hieu_luc ? b.ngay_hieu_luc : new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10)) + '"' + dis + '></label>' +
          '<label class="f">Số mẫu đo / lần<select data-f="so_mau"' + dis + '>' + [1, 2, 3, 4, 5].map(n => '<option value="' + n + '"' + (((b && b.so_mau) || 1) === n ? ' selected' : '') + '>' + n + (n === 1 ? ' (I-MR)' : ' (X̄-R)') + '</option>').join('') + '</select></label>' +
          '<label class="f">Tần suất<input data-f="tan_suat" value="' + esc((b && b.tan_suat) || '2h/lần') + '" style="width:90px"' + dis + '></label>' +
          '<label class="f">Mã biểu<input data-f="ma_bieu" value="' + esc((b && b.ma_bieu) || 'QP-82405-B') + '" style="width:110px"' + dis + '></label>' +
          '<label class="f" style="flex:1 1 200px">Nội dung sửa đổi<input data-f="noi_dung_sua_doi" value="' + esc(laNhap ? b.noi_dung_sua_doi || '' : cur ? '' : 'Lập mới') + '" placeholder="VD: Sửa dung sai hạng mục 2"' + dis + '></label>' +
          (q.soan ? '<button class="btn p" type="button" data-luu>' + (nhap ? 'Cập nhật bản nháp ' + esc(nhap.phien_ban) + ' & gửi lại' : 'Gửi duyệt phiên bản mới') + '</button>' : '') +
        '</div>' +
        '<div class="hint">' + (q.soan ? 'Gửi duyệt → Trưởng phòng QC kiểm tra → Giám đốc SX phê duyệt. IPQC dùng bản đang dùng đến khi bản mới được phê duyệt.'
          : q.uid ? 'Chỉ nhân viên QC / Trưởng phòng QC được soạn bảng tuần kiểm.' : 'Đăng nhập để soạn / duyệt.') + '</div><div data-msg></div></div>' +
        '<div style="display:flex;flex-wrap:wrap;gap:12px;align-items:stretch">' +
          '<div class="card" style="flex:1 1 280px;min-width:0"><div class="ttl"><span class="sp">Bản vẽ vị trí đo</span></div>' +
            '<div class="bv" data-bv>' + (st.banVe ? '<img src="' + esc(st.banVe) + '" alt="Bản vẽ">' + st.viTri.map(v => '<span class="b" style="left:' + v.x + '%;top:' + v.y + '%">' + esc(v.no) + '</span>').join('')
              : '<div>[Chưa có bản vẽ]' + (q.soan ? '<br><span style="font-size:11.5px">Tải ảnh PNG / JPG bản vẽ có các vị trí đo</span>' : '') + '</div>') + '</div>' +
            (q.soan ? '<div class="flds" style="margin-top:8px"><label class="btn sm" style="display:inline-flex">Tải ảnh bản vẽ<input type="file" accept="image/png,image/jpeg,image/webp" data-up hidden></label>' +
              (st.banVe ? '<label class="f">Đặt vị trí cho No<select data-nodat>' + st.rows.map(r => '<option' + (+r.muc_no === +st.noDat ? ' selected' : '') + '>' + esc(r.muc_no) + '</option>').join('') + '</select></label>' +
                '<button class="btn sm d" type="button" data-xoavt>Xoá vị trí</button>' : '') + '</div>' +
              '<div class="hint">' + (st.banVe ? 'Chọn No rồi bấm lên bản vẽ để đặt số. ' : '') + 'Bản vẽ + vị trí đo đi cùng khi gửi duyệt.</div>' : '') + '</div>' +
          '<div class="card" style="flex:3 1 520px;min-width:0"><div class="ttl"><span class="sp">Hạng mục kiểm tra</span>' + (q.soan ? '<button class="btn sm" type="button" data-them>+ Thêm hạng mục</button>' : '') + '</div>' +
            '<div class="tbl"><table style="min-width:860px"><tr><th>No</th><th>Hạng mục</th><th>Kiểu</th><th>Danh nghĩa</th><th>Dung sai +</th><th>Dung sai −</th><th>Tiêu chuẩn (OK/NG)</th><th>Dụng cụ KT</th><th>Tần suất</th><th>LSL – USL</th><th></th></tr>' +
            st.rows.map((r, i) => {
              const so = r.kieu === 'so';
              const sp = so ? S().specMuc(r) : null;
              const doi = ss ? ss.doi[i] : [];
              const td = c => '<td' + (doi && doi.includes(c) ? ' class="doi"' : '') + '>';
              const dso = so ? dis : ' disabled';
              return '<tr data-r="' + i + '"' + (ss && !doi ? ' class="moi"' : '') + '><td><input data-c="muc_no" value="' + esc(r.muc_no ?? '') + '" style="width:44px" inputmode="numeric"' + dis + '></td>' +
                td('hang_muc') + '<input data-c="hang_muc" value="' + esc(r.hang_muc || '') + '" style="width:150px"' + dis + '></td>' +
                td('kieu') + '<select data-c="kieu"' + dis + '><option value="so"' + (so ? ' selected' : '') + '>Đo số</option><option value="okng"' + (!so ? ' selected' : '') + '>OK / NG</option></select></td>' +
                td('danh_nghia') + '<input data-c="danh_nghia" value="' + esc(r.danh_nghia ?? '') + '" style="width:70px" inputmode="decimal"' + dso + '></td>' +
                td('dung_sai_tren') + '<input data-c="dung_sai_tren" value="' + esc(r.dung_sai_tren ?? '') + '" style="width:60px" inputmode="decimal"' + dso + '></td>' +
                td('dung_sai_duoi') + '<input data-c="dung_sai_duoi" value="' + esc(r.dung_sai_duoi ?? '') + '" style="width:60px" inputmode="decimal"' + dso + '></td>' +
                td('tieu_chuan') + '<input data-c="tieu_chuan" value="' + esc(r.tieu_chuan || '') + '" style="width:170px"' + (so ? ' placeholder="(tuỳ chọn)"' : '') + dis + '></td>' +
                td('dung_cu') + '<input data-c="dung_cu" value="' + esc(r.dung_cu || '') + '" style="width:110px"' + dis + '></td>' +
                td('tan_suat') + '<input data-c="tan_suat" value="' + esc(r.tan_suat || '') + '" style="width:70px"' + dis + '></td>' +
                '<td class="mono" style="white-space:nowrap;color:#475569">' + (so && (sp.usl !== null || sp.lsl !== null) ? (sp.lsl !== null ? S().fmt(sp.lsl, S().soLe(r)) : '—') + ' – ' + (sp.usl !== null ? S().fmt(sp.usl, S().soLe(r)) : '—') : '—') + '</td>' +
                '<td>' + (q.soan ? '<button class="btn sm d" type="button" data-xoa="' + i + '" aria-label="Xoá hạng mục">✕</button>' : '') + '</td></tr>';
            }).join('') + '</table></div>' +
            (ss ? '<div class="hint"><b>So với bản đang dùng ' + esc(ss.cur.phien_ban) + ':</b> ô vàng = đã sửa, vạch xanh đầu dòng = hạng mục mới' +
              (ss.bo.length ? '; bỏ: ' + ss.bo.map(g => 'No ' + esc(g.muc_no) + ' ' + esc(g.hang_muc)).join(', ') : '') +
              (b.so_mau !== ss.cur.so_mau ? '; số mẫu/lần ' + ss.cur.so_mau + ' → ' + b.so_mau : '') +
              (b.ban_ve_url !== ss.cur.ban_ve_url ? '; bản vẽ mới' : JSON.stringify(b.ban_ve_vi_tri || []) !== JSON.stringify(ss.cur.ban_ve_vi_tri || []) ? '; đổi vị trí đo trên bản vẽ' : '') + '.</div>' : '') +
            '<div class="hint">Dung sai −: ghi độ lớn (VD 0.2 nghĩa là −0.2). Ghi 0 nếu dung sai bằng 0; để trống = không giới hạn phía đó. Hạng mục OK/NG chỉ theo dõi tỉ lệ NG.</div></div>' +
        '</div>' +
        '<div class="card"><div class="ttl"><span class="sp">Lịch sử sửa đổi</span></div><div class="tbl"><table style="min-width:720px"><tr><th>Phiên bản</th><th>Trạng thái</th><th>Ngày hiệu lực</th><th>Nội dung sửa đổi</th><th>Người soạn</th><th>TP QC kiểm tra</th><th>GĐ SX phê duyệt</th></tr>' +
          (st.versions.map(v => {
            const tag = v.dang_dung ? '<span class="tag ok">đang dùng</span>' : v.trang_thai !== 'da_duyet' ? '<span class="tag ' + (v.trang_thai === 'tra_lai' ? 'ng' : 'w') + '">' + esc(TT[v.trang_thai]) + '</span>' : '<span class="hint">đã thay thế</span>';
            const ai = (ten, luc) => ten ? esc(ten) + '<div class="hint" style="margin:0">' + esc(ngayVN(luc)) + '</div>' : '';
            return '<tr><td><b>' + esc(v.phien_ban) + '</b></td><td>' + tag + '</td><td>' + esc(v.ngay_hieu_luc || '') + '</td><td>' + esc(v.noi_dung_sua_doi || '') + '</td>' +
              '<td>' + ai(v.nguoi_lap, v.gui_luc || v.tao_luc) + '</td><td>' + ai(v.nguoi_kiem_tra, v.kiem_tra_luc) + '</td>' +
              '<td>' + (v.nguoi_phe_duyet ? ai(v.nguoi_phe_duyet, v.phe_duyet_luc) : esc(v.nguoi_xac_nhan || '')) + '</td></tr>';
          }).join('') || '<tr><td colspan="7" class="hint">Chưa có phiên bản nào.</td></tr>') +
        '</table></div></div>';
    }

    function docBang() {
      main.querySelectorAll('tr[data-r]').forEach(tr => {
        const r = st.rows[+tr.dataset.r];
        tr.querySelectorAll('[data-c]').forEach(i => { r[i.dataset.c] = i.value; });
      });
    }
    function payload() {
      docBang();
      const f = k => (main.querySelector('[data-f="' + k + '"]') || {}).value || '';
      return {
        phien_ban: f('phien_ban').trim(), ngay_hieu_luc: f('ngay_hieu_luc'), so_mau: +f('so_mau') || 1, tan_suat: f('tan_suat'),
        ma_bieu: f('ma_bieu'), noi_dung_sua_doi: f('noi_dung_sua_doi'),
        ban_ve_url: st.banVe || '', ban_ve_vi_tri: st.viTri,
        muc: st.rows.map(r => ({ muc_no: String(r.muc_no ?? '').trim(), hang_muc: r.hang_muc, kieu: r.kieu,
          danh_nghia: soVN(r.danh_nghia), dung_sai_tren: soVN(r.dung_sai_tren), dung_sai_duoi: soVN(r.dung_sai_duoi),
          tieu_chuan: r.tieu_chuan, dung_cu: r.dung_cu, tan_suat: r.tan_suat })),
      };
    }

    async function upBanVe(file) {
      const m = main.querySelector('[data-msg]');
      try {
        const ext = (file.name.split('.').pop() || 'png').toLowerCase();
        const path = st.ma.replace(/[^a-zA-Z0-9_-]/g, '_') + '/ban_ve_' + Date.now() + '.' + ext;
        const { error } = await sb.storage.from('ipqc-ban-ve').upload(path, file, { contentType: file.type, upsert: false });
        if (error) throw new Error(error.message);
        st.banVe = sb.storage.from('ipqc-ban-ve').getPublicUrl(path).data.publicUrl;
        st.viTri = [];
        docBang(); ve(); msg(main.querySelector('[data-msg]'), 'Đã tải bản vẽ — chọn No rồi bấm lên bản vẽ để đặt vị trí đo, xong bấm gửi duyệt.');
      } catch (e) { msg(m, 'Không tải được bản vẽ: ' + e.message, 'err'); }
    }
    // Sau khi duyệt / huỷ / gửi: nạp lại mã đang mở rồi hiện thông báo.
    async function xong(text, idXem) {
      await taiDanhSach(); await chonMa(st.ma, idXem);
      msg(main.querySelector('[data-msg]'), text);
      baoDoi();
    }

    el.addEventListener('input', e => { if (e.target.matches('[data-tim]')) veDanhSach(); });
    el.addEventListener('change', async e => {
      const t = e.target;
      if (t.matches('[data-pb]')) { docBang(); napPhienBan(st.versions.find(v => String(v.id) === t.value) || null); }
      else if (t.matches('[data-c="kieu"]')) { docBang(); ve(); }
      else if (t.matches('[data-c="danh_nghia"],[data-c="dung_sai_tren"],[data-c="dung_sai_duoi"]')) { docBang(); ve(); }
      else if (t.matches('[data-nodat]')) st.noDat = t.value;
      else if (t.matches('[data-up]') && t.files[0]) upBanVe(t.files[0]);
    });
    el.addEventListener('click', async e => {
      const t = e.target;
      const li = t.closest('[data-ma]');
      if (li) return chonMa(li.dataset.ma);
      if (t.closest('[data-mau]')) return taiFileMau();
      if (t.closest('[data-nhap]')) return nhapExcel(() => { taiDanhSach(); if (st.ma) chonMa(st.ma); baoDoi(); });
      if (t.closest('[data-xuat]')) return xuatExcel(st.ma, st.xem, st.rows);
      const dy = t.closest('[data-duyet]'), hy = t.closest('[data-huy]');
      if (dy || hy) {
        const id = st.xem.id;
        (dy || hy).disabled = true;
        try {
          const kq = dy ? await duyet('btk', id, dy.dataset.duyet) : await huy('btk', id);
          if (kq) return xong(kq, hy ? null : id);
        } catch (er) { msg(main.querySelector('[data-msg]'), er.message, 'err'); }
        (dy || hy).disabled = false;
        return;
      }
      if (!q.soan) return;
      if (t.closest('[data-them]')) { docBang(); const mx = Math.max(0, ...st.rows.map(r => +r.muc_no || 0)); st.rows.push({ muc_no: mx + 1, kieu: 'so', tan_suat: '2h/lần' }); return ve(); }
      const x = t.closest('[data-xoa]');
      if (x) { docBang(); st.rows.splice(+x.dataset.xoa, 1); return ve(); }
      if (t.closest('[data-xoavt]')) { st.viTri = st.viTri.filter(v => String(v.no) !== String(st.noDat)); docBang(); return ve(); }
      const img = t.closest('[data-bv] img');
      if (img) {
        const r = img.getBoundingClientRect();
        const x2 = +((e.clientX - r.left) / r.width * 100).toFixed(1), y2 = +((e.clientY - r.top) / r.height * 100).toFixed(1);
        st.viTri = st.viTri.filter(v => String(v.no) !== String(st.noDat)).concat([{ no: +st.noDat, x: x2, y: y2 }]);
        const nos = st.rows.map(r2 => +r2.muc_no).filter(Boolean).sort((a, b) => a - b);
        const k = nos.indexOf(+st.noDat); if (k >= 0 && k < nos.length - 1) st.noDat = nos[k + 1];
        docBang(); return ve();
      }
      if (t.closest('[data-luu]')) {
        const m = main.querySelector('[data-msg]');
        const pl = payload();
        if (!pl.noi_dung_sua_doi.trim()) return msg(m, 'Nhập nội dung sửa đổi.', 'err');
        const btn = t.closest('[data-luu]'); btn.disabled = true;
        try {
          const { data, error } = await sb.rpc('ipqc_btk_luu', { p_ma_sp: st.ma, p_data: pl, p_nguoi: await nguoi() });
          if (error) throw new Error(error.message);
          if (!data || !data.ok) throw new Error((data && data.error) || 'Không lưu được');
          await xong('Đã gửi duyệt phiên bản ' + data.phien_ban + ' — chờ Trưởng phòng QC kiểm tra. IPQC vẫn dùng bản đang dùng đến khi Giám đốc SX phê duyệt.', data.id);
        } catch (er) { msg(m, er.message, 'err'); btn.disabled = false; }
      }
    });
    el.addEventListener('keydown', e => { const li = e.target.closest('[data-ma]'); if (li && e.key === 'Enter') chonMa(li.dataset.ma); });
    await taiDanhSach();
    return { mo: ma => chonMa(ma) };
  }

  // ── Excel: file mẫu / xuất / nhập ──────────────────────────────────────
  function taiFileMau() {
    if (typeof XLSX === 'undefined') return alert('Chưa tải được thư viện Excel — tải lại trang.');
    const rows = [COT,
      ['FCC-OUT-01', 'A', '2025-06-06', 1, 1, 'Chiều sâu', 'Đo số', 14.8, 0, 0.2, '', 'Thước đo sâu', '2h/lần', 'Lập mới', 'Mr Dũng'],
      ['FCC-OUT-01', 'A', '2025-06-06', 1, 2, 'Kích thước', 'Đo số', 8.1, 0.1, 0, '', 'Thước kẹp', '2h/lần', '', ''],
      ['FCC-OUT-01', 'A', '2025-06-06', 1, 4, 'Kích thước', 'Đo số', 14, 0.25, 0.25, '', 'Thước kẹp', '2h/lần', '', ''],
      ['FCC-OUT-01', 'A', '2025-06-06', 1, 5, 'Đường kính', 'Đo số', 4.2, 0.1, 0.1, '', 'Thước kẹp', '2h/lần', '', ''],
      ['FCC-OUT-01', 'A', '2025-06-06', 1, 6, 'Lắp ghép linh kiện', 'OK-NG', '', '', '', 'Không có độ dơ', 'Linh kiện (351819)', '2h/lần', '', '']];
    const hd = [['HƯỚNG DẪN NHẬP BẢNG TUẦN KIỂM'], [''],
      ['• Mỗi dòng = 1 hạng mục của 1 mã. Các dòng cùng Mã SP gộp thành 1 phiên bản bảng tuần kiểm.'],
      ['• Mã SP phải có trong Danh mục SP. Phiên bản để trống = tự tăng (A, B, ...). Phiên bản đã có sẽ bị từ chối.'],
      ['• Kiểu: "Đo số" (có Danh nghĩa + dung sai, vẽ biểu đồ kiểm soát) hoặc "OK-NG" (ghi Tiêu chuẩn, chỉ theo dõi tỉ lệ NG).'],
      ['• Dung sai −: ghi độ lớn dương (0.2 = −0.2). Ghi 0 nếu dung sai bằng 0; để trống = không giới hạn phía đó.'],
      ['• Danh nghĩa có thể ghi Ø4.2 — ký hiệu Ø sẽ được bỏ. Dùng dấu chấm hoặc phẩy thập phân đều được.'],
      ['• Số mẫu/lần: 1–5 (1 = biểu đồ I-MR; 2–5 = X̄-R). Ngày hiệu lực dạng yyyy-mm-dd.'],
      ['• Bản vẽ vị trí đo: tải ảnh trên màn hình QC Manager → Quản lý tiêu chuẩn sau khi nhập.']];
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.aoa_to_sheet(rows); ws['!cols'] = COT.map((c, i) => ({ wch: [14, 9, 12, 9, 5, 22, 14, 10, 9, 9, 22, 18, 9, 22, 14][i] }));
    XLSX.utils.book_append_sheet(wb, ws, 'Bang tuan kiem');
    const ws2 = XLSX.utils.aoa_to_sheet(hd); ws2['!cols'] = [{ wch: 110 }];
    XLSX.utils.book_append_sheet(wb, ws2, 'Huong dan');
    XLSX.writeFile(wb, 'Mau_nhap_bang_tuan_kiem.xlsx');
  }
  function xuatExcel(ma, b, rows) {
    if (typeof XLSX === 'undefined') return alert('Chưa tải được thư viện Excel — tải lại trang.');
    const aoa = [COT].concat(rows.map(r => [ma, b ? b.phien_ban : '', b ? b.ngay_hieu_luc : '', b ? b.so_mau : 1, r.muc_no, r.hang_muc,
      r.kieu === 'so' ? 'Đo số' : 'OK-NG', r.danh_nghia ?? '', r.dung_sai_tren ?? '', r.dung_sai_duoi ?? '', r.tieu_chuan || '', r.dung_cu || '', r.tan_suat || '',
      b ? b.noi_dung_sua_doi || '' : '', b ? b.nguoi_phe_duyet || b.nguoi_xac_nhan || '' : '']));
    const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), 'Bang tuan kiem');
    XLSX.writeFile(wb, 'Bang_tuan_kiem_' + ma.replace(/[^\w-]/g, '_') + (b ? '_' + b.phien_ban : '') + '.xlsx');
  }
  function nhapExcel(xong) {
    if (typeof XLSX === 'undefined') return alert('Chưa tải được thư viện Excel — tải lại trang.');
    const inp = document.createElement('input'); inp.type = 'file'; inp.accept = '.xlsx,.xls';
    inp.onchange = async () => {
      const f = inp.files[0]; if (!f) return;
      const wb = XLSX.read(await f.arrayBuffer(), { type: 'array', cellDates: true });
      const ws = wb.Sheets[wb.SheetNames.find(n => /tuan/i.test(n)) || wb.SheetNames[0]];
      const aoa = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' });
      const hi = aoa.findIndex(r => r.some(c => /mã\s*sp/i.test(String(c))));
      if (hi < 0) return alert('Không tìm thấy dòng tiêu đề có cột "Mã SP".');
      const norm = s => String(s).toLowerCase().normalize('NFC').replace(/\s+/g, ' ').trim();
      const H = aoa[hi].map(norm);
      const col = (...keys) => H.findIndex(h => keys.some(k => h.startsWith(k)));
      const C = { ma: col('mã sp'), pb: col('phiên bản'), nhl: col('ngày hiệu lực'), sm: col('số mẫu'), no: H.findIndex(h => h === 'no' || h === 'stt'),
        hm: col('hạng mục'), kieu: col('kiểu'), dn: col('danh nghĩa'), tren: col('dung sai +'), duoi: H.findIndex(h => /^dung sai\s*[−-]/.test(h)),
        tc: col('tiêu chuẩn'), dc: col('dụng cụ'), ts: col('tần suất'), nd: col('nội dung') };
      const { data: prods } = await sb.from('master_products').select('ma_sp');
      const coMa = new Set((prods || []).map(p => p.ma_sp));
      const nhom = {};
      aoa.slice(hi + 1).forEach((r, k) => {
        const v = i => i >= 0 ? r[i] : '';
        const ma = String(v(C.ma)).trim(); if (!ma) return;
        const g = nhom[ma] = nhom[ma] || { ma, loi: [], data: { muc: [] } };
        const d = g.data;
        if (!d.phien_ban && v(C.pb) !== '') d.phien_ban = String(v(C.pb)).trim();
        if (!d.ngay_hieu_luc && v(C.nhl) !== '') { const x = v(C.nhl); d.ngay_hieu_luc = x instanceof Date ? new Date(x.getTime() - x.getTimezoneOffset() * 60000).toISOString().slice(0, 10) : String(x).trim().replace(/^(\d{2})[./](\d{2})[./](\d{4})$/, '$3-$2-$1'); }
        if (!d.so_mau && v(C.sm) !== '') d.so_mau = +v(C.sm);
        if (!d.noi_dung_sua_doi && v(C.nd) !== '') d.noi_dung_sua_doi = String(v(C.nd));
        const kieuTxt = norm(v(C.kieu));
        const dn = soVN(v(C.dn));
        const kieu = /ok/.test(kieuTxt) ? 'okng' : /số|so|đo/.test(kieuTxt) ? 'so' : (dn !== '' && isFinite(+dn) ? 'so' : 'okng');
        const m = { muc_no: String(v(C.no)).trim(), hang_muc: String(v(C.hm)).trim(), kieu, danh_nghia: kieu === 'so' ? dn : '',
          dung_sai_tren: soVN(v(C.tren)), dung_sai_duoi: soVN(v(C.duoi)).replace(/^-/, ''), tieu_chuan: String(v(C.tc)).trim(),
          dung_cu: String(v(C.dc)).trim(), tan_suat: String(v(C.ts)).trim() };
        const dong = 'Dòng ' + (hi + k + 2);
        if (!m.muc_no || !/^\d+$/.test(m.muc_no)) g.loi.push(dong + ': No phải là số');
        if (!m.hang_muc) g.loi.push(dong + ': thiếu Hạng mục');
        if (kieu === 'so' && (dn === '' || !isFinite(+dn))) g.loi.push(dong + ': Danh nghĩa không phải số');
        if (kieu === 'so' && m.dung_sai_tren === '' && m.dung_sai_duoi === '') g.loi.push(dong + ': thiếu dung sai');
        if (kieu === 'so' && [m.dung_sai_tren, m.dung_sai_duoi].some(x => x !== '' && !isFinite(+x))) g.loi.push(dong + ': dung sai không phải số');
        if (kieu === 'okng' && !m.tieu_chuan) g.loi.push(dong + ': hạng mục OK-NG cần cột Tiêu chuẩn');
        d.muc.push(m);
      });
      const ds = Object.values(nhom);
      ds.forEach(g => {
        if (!coMa.has(g.ma)) g.loi.unshift('Mã SP không có trong Danh mục SP');
        const nos = g.data.muc.map(m => m.muc_no); if (new Set(nos).size !== nos.length) g.loi.push('Trùng No');
      });
      xemTruoc(ds, xong);
    };
    inp.click();
  }
  function xemTruoc(ds, xong) {
    const ok = ds.filter(g => !g.loi.length);
    const mask = document.createElement('div'); mask.className = 'bq-mask';
    mask.innerHTML = '<div class="bq-dlg bq"><div style="display:block;width:100%"><div style="font-weight:800;font-size:16px;margin-bottom:8px">Nhập bảng tuần kiểm — ' + ds.length + ' mã</div>' +
      '<table><tr><th>Mã SP</th><th>Phiên bản</th><th>Hạng mục</th><th>Kiểm tra</th></tr>' +
      ds.map(g => '<tr><td class="mono"><b>' + esc(g.ma) + '</b></td><td>' + esc(g.data.phien_ban || '(tự tăng)') + '</td><td>' + g.data.muc.length + ' (' + g.data.muc.filter(m => m.kieu === 'so').length + ' đo số)</td>' +
        '<td>' + (g.loi.length ? '<span class="tag ng">Lỗi</span> ' + g.loi.map(esc).join('<br>') : '<span class="tag ok">Hợp lệ</span>') + '</td></tr>').join('') + '</table>' +
      '<div data-kq></div><div style="display:flex;gap:8px;justify-content:flex-end;margin-top:12px"><button class="btn" type="button" data-dong>Đóng</button>' +
      '<button class="btn p" type="button" data-ghi' + (ok.length ? '' : ' disabled') + '>Gửi duyệt ' + ok.length + ' mã hợp lệ</button></div></div></div>';
    document.body.appendChild(mask);
    mask.querySelector('[data-dong]').onclick = () => mask.remove();
    mask.querySelector('[data-ghi]').onclick = async ev => {
      ev.target.disabled = true;
      const ten = await nguoi(), kq = [];
      for (const g of ok) {
        const { data, error } = await sb.rpc('ipqc_btk_luu', { p_ma_sp: g.ma, p_data: g.data, p_nguoi: ten });
        kq.push(g.ma + ': ' + (error ? error.message : data && data.ok ? 'đã gửi duyệt phiên bản ' + data.phien_ban : (data && data.error) || 'lỗi'));
      }
      mask.querySelector('[data-kq]').innerHTML = '<div class="msg ok">' + kq.map(esc).join('<br>') + '</div>';
      if (xong) xong();
    };
  }

  // ═══════════════════════════ BIỂU ĐỒ KIỂM SOÁT ═══════════════════════════
  async function mountChart(el) {
    css();
    const st = { dsMa: [], cache: {}, ma: null, no: null, may: '', khuon: '', ngay: 30 };
    el.innerHTML = '<div class="bq" style="flex-direction:column;align-items:stretch">' +
      '<div class="card flds" data-loc></div>' +
      '<div style="display:flex;flex-wrap:wrap;gap:12px;align-items:flex-start">' +
        '<div style="flex:999 1 620px;min-width:0;display:flex;flex-direction:column;gap:12px" data-trai></div>' +
        '<div style="flex:1 1 290px;max-width:370px;min-width:0;display:flex;flex-direction:column;gap:12px" data-phai>' +
          '<div class="card"><div class="ttl"><span class="sp">Cảnh báo bất thường · 7 ngày</span></div><div data-canh><div class="hint">Đang tải…</div></div></div>' +
          '<div class="card" data-nl></div><div class="card" data-gh></div>' +
          '<div class="card"><div class="ttl"><span class="sp">Quy tắc phát hiện sớm</span></div><ol style="margin:0;padding-left:18px;display:flex;flex-direction:column;gap:4px;font-size:12.5px">' +
            '<li>1 điểm vượt UCL / LCL (±3σ)</li><li>9 điểm liên tiếp cùng một phía đường trung tâm</li><li>6 điểm liên tiếp tăng dần hoặc giảm dần</li>' +
            '<li>2 trong 3 điểm liên tiếp vượt ±2σ cùng phía</li><li>Cpk &lt; 1.33</li></ol>' +
            '<div class="hint">UCL/LCL tự khoá sau 30 lần đo đầu. Trước đó dùng giới hạn tạm tính từ dữ liệu đang có.</div></div>' +
        '</div></div></div>';
    const locEl = el.querySelector('[data-loc]'), trai = el.querySelector('[data-trai]');

    async function layDuLieu(ma, ngay) {
      const k = ma + '|' + ngay;
      if (st.cache[k]) return st.cache[k];
      const tu = ngay ? new Date(Date.now() - ngay * 86400e3).toISOString() : null;
      const { data, error } = await sb.rpc('ipqc_do_du_lieu', { p_ma_sp: ma, p_tu: tu, p_den: null, p_so_lan: null });
      if (error) throw new Error(error.message);
      st.cache[k] = data; return data;
    }

    async function khoiDong() {
      const { data, error } = await sb.from('ipqc_btk').select('ma_sp,phien_ban').eq('dang_dung', true).order('ma_sp');
      if (error) { trai.innerHTML = '<div class="card msg err">' + esc(error.message) + ' — cần đăng nhập.</div>'; return; }
      st.dsMa = data || [];
      if (!st.dsMa.length) { trai.innerHTML = '<div class="card hint">Chưa có mã nào có bảng tuần kiểm — lập ở tab Quản lý tiêu chuẩn.</div>'; el.querySelector('[data-canh]').innerHTML = '<div class="hint">—</div>'; return; }
      st.ma = st.dsMa[0].ma_sp;
      await ve();
      taiCanhBao();
    }

    function diemVaViPham(data, m, loc) {
      const soMau = (data.btk && data.btk.so_mau) || 1;
      const pts = S().chuoi(data, m.muc_no, loc);
      const lim = S().gioiHan(data, m.muc_no, soMau, S().chuoi(data, m.muc_no));
      const sp = S().specMuc(m);
      const vp = S().quyTac(pts.map(p => p.x), lim);
      return { pts, lim, sp, vp, soMau };
    }

    async function ve() {
      let data;
      try { data = await layDuLieu(st.ma, st.ngay); } catch (e) { trai.innerHTML = '<div class="card msg err">' + esc(e.message) + '</div>'; return; }
      const mucSo = (data.muc || []).filter(m => m.kieu === 'so');
      if (!st.no || !mucSo.some(m => m.muc_no === st.no)) st.no = mucSo.length ? mucSo[0].muc_no : null;
      const mays = [...new Set((data.lan || []).map(l => l.ma_may).filter(Boolean))].sort();
      const khuons = [...new Set((data.lan || []).map(l => l.so_khuon).filter(Boolean))].sort();
      locEl.innerHTML =
        '<label class="f">Mã SP<select data-l="ma">' + st.dsMa.map(x => '<option' + (x.ma_sp === st.ma ? ' selected' : '') + '>' + esc(x.ma_sp) + '</option>').join('') + '</select></label>' +
        '<label class="f">Hạng mục<select data-l="no">' + mucSo.map(m => '<option value="' + m.muc_no + '"' + (m.muc_no === st.no ? ' selected' : '') + '>' + m.muc_no + '. ' + esc(m.hang_muc) + ' ' + esc(S().chuanText(m)) + '</option>').join('') + '</select></label>' +
        '<label class="f">Máy<select data-l="may"><option value="">Tất cả</option>' + mays.map(x => '<option' + (x === st.may ? ' selected' : '') + '>' + esc(x) + '</option>').join('') + '</select></label>' +
        '<label class="f">Khuôn<select data-l="khuon"><option value="">Tất cả</option>' + khuons.map(x => '<option' + (x === st.khuon ? ' selected' : '') + '>' + esc(x) + '</option>').join('') + '</select></label>' +
        '<label class="f">Khoảng thời gian<select data-l="ngay">' + [[7, '7 ngày'], [30, '30 ngày'], [90, '90 ngày'], [0, 'Tất cả']].map(([v, t]) => '<option value="' + v + '"' + (v === st.ngay ? ' selected' : '') + '>' + t + '</option>').join('') + '</select></label>' +
        '<div style="margin-left:auto;font-size:12px;color:#64748B">Bảng tuần kiểm ' + esc(data.btk ? data.btk.phien_ban : '') + ' · ' + ((data.btk && data.btk.so_mau) || 1) + ' mẫu/lần · ' + (data.lan || []).length + ' lần đo</div>';
      const loc = l => (!st.may || l.ma_may === st.may) && (!st.khuon || l.so_khuon === st.khuon);
      const m = mucSo.find(x => x.muc_no === st.no);
      if (!m) { trai.innerHTML = '<div class="card hint">Bảng tuần kiểm của mã này chưa có hạng mục đo số.</div>'; veTongQuan(data, loc); return; }
      const d = S().soLe(m);
      const { pts, lim, sp, vp, soMau } = diemVaViPham(data, m, loc);
      const vpIdx = new Set(vp.map(v => v.i));
      const mau = (p, i) => S().datGiaTri(p.x, sp) === false || p.vals.some(v => S().datGiaTri(v, sp) === false) ? '#DC2626' : vpIdx.has(i) ? '#D97706' : '#0F5FA5';
      const nhan = p => ngayVN(p.t) + ' · ' + (p.may || '') + (p.khuon ? ' · ' + p.khuon : '') + ' · ' + (p.nguoi || '') + ' · ' + p.vals.map(v => S().fmt(v, d)).join(' / ');
      const vung = vp.filter(v => v.quy_tac === 3).map(v => ({ tu: v.i - 5, den: v.i }));
      const ptsX = pts.map((p, i) => ({ x: p.x, mau: mau(p, i), nhan: nhan(p), tg: ngayVN(p.t) }));
      const rVals = soMau <= 1 ? pts.slice(1).map((p, i) => ({ x: Math.abs(p.x - pts[i].x), tg: ngayVN(p.t) })) : pts.map(p => ({ x: p.r, tg: ngayVN(p.t) }));
      trai.innerHTML =
        '<div class="card"><div class="ttl"><span class="sp" style="text-transform:none;font-size:14px;color:#0F172A;letter-spacing:0">' + (soMau <= 1 ? 'Biểu đồ giá trị đơn (I)' : 'Biểu đồ trung bình (X̄), ' + soMau + ' mẫu/lần') + ' — ' + m.muc_no + '. ' + esc(m.hang_muc) + ' ' + esc(S().chuanText(m)) + '</span>' +
          (lim ? (lim.tam ? '<span class="tag w">Giới hạn tạm (' + lim.n + ' lần)</span>' : '<span class="tag ok">Giới hạn đã khoá</span>') : '<span class="tag no">Chưa đủ dữ liệu tính giới hạn</span>') + '</div>' +
          (pts.length ? S().bieuDo({ pts: ptsX, lim, usl: sp.usl, lsl: sp.lsl, d, h: 290, vung, aria: 'Biểu đồ kiểm soát ' + m.hang_muc }) : '<div class="hint">Chưa có lần đo nào trong khoảng đã chọn.</div>') +
          '<div class="lg"><span style="color:#B91C1C">- - USL / LSL (tiêu chuẩn)</span><span style="color:#B45309">··· UCL / LCL (±3σ)</span><span><span style="color:#DC2626">●</span> ngoài tiêu chuẩn</span><span><span style="color:#D97706">●</span> vi phạm quy tắc</span><span>Rê chuột lên điểm để xem chi tiết</span></div></div>' +
        '<div class="card"><div class="ttl"><span class="sp" style="text-transform:none;font-size:14px;color:#0F172A;letter-spacing:0">' + (soMau <= 1 ? 'Biểu đồ khoảng biến thiên (MR)' : 'Biểu đồ độ rộng (R)') + '</span></div>' +
          (rVals.length ? S().bieuDo({ pts: rVals, lim: lim ? { cl: lim.clR, ucl: lim.uclR, lcl: null } : null, d, h: 150, nhanGH: ['UCL', soMau <= 1 ? 'MR̄' : 'R̄', ''], aria: 'Biểu đồ biến thiên' }) : '<div class="hint">—</div>') + '</div>' +
        '<div class="card" data-tq></div>';
      veTongQuan(data, loc);
      // Năng lực
      const tatCa = []; pts.forEach(p => tatCa.push(...p.vals));
      const nl = S().nangLuc(tatCa, sp);
      el.querySelector('[data-nl]').innerHTML = '<div class="ttl"><span class="sp">Năng lực quá trình — hạng mục ' + m.muc_no + '</span></div><div class="kpi">' +
        '<div><div class="k">Số giá trị đo</div><div class="v">' + nl.n + '</div></div><div><div class="k">Trung bình</div><div class="v">' + S().fmt(nl.tb, d) + '</div></div>' +
        '<div><div class="k">Cp</div><div class="v">' + (nl.cp === null ? '—' : nl.cp.toFixed(2)) + '</div></div>' +
        '<div style="background:' + (nl.cpk !== null && nl.cpk < 1.33 ? '#FEF2F2' : '#F8FAFC') + '"><div class="k">Cpk (mục tiêu ≥ 1.33)</div><div class="v" style="color:' + (nl.cpk !== null && nl.cpk < 1.33 ? '#B91C1C' : '#166534') + '">' + (nl.cpk === null ? '—' : nl.cpk.toFixed(2)) + '</div></div></div>' +
        '<div class="hint">Tính trên ' + nl.n + ' giá trị đo trong khoảng + bộ lọc đang chọn.</div>';
      veGioiHan(m, lim, d);
    }

    function veTongQuan(data, loc) {
      const tq = el.querySelector('[data-tq]'); if (!tq) return;
      const lan = (data.lan || []).filter(loc);
      const rows = (data.muc || []).map(m => {
        if (m.kieu !== 'so') {
          const kq = []; lan.forEach(l => (l.kq || []).filter(k => k.muc_no === m.muc_no).forEach(k => kq.push(k)));
          const ng = kq.filter(k => !k.dat).length;
          return '<tr><td><span class="no">' + m.muc_no + '</span></td><td>' + esc(m.hang_muc) + '</td><td class="mono">' + kq.length + '</td><td>—</td><td>—</td><td class="mono">NG ' + (kq.length ? (ng / kq.length * 100).toFixed(1) : '0') + '%</td><td>' + (ng ? '<span class="tag ng">Có NG</span>' : '<span class="tag ok">Ổn định</span>') + '</td></tr>';
        }
        const r = diemVaViPham(data, m, loc), d = S().soLe(m);
        const vals = []; r.pts.forEach(p => vals.push(...p.vals));
        const nl = S().nangLuc(vals, r.sp);
        const ngoai = vals.filter(v => S().datGiaTri(v, r.sp) === false).length;
        const gan = r.vp.some(v => v.i >= r.pts.length - 10);
        const tag = ngoai ? '<span class="tag ng">Có điểm NG</span>' : gan ? '<span class="tag w">Bất thường</span>' : nl.cpk !== null && nl.cpk < 1.33 ? '<span class="tag w">Cpk thấp</span>' : '<span class="tag ok">Ổn định</span>';
        return '<tr class="clk' + (m.muc_no === st.no ? ' sel' : '') + '" data-chonno="' + m.muc_no + '"><td><span class="no">' + m.muc_no + '</span></td><td>' + esc(m.hang_muc) + ' <span class="mono" style="color:#475569">' + esc(S().chuanText(m)) + '</span></td>' +
          '<td class="mono">' + r.pts.length + '</td><td class="mono">' + S().fmt(nl.tb, d) + '</td><td class="mono" style="font-weight:700;color:' + (nl.cpk !== null && nl.cpk < 1.33 ? '#B91C1C' : '#166534') + '">' + (nl.cpk === null ? '—' : nl.cpk.toFixed(2)) + '</td><td class="mono">' + ngoai + '</td><td>' + tag + '</td></tr>';
      }).join('');
      tq.innerHTML = '<div class="ttl"><span class="sp">Tổng quan các hạng mục — ' + esc(st.ma) + '</span></div><div class="tbl"><table style="min-width:600px"><tr><th>No</th><th>Hạng mục</th><th>Số lần</th><th>X̄</th><th>Cpk</th><th>Ngoài TC</th><th>Trạng thái</th></tr>' + rows + '</table></div>';
    }

    async function veGioiHan(m, lim, d) {
      const box = el.querySelector('[data-gh]');
      const { data: ls } = await sb.from('ipqc_gioi_han').select('*').eq('ma_sp', st.ma).eq('muc_no', m.muc_no).order('tao_luc', { ascending: false }).limit(10);
      const CACH = { tu_dong: 'Tự khoá 30 lần đầu', tinh_lai: 'Tính lại', tay: 'Nhập tay' };
      const homNay = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
      box.innerHTML = '<div class="ttl"><span class="sp">Giới hạn kiểm soát — hạng mục ' + m.muc_no + '</span></div>' +
        (lim ? '<div class="mono" style="font-size:12.5px">UCL ' + S().fmt(lim.ucl, d) + ' · CL ' + S().fmt(lim.cl, d) + ' · LCL ' + S().fmt(lim.lcl, d) + '</div><div class="hint">' + (lim.tam ? 'Tạm tính từ ' + lim.n + ' lần đo (tự khoá khi đủ 30 lần).' : CACH[lim.cach] + ' · ' + esc(lim.raw.ghi_chu || '') + ' · ' + esc(ngayVN(lim.raw.tao_luc))) + '</div>' : '<div class="hint">Chưa đủ dữ liệu.</div>') +
        '<details style="margin-top:8px"><summary style="cursor:pointer;font-weight:700;color:#0F5FA5">Đặt lại giới hạn (cải tiến / điều chỉnh)</summary>' +
          '<div class="flds" style="margin-top:8px"><label class="f">Cách<select data-gc><option value="tinh_lai">Tính lại từ khoảng thời gian</option><option value="tay">Nhập tay</option></select></label></div>' +
          '<div class="flds" data-gtl style="margin-top:6px"><label class="f">Từ ngày<input type="date" data-gtu value="' + homNay + '"></label><label class="f">Đến ngày<input type="date" data-gden></label></div>' +
          '<div class="flds" data-gtay style="margin-top:6px;display:none"><label class="f">CL<input data-gcl style="width:80px"></label><label class="f">UCL<input data-gucl style="width:80px"></label><label class="f">LCL<input data-glcl style="width:80px"></label><label class="f">' + (((st.cache[st.ma + '|' + st.ngay] || {}).btk || {}).so_mau > 1 ? 'R̄' : 'MR̄') + '<input data-gr style="width:80px"></label></div>' +
          '<label class="f" style="margin-top:6px">Lý do (bắt buộc)<input data-gly placeholder="VD: Sửa khuôn ngày 20/10, đo lại 30 lần"></label>' +
          '<div style="margin-top:8px"><button class="btn p sm" type="button" data-gluu>Lưu giới hạn mới</button></div>' +
          '<div class="hint">Tính lại: dùng tối đa 30 lần đo đầu tiên từ "Từ ngày" (cần ≥ 10 lần). Chỉ QC Manager / admin.</div><div data-gmsg></div></details>' +
        (ls && ls.length ? '<div style="margin-top:8px;font-size:12px"><b>Lịch sử</b>' + ls.map(g => '<div style="border-top:1px solid #EEF1F5;padding:4px 0">' + (g.dang_dung ? '<span class="tag ok">đang dùng</span> ' : '') + esc(CACH[g.cach]) + ' · UCL ' + S().fmt(+g.ucl, d) + ' / CL ' + S().fmt(+g.cl, d) + ' / LCL ' + S().fmt(+g.lcl, d) +
          '<div class="hint" style="margin:0">' + esc(ngayVN(g.tao_luc)) + ' · ' + esc(g.nguoi || '') + ' · ' + esc(g.ghi_chu || '') + '</div></div>').join('') + '</div>' : '');
      box.querySelector('[data-gc]').onchange = e => {
        box.querySelector('[data-gtl]').style.display = e.target.value === 'tinh_lai' ? '' : 'none';
        box.querySelector('[data-gtay]').style.display = e.target.value === 'tay' ? '' : 'none';
      };
      box.querySelector('[data-gluu]').onclick = async () => {
        const g = s => box.querySelector(s).value.trim();
        const cach = g('[data-gc]');
        const tu = cach === 'tinh_lai' && g('[data-gtu]') ? g('[data-gtu]') + 'T00:00:00+07:00' : null;
        const den = cach === 'tinh_lai' && g('[data-gden]') ? g('[data-gden]') + 'T23:59:59+07:00' : null;
        const gt = cach === 'tay' ? { cl: soVN(g('[data-gcl]')), ucl: soVN(g('[data-gucl]')), lcl: soVN(g('[data-glcl]')), cl_r: soVN(g('[data-gr]')) || 0, ucl_r: (+soVN(g('[data-gr]')) || 0) * 3.267 } : null;
        const { data, error } = await sb.rpc('ipqc_gioi_han_dat', { p_ma_sp: st.ma, p_muc_no: m.muc_no, p_cach: cach, p_tu: tu, p_den: den, p_gt: gt, p_ghi_chu: g('[data-gly]'), p_nguoi: await nguoi() });
        if (error || !data || !data.ok) return msg(box.querySelector('[data-gmsg]'), (error && error.message) || (data && data.error), 'err');
        st.cache = {}; await ve(); taiCanhBao();
      };
    }

    // Cảnh báo 7 ngày trên tất cả mã có bảng tuần kiểm.
    async function taiCanhBao() {
      const box = el.querySelector('[data-canh]');
      const moc = Date.now() - 7 * 86400e3, ds = [];
      for (const x of st.dsMa) {
        let data;
        try { data = await layDuLieu(x.ma_sp, 0); } catch (e) { continue; }
        (data.muc || []).forEach(m => {
          if (m.kieu !== 'so') {
            (data.lan || []).filter(l => new Date(l.thoi_diem) >= moc).forEach(l => (l.kq || []).filter(k => k.muc_no === m.muc_no && !k.dat)
              .forEach(() => ds.push({ ng: true, ma: x.ma_sp, no: m.muc_no, t: l.thoi_diem, tieuDe: x.ma_sp + ' · ' + m.muc_no + '. ' + m.hang_muc + ' NG', moTa: (l.ma_may || '') + (l.so_khuon ? ' · ' + l.so_khuon : '') })));
            return;
          }
          const r = diemVaViPham(data, m), d = S().soLe(m);
          r.pts.forEach((p, i) => {
            if (new Date(p.t) < moc) return;
            const ngoai = p.vals.filter(v => S().datGiaTri(v, r.sp) === false);
            if (ngoai.length) ds.push({ ng: true, ma: x.ma_sp, no: m.muc_no, t: p.t, tieuDe: x.ma_sp + ' · ' + m.muc_no + '. ' + m.hang_muc + ' = ' + ngoai.map(v => S().fmt(v, d)).join(' / ') + ' ngoài tiêu chuẩn', moTa: (p.may || '') + (p.khuon ? ' · ' + p.khuon : '') + ' · ' + (p.nguoi || '') });
          });
          r.vp.filter(v => new Date(r.pts[v.i].t) >= moc).forEach(v => ds.push({ ma: x.ma_sp, no: m.muc_no, t: r.pts[v.i].t, tieuDe: x.ma_sp + ' · ' + m.muc_no + '. ' + m.hang_muc + ' — ' + v.msg, moTa: 'Quy tắc ' + v.quy_tac + (r.lim && r.lim.tam ? ' (giới hạn tạm)' : '') + ' · ' + (r.pts[v.i].may || '') }));
        });
      }
      ds.sort((a, b) => new Date(b.t) - new Date(a.t));
      // 1 chuỗi vi phạm kéo dài sinh cảnh báo ở mỗi điểm → giữ lần mới nhất mỗi (mã, hạng mục, quy tắc).
      const daCo = new Set();
      const gon = ds.filter(a => { if (a.ng) return true; const k = a.ma + '|' + a.no + '|' + a.moTa.split(' ·')[0]; if (daCo.has(k)) return false; daCo.add(k); return true; });
      ds.length = 0; ds.push(...gon);
      box.innerHTML = ds.length ? ds.slice(0, 40).map(a => '<div class="al' + (a.ng ? ' ng' : '') + '" data-al="' + esc(a.ma) + '|' + a.no + '" role="button" tabindex="0"><div class="h"><span class="tag ' + (a.ng ? 'ng' : 'w') + '">' + (a.ng ? 'NG' : 'Bất thường') + '</span><span style="flex:1">' + esc(a.tieuDe) + '</span></div>' +
        '<div class="s">' + esc(ngayVN(a.t)) + ' · ' + esc(a.moTa) + '</div></div>').join('') + (ds.length > 40 ? '<div class="hint">… và ' + (ds.length - 40) + ' cảnh báo khác</div>' : '')
        : '<div class="hint">Không có cảnh báo trong 7 ngày.</div>';
    }

    el.addEventListener('change', async e => {
      const t = e.target.closest('[data-l]'); if (!t) return;
      const k = t.dataset.l;
      if (k === 'ma') { st.ma = t.value; st.no = null; st.may = ''; st.khuon = ''; }
      if (k === 'no') st.no = +t.value;
      if (k === 'may') st.may = t.value;
      if (k === 'khuon') st.khuon = t.value;
      if (k === 'ngay') st.ngay = +t.value;
      await ve();
    });
    el.addEventListener('click', async e => {
      const r = e.target.closest('[data-chonno]');
      if (r) { st.no = +r.dataset.chonno; return ve(); }
      const a = e.target.closest('[data-al]');
      if (a) { const [ma, no] = a.dataset.al.split('|'); st.ma = ma; st.no = +no; st.may = ''; st.khuon = ''; await ve(); el.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
    });
    await khoiDong();
    return { taiLai: async () => { st.cache = {}; await ve(); taiCanhBao(); } };
  }

  window.IpqcBtkQc = { mountEditor, mountChart, quyen, khoiDuyet, duyet, huy, TT };
})();
