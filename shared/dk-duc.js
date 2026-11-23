// T322: Điều kiện đúc Bước 6 — nút "ĐK đúc" ở Bảng điều khiển Đúc (duc-dashboard.html, mobile.html).
//   DkDuc.batDau(onDoi)          → tải danh sách phiếu Hiệu lực (làm mới 5 phút/lần), gọi onDoi khi có dữ liệu
//   DkDuc.co(maMay, maSp)        → true nếu cặp (máy, mã SP) có phiếu Hiệu lực
//   DkDuc.link(maMay, maSp)      → đường dẫn trang dieu-kien-duc.html của cặp đó
//   DkDuc.nut(maMay, maSp, cls)  → html nút: "📋 ĐK đúc" (có phiếu) | xám "Chưa có ĐK"
(function () {
  if (window.DkDuc) return;
  let hl = new Map(), daTai = false, timer = null, dangTai = null;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const khoa = (m, s) => String(m || '') + '|' + String(s || '').toUpperCase();

  async function tai() {
    const { data, error } = await sb.from('duc_dk_phieu').select('id,ma_may,ma_sp,lan').eq('trang_thai', 'hieu_luc').range(0, 4999);
    if (error) return false;
    const m = new Map();
    (data || []).forEach(p => m.set(khoa(p.ma_may, p.ma_sp), p));
    hl = m; daTai = true;
    return true;
  }

  function batDau(onDoi) {
    if (!document.getElementById('dkDucCss')) {
      const st = document.createElement('style'); st.id = 'dkDucCss';
      st.textContent = '.dkduc-btn{display:inline-flex;align-items:center;gap:3px;font-size:11px;font-weight:600;padding:2px 7px;border-radius:4px;border:1px solid #93C5FD;background:#EFF6FF;color:#1D4ED8;text-decoration:none;white-space:nowrap;margin-top:3px;align-self:flex-start}' +
        '.dkduc-btn:hover{background:#DBEAFE}' +
        '.dkduc-btn.chua{border-color:var(--border,#E5E7EB);background:#F3F4F6;color:#9CA3AF}' +
        '.wallboard-mode .dkduc-btn{display:none!important}';
      document.head.appendChild(st);
    }
    if (dangTai) return dangTai;
    const goi = () => { if (typeof onDoi === 'function') onDoi(); };
    dangTai = tai().then(ok => { if (ok) goi(); });
    if (!timer) timer = setInterval(() => tai().then(ok => { if (ok) goi(); }), 300000);
    return dangTai;
  }

  const co = (m, s) => hl.has(khoa(m, s));
  const link = (m, s) => 'dieu-kien-duc.html?ma_may=' + encodeURIComponent(m || '') + '&ma_sp=' + encodeURIComponent(String(s || '').toUpperCase());

  function nut(m, s, cls) {
    if (!daTai || !m || !s) return '';
    const p = hl.get(khoa(m, s));
    return p
      ? '<a class="dkduc-btn ' + esc(cls || '') + '" href="' + esc(link(m, s)) + '" target="_blank" rel="noopener" title="Phiếu điều kiện đúc đang hiệu lực (lần ' + p.lan + ')">📋 ĐK đúc</a>'
      : '<a class="dkduc-btn chua ' + esc(cls || '') + '" href="' + esc(link(m, s)) + '" target="_blank" rel="noopener" title="Máy này chưa có phiếu điều kiện đúc hiệu lực cho mã SP này">Chưa có ĐK</a>';
  }

  window.DkDuc = { batDau, co, link, nut, get daTai() { return daTai; } };
})();
