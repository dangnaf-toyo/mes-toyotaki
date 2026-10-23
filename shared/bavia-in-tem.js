/*
 * shared/bavia-in-tem.js — In tem xuất hàng của thùng Bavia (T145).
 * Dùng ở bavia-dashboard.html. Dữ liệu lấy từ RPC bavia_du_lieu_in(p_tags).
 *
 * Mẫu theo khách (thiết kế đã chốt 23/10/2026):
 *   - FCC   : Phiếu quản lý lô sản phẩm, A6 NGANG (148×105mm), đúng bố cục file
 *             "Excel file/Tem xuất hàng FCC.xlsx" — giữ các dòng công đoạn sau
 *             (Trimming, Ktra ngoại quan, Sandblast, Dipping, Roll Coater, Packing)
 *             để trống cho khách ghi tay khi nhận hàng.
 *   - Astemo: Phiếu quản lý lô thẻ dọc, A6 DỌC (105×148mm), theo ảnh
 *             Picture/PHIẾU QUẢN LÝ LÔ ASTEMO.png — khối GIA CÔNG/SƠN/LẮP RÁP để
 *             trống. (Khổ A6 cho Astemo user CHƯA chốt, xem lại sau.)
 *   - Khách khác: TEM HÀNG, A4 ngang 4 tem/tờ (như T130).
 * Mọi mẫu có logo công ty + QR Tag No + người kiểm tra (theo Line).
 *
 * Cần thư viện qrcode-generator (window.qrcode) nạp trước.
 */
