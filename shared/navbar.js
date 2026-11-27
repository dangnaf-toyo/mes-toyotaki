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
  // T189: bảng dài — cố định tiêu đề + nút lọc từng cột (shared/bang-dai.js), cả khi nhúng.
  if (document.currentScript && !window.BangDai) {
    const s = document.createElement('script');
    s.src = document.currentScript.src.replace(/navbar\.js(\?.*)?$/, 'bang-dai.js');
    document.head.appendChild(s);
  }
  // T261: hộp duyệt có ô ghi chú (shared/ghi-chu-duyet.js → window.hoiGhiChuDuyet) cho mọi màn phê duyệt.
  if (document.currentScript && !window.hoiGhiChuDuyet) {
    const s = document.createElement('script');
    s.src = document.currentScript.src.replace(/navbar\.js(\?.*)?$/, 'ghi-chu-duyet.js');
    document.head.appendChild(s);
  }
  // T255 (X.1): hộp alert của trình duyệt → thông báo góc màn hình (không chặn thao tác) cho MỌI trang có navbar.
  // Trang đã tự thay alert (vd ipqc-approval.html) thì giữ bản của trang. hộp confirm giữ nguyên (xoá/kết ca/không hoàn tác).
  // Tin có ⛔ hoặc dài thì không tự tắt — bấm × để đóng. Tin hiện ngay trước khi tải lại/chuyển trang được mang sang trang sau.
  if (/\[native code\]/.test(String(window.alert))) {
    const KEY = 'mesThongBaoGoc';
    let hop = null, giuLai = [];
    const veHop = () => {
      if (hop) return hop;
      const st = document.createElement('style');
      st.textContent =
        '#mesTbg{position:fixed;right:16px;bottom:16px;z-index:100000;display:flex;flex-direction:column;gap:8px;max-width:min(420px,calc(100vw - 32px));pointer-events:none}' +
        '#mesTbg .t{pointer-events:auto;display:flex;gap:10px;align-items:flex-start;background:#14181F;color:#fff;border-radius:8px;padding:10px 12px;font:500 14px/1.45 Inter,system-ui,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,.25);border-left:4px solid #3B82F6;white-space:pre-line;word-break:break-word}' +
        '#mesTbg .t.loi{border-left-color:#DC2626}#mesTbg .t.ok{border-left-color:#16A34A}' +
        '#mesTbg .t span{flex:1}#mesTbg .t button{background:none;border:0;color:#CBD5E1;font-size:18px;line-height:1;cursor:pointer;padding:0 2px}' +
        '@media print{#mesTbg{display:none}}';
      document.head.appendChild(st);
      hop = document.createElement('div');
      hop.id = 'mesTbg'; hop.setAttribute('role', 'status'); hop.setAttribute('aria-live', 'polite');
      document.body.appendChild(hop);
      document.addEventListener('close', (e) => { if (e.target.contains && e.target.contains(hop)) document.body.appendChild(hop); }, true);
      return hop;
    };
    const hien = (msg) => {
      const s = String(msg ?? '').trim();
      if (!s) return;
      if (!document.body) { document.addEventListener('DOMContentLoaded', () => hien(s), { once: true }); return; }
      const loi = /⛔|❌|lỗi|không (được|thể|có quyền)|thất bại|chưa (chọn|nhập|có)|vui lòng|cần /i.test(s);
      const ok = !loi && /✅|✓|đã (lưu|gửi|xoá|xóa|cập nhật|tạo|duyệt|ghi)|thành công/i.test(s);
      const dinh = s.includes('⛔') || s.length > 160;
      const t = document.createElement('div');
      t.className = 't' + (loi ? ' loi' : ok ? ' ok' : '');
      t.innerHTML = '<span></span><button type="button" aria-label="Đóng">×</button>';
      t.firstChild.textContent = s;
      const dong = () => { t.remove(); giuLai = giuLai.filter(x => x.t !== t); };
      t.lastChild.onclick = dong;
      const h = veHop();
      // Đang mở hộp sửa (dialog dạng modal) → đặt thông báo bên trong hộp để không bị lớp phủ che.
      const dlg = [...document.querySelectorAll('dialog[open]')].reverse().find(d => { try { return d.matches(':modal'); } catch (e) { return false; } });
      const cha = dlg || document.body;
      if (h.parentNode !== cha) cha.appendChild(h);
      h.appendChild(t);
      while (h.children.length > 4) h.firstChild.remove();
      const muc = { t, s, luc: Date.now() };
      giuLai.push(muc);
      if (!dinh) setTimeout(dong, Math.min(12000, 4000 + s.length * 50));
    };
    window.alert = hien;
    window.addEventListener('pagehide', () => {
      const con = giuLai.filter(x => Date.now() - x.luc < 3000).map(x => x.s);
      try { if (con.length) sessionStorage.setItem(KEY, JSON.stringify(con)); } catch (e) {}
    });
    try {
      const cu = JSON.parse(sessionStorage.getItem(KEY) || '[]');
      sessionStorage.removeItem(KEY);
      cu.forEach(hien);
    } catch (e) {}
  }
  // T208: trang nhúng trong tab quản trị (vd bom.html?embed=1 trong Quản lý danh mục) không cần thanh menu thứ hai.
  if (new URLSearchParams(location.search).has('embed')) return;
  const MENU = [
    { label: 'Điều hành & Báo cáo', items: [
      { label: 'Dashboard Sản lượng', href: 'sanluong-supabase.html' },
      { label: 'Dashboard Chất lượng', href: 'chatluong-supabase.html' },
      { label: 'Báo cáo kết ca', href: 'bao-cao-ca.html' },
      { label: 'Báo cáo cuối ca công đoạn', href: 'cong-doan-bao-cao-ca.html' },
      { label: 'Báo cáo sản xuất tuần', href: 'bao-cao-tuan.html' },
      { label: 'Kế hoạch tuần', href: 'khsx-tuan.html' },
      { label: 'Forecast sản lượng năm', href: 'forecast-san-luong.html' },
    ] },
    // T161: module Quản lý công việc.
    { label: 'Công việc', items: [
      { label: 'Việc của tôi', href: 'cong-viec-cua-toi.html' },
      { label: 'Bảng công việc', href: 'cong-viec.html' },
      { label: 'Giao việc mới', href: 'cong-viec-giao.html' },
      { label: 'Thông báo', href: 'thong-bao.html' },
    ] },
    { label: 'Sản xuất', items: [
      { label: 'Bảng điều khiển Đúc', href: 'duc-dashboard.html' },
      { label: 'Bảng điều khiển Bavia', href: 'bavia-dashboard.html' },
      { label: 'Bảng điều khiển Gia công', href: 'gia-cong-dashboard.html' },
      { label: 'Bảng điều khiển Sơn', href: 'cong-doan-dashboard.html?cd=S%C6%A1n' },
      { label: 'Bảng điều khiển OQC', href: 'cong-doan-dashboard.html?cd=OQC' },
      // T246: chỉ hiện trên điện thoại (màn rút gọn 1 máy / màn hình).
      { label: 'Nhập liệu di động', href: 'mobile.html', mobileOnly: true },
      // T246: In tem + Tra cứu tem đã in = 1 mục, 2 tab.
      { label: 'In tem', href: 'intem.html', subTabs: 'in_tem' },
      { label: 'Ghi nhận thùng thành phẩm', href: 'ghi-nhan-tem-thanh-pham.html' },
      // T137: 1 mục "Tổ khuôn" — các trang con hiện dải tab (SUB_TABS bên dưới).
      { label: 'Tổ khuôn', href: 'bao-duong-khuon-tuan.html', subTabs: 'to_khuon' },
      // T329: Điều kiện đúc bỏ khỏi menu — mở bằng nút "ĐK đúc" ở Bảng điều khiển Đúc.
      // T330: Dụng cụ đúc bỏ khỏi menu — mở bằng nút "Dụng cụ" ở Bảng điều khiển Đúc.
      // T246: Chuyển công đoạn + Đóng gói Pallet = 1 mục, 2 tab.
      { label: 'Chuyển công đoạn / Đóng gói', href: 'chuyencongdoan.html', subTabs: 'chuyen_dong_goi' },
    ] },
    { label: 'Chất lượng', items: [
      { label: 'IPQC Đúc', href: 'ipqc.html' },
      { label: 'IPQC Gia công', href: 'ipqc-gia-cong.html' },
      { label: 'Duyệt tiếp tục SX IPQC', href: 'ipqc-approval.html' },
      { label: 'IQC đầu vào', href: 'iqc.html' },
      { label: 'OQC kiểm tra', href: 'oqc-daily.html' },
      { label: 'QC Manager / NCP', href: 'qc-manager.html' },
      { label: 'Biểu đồ chất lượng', href: 'bieu-do-chat-luong.html' },
    ] },
    { label: 'Kho & Truy xuất', items: [
      { label: 'Kho NVL', href: 'nvl.html' },
      { label: 'Kho dao cụ', href: 'dao-cu.html' },   // T272
      { label: 'Kho thành phẩm', href: 'kho-thanh-pham.html' },
      { label: 'Truy xuất nguồn gốc', href: 'truy-xuat-nguon-goc.html' },
      { label: 'Lịch sử quét tem', href: 'lich-su-quet-tem.html' },   // T350
      { label: 'Tồn theo công đoạn', href: 'ton-cong-doan.html' },   // T374
    ] },
    { label: 'QMS · Tài liệu', items: [
      { label: 'Tài liệu kỹ thuật', href: 'tai-lieu-danh-muc.html' },
      { label: 'BOM sản phẩm', href: 'bom.html' },
      { label: 'Tài liệu hệ thống', href: 'tai-lieu-he-thong.html' },
      { label: 'Phiếu thay đổi tài liệu', href: 'danh-sach-phieu-thay-doi.html' },
      { label: 'Tài liệu bên ngoài', href: 'tai-lieu-ben-ngoai.html' },
      { label: 'Cung cấp tài liệu ra ngoài', href: 'cung-cap-tai-lieu-ra-ngoai.html' },
      { label: 'Cấu hình kiểm soát tài liệu', href: 'cau-hinh-tai-lieu.html' },
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
    'dieu-kien-duc.html': { icon: '⚙', title: 'Điều kiện đúc', desc: 'Phiếu điều kiện đúc theo Mã SP × Máy: lập, kiểm tra, duyệt', noTitleBar: true },   // T320
    'dung-cu-duc.html': { icon: '🔩', title: 'Dụng cụ đúc', desc: 'Từng cái đầu típ, ống liệu, piston: đang lắp máy nào, đã bắn bao nhiêu', noTitleBar: true },   // T325
    'diem-thay-doi.html': { icon: '±', title: 'Điểm thay đổi Đúc', desc: 'Thay đổi chủ động: duyệt, IPQC sau thay đổi, lịch sử', noTitleBar: true },   // T307
    'mobile.html': { icon: '📱', title: 'Nhập liệu di động — Đúc', desc: 'Bản rút gọn cho điện thoại, 1 máy/màn hình' },
    'ipqc.html': { icon: '🔎', title: 'IPQC Đúc', desc: 'Hàng đợi điểm kiểm, nộp kết quả kèm ảnh', noTitleBar: true },
    'ipqc-gia-cong.html': { icon: '📐', title: 'IPQC Gia công', desc: 'Nhập kết quả và dashboard IPQC Gia công', noTitleBar: true },
    'ipqc-approval.html': { icon: '⚠️', title: 'Duyệt tiếp tục SX IPQC', desc: 'Tạo, duyệt và theo dõi yêu cầu tiếp tục chạy có điều kiện', noTitleBar: true },
    'iqc.html': { icon: '📋', title: 'IQC đầu vào', desc: 'Theo dõi LOT, nhà cung cấp, lỗi và tỷ lệ NG theo thời gian', noTitleBar: true },
    'oqc-daily.html': { icon: '✅', title: 'OQC kiểm tra', desc: 'Dashboard · CAPA · kế hoạch và hiệu suất kiểm tra', noTitleBar: true },
    'oqc-capacity.html': { icon: '⏱', title: 'Định mức kiểm tra QC', desc: 'Kế hoạch kiểm tra · Hiệu suất kế hoạch 80%', noTitleBar: true },
    'chuyencongdoan.html': { icon: '🔀', title: 'Chuyển công đoạn', desc: 'Quét QR chuyển hàng, đóng gói lại, đổi mã SP', noTitleBar: true },
    'oqc.html': { icon: '📦', title: 'Đóng gói Pallet', desc: 'Quét tem, gom pallet, đóng gói — dùng cho mọi công đoạn cuối trước nhập kho', noTitleBar: true },
    'kho-thanh-pham.html': { icon: '🏬', title: 'Kho thành phẩm', desc: 'Nhập kho / Xuất hàng bằng QR', noTitleBar: true },
    'truy-xuat-nguon-goc.html': { icon: '🔍', title: 'Truy xuất nguồn gốc', desc: 'Phả hệ tem: tách/gộp xuyên công đoạn', noTitleBar: true },
    'lich-su-quet-tem.html': { icon: '🕒', title: 'Lịch sử quét tem', desc: 'Giờ quét tem trong ngày — mọi công đoạn', noTitleBar: true },
    'ton-cong-doan.html': { icon: '📦', title: 'Tồn theo công đoạn', desc: 'Tồn từng mã sản phẩm ở từng công đoạn', noTitleBar: true },   // T374
    'tra-cuu-tem.html': { icon: '🏷️', title: 'Tra cứu tem đã in', desc: 'Danh sách tem — lọc theo ngày in/máy/mã SP', noTitleBar: true },
    'cong-doan-bao-cao-ca.html': { icon: '📋', title: 'Báo cáo cuối ca công đoạn', desc: 'Bavia / Gia công / Cắt viền / Đánh bóng Kẽm / Sơn / OQC', noTitleBar: true },
    'cong-doan-dashboard.html': { icon: '🏭', title: 'Bảng điều khiển công đoạn', desc: 'Trạm/line/máy, sản lượng OK/NG real-time', noTitleBar: true },
    'bao-duong-khuon-tuan.html': { icon: '🔧', title: 'Tổ khuôn', desc: 'KH bảo dưỡng khuôn tuần + xử lý bất thường A2/B1/F1', noTitleBar: true },
    'forecast-san-luong.html': { icon: '📈', title: 'Forecast sản lượng năm', desc: 'Dự báo sản lượng từng mã SP theo tháng — giờ máy, tuổi thọ khuôn', noTitleBar: true },
    'van-de-khuon.html': { icon: '⚠', title: 'Vấn đề khuôn', desc: 'Vấn đề khuôn chưa đóng, lịch sử sự cố + IPQC của khuôn', noTitleBar: true },
    'linh-kien-khuon.html': { icon: '🔩', title: 'Linh kiện dự phòng khuôn', desc: 'Danh mục, tồn kho, gán khuôn, lịch sử nhập / xuất thay', noTitleBar: true },
    'bao-cao-to-khuon-tuan.html': { icon: '📊', title: 'Báo cáo tuần tổ khuôn', desc: 'KH bảo dưỡng, vấn đề khuôn, sự cố, linh kiện, theo người — biểu đồ QC', noTitleBar: true },
    'quan-ly-khuon.html': { icon: '🧊', title: 'Quản lý khuôn', desc: 'Danh sách khuôn, vấn đề khuôn, hạng mục check sheet bảo dưỡng', noTitleBar: true },
    'checksheet-bao-duong-khuon.html': { icon: '📋', title: 'Check sheet bảo dưỡng khuôn', desc: 'Ghi kết quả bảo dưỡng từng khuôn theo hạng mục', noTitleBar: true },
    'khsx-tuan.html': { icon: '📅', title: 'Kế hoạch sản xuất tuần', desc: 'Đúc / Bavia / Gia công / Cắt viền / Đánh bóng Kẽm / Sơn / OQC — 1 màn hình, chuyển tab', noTitleBar: true },
    'phieu-cap-nvl.html': { icon: '📝', title: 'Phiếu cấp NVL', desc: 'Đề nghị cấp NVL: Thống kê lập, QL bộ phận xác nhận, kho cấp, GĐ hành chính duyệt', noTitleBar: true },
    'xnt-nvl.html': { icon: '📊', title: 'Xuất nhập tồn NVL', desc: 'Báo cáo tồn đầu, nhập, xuất, tồn cuối từng mã NVL theo khoảng ngày', noTitleBar: true },
    'nvl.html': { icon: '🧪', title: 'Kho NVL', desc: 'Theo dõi tồn, in tem QR, quét nhập/xuất', noTitleBar: true },
    'dao-cu.html': { icon: '🔪', title: 'Kho dao cụ', desc: 'Dao cụ Gia công: danh mục, tồn Mới / Đang dùng / NG, phiếu nhập xuất', noTitleBar: true },
    'intem.html': { icon: '🏷️', title: 'In tem', desc: 'Tạo/tra cứu tem Đúc, chỉ thị Kanban, tem thành phẩm', noTitleBar: true },
    'ghi-nhan-kanban.html': { icon: '📥', title: 'Ghi nhận thùng (Kanban)', desc: 'Quét QR ghi nhận thùng sản phẩm đã sản xuất — máy chạy theo tem chỉ thị in trước' },
    'gia-cong-dashboard.html': { icon: '⚙️', title: 'Bảng điều khiển Gia công', desc: '30 máy CNC: quét tem thùng, NG, hàng test, dừng máy, kết ca', noTitleBar: true },
    'bavia-dashboard.html': { icon: '🛠️', title: 'Bảng điều khiển Bavia', desc: 'Line Bavia: khai báo tem Đúc, NG, hàng test, đóng thùng in tem xuất hàng / quét tem thùng', noTitleBar: true },
    'bavia-tem-xuat-hang.html': { icon: '🏷️', title: 'Tem xuất hàng Bavia', desc: 'Quét QR tem Đúc ghi nhận sản lượng Bavia — đủ thùng in tem xuất hàng theo mẫu khách (FCC / Astemo / Soji / Mikasa / Cosmos)' },
    'ghi-nhan-tem-thanh-pham.html': { icon: '📦', title: 'Ghi nhận thùng thành phẩm', desc: 'Quét QR tem thành phẩm in trước — tự trừ nguồn từ tem Đúc, truy xuất nguồn gốc' },
    'qc-manager.html': { icon: '🔬', title: 'QC Manager / NCP', desc: 'Giám sát real-time, xử lý SP không phù hợp', noTitleBar: true },
    'bieu-do-chat-luong.html': { icon: '📈', title: 'Biểu đồ chất lượng', desc: 'Biểu đồ kiểm soát kích thước IPQC · P-Chart NG OQC', noTitleBar: true },
    'quan-ly-danh-muc.html': { icon: '⚙️', title: 'Danh mục', desc: 'Máy, sản phẩm, nhân sự, khuôn — chỉ Admin', noTitleBar: true },
    'tai-lieu-danh-muc.html': { icon: '📁', title: 'Tài liệu kỹ thuật', desc: 'Bản vẽ SP/khuôn, dữ liệu báo giá, KQ sản xuất thử, Jig - đồ gá, LK dự phòng khuôn, dưỡng kiểm, QCP, tiêu chuẩn — theo mã SP', noTitleBar: true },
    'tai-lieu-chi-tiet.html': { icon: '📄', title: 'Chi tiết tài liệu kỹ thuật', desc: 'Xem view-only, tải bản gốc CAD (nếu có quyền), quản lý phiên bản', noTitleBar: true },
    'tai-lieu-he-thong.html': { icon: '📘', title: 'Tài liệu hệ thống', desc: 'Sổ tay chất lượng, thủ tục, phương pháp/tiêu chuẩn, biểu mẫu — theo cấp 1-4', noTitleBar: true },
    'phieu-thay-doi-tai-lieu.html': { icon: '📝', title: 'Lập phiếu thay đổi tài liệu', desc: 'Tạo mới / sửa đổi / huỷ tài liệu — tự tính tầng rủi ro A/B/C', noTitleBar: true },
    'phieu-thay-doi-chi-tiet.html': { icon: '📝', title: 'Chi tiết phiếu thay đổi tài liệu', desc: 'Xác nhận theo bộ phận, duyệt theo tầng, phát hành', noTitleBar: true },
    'danh-sach-phieu-thay-doi.html': { icon: '📋', title: 'Phiếu thay đổi tài liệu', desc: 'Việc của tôi, toàn bộ phiếu theo tầng/trạng thái', noTitleBar: true },
    'tai-lieu-ben-ngoai.html': { icon: '📥', title: 'Tài liệu bên ngoài', desc: 'Tiếp nhận, bảng kiểm 7 mục, duyệt áp dụng', noTitleBar: true },
    'cung-cap-tai-lieu-ra-ngoai.html': { icon: '📤', title: 'Cung cấp tài liệu ra ngoài', desc: 'Ghi nhận cung cấp tài liệu nội bộ/bên ngoài cho khách hàng, NCC', noTitleBar: true },
    'cau-hinh-tai-lieu.html': { icon: '⚙️', title: 'Cấu hình kiểm soát tài liệu', desc: '16 tham số, ủy quyền duyệt, mức mật, chỉ số — chỉ Admin', noTitleBar: true },
    'nang-luc-cnc.html': { icon: '🛠️', title: 'Năng lực máy CNC', desc: 'Quy trình CNC theo SP, forecast tháng, tính số máy cần — chỉ Admin', noTitleBar: true },
    'quan-ly-tai-khoan.html': { icon: '👤', title: 'Tài khoản', desc: 'Tạo tài khoản, phân quyền — chỉ Admin', noTitleBar: true },
    'ncp-detail.html': { icon: '📝', title: 'Chi tiết NCP', desc: 'Nguyên nhân & Đối sách', noTitleBar: true },
    'bao-cao-ca.html': { icon: '🗂️', title: 'Báo cáo kết ca', desc: 'Tra cứu báo cáo đã lưu theo ngày/ca', noTitleBar: true },
    'bao-cao-tuan.html': { icon: '📅', title: 'Báo cáo sản xuất tuần', desc: 'KPI, dừng máy, vấn đề & hành động đối ứng — theo tuần bất kỳ', noTitleBar: true },
    'bom.html': { icon: '🧾', title: 'BOM sản phẩm', desc: 'Định mức kim loại theo shot, vật tư theo công đoạn, duyệt phiên bản', noTitleBar: true },
    'sanluong-supabase.html': { icon: '📊', title: 'Dashboard Sản lượng', desc: 'Tỷ lệ giao hàng, hoàn thành KHSX, forecast', noTitleBar: true },
    'chatluong-supabase.html': { icon: '📈', title: 'Dashboard Chất lượng', desc: 'Tổng quan, theo công đoạn, theo khách hàng', noTitleBar: true },
    // T161: Quản lý công việc
    'cong-viec-cua-toi.html': { icon: '✅', title: 'Việc của tôi', desc: 'Việc tôi làm, tôi giao, chờ tôi duyệt — quá hạn, hôm nay, tuần này', noTitleBar: true },
    'cong-viec.html': { icon: '🗂️', title: 'Bảng công việc', desc: 'Kanban theo trạng thái · ma trận ưu tiên Quan trọng × Gấp', noTitleBar: true },
    'cong-viec-chi-tiet.html': { icon: '📄', title: 'Chi tiết công việc', desc: 'Các bước, tệp/ảnh, trao đổi & góp ý, lịch sử', noTitleBar: true },
    'cong-viec-giao.html': { icon: '➕', title: 'Giao việc', desc: 'Giao việc mới hoặc sửa việc — người làm, hạn, mức ưu tiên, các bước', noTitleBar: true },
    'cong-viec-nhap-excel.html': { icon: '📥', title: 'Giao việc từ Excel', desc: 'Giao nhiều việc cùng lúc từ biên bản họp (file mẫu Excel) — gom theo cuộc họp để theo dõi', noTitleBar: true },
    'thong-bao.html': { icon: '🔔', title: 'Thông báo', desc: 'Thông báo công việc — chưa đọc, cần tôi xử lý', noTitleBar: true },
  };

  // T137: nhóm trang dùng chung 1 bộ tab. Tab đầu = trang mặc định của mục
  // menu; "also" = trang phụ (mở từ trong tab) vẫn tô sáng mục menu. Tab vẽ vào
  // chỗ đặt sẵn trong header tối của trang: <nav data-subtabs="to_khuon"></nav>.
  const SUB_TABS = {
    to_khuon: { label: 'Tổ khuôn', tabs: [
      { label: 'Dashboard tổ khuôn', href: 'bao-duong-khuon-tuan.html', also: ['checksheet-bao-duong-khuon.html'] },
      { label: 'Quản lý khuôn', href: 'quan-ly-khuon.html', also: ['van-de-khuon.html'] },
      { label: 'Linh kiện dự phòng khuôn', href: 'linh-kien-khuon.html' },
      { label: 'Báo cáo tuần', href: 'bao-cao-to-khuon-tuan.html' },   // T193
    ] },
    in_tem: { label: 'In tem', tabs: [
      { label: 'In tem', href: 'intem.html' },
      { label: 'Tra cứu tem đã in', href: 'tra-cuu-tem.html' },
    ] },
    chuyen_dong_goi: { label: 'Chuyển công đoạn / Đóng gói', tabs: [
      { label: 'Chuyển công đoạn', href: 'chuyencongdoan.html' },
      { label: 'Đóng gói Pallet', href: 'oqc.html' },
    ] },
  };
  function subTabPages(key) {
    const g = SUB_TABS[key]; if (!g) return [];
    return g.tabs.reduce((a, t) => a.concat([t.href], t.also || []), []);
  }
  function subGroupOf(cur) {
    return Object.keys(SUB_TABS).find(k => subTabPages(k).includes(cur)) || null;
  }

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
.mnb-caret{font-size:11px;opacity:.7}
.mnb-dropdown{display:none;position:absolute;top:100%;left:0;background:#fff;border-radius:0 0 8px 8px;
  box-shadow:0 8px 20px rgba(0,0,0,.22);min-width:230px;padding:6px;flex-direction:column;z-index:5001}
.mnb-group:hover .mnb-dropdown,.mnb-group.open .mnb-dropdown{display:flex}
.mnb-item{padding:9px 12px;border-radius:6px;color:#333;text-decoration:none;font-size:13px;font-weight:600}
.mnb-item:hover{background:#faf5f0;color:#C87941}
.mnb-item.route-active{background:#f5e6d7;color:#a85e2a}
.mnb-item.mnb-mobile-only{display:none}
.mnb-folder{padding:9px 12px;border-radius:6px;color:#333;font-size:13px;font-weight:600;cursor:default}
.mnb-auth{flex-shrink:0;font-size:11.5px;color:#c9c2b6;display:flex;align-items:center;gap:8px;white-space:nowrap;padding-right:6px}
.mnb-auth a{color:#C87941;text-decoration:none;font-weight:700}
.mnb-burger{display:none;background:none;border:none;color:#fff;font-size:19px;cursor:pointer;padding:0 6px;flex-shrink:0;min-width:40px;min-height:40px}
.mnb-auth-mobile{display:none}
.mnb-bell{display:none;position:relative;flex-shrink:0;width:40px;height:40px;border-radius:8px;align-items:center;justify-content:center;color:#e8e0d5;text-decoration:none}
.mnb-bell.on{display:inline-flex}
.mnb-bell:hover,.mnb-bell:focus-visible{color:#fff;background:rgba(255,255,255,.09)}
.mnb-bell.route-active{color:#C87941}
.mnb-bell svg{display:block}
.mnb-bell-n{position:absolute;top:2px;right:1px;min-width:17px;height:17px;padding:0 4px;border-radius:9px;background:#DC2626;color:#fff;font-size:11px;font-weight:700;line-height:17px;text-align:center;box-shadow:0 0 0 2px #211a15;box-sizing:border-box}
.mnb-bell-n[hidden]{display:none}
.mnb-fs{display:inline-flex;flex-shrink:0;width:40px;height:40px;border-radius:8px;align-items:center;justify-content:center;background:none;border:none;color:#e8e0d5;cursor:pointer;padding:0}
.mnb-fs:hover,.mnb-fs:focus-visible{color:#fff;background:rgba(255,255,255,.09)}
.mnb-fs svg{display:block}
.mnb-fs[hidden]{display:none}
@media (max-width:820px){
  .mnb-bell{margin-left:auto}
  .mnb-fs{margin-left:auto}
  .mnb-bell.on + .mnb-fs{margin-left:0}
  .mnb-groups{display:none;position:fixed;top:var(--navbar-h);left:0;right:0;bottom:0;
    background:#fff;flex-direction:column;overflow-y:auto;padding:8px;z-index:4999}
  .mnb-groups.open{display:flex}
  .mnb-group{width:100%}
  .mnb-group-btn{width:100%;color:#8a5a30;height:auto;padding:12px 8px;justify-content:space-between;border-bottom:1px solid #f0e6d8}
  .mnb-group-btn:hover,.mnb-group.route-active .mnb-group-btn{color:#8a5a30;background:#faf5f0}
  .mnb-dropdown{display:none;position:static;box-shadow:none;padding:0 0 6px 12px;min-width:0}
  .mnb-group.mobile-open .mnb-dropdown{display:flex}
  .mnb-item.mnb-mobile-only{display:block}
  .mnb-burger{display:block}
  .mnb-auth{display:none}
  .mnb-auth-mobile{display:flex;margin-top:8px;padding:12px 8px;border-top:2px solid #f0e6d8;font-size:12.5px;color:#666}
}
[data-subtabs]{display:flex;gap:6px;flex-wrap:wrap}
.mnb-htab{background:transparent;border:1px solid #475569;color:#CBD5E1;padding:6px 14px;border-radius:6px;font-size:12px;font-weight:600;text-decoration:none;min-height:32px;box-sizing:border-box;display:inline-flex;align-items:center;white-space:nowrap}
.mnb-htab:hover{background:#334155;color:#fff}
.mnb-htab.route-active{background:#0F5FA5;border-color:#0F5FA5;color:#fff}
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

  function itemActive(it, cur) {
    if (!it.href) return false;
    return it.href.toLowerCase() === cur || (!!it.subTabs && subTabPages(it.subTabs).includes(cur));
  }

  function groupsHtml(groups, cur) {
    return groups.map(g => {
      const itemsHtml = g.items.map(it => it.folder
        ? `<div class="mnb-folder" title="Thư mục Bom">${it.label}</div>`
        : `<a href="${it.href}" class="mnb-item${it.mobileOnly ? ' mnb-mobile-only' : ''}${itemActive(it, cur) ? ' route-active' : ''}">${it.label}</a>`
      ).join('');
      const groupActive = g.items.some(it => itemActive(it, cur));
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
      BELL_HTML + FS_HTML +
      '<div class="mnb-auth" id="mnbAuth">…</div>';
    document.body.insertBefore(bar, document.body.firstChild);
    ganNutToanManHinh();

    if (typeof IS_STAGING !== 'undefined' && IS_STAGING) {
      const stagingBanner = document.createElement('div');
      stagingBanner.textContent = '⚠️ MÔI TRƯỜNG STAGING — dữ liệu thử nghiệm, KHÔNG dùng cho sản xuất thật';
      stagingBanner.style.cssText = 'background:#B91C1C;color:#fff;text-align:center;font-weight:700;font-size:13px;padding:6px 10px;position:relative;z-index:1001';
      document.body.insertBefore(stagingBanner, bar.nextSibling);
    }

    const pwMask = document.createElement('div');
    pwMask.className = 'mnb-pw-mask';
    pwMask.id = 'mnbPwMask';
    pwMask.innerHTML =
      '<div class="mnb-pw-modal">' +
        '<h3>Đổi mật khẩu</h3>' +
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

    // T137: tab nhóm trang (VD Tổ khuôn) vẽ vào header tối của trang.
    document.querySelectorAll('[data-subtabs]').forEach(nav => {
      const g = SUB_TABS[nav.getAttribute('data-subtabs')];
      if (!g) return;
      nav.setAttribute('aria-label', g.label);
      nav.innerHTML = g.tabs.map(t => {
        const on = t.href === cur || (t.also || []).includes(cur);
        return '<a class="mnb-htab' + (on ? ' route-active' : '') + '" href="' + t.href + '"' + (on ? ' aria-current="page"' : '') + '>' + t.label + '</a>';
      }).join('');
    });

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
    if (email) startBell();
  }

  // T161: chuông thông báo công việc (cv_thong_bao). Chỉ hiện khi đã đăng
  // nhập VÀ đếm được. Đếm lỗi (VD production chưa chạy migration T161 → bảng
  // không có) → ẩn chuông im lặng; lỗi "không có bảng" thì ngừng hẳn, lỗi
  // khác (mất mạng) thử lại ở lượt 60 giây sau — không ghi console.
  const BELL_HTML =
    '<a href="thong-bao.html" class="mnb-bell" id="mnbBell" aria-label="Thông báo">' +
      '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"></path><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"></path></svg>' +
      '<span class="mnb-bell-n" id="mnbBellN" hidden></span>' +
    '</a>';
  let bellUid = null, bellStopped = false, bellBusy = false, bellTimer = null;

  // T316: nút toàn màn hình chung cho mọi màn (trước chỉ có ở Bảng điều khiển Đúc).
  // Trình duyệt tự thoát toàn màn hình khi chuyển trang — giới hạn của trình duyệt.
  // Máy không hỗ trợ (iPhone Safari) → ẩn nút.
  const FS_VAO = '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"></path></svg>';
  const FS_RA = '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3v3a2 2 0 0 1-2 2H3M21 8h-3a2 2 0 0 1-2-2V3M3 16h3a2 2 0 0 1 2 2v3M16 21v-3a2 2 0 0 1 2-2h3"></path></svg>';
  const FS_HTML = '<button type="button" class="mnb-fs" id="mnbFs" title="Toàn màn hình" aria-label="Toàn màn hình" hidden>' + FS_VAO + '</button>';
  function ganNutToanManHinh() {
    const b = document.getElementById('mnbFs');
    const d = document, el = d.documentElement;
    const vao = el.requestFullscreen || el.webkitRequestFullscreen;
    const ra = d.exitFullscreen || d.webkitExitFullscreen;
    if (!b || !vao || !ra) return;
    const dang = () => !!(d.fullscreenElement || d.webkitFullscreenElement);
    const ve = () => {
      const on = dang();
      b.innerHTML = on ? FS_RA : FS_VAO;
      b.title = on ? 'Thoát toàn màn hình' : 'Toàn màn hình';
      b.setAttribute('aria-label', b.title);
    };
    b.hidden = false;
    b.addEventListener('click', () => {
      try {
        const r = dang() ? ra.call(d) : vao.call(el);
        if (r && r.catch) r.catch(() => {});
      } catch (e) {}
    });
    ['fullscreenchange', 'webkitfullscreenchange'].forEach(ev => d.addEventListener(ev, ve));
  }
  async function refreshBell() {
    const el = document.getElementById('mnbBell');
    if (!el || bellStopped || bellBusy || !bellUid) return;
    bellBusy = true;
    try {
      const res = await sb.from('cv_thong_bao').select('id', { count: 'exact', head: true })
        .eq('nguoi_nhan', bellUid).eq('da_doc', false);
      if (res.error || typeof res.count !== 'number') {
        el.classList.remove('on');
        const code = res.error && res.error.code;
        if (res.status === 404 || code === 'PGRST205' || code === '42P01' || code === '42501') stopBell();
        return;
      }
      const n = res.count;
      const badge = document.getElementById('mnbBellN');
      badge.textContent = n > 99 ? '99+' : String(n);
      badge.hidden = n === 0;
      el.setAttribute('aria-label', n ? 'Thông báo, ' + n + ' chưa đọc' : 'Thông báo, không có thông báo mới');
      el.title = n ? n + ' thông báo chưa đọc' : 'Thông báo';
      el.classList.add('on');
    } catch (e) {
      el.classList.remove('on');
    } finally {
      bellBusy = false;
    }
  }
  function onBellVisible() { if (document.visibilityState === 'visible') refreshBell(); }
  function stopBell() {
    bellStopped = true;
    if (bellTimer) clearInterval(bellTimer);
    document.removeEventListener('visibilitychange', onBellVisible);
  }
  async function startBell() {
    if (bellUid || bellStopped) return;
    try {
      const session = await MesAuth.getSession();
      if (!session) return;
      bellUid = session.user.id;
    } catch (e) { return; }
    const el = document.getElementById('mnbBell');
    if (el && currentFile() === 'thong-bao.html') el.classList.add('route-active');
    refreshBell();
    bellTimer = setInterval(() => { if (document.visibilityState === 'visible') refreshBell(); }, 60000);
    document.addEventListener('visibilitychange', onBellVisible);
  }
  window.MesNav.refreshBell = refreshBell;

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
