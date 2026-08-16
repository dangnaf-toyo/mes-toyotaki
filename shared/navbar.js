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
      { label: 'Nhập liệu di động', href: 'mobile.html' },
      { label: 'In tem', href: 'intem.html' },
      { label: 'Kế hoạch bảo dưỡng khuôn', href: 'bao-duong-khuon-tuan.html' },
      { label: 'Dashboard công đoạn', href: 'cong-doan-dashboard.html' },
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

  const CSS = `
:root{--navbar-h:50px}
body{padding-top:var(--navbar-h)}
.mnb-bar{position:fixed;top:0;left:0;right:0;z-index:5000;background:#211a15;color:#F7F1E7;
  height:var(--navbar-h);display:flex;align-items:center;padding:0 6px 0 14px;gap:6px;
  box-shadow:0 2px 8px rgba(0,0,0,.15);font-family:Arial,Helvetica,sans-serif}
.mnb-logo{font-weight:800;font-size:14px;letter-spacing:.03em;color:#fff;text-decoration:none;flex-shrink:0;white-space:nowrap}
.mnb-logo span{color:#C87941}
.mnb-groups{display:flex;gap:2px;flex:1;overflow-x:auto;height:100%}
.mnb-group{position:relative;flex-shrink:0}
.mnb-group-btn{background:none;border:none;color:#e8e0d5;font-size:12.5px;font-weight:700;
  padding:0 10px;height:var(--navbar-h);cursor:pointer;white-space:nowrap;display:flex;align-items:center;gap:4px;font-family:inherit}
.mnb-group-btn:hover,.mnb-group.route-active .mnb-group-btn{color:#fff;background:rgba(255,255,255,.09)}
.mnb-caret{font-size:9px;opacity:.7}
.mnb-dropdown{display:none;position:absolute;top:100%;left:0;background:#fff;border-radius:0 0 8px 8px;
  box-shadow:0 8px 20px rgba(0,0,0,.22);min-width:230px;padding:6px;flex-direction:column;z-index:5001}
.mnb-group:hover .mnb-dropdown{display:flex}
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
    document.querySelectorAll('.mnb-group-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        if (window.innerWidth > 820) return; // desktop: hover lo dropdown, không cần bấm
        btn.parentElement.classList.toggle('mobile-open');
      });
    });
  }

  async function init() {
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

    let groups = MENU;
    let email = null;
    try {
      email = await MesAuth.getCurrentUserEmail();
      if (email) {
        const session = await MesAuth.getSession();
        const { data: myRole } = await sb.from('user_roles').select('role').eq('user_id', session.user.id).maybeSingle();
        if (myRole && myRole.role === 'admin') groups = MENU.concat([ADMIN_MENU]);
      }
    } catch (e) { /* không chặn hiện menu nếu lỗi tra quyền — chỉ không hiện nhóm Quản trị */ }

    const cur = currentFile();
    document.getElementById('mnbGroups').innerHTML = groupsHtml(groups, cur) + '<div class="mnb-auth-mobile" id="mnbAuthMobile"></div>';
    renderAuthInto('mnbAuth', email);
    renderAuthInto('mnbAuthMobile', email);
    wireInteractions();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