(function () {
  const LOGO =
    'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iODIiIGhlaWdodD0iNzciIHZpZXdCb3g9IjAgMCA4MiA3NyIgZmlsbD0ibm' +
    '9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZmlsbC1ydWxlPSJldmVub2RkIiBjbGlwLXJ1bG' +
    'U9ImV2ZW5vZGQiIGQ9Ik0yMC42MTE5IDIwLjU3OTlWNTEuMTAzM0gyNS4yMTcxVjE2LjEyNDlIMFYwLjg2MDM1Mkg0NC4xMTI2Vj' +
    'MxLjMwMzhMNDcuNzc4NyAyNy42NDcyTDY1LjgwNjQgNTEuMTAzM0g3MS43NjkzTDUxLjE1MzYgMjQuMjgwM0w3NC42MjU0IDAuOD' +
    'YwMzUySDgyTDU3Ljk5NCAyNC44NDA1TDgwLjU2OSA1Ni4yOTE5SDYzLjIwMjlMNDcuMTk2MyAzNS42MjUzTDM4Ljg2MTMgNDMuOT' +
    'UwMlY2LjA0ODlINS4yNTEzMlYxMC45MzY0SDMwLjQ2ODRWNTYuMjkxOUgxNS4zNjA1VjIwLjU3OTlIMjAuNjExOVoiIGZpbGw9Ii' +
    'NDQTY2MjciLz4KPC9zdmc+Cg==';
  const NHA_SX = 'Công ty Cổ Phần Công Nghiệp Toyotaki<br>KCN Khai Quang, P. Vĩnh Phúc, T. Phú Thọ, Việt Nam';
  // Tên khách in trên TEM HÀNG (theo file mẫu Excel) — khớp theo ten_khach_hang trong Danh mục SP.
  const KHACH = [
    { re: /cosmos/i, ten: 'CÔNG TY TNHH CÔNG NGHỆ COSMOS', partNo: false },
    { re: /mikasa/i, ten: 'CÔNG TY TNHH MIKASA VIỆT NAM', partNo: true },
    { re: /soji/i, ten: 'CÔNG TY CỔ PHẦN ĐIỆN TỬ SOJI', partNo: false },
  ];

  const esc = s =>
    String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const num = n => (Number(n) || 0).toLocaleString('vi-VN');
  const uniq = a => [...new Set(a.filter(Boolean))].join(', ');
  function dmy(d, sep) {
    if (!d) return '';
    const s = String(d).slice(0, 10).split('-');
    return s.length === 3 ? s[2] + (sep || '/') + s[1] + (sep || '/') + s[0] : String(d);
  }
  const dmyNgan = d => {
    const s = dmy(d);
    return s ? s.slice(0, 6) + s.slice(8) : '';
  };
  const caNgan = c => String(c || '').replace(/^Ca\s+/i, '');
  function tenNguoi(s) {
    s = String(s || '');
    const i = s.indexOf('_');
    return i > 0 && /^\d+$/.test(s.slice(0, i)) ? s.slice(i + 1) : s;
  }
  const nguoiDs = s => uniq(String(s || '').split(',').map(x => tenNguoi(x.trim())));
  function qrSvg(text) {
    const q = qrcode(0, 'M');
    q.addData(text);
    q.make();
    return q.createSvgTag({ cellSize: 2, margin: 0, scalable: true });
  }
  const nvl = s => (/ADC\s*12/i.test(String(s || '')) ? 'Nhôm ADC12' : String(s || '') || 'Nhôm ADC12');
  function lotNo(t) {
    const ds = [...new Set((t.nguon || []).map(n => n.ngay).filter(Boolean).concat(t.ngay ? [t.ngay] : []))].sort();
    return ds.map(d => dmy(d, '.')).join(' / ');
  }
  const ngayBavia = t => t.ngay_bavia || (t.luc ? new Date(new Date(t.luc).getTime() + 7 * 3600e3).toISOString() : '');

  /* ── TEM HÀNG (A4 ngang, 4 tem/tờ) ── */
  function temHang(t) {
    const k = KHACH.find(x => x.re.test(t.ten_khach_hang || '')) || { ten: null, partNo: false };
    const L = k.partNo ? ['Part No.', 'Part name'] : ['Product code', "Product's name"];
    const lb = (vi, en) => '<td class="lb">' + vi + '<br><i>' + en + '</i></td>';
    return (
      '<div class="th"><table>' +
      '<colgroup><col style="width:22%"><col style="width:30%"><col style="width:22%"><col style="width:26%"></colgroup>' +
      '<tr class="hd"><td class="logo"><img src="' + LOGO + '"><div>TOYOTAKI</div></td><td colspan="2" class="ti">TEM HÀNG</td>' +
      '<td class="qr">' + qrSvg(t.tag_no) + '<div>' + esc(t.tag_no) + '</div></td></tr>' +
      '<tr>' + lb('Khách hàng', 'Customer') + '<td colspan="3" class="v big">' + esc(k.ten || t.ten_khach_hang || '') + '</td></tr>' +
      '<tr>' + lb('Mã sản phẩm', L[0]) + '<td class="v big">' + esc(t.ma_sp_khach_hang || t.ma_sp) + '</td>' +
      lb('Nguyên vật liệu', 'Materials') + '<td class="v">' + esc(nvl(t.nguyen_lieu)) + '</td></tr>' +
      '<tr>' + lb('Tên sản phẩm', L[1]) + '<td class="v">' + esc(t.ten_sp || '') + '</td>' + lb('Số lượng', 'Quantity') +
      '<td class="v big">' + num(t.so_luong) + ' PCS' + (t.thung_le ? '<div class="le">thùng lẻ</div>' : '') + '</td></tr>' +
      '<tr>' + lb('Người làm', 'Operator') + '<td class="v">' + esc(nguoiDs(t.nguoi_bavia)) + '</td>' +
      lb('Người kiểm tra', 'Final checker') + '<td class="v">' + esc(tenNguoi(t.nguoi_kiem)) + '</td></tr>' +
      '<tr>' + lb('Số lô sản xuất', 'Lot No.') + '<td class="v">' + esc(lotNo(t)) + '</td>' +
      lb('Ngày sản xuất', 'Prod. date') + '<td class="v">' + dmy(ngayBavia(t), '.') + ' · ' + esc(caNgan(t.ca_bavia)) + '</td></tr>' +
      '<tr>' + lb('Nhà sản xuất', 'Producer') + '<td colspan="3" class="v sm">' + NHA_SX + '</td></tr>' +
      '</table></div>'
    );
  }

  /* ── Phiếu quản lý lô FCC (A6 ngang) ── */
  function phieuFcc(t) {
    const ng = t.nguon || [];
    const r = (c, cls) =>
      '<tr>' + c.map((v, i) => '<td' + (i === 5 || i === 6 ? ' class="n"' : '') + '>' + (v || '') + '</td>').join('') + '</tr>';
    const trong = n => Array.from({ length: n }, () => r(['', '', '', '', '', '', '', ''])).join('');
    const r2 = (b, n) =>
      Array.from({ length: n }, (_, i) => '<tr><td></td><td>' + (b[i] || '') + '</td><td colspan="3"></td><td></td><td></td></tr>').join('');
    return (
      '<div class="a6 land fcc">' +
      '<table class="hd"><colgroup><col style="width:17mm"><col><col style="width:16mm"></colgroup>' +
      '<tr><td rowspan="2" class="logo"><img src="' + LOGO + '">TOYOTAKI</td><td class="co">CÔNG TY CỔ PHẦN CÔNG NGHIỆP TOYOTAKI</td>' +
      '<td rowspan="2" class="qr">' + qrSvg(t.tag_no) + '<div>' + esc(t.tag_no) + '</div></td></tr>' +
      '<tr><td class="ti">PHIẾU QUẢN LÝ LÔ SẢN PHẨM</td></tr></table>' +
      '<table><colgroup><col style="width:17%"><col style="width:41%"><col style="width:18%"><col style="width:24%"></colgroup>' +
      '<tr><td class="b">Mã sản phẩm</td><td class="b">' + esc(t.ma_sp_khach_hang || t.ma_sp) + '</td><td class="b">Số lô nhận</td><td></td></tr>' +
      '<tr><td class="b">Tên sản phẩm</td><td class="b">' + esc(t.ten_sp || '') + '</td><td class="b">Số lượng nhận</td><td></td></tr>' +
      '<tr><td class="b">Lot No</td><td class="b">' + esc(lotNo(t)) + '</td><td class="b">Số lô NVL</td><td>' + esc(t.nguyen_lieu || '') + '</td></tr>' +
      '<tr><td class="b">Cavity</td><td class="b">' + esc(t.so_khuon || '') + '</td><td class="b">Số lượng</td><td class="b">' +
      num(t.so_luong) + ' pcs' + (t.thung_le ? ' (lẻ)' : '') + '</td></tr></table>' +
      '<table><colgroup><col style="width:12%"><col style="width:16%"><col style="width:6%"><col style="width:17%"><col style="width:17%">' +
      '<col style="width:9%"><col style="width:8%"><col style="width:15%"></colgroup>' +
      '<tr class="cot"><td>Ngày tháng</td><td>Tên thiết bị</td><td>Ca</td><td>Công đoạn</td><td>Người làm</td><td>OK</td><td>NG</td><td>Ghi chú</td></tr>' +
      r([
        esc(uniq(ng.map(n => dmyNgan(n.ngay)))),
        'DC - 350J No ' + esc(uniq(ng.map(n => String(n.may || '').replace(/\D/g, '')))),
        esc(uniq(ng.map(n => caNgan(n.ca)))),
        'Đúc',
        esc(uniq(ng.map(n => tenNguoi(n.nguoi)))),
        num(ng.reduce((s, n) => s + Number(n.so_luong_lay), 0)),
        '',
        esc(uniq(ng.map(n => String(n.tag_no || '').slice(-4)))),
      ]) +
      r(['', 'Trimming', '', 'Cắt cuống liệu', '', '', '', '']) +
      r([
        dmyNgan(ngayBavia(t)),
        'Xử Lý Bavia',
        esc(caNgan(t.ca_bavia)),
        'Xử lý Bavia',
        esc(nguoiDs(t.nguoi_bavia)),
        num(t.so_luong),
        '',
        'KT: ' + esc(tenNguoi(t.nguoi_kiem)),
      ]) +
      r(['', 'Ktra ngoại quan', '', 'Ktra ngoại quan', '', '', '', '']) +
      r(['', 'Sandblast No', '', 'Tạo nhám ( Phun bi)', '', '', '', '']) +
      trong(2) +
      '</table>' +
      '<div class="xs">Xuất sang công đoạn sau</div>' +
      '<table><colgroup><col style="width:12%"><col style="width:16%"><col style="width:6%"><col style="width:17%"><col style="width:17%">' +
      '<col style="width:17%"><col style="width:15%"></colgroup>' +
      '<tr class="cot"><td>Ngày tháng</td><td>Công đoạn</td><td colspan="3">Số lô xuất</td><td>Số lượng xuất</td><td>Số lượng tồn</td></tr>' +
      r2(['Dipping', 'Roll Coater', 'Packing'], 5) +
      '</table></div>'
    );
  }

  /* ── Phiếu quản lý lô Astemo (A6 dọc) ── */
  function phieuAstemo(t) {
    const ng = t.nguon || [];
    const c = (l1, v1, l2, v2) => '<td class="l">' + l1 + '</td><td class="v">' + (v1 || '') + '</td><td class="l">' + l2 + '</td><td class="v">' + (v2 || '') + '</td>';
    const khoi = (ten, maSo, buoc) => {
      const rows = [];
      if (maSo) rows.push(c('Mã số', '', 'Tên chi tiết', ''));
      buoc.forEach(b => {
        rows.push(c(b[0], b[1], 'Số lượng', b[2]));
        rows.push(c('Người làm', b[3], 'Ca', b[4]));
      });
      return rows.map((x, i) => '<tr>' + (i === 0 ? '<td class="bp" rowspan="' + rows.length + '"><span>' + ten + '</span></td>' : '') + x + '</tr>').join('');
    };
    const trong = a => a.map(x => [x, '', '', '', '']);
    const nb = dmyNgan(ngayBavia(t));
    return (
      '<div class="a6 port ast">' +
      '<div class="top"><div class="nl">Nguyên liệu<b>' + esc(t.nguyen_lieu || '') + '</b></div>' +
      '<div class="ti"><div class="lg"><img src="' + LOGO + '"><span><span class="hr">HR</span>PHIẾU QUẢN LÝ LÔ <small>- (Màu đen)</small></span></div></div>' +
      '<div class="qr">' + qrSvg(t.tag_no) + '<div>' + esc(t.tag_no) + (t.thung_le ? ' · lẻ' : '') + '</div></div></div>' +
      '<table><colgroup><col style="width:6.5%"><col style="width:23%"><col style="width:27%"><col style="width:17%"><col style="width:26.5%"></colgroup>' +
      '<tr><td class="bp0" rowspan="2">Bộ phận</td>' + c('Mã số', esc(t.ma_sp_khach_hang || t.ma_sp), 'Tên chi tiết', esc(t.ten_sp || '')) + '</tr>' +
      '<tr>' + c('Số lô', esc(lotNo(t)), 'Số khuôn', esc(t.so_khuon || '')) + '</tr>' +
      khoi('ĐÚC', false, [
        [
          'Ngày đúc',
          esc(uniq(ng.map(n => dmyNgan(n.ngay)))),
          num(ng.reduce((s, n) => s + Number(n.so_luong_lay), 0)),
          esc(uniq(ng.map(n => tenNguoi(n.nguoi)))),
          esc(uniq(ng.map(n => caNgan(n.ca)))),
        ],
        ['Ngày mài', nb, num(t.so_luong), esc(nguoiDs(t.nguoi_bavia)), esc(caNgan(t.ca_bavia))],
        ['Ngày kiểm tra', nb, num(t.so_luong), esc(tenNguoi(t.nguoi_kiem)), esc(caNgan(t.ca_bavia))],
        ['Ngày kiểm tra', '', '', '', ''],
      ]) +
      khoi('GIA CÔNG', true, trong(['Ngày gia công', 'Ngày KT áp lực', 'Ngày ép Pin', 'Ngày cạo via', 'Ngày kiểm tra'])) +
      khoi('SƠN', true, trong(['Ngày xử lý', 'Ngày treo giàn', 'Ngày sơn', 'Ngày bóc making', 'Ngày kiểm tra'])) +
      khoi('LẮP RÁP', true, trong(['Ngày lắp ráp'])) +
      '</table>' +
      '<div class="ft">ĐÚC → GIA CÔNG → SƠN → LẮP RÁP → LƯU GIỮ TẠI LẮP RÁP<br>THỜI GIAN BẢO LƯU 20 NĂM</div>' +
      '</div>'
    );
  }

  // CSS phiếu A6 (đơn vị mm) — dùng cả khi xem trước trên trang và khi in.
  const A6_CSS =
    '.a6{background:#fff;color:#000;font-family:Arial,Helvetica,sans-serif;box-sizing:border-box;padding:3mm;display:flex;flex-direction:column;gap:1mm;overflow:hidden}' +
    '.a6 *{box-sizing:border-box}.a6.port{width:105mm;height:148mm}.a6.land{width:148mm;height:105mm}' +
    '.a6 table{width:100%;border-collapse:collapse;table-layout:fixed}' +
    '.a6 td{border:.25mm solid #000;padding:0 .7mm;font-size:2.3mm;line-height:1.05;vertical-align:middle;overflow:hidden;white-space:nowrap}' +
    '.a6 td.sq{white-space:normal;font-size:1.75mm;line-height:1}' +
    '.a6 td.n{text-align:right;font-weight:bold}.a6 .b{font-weight:bold}' +
    '.a6 .qr{text-align:center;font-family:monospace;font-size:1.7mm;font-weight:bold}.a6 .qr svg{width:11mm;height:11mm;display:block;margin:0 auto}' +
    '.a6.fcc td{height:4.2mm}.a6.fcc .hd td{text-align:center;font-weight:bold}' +
    '.a6.fcc .hd .logo{color:#CA6627;font-size:2mm}.a6 .logo img{height:6.5mm;width:auto;display:block;margin:0 auto .3mm}' +
    '.a6.fcc .hd .co{font-size:2.8mm;height:4.6mm}.a6.fcc .hd .ti{font-size:4mm;height:6.6mm}' +
    '.a6.fcc .cot td{font-weight:bold;text-align:center;background:#F1F5F9}.a6.fcc .xs{font-weight:bold;font-size:2.6mm;margin-top:.6mm}' +
    '.a6.ast .top{display:grid;grid-template-columns:21mm minmax(0,1fr) 13mm;gap:1.5mm;align-items:center;height:14mm}' +
    '.a6.ast .nl{border:.3mm solid #000;text-align:center;font-size:2mm;padding:.6mm;line-height:1.2}.a6.ast .nl b{display:block;font-size:2.8mm}' +
    '.a6.ast .ti{text-align:center;font-weight:bold;font-size:3.2mm;white-space:nowrap}.a6.ast .ti small{font-weight:normal;font-size:2.1mm}' +
    '.a6.ast .lg{display:flex;align-items:center;justify-content:center;gap:1.2mm}.a6.ast .lg img{height:5mm;width:auto}' +
    '.a6.ast .qr div{font-size:1.45mm}' +
    '.a6.ast .hr{display:inline-block;border:.3mm solid #000;border-radius:50%;font-size:1.8mm;padding:.4mm .8mm;margin-right:1.2mm;vertical-align:middle}' +
    '.a6.ast table{flex:1}.a6.ast td{height:1mm;font-size:2.1mm}.a6.ast td.l{font-weight:bold;font-size:2mm}.a6.ast td.v{font-weight:bold}' +
    '.a6.ast td.bp,.a6.ast td.bp0{text-align:center;font-weight:bold;padding:0;white-space:normal;font-size:1.8mm}' +
    '.a6.ast td.bp span{display:inline-block;writing-mode:vertical-rl;transform:rotate(180deg);font-size:2.4mm;letter-spacing:.2mm}' +
    '.a6.ast .ft{text-align:center;font-weight:bold;font-size:1.9mm;line-height:1.3}';

  const TEM_HANG_CSS =
    '.th{border:0.4mm solid #000;overflow:hidden;background:#fff;color:#000;font-family:Arial,Helvetica,sans-serif}' +
    '.th table{width:100%;height:100%;border-collapse:collapse;table-layout:fixed}' +
    '.th td{border:0.3mm solid #000;padding:0.6mm 1.6mm;vertical-align:middle;font-size:3.3mm;line-height:1.15}' +
    '.th tr.hd td{height:20mm}.th .logo{text-align:center;font-weight:bold;color:#CA6627;font-size:2.6mm}.th .logo img{height:11mm;display:block;margin:0 auto 0.5mm}' +
    '.th .ti{text-align:center;font-size:9mm;font-weight:bold;letter-spacing:0.5mm}' +
    '.th .qr{text-align:center;font-family:monospace;font-size:2.4mm;font-weight:bold}.th .qr svg{width:15mm;height:15mm;display:block;margin:0 auto 0.4mm}' +
    '.th .lb{font-weight:bold;font-size:3mm}.th .lb i{font-weight:normal;font-size:2.5mm}' +
    '.th .v{font-weight:bold;text-align:center}.th .v.big{font-size:4.4mm}.th .v.sm{font-size:3mm;font-weight:normal}.th .le{font-size:2.6mm;font-weight:normal}';

  const PAGE_CSS = {
    chung:
      '@page{size:A4 landscape;margin:5mm}' +
      '.pg{display:grid;grid-template-columns:1fr 1fr;grid-auto-rows:97mm;gap:3mm;page-break-after:always}.pg:last-child{page-break-after:auto}',
    fcc: '@page{size:148mm 105mm;margin:0}.pg{page-break-after:always}.pg:last-child{page-break-after:auto}',
    astemo: '@page{size:105mm 148mm;margin:0}.pg{page-break-after:always}.pg:last-child{page-break-after:auto}',
  };
  const MAU_TEN = { fcc: 'Phiếu QL lô FCC · A6 ngang', astemo: 'Phiếu QL lô Astemo · A6 dọc', chung: 'TEM HÀNG · A4 ngang 4 tem/tờ' };
  const VE = { chung: temHang, fcc: phieuFcc, astemo: phieuAstemo };

  // Chữ dài hơn ô (VD 2 người làm) thì cho xuống dòng, cỡ nhỏ hơn.
  function coChu(root) {
    root.querySelectorAll('.a6 td').forEach(td => {
      if (!td.classList.contains('sq') && td.scrollWidth > td.clientWidth + 1) td.classList.add('sq');
    });
  }

  let cssDaNap = false;
  function napCss() {
    if (cssDaNap) return;
    const st = document.createElement('style');
    st.textContent = A6_CSS + TEM_HANG_CSS + '.bv-th-xem{width:190mm;height:97mm}';
    document.head.appendChild(st);
    cssDaNap = true;
  }

  /** HTML 1 tem/phiếu (để xem trước trên trang). */
  function veMot(t) {
    napCss();
    const m = VE[t.mau] ? t.mau : 'chung';
    return m === 'chung' ? '<div class="bv-th-xem">' + temHang(t) + '</div>' : VE[m](t);
  }

  /** In danh sách tem (dữ liệu từ bavia_du_lieu_in), mỗi mẫu 1 lệnh in riêng vì khổ giấy khác nhau. */
  async function inDs(ds, ban) {
    ban = Math.max(1, Math.min(6, Number(ban) || 1));
    const groups = { chung: [], fcc: [], astemo: [] };
    (ds || []).forEach(t => {
      for (let i = 0; i < ban; i++) groups[groups[t.mau] ? t.mau : 'chung'].push(t);
    });
    for (const m of ['chung', 'fcc', 'astemo']) {
      const g = groups[m];
      if (!g.length) continue;
      const per = m === 'chung' ? 4 : 1;
      let pages = '';
      for (let i = 0; i < g.length; i += per) pages += '<div class="pg">' + g.slice(i, i + per).map(VE[m]).join('') + '</div>';
      await inHtml(
        '<!DOCTYPE html><html lang="vi"><head><meta charset="UTF-8"><title>Tem xuất hàng Bavia</title><style>' +
          '*{margin:0;padding:0;box-sizing:border-box}body{background:#fff}' + A6_CSS + TEM_HANG_CSS + PAGE_CSS[m] +
          '</style></head><body>' + pages + '</body></html>',
      );
    }
  }

  // In qua iframe ẩn (không bị trình duyệt chặn popup sau khi chờ RPC).
  function inHtml(html) {
    return new Promise(resolve => {
      const f = document.createElement('iframe');
      f.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0';
      document.body.appendChild(f);
      const d = f.contentDocument;
      d.open();
      d.write(html);
      d.close();
      setTimeout(() => {
        try {
          coChu(d);
          f.contentWindow.focus();
          f.contentWindow.print();
        } catch (e) {
          console.error(e);
        }
        setTimeout(() => {
          f.remove();
          resolve();
        }, 1500);
      }, 350);
    });
  }

  window.BaviaInTem = { veMot, inDs, coChu, MAU_TEN, tenNguoi };
})();
