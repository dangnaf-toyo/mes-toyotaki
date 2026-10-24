/**
 * ============================================================================
 * cong-viec.js — dùng chung cho module Quản lý công việc (T161).
 * Thiết kế + hợp đồng dữ liệu: docs/CONG_VIEC_THIET_KE.md
 *
 * Nhúng SAU shared/supabase-client.js (cần `sb`). Kèm shared/cong-viec.css.
 * Mọi thứ nằm dưới window.CV — trang không tự định nghĩa lại hằng số/màu.
 * ============================================================================
 */
(function () {
  const TRANG_THAI = {
    moi:        { label: 'Mới',        color: '#64748B', bg: '#F1F5F9', fg: '#475569' },
    dang_lam:   { label: 'Đang làm',   color: '#2563EB', bg: '#DBEAFE', fg: '#1D4ED8' },
    cho_duyet:  { label: 'Chờ duyệt',  color: '#D97706', bg: '#FEF3C7', fg: '#92400E' },
    hoan_thanh: { label: 'Hoàn thành', color: '#047857', bg: '#D1FAE5', fg: '#065F46' },
    huy:        { label: 'Đã huỷ',     color: '#94A3B8', bg: '#F1F5F9', fg: '#475569' },
  };
  const THU_TU_TRANG_THAI = ['moi', 'dang_lam', 'cho_duyet', 'hoan_thanh'];

  // Nhóm ưu tiên = Quan trọng × Gấp (gấp hiệu lực: tự bật khi còn ≤ 2 ngày).
  const NHOM = {
    1: { ten: 'Làm ngay',     mo_ta: 'Quan trọng + Gấp',        color: '#B91C1C', soft: '#FEF2F2',
         goi_y: 'Ảnh hưởng chất lượng, giao hàng, an toàn hoặc chi phí lớn — và cần xong trong 2 ngày. Làm trước mọi việc khác.' },
    2: { ten: 'Lên kế hoạch', mo_ta: 'Quan trọng, chưa gấp',    color: '#0F5FA5', soft: '#EFF6FF',
         goi_y: 'Quan trọng nhưng còn thời gian. Đặt mốc, chia bước, làm đều để không trở thành gấp.' },
    3: { ten: 'Xử lý nhanh',  mo_ta: 'Gấp, ít quan trọng',      color: '#B45309', soft: '#FFFBEB',
         goi_y: 'Cần xong sớm nhưng ảnh hưởng nhỏ. Làm gọn trong ngày hoặc giao lại cho người phù hợp.' },
    4: { ten: 'Làm sau',      mo_ta: 'Chưa gấp, ít quan trọng', color: '#64748B', soft: '#F8FAFC',
         goi_y: 'Làm khi có thời gian. Trưởng bộ phận xem lại hằng tuần: nâng mức, giữ hay huỷ.' },
  };
  function nhomCua(quanTrong, gap) { return quanTrong && gap ? 1 : quanTrong ? 2 : gap ? 3 : 4; }

  const LOAI_BL = {
    binh_luan: { label: 'Bình luận', bg: '#F1F5F9', fg: '#475569' },
    gop_y:     { label: 'Góp ý',     bg: '#EDE9FE', fg: '#5B21B6' },
    cau_hoi:   { label: 'Câu hỏi',   bg: '#FEF3C7', fg: '#92400E' },
    de_xuat:   { label: 'Đề xuất',   bg: '#DCFCE7', fg: '#166534' },
    cap_nhat:  { label: 'Cập nhật',  bg: '#F1F5F9', fg: '#475569' },
    tra_lai:   { label: 'Trả lại',   bg: '#FEE2E2', fg: '#B91C1C' },
  };
  const TRANG_THAI_GOP_Y = {
    dang_xem_xet:  { label: 'Đang xem xét',              bg: '#FFFBEB', fg: '#92400E' },
    da_tiep_thu:   { label: '✓ Đã tiếp thu',             bg: '#ECFDF5', fg: '#065F46' },
    da_tra_loi:    { label: '✓ Đã trả lời',              bg: '#ECFDF5', fg: '#065F46' },
    khong_ap_dung: { label: 'Không áp dụng',             bg: '#F1F5F9', fg: '#475569' },
  };
  const LIEN_KET = {
    ncp:            { label: 'NCP' },
    su_co:          { label: 'Sự cố' },
    khuon:          { label: 'Khuôn' },
    may:            { label: 'Máy' },
    ma_sp:          { label: 'Mã SP' },
    phieu_thay_doi: { label: 'Phiếu thay đổi' },
  };
  const LOAI_THONG_BAO = {
    giao_viec: 'Giao việc', nhan_viec: 'Đã nhận', cho_duyet: 'Chờ duyệt', hoan_thanh: 'Hoàn thành',
    tra_lai: 'Trả lại', xin_gia_han: 'Xin gia hạn', tra_loi_gia_han: 'Gia hạn', nhac_viec: 'Nhắc việc',
    cap_nhat_viec: 'Cập nhật', mo_lai: 'Mở lại', huy_viec: 'Huỷ việc', binh_luan: 'Bình luận',
    gop_y: 'Góp ý', nhac_ten: 'Nhắc tên', qua_han: 'Quá hạn',
  };

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  // Hiển thị theo giờ Việt Nam bất kể máy đặt múi giờ nào.
  const TZ = 'Asia/Ho_Chi_Minh';
  function parts(ts) {
    const d = ts instanceof Date ? ts : new Date(ts);
    const f = new Intl.DateTimeFormat('en-GB', { timeZone: TZ, day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false });
    const o = {}; f.formatToParts(d).forEach(p => { o[p.type] = p.value; });
    return o;
  }
  function fmtNgay(ts) { if (!ts) return ''; const p = parts(ts); return p.day + '/' + p.month; }
  function fmtNgayGio(ts) { if (!ts) return ''; const p = parts(ts); return p.day + '/' + p.month + ' ' + p.hour + ':' + p.minute; }
  function fmtDayDu(ts) { if (!ts) return ''; const p = parts(ts); return p.day + '/' + p.month + '/' + p.year + ' ' + p.hour + ':' + p.minute; }
  function ngayVN(ts) { const p = parts(ts || new Date()); return p.year + '-' + p.month + '-' + p.day; }

  /** Chữ hạn cho thẻ việc: { text, cls } — cls 'late' (đỏ) | 'soon' (cam) | ''. */
  function hanText(row) {
    if (row.trang_thai === 'hoan_thanh') return { text: row.dung_han === false ? 'Trễ hạn' : 'Đúng hạn', cls: row.dung_han === false ? 'late' : '' };
    if (row.trang_thai === 'huy') return { text: 'Đã huỷ', cls: '' };
    if (row.trang_thai === 'cho_duyet') return { text: 'Chờ duyệt từ ' + fmtNgay(row.bao_xong_luc), cls: '' };
    const gio = (new Date(row.han) - Date.now()) / 3600000;
    if (gio < 0) {
      const ngay = Math.floor(-gio / 24);
      return { text: ngay >= 1 ? 'Quá hạn ' + ngay + ' ngày' : 'Quá hạn ' + Math.max(1, Math.round(-gio)) + ' giờ', cls: 'late' };
    }
    if (ngayVN(row.han) === ngayVN()) return { text: 'Hôm nay ' + fmtNgayGio(row.han).slice(6), cls: 'soon' };
    if (gio <= 48) return { text: 'Còn ' + Math.max(1, Math.ceil(gio / 24)) + ' ngày', cls: 'soon' };
    return { text: 'Hạn ' + fmtNgay(row.han), cls: '' };
  }

  /** Gọi RPC; lỗi thì ném Error với câu tiếng Việt từ server. */
  async function rpc(name, args) {
    const { data, error } = await sb.rpc(name, args || {});
    if (error) throw new Error(loiDeHieu(error.message || String(error)));
    return data;
  }

  let _nguoi = null;
  async function nguoi() {
    if (!_nguoi) _nguoi = rpc('cv_danh_sach_nguoi').then(r => r || []);
    return _nguoi;
  }
  async function tenNguoi(uid) {
    const ds = await nguoi();
    const n = ds.find(x => x.user_id === uid);
    return n ? n.ten : '';
  }
  function viTat(ten) {
    const w = String(ten || '?').trim().split(/\s+/).filter(Boolean);
    if (!w.length) return '?';
    return (w.length === 1 ? w[0].slice(0, 2) : w[0][0] + w[w.length - 1][0]).toUpperCase();
  }

  let _boPhan = null;
  async function boPhan() {
    if (!_boPhan) _boPhan = sb.from('cv_bo_phan').select('ten,thu_tu').order('thu_tu').then(({ data }) => (data || []).map(r => r.ten));
    return _boPhan;
  }

  let _me = null;
  /** { id, ten, role, laBGD } của người đang đăng nhập (null nếu chưa đăng nhập). */
  async function me() {
    if (_me) return _me;
    const { data } = await sb.auth.getSession();
    const s = data.session;
    if (!s) return null;
    const { data: r } = await sb.from('user_roles').select('role,full_name,username').eq('user_id', s.user.id).maybeSingle();
    const role = r ? r.role : null;
    _me = { id: s.user.id, ten: (r && (r.full_name || r.username)) || s.user.email, role, laBGD: role === 'admin' || role === 'giam_doc_sx' };
    return _me;
  }

  function badgeNhom(n) {
    const g = NHOM[n] || NHOM[4];
    return `<span class="cv-badge" style="background:${g.color}">${n} · ${esc(g.ten)}</span>`;
  }
  function badgeTrangThai(tt) {
    const t = TRANG_THAI[tt] || TRANG_THAI.moi;
    return `<span class="cv-st" style="background:${t.bg};color:${t.fg}">${esc(t.label)}</span>`;
  }
  function lienKetText(lk) { const d = LIEN_KET[lk && lk.loai]; return (d ? d.label + ' ' : '') + (lk && lk.ma || ''); }

  /**
   * Thẻ việc dùng chung (bảng, việc của tôi). row = 1 dòng cv_cong_viec_v.
   * opts.trangThai: hiện chip trạng thái (dùng ở ma trận / danh sách).
   */
  function theViec(row, opts) {
    opts = opts || {};
    const g = NHOM[row.nhom] || NHOM[4];
    const h = hanText(row);
    const tags = [];
    if (row.so_lan_tra_lai > 0 && row.trang_thai !== 'hoan_thanh') tags.push(`<span class="cv-tag back">Bị trả lại ${row.so_lan_tra_lai} lần</span>`);
    if (row.gia_han_den) tags.push(`<span class="cv-tag warn">Xin gia hạn</span>`);
    (row.lien_ket || []).slice(0, 3).forEach(lk => tags.push(`<span class="cv-tag link">${esc(lienKetText(lk))}</span>`));
    if (row.ten_du_an) tags.push(`<span class="cv-tag">${esc(row.ten_du_an)}</span>`);
    const bar = row.so_buoc > 0
      ? `<div class="cv-bar"><span style="width:${Math.round(row.so_buoc_xong / row.so_buoc * 100)}%"></span></div>` : '';
    return `<a class="cv-card${row.trang_thai === 'hoan_thanh' || row.trang_thai === 'huy' ? ' done' : ''}" href="cong-viec-chi-tiet.html?id=${row.id}"
        draggable="${opts.draggable ? 'true' : 'false'}" data-id="${row.id}" style="border-left-color:${g.color}">
      <div class="cv-card-top">${badgeNhom(row.nhom)}<span class="cv-axes">${row.quan_trong ? 'Quan trọng' : 'Ít quan trọng'} · ${row.gap_hieu_luc ? 'Gấp' : 'Chưa gấp'}</span>${opts.trangThai ? badgeTrangThai(row.trang_thai) : ''}</div>
      <div class="cv-card-title">${esc(row.tieu_de)}</div>
      ${tags.length ? `<div class="cv-tags">${tags.join('')}</div>` : ''}
      ${bar}
      <div class="cv-meta"><span class="cv-av" title="${esc(row.ten_nguoi_lam)}">${esc(viTat(row.ten_nguoi_lam))}</span><span class="cv-meta-name">${esc(row.ten_nguoi_lam)}</span>
        ${row.so_buoc > 0 ? `<span>${row.so_buoc_xong}/${row.so_buoc} bước</span>` : ''}
        ${row.so_binh_luan > 0 ? `<span>${row.so_binh_luan} bình luận</span>` : ''}
        <span class="cv-due ${h.cls}">${esc(h.text)}</span></div>
    </a>`;
  }

  /**
   * Thanh tab của module, đặt trong header tối của trang:
   *   <nav class="cv-modtabs" data-cv-tabs="cua-toi"></nav>
   * key: 'cua-toi' | 'bang' | 'thong-bao'.
   */
  function veTabModule() {
    document.querySelectorAll('[data-cv-tabs]').forEach(nav => {
      const cur = nav.getAttribute('data-cv-tabs');
      const tabs = [
        ['cua-toi', 'Việc của tôi', 'cong-viec-cua-toi.html'],
        ['bang', 'Bảng công việc', 'cong-viec.html'],
        ['thong-bao', 'Thông báo', 'thong-bao.html'],
      ];
      nav.innerHTML = tabs.map(t => `<a href="${t[2]}" class="cv-modtab${t[0] === cur ? ' on' : ''}">${t[1]}</a>`).join('')
        + `<a href="cong-viec-giao.html" class="cv-modtab cv-giao">+ Giao việc</a>`;
    });
  }

  /** Đổi lỗi kỹ thuật (quyền, phiên, mạng) thành câu dễ hiểu; lỗi nghiệp vụ tiếng Việt giữ nguyên. */
  function loiDeHieu(msg) {
    const s = String(msg || '');
    if (/permission denied|42501|JWT|not authenticated/i.test(s)) return 'Phiên đăng nhập đã hết hạn hoặc bạn chưa có quyền. Hãy tải lại trang hoặc đăng nhập lại.';
    if (/Failed to fetch|NetworkError|Load failed|network/i.test(s)) return 'Mất kết nối mạng. Kiểm tra mạng rồi thử lại.';
    if (/does not exist|PGRST\d+|schema cache/i.test(s)) return 'Hệ thống đang cập nhật, chức năng này chưa sẵn sàng. Hãy thử lại sau.';
    return s;
  }

  function toast(msg, kind) {
    if (kind === 'err') msg = String(msg || '').replace(/(permission denied|JWT|Failed to fetch|NetworkError|Load failed|does not exist|PGRST\d+)[^\n]*/i, m => loiDeHieu(m));
    let el = document.getElementById('cvToast');
    if (!el) { el = document.createElement('div'); el.id = 'cvToast'; el.className = 'cv-toast'; document.body.appendChild(el); }
    el.textContent = msg;
    el.className = 'cv-toast show ' + (kind || '');
    clearTimeout(el._t);
    el._t = setTimeout(() => { el.className = 'cv-toast'; }, kind === 'err' ? 6000 : 3000);
  }

  /** Đọc các việc từ view (RLS tự lọc việc "hạn chế"). */
  function viecQuery() { return sb.from('cv_cong_viec_v').select('*'); }

  window.CV = {
    TRANG_THAI, THU_TU_TRANG_THAI, NHOM, LOAI_BL, TRANG_THAI_GOP_Y, LIEN_KET, LOAI_THONG_BAO,
    nhomCua, esc, loiDeHieu, fmtNgay, fmtNgayGio, fmtDayDu, ngayVN, hanText, rpc, nguoi, tenNguoi, viTat, boPhan, me,
    badgeNhom, badgeTrangThai, lienKetText, theViec, veTabModule, toast, viecQuery,
  };
  // Trang vừa đánh dấu thông báo đã đọc → chuông trên navbar đếm lại ngay.
  window.addEventListener('cv-thong-bao-doi', () => { if (window.MesNav && MesNav.refreshBell) MesNav.refreshBell(); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', veTabModule); else veTabModule();
})();
