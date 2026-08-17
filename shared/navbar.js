/**
 * ============================================================================
 * navbar.js — thanh menu ngang cố định dùng chung cho MỌI trang MES.
 *
 * Cách dùng: nhúng SAU shared/supabase-client.js (cần `sb`/`MesAuth` sẵn có):
 *   <script src="shared/supabase-client.js"></script>
 *   <script src="shared/navbar.js"></script>
 *
 * Tự vẽ + chèn 1 thanh position:fixed vào đầu <body>, đẩy nội dung trang
 * xuống bằng padding-top. KHÔNG dùng ở shared/login.html (trang đăng nhập cố
 * tình tối giản, xem KE_HOACH_TINH_NANG_MOI.md / ghi chú trong plan lúc làm).
 *
 * Nhóm menu theo khu vực làm việc (Đúc ngang hàng với Bavia/Gia công/Sơn/OQC,
 * không tách riêng — theo đúng góp ý người dùng khi thiết kế). "Quản trị" chỉ
 * hiện với role admin (tra user_roles, cùng cách quan-ly-danh-muc.html đang
 * gate quyền vào trang).
 * ============================================================================
 */
(function () {
  const MENU = [
    { label: 'Điều hành & Báo cáo', items: [
      { label: 'Dashboard Sản lượng', href: 'sanluong-supabase.html' },
      { label: 'Dashboard Chất lượng', href: 'chatluong-supabase.html' },
      { label: 'Báo cáo kết ca', href: 'bao-cao-ca.html' },
      { label: 'Kế hoạch tuần', href: 'khsx-tuan.html' },
    ] },
    { label: 'Sản xuất', items: [
      { label: 'Bảng điều khiển Đúc', href: 'duc-dashboard.html' },
      { label: 'Bảng điều khiển Bavia', href: 'cong-doan-dashboard.html?cd=Bavia' },
      { label: 'Bảng điều khiển Gia Công', href: 'cong-doan-dashboard.html?cd=Gia+C%C3%B4ng' },
      { label: 'Bảng điều khiển Sơn', href: 'cong-doan-dashboard.html?cd=S%C6%A1n' },
      { label: 'Bảng điều khiển OQC', href: 'cong-doan-dashboard.html?cd=OQC' },
      { label: 'Nhập liệu di động', href: 'mobile.html' },
      { label: 'In tem', href: 'intem.html' },
      { label: 'Kế hoạch bảo dưỡng khuôn', href: 'bao-duong-khuon-tuan.html' },
      { label: 'Chuyển công đoạn / Đóng gói', href: 'chuyencongdoan.html' },
      { label: 'OQC đóng gói', href: 'oqc.html' },
      { label: 'Báo cáo cuối ca công đoạn', href: 'cong-doan-bao-cao-ca.html' },
    ] },
    { label: 'Chất lượng', items: [
      { label: 'IPQC', href: 'ipqc.html' },
      { label: 'QC Manager / NCP', href: 'qc-manager.html' },
    ] },
    { label: 'Kho & Truy xuất', items: [
      { label: 'Kho NVL', href: 'nvl.html' },
      { label: 'Kho thành phẩm', href: 'kho-thanh-pham.html' },
      { label: 'Truy xuất nguồn gốc', href: 'truy-xuat-nguon-goc.html' },
    ] },
  ];
  const ADMIN_MENU = { label: 'Quản trị', items: [
    { label: 'Tài khoản', href: 'quan-ly-tai-khoan.html' },
    { label: 'Danh mục', href: 'quan-ly-danh-muc.html' },
  ] };

  // Tiêu đề chuẩn hoá cho từng trang — 1 nguồn duy nhất, thay cho header tự
  // viết riêng (không đồng nhất) ở mỗi trang. Trang nào cần đổi tiêu đề theo
  // ngữ cảnh (VD cong-doan-dashboard.html theo công đoạn đang chọn) gọi
  // window.MesNav.setTitle(title, desc) — desc truyền null nếu giữ nguyên.
  const PAGE_META = {
    'index.html': { icon: '🏠', title: 'Trang chủ MES', desc: 'Chọn chức năng bạn muốn sử dụng' },
    'duc-dashboard.html': { icon: '🏭', title: 'Bảng điều khiển Đúc', desc: 'Kế hoạch, sản lượng, sự cố, khuôn theo ca' },
    'mobile.html': { icon: '📱', title: 'Nhập liệu di động — Đúc', desc: 'Bản rút gọn cho điện thoại, 1 máy/màn hình' },
    'ipqc.html': { icon: '🔎', title: 'IPQC — Kiểm tra tuần kiểm', desc: 'Hàng đợi điểm kiểm, nộp kết quả kèm ảnh' },
    'chuyencongdoan.html': { icon: '🔀', title: 'Chuyển công đoạn & Đóng gói', desc: 'Quét QR chuyển hàng, đóng gói lại, đổi mã SP' },
    'oqc.html': { icon: '📦', title: 'OQC — Đóng gói Pallet', desc: 'Quét tem, gom pallet, đóng gói' },
    'kho-thanh-pham.html': { icon: '🏬', title: 'Kho Thành Phẩm', desc: 'Nhập kho / Xuất hàng bằng QR' },
    'truy-xuat-nguon-goc.html': { icon: '🔍', title: 'Truy Xuất Nguồn Gốc', desc: 'Phả hệ tem: tách/gộp xuyên công đoạn' },
    'cong-doan-bao-cao-ca.html': { icon: '📋', title: 'Báo Cáo Cuối Ca — Ngoài Đúc', desc: 'Bavia / Gia công / Sơn / OQC' },
    'cong-doan-dashboard.html': { icon: '🏭', title: 'Dashboard Công Đoạn', desc: 'Trạm/line/máy, sản lượng OK/NG real-time' },
    'bao-duong-khuon-tuan.html': { icon: '🔧', title: 'Kế Hoạch Bảo Dưỡng Khuôn Tuần', desc: 'Gợi ý tự động theo lịch sản xuất' },
    'khsx-tuan.html': { icon: '📅', title: 'Kế Hoạch Sản Xuất Tuần — Đúc', desc: 'Nhập/sửa kế hoạch theo máy' },
    'nvl.html': { icon: '🧪', title: 'Quản Lý Tồn Kho NVL', desc: 'Theo dõi tồn, in tem QR, quét nhập/xuất' },
    'intem.html': { icon: '🏷️', title: 'In Tem — Đúc', desc: 'Tạo, tra cứu, sửa, in lại tem' },
    'qc-manager.html': { icon: '🔬', title: 'QC Giám Sát & NCP', desc: 'Giám sát real-time, xử lý SP không phù hợp' },
    'quan-ly-danh-muc.html': { icon: '⚙️', title: 'Quản Lý Danh Mục', desc: 'Máy, sản phẩm, nhân sự, khuôn — chỉ Admin' },
    'quan-ly-tai-khoan.html': { icon: '👤', title: 'Quản Lý Tài Khoản', desc: 'Tạo tài khoản, phân quyền — chỉ Admin' },
    'ncp-detail.html': { icon: '📝', title: 'Chi Tiết NCP', desc: 'Nguyên nhân & Đối sách' },
    'bao-cao-ca.html': { icon: '🗂️', title: 'Xem Lại Báo Cáo Kết Ca', desc: 'Tra cứu báo cáo đã lưu theo ngày/ca' },
    'sanluong-supabase.html': { icon: '📊', title: 'Dashboard Sản Lượng & Giao Hàng', desc: 'Tỷ lệ giao hàng, hoàn thành KHSX, forecast' },
    'chatluong-supabase.html': { icon: '📈', title: 'Dashboard KPI Chất Lượng', desc: 'Tổng quan, theo công đoạn, theo khách hàng' },
  };

  const CSS = `
:root{--navbar-h:50px}
body{padding-top:var(--navbar-h)}
.mnb-bar{position:fixed;top:0;left:0;right:0;z-index:5000;background:#211a15;color:#F7F1E7;
  height:var(--navbar-h);display:flex;align-items:center;padding:0 6px 0 14px;gap:6px;
  box-shadow:0 2px 8px rgba(0,0,0,.15);font-family:Arial,Helvetica,sans-serif}
.mnb-logo{font-weight:800;font-size:14px;letter-spacing:.03em;color:#fff;text-decoration:none;flex-shrink:0;white-space:nowrap}
.mnb-logo span{color:#C87941}
.mnb-groups{display:flex;gap:2px;flex:1;height:100%;overflow:visible}
.mnb-group{position:relative;flex-shrink:0}
.mnb-group-btn{background:none;border:none;color:#e8e0d5;font-size:12.5px;font-weight:700;
  padding:0 10px;height:var(--navbar-h);cursor:pointer;white-space:nowrap;display:flex;align-items:center;gap:4px;font-family:inherit}
.mnb-group-btn:hover,.mnb-group.route-active .mnb-group-btn{color:#fff;background:rgba(255,255,255,.09)}
.mnb-caret{font-size:9px;opacity:.7}
.mnb-dropdown{display:none;position:absolute;top:100%;left:0;background:#fff;border-radius:0 0 8px 8px;
  box-shadow:0 8px 20px rgba(0,0,0,.22);min-width:230px;padding:6px;flex-direction:column;z-index:5001}
.mnb-group:hover .mnb-dropdown,.mnb-group.open .mnb-dropdown{display:flex}
.mnb-item{padding:9px 12px;border-radius:6px;color:#333;text-decoration:none;font-size:13px;font-weight:600}
.mnb-item:hover{background:#faf5f0;color:#C87941}
.mnb-item.route-active{background:#f5e6d7;color:#a85e2a}
.mnb-auth{flex-shrink:0;font-size:11.5px;color:#c9c2b6;display:flex;align-items:center;gap:8px;white-space:nowrap;padding-right:6px}
.mnb-auth a{color:#C87941;text-decoration:none;font-weight:700}
.mnb-burger{display:none;background:none;border:none;color:#fff;font-size:19px;cursor:pointer;padding:0 6px;flex-shrink:0}
.mnb-auth-mobile{display:none}
@media (max-width:820px){
  .mnb-groups{display:none;position:fixed;top:var(--navbar-h);left:0;right:0;bottom:0;
    background:#fff;flex-direction:column;overflow-y:auto;padding:8px;z-index:4999}
  .mnb-groups.open{display:flex}
  .mnb-group{width:100%}
  .mnb-group-btn{width:100%;color:#8a5a30;height:auto;padding:12px 8px;justify-content:space-between;border-bottom:1px solid #f0e6d8}
  .mnb-dropdown{display:none;position:static;box-shadow:none;padding:0 0 6px 12px;min-width:0}
  .mnb-group.mobile-open .mnb-dropdown{display:flex}
  .mnb-burger{display:block}
  .mnb-auth{display:none}
  .mnb-auth-mobile{display:flex;margin-top:8px;padding:12px 8px;border-top:2px solid #f0e6d8;font-size:12.5px;color:#666}
}
.mnb-title-bar{background:#fff;border-bottom:1px solid #E4DACB;padding:12px 20px;
  display:flex;align-items:baseline;gap:10px;flex-wrap:wrap;font-family:Arial,Helvetica,sans-serif}
.mnb-title-icon{font-size:18px;line-height:1}
.mnb-page-title{font-size:16px;font-weight:700;color:#211a15;margin:0}
.mnb-page-desc{font-size:11.5px;color:#8A7C68}
@media (max-width:820px){
  .mnb-title-bar{padding:10px 14px}
  .mnb-page-title{font-size:14px}
  .mnb-page-desc{width:100%}
}
`;

  function currentFile() {
    const parts = location.pathname.split('/').filter(Boolean);
    return (parts[parts.length - 1] || 'index.html').toLowerCase();
  }

  function groupsHtml(groups, cur) {
    return groups.map(g => {
      const itemsHtml = g.items.map(it =>
        `<a href="${it.href}" class="mnb-item${it.href.toLowerCase() === cur ? ' route-active' : ''}">${it.label}</a>`
      ).join('');
      const groupActive = g.items.some(it => it.href.toLowerCase() === cur);
      return `<div class="mnb-group${groupActive ? ' route-active' : ''}">
        <button type="button" class="mnb-group-btn">${g.label} <span class="mnb-caret">▾</span></button>
        <div class="mnb-dropdown">${itemsHtml}</div>
      </div>`;
    }).join('');
  }

  function renderAuthInto(containerId, email) {
    const el = document.getElementById(containerId);
    if (!el) return;
    el.innerHTML = email
      ? ('👤 ' + email + ' · <a href="#" class="mnb-signout">Đăng xuất</a>')
      : '<a href="shared/login.html">Đăng nhập</a>';
    const so = el.querySelector('.mnb-signout');
    if (so) so.addEventListener('click', (e) => { e.preventDefault(); MesAuth.signOut(); });
  }

  function wireInteractions() {
    document.getElementById('mnbBurger').addEventListener('click', () => {
      document.getElementById('mnbGroups').classList.toggle('open');
    });
    // Bấm để mở/đóng dropdown — không chỉ dựa vào hover (chuột không rê qua,
    // trackpad, hoặc bấm thẳng vào nút đều phải mở được). Trên desktop dùng
    // class "open" (đè lên nội dung trang, đóng khi bấm ra ngoài); trên mobile
    // dùng "mobile-open" (kiểu accordion, xổ ngay dưới nút, không cần đóng ra
    // ngoài vì đã ở trong lớp phủ toàn màn hình riêng).
    document.querySelectorAll('.mnb-group-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const group = btn.parentElement;
        const cls = window.innerWidth > 820 ? 'open' : 'mobile-open';
        const wasOpen = group.classList.contains(cls);
        document.querySelectorAll('.mnb-group.open, .mnb-group.mobile-open').forEach(g => {
          if (g !== group) { g.classList.remove('open'); g.classList.remove('mobile-open'); }
        });
        group.classList.toggle(cls, !wasOpen);
      });
    });
    document.addEventListener('click', () => {
      document.querySelectorAll('.mnb-group.open').forEach(g => g.classList.remove('open'));
    });
  }

  function init() {
    const style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    const bar = document.createElement('div');
    bar.className = 'mnb-bar';
    bar.innerHTML =
      '<button type="button" class="mnb-burger" id="mnbBurger">☰</button>' +
      '<a href="index.html" class="mnb-logo">TOYOTAKI <span>MES</span></a>' +
      '<div class="mnb-groups" id="mnbGroups"></div>' +
      '<div class="mnb-auth" id="mnbAuth">…</div>';
    document.body.insertBefore(bar, document.body.firstChild);

    // Vẽ menu + gắn sự kiện click NGAY — không đợi mạng/đăng nhập, để menu
    // luôn bấm được dù kiểm tra quyền admin bên dưới chậm hoặc treo (kiểm tra
    // quyền chỉ ảnh hưởng việc CÓ THÊM nhóm "Quản trị" hay không, không phải
    // điều kiện để menu hiển thị được).
    const cur = currentFile();
    document.getElementById('mnbGroups').innerHTML = groupsHtml(MENU, cur) + '<div class="mnb-auth-mobile" id="mnbAuthMobile"></div>';
    renderAuthInto('mnbAuth', null);
    renderAuthInto('mnbAuthMobile', null);
    wireInteractions();

    // Thanh tiêu đề chuẩn hoá — thay header tự viết riêng (không đồng nhất)
    // ở từng trang. Trang không có trong PAGE_META (hiếm) thì không vẽ gì,
    // giữ nguyên header cũ của trang đó thay vì hiện rỗng.
    const meta = PAGE_META[cur];
    if (meta) {
      const titleBar = document.createElement('div');
      titleBar.className = 'mnb-title-bar';
      titleBar.innerHTML =
        '<span class="mnb-title-icon">' + (meta.icon || '') + '</span>' +
        '<h1 class="mnb-page-title" id="mnbPageTitle">' + meta.title + '</h1>' +
        '<span class="mnb-page-desc" id="mnbPageDesc">' + (meta.desc || '') + '</span>';
      bar.after(titleBar);
    }

    // Tăng cường sau: thêm nhóm "Quản trị" nếu là admin, cập nhật ô đăng nhập
    // — chạy nền, không chặn menu chính.
    enhanceWithAuth(cur);
  }

  // Cho trang tự đổi tiêu đề theo ngữ cảnh (VD cong-doan-dashboard.html theo
  // công đoạn đang chọn, ncp-detail.html theo mã NCP đang xem). Truyền null
  // ở tham số nào muốn giữ nguyên.
  window.MesNav = {
    setTitle(title, desc) {
      if (title != null) { const t = document.getElementById('mnbPageTitle'); if (t) t.textContent = title; }
      if (desc != null) { const d = document.getElementById('mnbPageDesc'); if (d) d.textContent = desc; }
    },
  };

  async function enhanceWithAuth(cur) {
    let email = null;
    try {
      email = await MesAuth.getCurrentUserEmail();
      if (email) {
        const session = await MesAuth.getSession();
        const { data: myRole } = await sb.from('user_roles').select('role').eq('user_id', session.user.id).maybeSingle();
        if (myRole && myRole.role === 'admin') {
          document.getElementById('mnbGroups').innerHTML = groupsHtml(MENU.concat([ADMIN_MENU]), cur) + '<div class="mnb-auth-mobile" id="mnbAuthMobile"></div>';
          wireInteractions();
        }
      }
    } catch (e) { /* không chặn menu nếu lỗi tra quyền — chỉ không thêm nhóm Quản trị */ }
    renderAuthInto('mnbAuth', email);
    renderAuthInto('mnbAuthMobile', email);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
