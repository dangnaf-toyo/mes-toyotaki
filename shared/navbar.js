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
      { label: 'Báo cáo sản xuất tuần', href: 'bao-cao-tuan.html' },
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
      { label: 'Tra cứu tem đã in', href: 'tra-cuu-tem.html' },
    ] },
  ];
  const ADMIN_MENU = { label: 'Quản trị', items: [
    { label: 'Tài khoản', href: 'quan-ly-tai-khoan.html' },
    { label: 'Danh mục', href: 'quan-ly-danh-muc.html' },
    { label: 'Năng lực máy CNC', href: 'nang-luc-cnc.html' },
  ] };

  // Tiêu đề chuẩn hoá cho từng trang — 1 nguồn duy nhất, thay cho header tự
  // viết riêng (không đồng nhất) ở mỗi trang. Trang nào cần đổi tiêu đề theo
  // ngữ cảnh (VD cong-doan-dashboard.html theo công đoạn đang chọn) gọi
  // window.MesNav.setTitle(title, desc) — desc truyền null nếu giữ nguyên.
  const PAGE_META = {
    'index.html': { icon: '🏠', title: 'Trang chủ MES', desc: 'Chọn chức năng bạn muốn sử dụng', noTitleBar: true },
    'duc-dashboard.html': { icon: '🏭', title: 'Bảng điều khiển Đúc', desc: 'Kế hoạch, sản lượng, sự cố, khuôn theo ca', noTitleBar: true },
    'mobile.html': { icon: '📱', title: 'Nhập liệu di động — Đúc', desc: 'Bản rút gọn cho điện thoại, 1 máy/màn hình' },
    'ipqc.html': { icon: '🔎', title: 'IPQC — Kiểm tra tuần kiểm', desc: 'Hàng đợi điểm kiểm, nộp kết quả kèm ảnh' },
    'chuyencongdoan.html': { icon: '🔀', title: 'Chuyển công đoạn & Đóng gói', desc: 'Quét QR chuyển hàng, đóng gói lại, đổi mã SP', noTitleBar: true },
    'oqc.html': { icon: '📦', title: 'OQC — Đóng gói Pallet', desc: 'Quét tem, gom pallet, đóng gói', noTitleBar: true },
    'kho-thanh-pham.html': { icon: '🏬', title: 'Kho Thành Phẩm', desc: 'Nhập kho / Xuất hàng bằng QR', noTitleBar: true },
    'truy-xuat-nguon-goc.html': { icon: '🔍', title: 'Truy Xuất Nguồn Gốc', desc: 'Phả hệ tem: tách/gộp xuyên công đoạn', noTitleBar: true },
    'tra-cuu-tem.html': { icon: '🏷️', title: 'Tra Cứu Tem Đã In', desc: 'Danh sách tem — lọc theo ngày in/máy/mã SP', noTitleBar: true },
    'cong-doan-bao-cao-ca.html': { icon: '📋', title: 'Báo Cáo Cuối Ca — Ngoài Đúc', desc: 'Bavia / Gia công / Cắt viền / Sơn / OQC', noTitleBar: true },
    'cong-doan-dashboard.html': { icon: '🏭', title: 'Dashboard Công Đoạn', desc: 'Trạm/line/máy, sản lượng OK/NG real-time', noTitleBar: true },
    'bao-duong-khuon-tuan.html': { icon: '🔧', title: 'Kế Hoạch Bảo Dưỡng Khuôn Tuần', desc: 'Gợi ý tự động theo lịch sản xuất', noTitleBar: true },
    'khsx-tuan.html': { icon: '📅', title: 'Kế Hoạch Sản Xuất Tuần', desc: 'Đúc / Bavia / Gia công / Cắt viền / Sơn / OQC — 1 màn hình, chuyển tab', noTitleBar: true },
    'nvl.html': { icon: '🧪', title: 'Quản Lý Tồn Kho NVL', desc: 'Theo dõi tồn, in tem QR, quét nhập/xuất', noTitleBar: true },
    'intem.html': { icon: '🏷️', title: 'In Tem — Đúc', desc: 'Tạo, tra cứu, sửa, in lại tem', noTitleBar: true },
    'qc-manager.html': { icon: '🔬', title: 'QC Giám Sát & NCP', desc: 'Giám sát real-time, xử lý SP không phù hợp', noTitleBar: true },
    'quan-ly-danh-muc.html': { icon: '⚙️', title: 'Quản Lý Danh Mục', desc: 'Máy, sản phẩm, nhân sự, khuôn — chỉ Admin', noTitleBar: true },
    'nang-luc-cnc.html': { icon: '🛠️', title: 'Năng Lực Máy Gia Công CNC', desc: 'Quy trình CNC theo SP, forecast tháng, tính số máy cần — chỉ Admin', noTitleBar: true },
    'quan-ly-tai-khoan.html': { icon: '👤', title: 'Quản Lý Tài Khoản', desc: 'Tạo tài khoản, phân quyền — chỉ Admin', noTitleBar: true },
    'ncp-detail.html': { icon: '📝', title: 'Chi Tiết NCP', desc: 'Nguyên nhân & Đối sách', noTitleBar: true },
    'bao-cao-ca.html': { icon: '🗂️', title: 'Xem Lại Báo Cáo Kết Ca', desc: 'Tra cứu báo cáo đã lưu theo ngày/ca', noTitleBar: true },
    'bao-cao-tuan.html': { icon: '📅', title: 'Báo Cáo Sản Xuất Tuần', desc: 'KPI, dừng máy, vấn đề & hành động đối ứng — theo tuần bất kỳ', noTitleBar: true },
    'sanluong-supabase.html': { icon: '📊', title: 'Dashboard Sản Lượng & Giao Hàng', desc: 'Tỷ lệ giao hàng, hoàn thành KHSX, forecast', noTitleBar: true },
    'chatluong-supabase.html': { icon: '📈', title: 'Dashboard KPI Chất Lượng', desc: 'Tổng quan, theo công đoạn, theo khách hàng', noTitleBar: true },
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
.mnb-pw-mask{display:none;position:fixed;inset:0;background:rgba(15,23,42,.55);align-items:center;justify-content:center;z-index:6000;padding:14px;font-family:Arial,Helvetica,sans-serif}
.mnb-pw-mask.open{display:flex}
.mnb-pw-modal{background:#fff;border-radius:12px;max-width:360px;width:100%;padding:20px}
.mnb-pw-modal h3{font-size:15px;margin-bottom:14px;color:#211a15}
.mnb-pw-modal label{display:block;font-size:11.5px;font-weight:700;color:#666;margin:10px 0 4px}
.mnb-pw-modal input{width:100%;padding:8px 10px;border:1.5px solid #ddd;border-radius:7px;font-size:13.5px;font-family:inherit;box-sizing:border-box}
.mnb-pw-modal input:focus{outline:none;border-color:#C87941}
.mnb-pw-msg{font-size:12px;margin-top:10px;display:none;padding:8px 10px;border-radius:7px}
.mnb-pw-msg.err{display:block;background:#fbe9e7;color:#c0392b}
.mnb-pw-msg.ok{display:block;background:#e7f5ea;color:#1a7a3a}
.mnb-pw-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:16px}
.mnb-pw-actions button{border:none;border-radius:8px;padding:9px 16px;font-size:13px;font-weight:700;cursor:pointer;font-family:inherit}
.mnb-pw-cancel{background:#fff;border:1.5px solid #ddd!important;color:#555}
.mnb-pw-submit{background:#C87941;color:#fff}
.mnb-pw-submit:disabled{opacity:.6;cursor:default}
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

  // displayText ưu tiên "MãNV_TênNV" (username_full_name, giống cách
  // ipqc.html lưu "Người kiểm") — chỉ dùng lại email khi tài khoản chưa khai
  // đủ username/full_name ở trang Quản lý tài khoản.
  function renderAuthInto(containerId, email, displayText) {
    const el = document.getElementById(containerId);
    if (!el) return;
    el.innerHTML = email
      ? ('👤 ' + escapeHtmlAttr(displayText || email) + ' · <a href="#" class="mnb-changepw">Đổi mật khẩu</a> · <a href="#" class="mnb-signout">Đăng xuất</a>')
      : '<a href="shared/login.html">Đăng nhập</a>';
    const so = el.querySelector('.mnb-signout');
    if (so) so.addEventListener('click', (e) => { e.preventDefault(); MesAuth.signOut(); });
    const cp = el.querySelector('.mnb-changepw');
    if (cp) cp.addEventListener('click', (e) => { e.preventDefault(); openChangePasswordModal(); });
  }
  function escapeHtmlAttr(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  // Gắn cho các nút nhóm (.mnb-group-btn) — hàm này được gọi LẠI mỗi khi menu
  // được vẽ lại (VD thêm nhóm "Quản trị" cho admin ở enhanceWithAuth), vì các
  // nút đó bị tạo mới (innerHTML replace) nên cần gắn listener lại từ đầu.
  function wireGroupButtons() {
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
  }

  // Nút ☰ và listener đóng-khi-bấm-ra-ngoài gắn vào phần tử CỐ ĐỊNH (không
  // bị vẽ lại khi menu cập nhật cho admin) — chỉ gọi 1 LẦN DUY NHẤT ở init().
  // Gọi lại (như trước đây do dùng chung wireInteractions() cho cả 2 việc) sẽ
  // gắn trùng listener lên #mnbBurger → mỗi lần bấm bật rồi tắt ngay trong
  // cùng 1 sự kiện, nhìn như nút không phản ứng gì (chỉ lộ ra với tài khoản
  // admin, vì chỉ nhánh đó gọi lại hàm gắn sự kiện).
  function wireStaticInteractions() {
    document.getElementById('mnbBurger').addEventListener('click', () => {
      document.getElementById('mnbGroups').classList.toggle('open');
    });
    document.addEventListener('click', () => {
      document.querySelectorAll('.mnb-group.open').forEach(g => g.classList.remove('open'));
    });
  }

  // Trang gọi MesNav.setTitle() ngay khi script của nó chạy (VD
  // cong-doan-dashboard.html/khsx-tuan.html) — nhưng lúc đó navbar.js có thể
  // CHƯA vẽ xong thanh tiêu đề (init() đợi DOMContentLoaded nếu script này
  // được parse trước khi HTML load xong, tức luôn luôn đúng vì thẻ script
  // nằm giữa <body>). Định nghĩa MesNav NGAY (không đợi init) và nhớ tạm
  // tiêu đề nếu gọi sớm — init() sẽ áp dụng lại sau khi tạo xong thanh.
  let pendingTitle = null;
  window.MesNav = {
    setTitle(title, desc) {
      const t = document.getElementById('mnbPageTitle');
      const d = document.getElementById('mnbPageDesc');
      if (!t && !d) { pendingTitle = { title, desc }; return; }
      if (title != null && t) t.textContent = title;
      if (desc != null && d) d.textContent = desc;
    },
  };

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

    const pwMask = document.createElement('div');
    pwMask.className = 'mnb-pw-mask';
    pwMask.id = 'mnbPwMask';
    pwMask.innerHTML =
      '<div class="mnb-pw-modal">' +
        '<h3>🔑 Đổi mật khẩu</h3>' +
        // Bọc trong <form> + 1 ô "username" ẩn cho 3 ô mật khẩu bên dưới —
        // nếu không, Chrome/Edge (nhất là trên di động) coi 3 ô mật khẩu này
        // là "mồ côi" (orphan, xem cảnh báo DOM "Password field is not
        // contained in a form") và tự đoán ô văn bản GẦN NHẤT bất kỳ trên
        // trang là ô "username" để tự điền mã đăng nhập đã lưu vào đó — từng
        // gây điền nhầm mã NV vào ô "Tìm máy" ở mobile.html. Form không submit
        // thật (JS xử lý qua nút bấm), chỉ để khoanh phạm vi autofill.
        '<form id="mnbPwForm" autocomplete="off" onsubmit="return false">' +
          '<input type="text" name="username" autocomplete="username" value="" style="position:absolute;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none" tabindex="-1" aria-hidden="true">' +
          '<label for="mnbPwOld">Mật khẩu hiện tại</label>' +
          '<input type="password" id="mnbPwOld" autocomplete="current-password">' +
          '<label for="mnbPwNew">Mật khẩu mới (tối thiểu 6 ký tự)</label>' +
          '<input type="password" id="mnbPwNew" autocomplete="new-password" minlength="6">' +
          '<label for="mnbPwNew2">Nhập lại mật khẩu mới</label>' +
          '<input type="password" id="mnbPwNew2" autocomplete="new-password" minlength="6">' +
          '<div class="mnb-pw-msg" id="mnbPwMsg"></div>' +
          '<div class="mnb-pw-actions">' +
            '<button type="button" class="mnb-pw-cancel" id="mnbPwCancel">Huỷ</button>' +
            '<button type="button" class="mnb-pw-submit" id="mnbPwSubmit">Đổi mật khẩu</button>' +
          '</div>' +
        '</form>' +
      '</div>';
    document.body.appendChild(pwMask);
    document.getElementById('mnbPwCancel').addEventListener('click', closeChangePasswordModal);
    pwMask.addEventListener('click', (e) => { if (e.target === pwMask) closeChangePasswordModal(); });
    document.getElementById('mnbPwSubmit').addEventListener('click', submitChangePassword);

    // Vẽ menu + gắn sự kiện click NGAY — không đợi mạng/đăng nhập, để menu
    // luôn bấm được dù kiểm tra quyền admin bên dưới chậm hoặc treo (kiểm tra
    // quyền chỉ ảnh hưởng việc CÓ THÊM nhóm "Quản trị" hay không, không phải
    // điều kiện để menu hiển thị được).
    const cur = currentFile();
    document.getElementById('mnbGroups').innerHTML = groupsHtml(MENU, cur) + '<div class="mnb-auth-mobile" id="mnbAuthMobile"></div>';
    renderAuthInto('mnbAuth', null);
    renderAuthInto('mnbAuthMobile', null);
    wireGroupButtons();
    wireStaticInteractions();

    // Thanh tiêu đề chuẩn hoá — thay header tự viết riêng (không đồng nhất)
    // ở từng trang. Trang không có trong PAGE_META (hiếm) thì không vẽ gì,
    // giữ nguyên header cũ của trang đó thay vì hiện rỗng.
    const meta = PAGE_META[cur];
    if (meta && !meta.noTitleBar) {
      const titleBar = document.createElement('div');
      titleBar.className = 'mnb-title-bar';
      titleBar.innerHTML =
        '<span class="mnb-title-icon">' + (meta.icon || '') + '</span>' +
        '<h1 class="mnb-page-title" id="mnbPageTitle">' + meta.title + '</h1>' +
        '<span class="mnb-page-desc" id="mnbPageDesc">' + (meta.desc || '') + '</span>';
      bar.after(titleBar);
      if (pendingTitle) { window.MesNav.setTitle(pendingTitle.title, pendingTitle.desc); pendingTitle = null; }
    }

    // Tăng cường sau: thêm nhóm "Quản trị" nếu là admin, cập nhật ô đăng nhập
    // — chạy nền, không chặn menu chính.
    enhanceWithAuth(cur);
  }

  async function enhanceWithAuth(cur) {
    let email = null;
    let identity = null;
    try {
      email = await MesAuth.getCurrentUserEmail();
      if (email) {
        identity = await MesAuth.getCurrentUserIdentity();
        const session = await MesAuth.getSession();
        const { data: myRow } = await sb.from('user_roles').select('role').eq('user_id', session.user.id).maybeSingle();
        if (myRow) {
          if (myRow.role === 'admin') {
            document.getElementById('mnbGroups').innerHTML = groupsHtml(MENU.concat([ADMIN_MENU]), cur) + '<div class="mnb-auth-mobile" id="mnbAuthMobile"></div>';
            wireGroupButtons();
          }
        }
      }
    } catch (e) { /* không chặn menu nếu lỗi tra quyền — chỉ không thêm nhóm Quản trị */ }
    renderAuthInto('mnbAuth', email, identity);
    renderAuthInto('mnbAuthMobile', email, identity);
  }

  function openChangePasswordModal(){
    ['mnbPwOld', 'mnbPwNew', 'mnbPwNew2'].forEach(id => { document.getElementById(id).value = ''; });
    const msg = document.getElementById('mnbPwMsg');
    msg.className = 'mnb-pw-msg'; msg.textContent = '';
    document.getElementById('mnbPwMask').classList.add('open');
    setTimeout(() => document.getElementById('mnbPwOld').focus(), 50);
  }
  function closeChangePasswordModal(){
    document.getElementById('mnbPwMask').classList.remove('open');
  }
  async function submitChangePassword(){
    const oldPw = document.getElementById('mnbPwOld').value;
    const newPw = document.getElementById('mnbPwNew').value;
    const newPw2 = document.getElementById('mnbPwNew2').value;
    const msg = document.getElementById('mnbPwMsg');
    const btn = document.getElementById('mnbPwSubmit');
    if (!oldPw || !newPw) { msg.className = 'mnb-pw-msg err'; msg.textContent = 'Nhập đủ mật khẩu hiện tại và mật khẩu mới.'; return; }
    if (newPw.length < 6) { msg.className = 'mnb-pw-msg err'; msg.textContent = 'Mật khẩu mới cần tối thiểu 6 ký tự.'; return; }
    if (newPw !== newPw2) { msg.className = 'mnb-pw-msg err'; msg.textContent = 'Mật khẩu mới nhập lại không khớp.'; return; }
    btn.disabled = true;
    msg.className = 'mnb-pw-msg'; msg.textContent = '';
    try {
      await MesAuth.changePassword(oldPw, newPw);
      msg.className = 'mnb-pw-msg ok'; msg.textContent = '✓ Đã đổi mật khẩu.';
      setTimeout(closeChangePasswordModal, 1200);
    } catch (e) {
      msg.className = 'mnb-pw-msg err'; msg.textContent = 'Lỗi: ' + e.message;
    } finally {
      btn.disabled = false;
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
