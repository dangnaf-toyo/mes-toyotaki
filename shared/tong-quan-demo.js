/**
 * ============================================================================
 * tong-quan-demo.js — T245: dữ liệu DEMO cho wallboard khi MES phủ toàn bộ
 * công đoạn (NVL/IQC → Đúc → Bavia → Gia công → Sơn → OQC → Kho TP → Xuất).
 *
 * Bật bằng wallboard.html?demo=1 (kèm ?k= hoặc đăng nhập như thường).
 * Chỉ SINH số cho công đoạn chưa có số liệu thật; Đúc, OQC, IPQC, NCP, sự cố
 * vẫn là số thật từ RPC tong_quan_hom_nay. Mọi số demo bám theo số thật:
 *   - Đầu vào Bavia hôm nay = sản lượng Đúc thật ngày hôm trước (trend[-2]).
 *   - Mã đi tiếp Gia công / Sơn / OQC / Nhập kho theo quy_trinh_cong_doan
 *     của master_products (bảng ROUTE bên dưới, chụp 12/11/2026).
 *   - Tỷ lệ NG theo mô tả nhà máy (Công đoạn của Toyotaki.md): Bavia ≈3%,
 *     Gia công ≈1%, Sơn ≈10%; Đúc mục tiêu 2,5% (tong-quan.js).
 *   - Nhôm lỏng cấp lò = Σ sản lượng Đúc thật × trọng lượng SP (T244) × 1,03.
 *   - Tiến độ trong ngày theo đồng hồ thật (ca 06:00–22:00 cho công đoạn sau Đúc).
 *   - Số ngẫu nhiên có hạt giống = ngày → tải lại trong ngày không nhảy số.
 * Khi công đoạn nào lên MES thật thì thay nguồn tương ứng trong RPC và xoá
 * phần demo của nó ở đây. Viết kiểu ES2017 cho trình duyệt TV.
 * ============================================================================
 */
(function () {
  // Quy trình công đoạn từng mã (B = Bavia, Z = Đánh bóng kẽm, G = Gia công, S = Sơn, O = OQC, K = Nhập kho)
  var ROUTE = {
    'AST-GRA-01': 'BK', 'AST-PAN-01': 'BK', 'AST-PAN-02': 'BK', 'BPH-SHO-01': 'ZGOK', 'BPH-SHO-02': 'ZGOK', 'BPH-SHO-03': 'ZGOK',
    'COS-CVR-01': 'BK', 'COS-GZ5-01': 'BGOK', 'COS-GZ5-02': 'BK', 'EXE-CEN-01': 'BGO', 'EXE-OUT-01': 'BGOK', 'EXE-PLT-01': 'BGOK',
    'EXE-PLY-01': 'BK', 'EXE-PLY-02': 'BK', 'EXE-PLY-03': 'BK', 'EXE-PLY-04': 'BGOK', 'EXE-SHO-01': 'ZK', 'EXE-SHO-02': 'ZK', 'EXE-SHO-03': 'ZK',
    'FCC-CEN-01': 'BK', 'FCC-CEN-02': 'BK', 'FCC-KFL-01': 'BK', 'FCC-KFM-01': 'BK', 'FCC-KPH-01': 'BK', 'FCC-KPH-02': 'BK', 'FCC-OUT-01': 'BK', 'FCC-OUT-02': 'BK',
    'FCC-TAD-01': 'BSOK', 'FCC-TAD-02': 'BSOK', 'FMC-PNH-01': 'BK', 'FMC-PNL-01': 'BOK', 'FUS-CBN-01': 'BGSOK', 'FUS-CBN-02': 'BGSOK', 'FUS-UH2-01': 'BGSOK',
    'IWT-114-01': 'BGSOK', 'IWT-115-01': 'BGOK', 'IWT-116-01': 'BGOK', 'IWT-118-01': 'BGOK', 'IWT-119-01': 'BGOK',
    'MIK-389-01': 'BGOK', 'MIK-389-02': 'BGOK', 'MIK-398-01': 'BGOK', 'MIK-399-01': 'BGOK', 'MIK-MT4-01': 'BK', 'MIK-MT5-01': 'BK', 'MIK-MT6-01': 'BK', 'MIK-MT7-01': 'BK', 'MIK-MT7-02': 'BK',
    'OKA-GJT-01': 'BSOK', 'OKA-GJT-02': 'BSOK', 'OKA-GJT-03': 'BSOK', 'OKA-GJT-04': 'BSOK', 'OKA-GJT-05': 'BSOK', 'OKA-GJT-06': 'BSOK', 'OKA-GJT-07': 'BSOK', 'OKA-GJT-08': 'BSOK',
    'OKA-GMN-01': 'BSOK', 'OKA-GMN-02': 'BSOK', 'OKA-GMN-03': 'BSOK', 'OKA-GMN-06': 'BSOK', 'OKA-GWI-01': 'BSOK', 'OKA-GWI-02': 'BSOK', 'OKA-GWI-03': 'BSOK', 'OKA-GWI-04': 'BSOK', 'OKA-GWI-05': 'BSOK', 'OKA-GWI-06': 'BSOK',
    'PRE-W99-01': 'BGOK', 'QTL-FOT-01': 'BGSOK', 'QTL-FOT-02': 'BGSOK', 'SOJ-LIG-01': 'BK', 'SUM-DH3-01': 'BK', 'SVP-BAL-01': 'BGSOK', 'SVP-LOC-01': 'BGSOK',
    'TTI-HSG-01': 'BGSOK', 'TTI-MOT-01': 'BGOK', 'TTI-MOT-02': 'BGOK', 'TTI-MOT-03': 'BGOK', 'TTI-MOT-04': 'BGOK', 'TTI-MOT-05': 'BGOK', 'TTI-PUM-01': 'BGOK', 'TTI-PUM-02': 'BGOK', 'TTI-PUM-03': 'BGOK', 'YHS-HAN-01': 'K',
  };
  // Trọng lượng SP sau đúc (kg, v_sp_trong_luong_hien_tai T244) — để tính nhôm lỏng cấp lò
  var TL = {
    'AST-GRA-01': 1.7176, 'AST-PAN-01': 0.432, 'AST-PAN-02': 0.618, 'COS-CVR-01': 0.0204, 'COS-GZ5-01': 0.648, 'COS-GZ5-02': 0.6412,
    'EXE-CEN-01': 0.1948, 'EXE-OUT-01': 0.2252, 'EXE-PLT-01': 0.1442, 'EXE-PLY-01': 0.2316, 'EXE-PLY-02': 0.27, 'EXE-PLY-03': 0.184,
    'EXE-SHO-01': 0.2159, 'EXE-SHO-02': 0.1756, 'EXE-SHO-03': 0.254, 'FCC-CEN-01': 0.2006, 'FCC-CEN-02': 0.196, 'FCC-KFM-01': 0.1482,
    'FCC-KPH-01': 0.1868, 'FCC-KPH-02': 0.135, 'FCC-OUT-01': 0.19, 'FCC-OUT-02': 0.1967, 'FCC-TAD-01': 0.4468, 'FCC-TAD-02': 0.447,
    'FMC-PNH-01': 0.0844, 'FMC-PNL-01': 0.092, 'FUS-CBN-01': 0.2544, 'FUS-CBN-02': 0.2551, 'FUS-UH2-01': 0.0836, 'IWT-114-01': 0.0863,
    'IWT-115-01': 0.0332, 'IWT-116-01': 0.0279, 'IWT-118-01': 0.1842, 'IWT-119-01': 0.1221, 'MIK-389-01': 0.259, 'MIK-389-02': 0.2458,
    'MIK-398-01': 0.1555, 'MIK-399-01': 0.1898, 'MIK-MT4-01': 0.466, 'MIK-MT5-01': 0.46, 'MIK-MT6-01': 0.6574, 'MIK-MT7-01': 0.6588, 'MIK-MT7-02': 0.6462,
    'OKA-GJT-01': 1.2884, 'OKA-GJT-02': 1.6422, 'OKA-GJT-03': 1.2798, 'OKA-GJT-04': 1.6466, 'OKA-GJT-05': 1.2714, 'OKA-GJT-06': 1.6512, 'OKA-GJT-07': 1.2806, 'OKA-GJT-08': 1.6258,
    'OKA-GMN-01': 1.1198, 'OKA-GMN-02': 1.4614, 'OKA-GMN-03': 1.12, 'OKA-GMN-06': 1.4624, 'OKA-GWI-01': 1.264, 'OKA-GWI-02': 1.685, 'OKA-GWI-03': 1.2583, 'OKA-GWI-04': 1.6783, 'OKA-GWI-05': 1.2624, 'OKA-GWI-06': 1.68,
    'PRE-W99-01': 0.2136, 'QTL-FOT-01': 1.5504, 'QTL-FOT-02': 1.5504, 'SOJ-LIG-01': 0.1758, 'SUM-DH3-01': 2.211, 'SVP-BAL-01': 0.0583, 'SVP-LOC-01': 0.5288,
    'TTI-HSG-01': 0.0623, 'TTI-MOT-01': 0.2401, 'TTI-MOT-02': 0.2316, 'TTI-MOT-03': 0.243, 'TTI-MOT-04': 0.1575, 'TTI-MOT-05': 0.1471, 'TTI-PUM-01': 0.2058, 'TTI-PUM-02': 0.2344, 'TTI-PUM-03': 0.2344, 'YHS-HAN-01': 0.0372,
  };
  var KEM = { 'EXE-SHO-01': 1, 'EXE-SHO-02': 1, 'EXE-SHO-03': 1, 'YHS-HAN-01': 1, 'BPH-SHO-01': 1, 'BPH-SHO-02': 1, 'BPH-SHO-03': 1 };
  var GC_MAY = { phay3: ['Phay 01', 'Phay 02', 'Phay 03', 'Phay 04', 'Phay 05', 'Phay 06', 'Phay 07', 'Phay 09', 'Phay 11', 'Phay 12', 'Phay 13', 'Phay 14', 'Phay 15'],
    phay4: ['Phay 08', 'Phay 10', 'Phay 16', 'Phay 17'], tien: ['Tiện 01', 'Tiện 02', 'Tiện 03', 'Tiện 04', 'Tiện 05', 'Tiện 06', 'Tiện 07', 'Tiện 08', 'Tiện 09', 'Tiện 10', 'Tiện 11', 'Tiện 12'], chuot: ['Chuốt 01'] };
  var NG = { bavia: 0.03, gc: 0.01, son: 0.10, kem: 0.03 };
  var NG_MT = { bavia: 0.03, gc: 0.01, son: 0.08, oqc: 0.03 };

  // PRNG có hạt giống (mulberry32) — cùng ngày cùng số
  function rng(seed) { var a = seed >>> 0; return function () { a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
  function hash(s) { var h = 2166136261; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function num(v) { var n = Number(v); return isFinite(n) ? n : 0; }
  function r(x) { return Math.round(x); }
  function has(ma, k) { return (ROUTE[ma] || 'BK').indexOf(k) >= 0; }
  // Tiến độ ngày của công đoạn sau Đúc: 2 ca 8h, 06:00–22:00 (giờ địa phương máy TV)
  function fracNgay(now, ngay) {
    var d = new Date(ngay + 'T06:00:00'), e = new Date(ngay + 'T22:00:00');
    return Math.max(0, Math.min(1, (now - d) / (e - d)));
  }

  function apply(M, D) {
    var now = M.now, ngay = M.ngay, R = rng(hash('demo|' + ngay)), f = fracNgay(now, ngay);
    var jit = function (a, b) { return a + (b - a) * R(); };
    var tr = M.trend, homQua = tr.length > 1 ? tr[tr.length - 2] : null;
    // ---- Đầu vào Bavia = Đúc thật hôm qua (fallback: KH ngày hoặc 24.000) ----
    var ducHomQua = 0; (D.bao_cao || []).forEach(function (b) { if (homQua && b.ngay === homQua.ngay) ducHomQua += num(b.tt); });
    if (!ducHomQua) ducHomQua = M.duc.khNgay || 24000;
    // Cơ cấu mã: lấy từ máy Đúc thật đang có KH (trọng số = KH ca); thiếu thì dùng 8 mã phổ biến
    var mix = {}; M.machines.forEach(function (m) { if (m.sp && ROUTE[m.sp]) mix[m.sp] = (mix[m.sp] || 0) + (m.kh || 600); }); // máy có SP nhưng KH 0 (đang sự cố) vẫn tính trọng số nhỏ
    if (!Object.keys(mix).length) ['TTI-MOT-05', 'FCC-KPH-01', 'EXE-PLY-01', 'OKA-GMN-02', 'AST-PAN-01', 'MIK-389-01', 'FCC-TAD-01', 'IWT-114-01'].forEach(function (k) { mix[k] = 2000; });
    var tongMix = 0; Object.keys(mix).forEach(function (k) { tongMix += mix[k]; });
    var share = function (k) { var s = 0; Object.keys(mix).forEach(function (ma) { if (has(ma, k)) s += mix[ma]; }); return s / tongMix; };
    var maCo = function (k) { return Object.keys(mix).filter(function (ma) { return has(ma, k); }).sort(function (a, b) { return mix[b] - mix[a]; }); };

    // ---- NVL & lò: nhôm lỏng = Đúc thật hôm nay × TL × 1,03 (định mức T244) ----
    var kgHomNay = 0, kgKem = 0;
    M.machines.forEach(function (m) { var kg = m.tt * (TL[m.sp] || 0.25) * 1.03; if (KEM[m.sp]) kgKem += kg; else kgHomNay += kg; });
    (D.bao_cao || []).forEach(function (b) { if (b.ngay === ngay) kgHomNay += num(b.tt) * 0.3 * 1.03; }); // ca đã kết: TL trung bình 0,3 kg
    var nvl = {
      ton: [
        { ma: 'ADC12-CHT', ten: 'Nhôm ADC12 Chiến Thắng', kg: r(58235 - kgHomNay * 0.6), ngay: null },
        { ma: 'ADC12-DAK', ten: 'Nhôm ADC12 Daikin', kg: r(42600 - kgHomNay * 0.4), ngay: null },
        { ma: 'HD2-HDT', ten: 'Nhôm HD2-BS1', kg: 12741, ngay: null },
        { ma: 'EZDA3-HDT', ten: 'Kẽm Honda Trading', kg: r(13458 - kgKem), ngay: null },
        { ma: 'ADC6-CHT', ten: 'Nhôm ADC6 Chiến Thắng', kg: 248, ngay: null },
      ],
      lo: [{ ten: 'Lò 1 · 800 kg/h', nhiet: r(jit(735, 748)), kgh: r(jit(560, 700)), st: 'run' }, { ten: 'Lò 2 · 1000 kg/h', nhiet: r(jit(738, 750)), kgh: r(jit(700, 880)), st: 'run' }],
      capLoKg: r(kgHomNay), kemKg: r(kgKem),
      iqc: { choKiem: r(jit(0, 2.9)), homNay: 2, ng: 0, lo: [{ ma: 'ADC12-CHT', sl: 8000, kq: 'OK', luc: '07:40' }, { ma: 'EZDA3-HDT', sl: 2000, kq: 'OK', luc: '09:15' }] },
      phe: r(kgHomNay * jit(0.012, 0.02)),
    };
    nvl.ton.forEach(function (t) { var tieu = t.ma === 'EZDA3-HDT' ? 450 : t.ma === 'HD2-HDT' ? 300 : t.ma === 'ADC6-CHT' ? 60 : 4800; t.ngay = Math.floor(t.kg / tieu); });

    // ---- Bavia: 13 line, 45 người/ca, NG ≈3% ----
    var khBavia = r(ducHomQua * 0.97), ttBavia = r(khBavia * f * jit(0.93, 1.02));
    var ngBavia = r(ttBavia * jit(0.022, 0.038));
    var maB = maCo('B'), lines = [];
    for (var i = 1; i <= 13; i++) {
      var ma = maB[(i - 1) % Math.max(1, maB.length)], kh = r(khBavia / 10 * jit(0.8, 1.2)); // 10 line chạy, 3 line dự phòng
      var pct = jit(0.78, 1.06), st = i > 10 ? 'idle' : R() < 0.08 ? 'warn' : 'run';
      lines.push({ ten: 'LINE ' + (i < 10 ? '0' + i : i), sp: st === 'idle' ? '' : ma, kh: st === 'idle' ? 0 : kh, tt: st === 'idle' ? 0 : r(kh * f * pct), pct: st === 'idle' ? null : pct, nguoi: st === 'idle' ? 0 : 4 + (i % 3), st: st, nhan: st === 'idle' ? 'Không chạy' : st === 'warn' ? 'Chờ hàng Đúc' : 'Đang chạy' });
    }
    var bavia = { kh: khBavia, tt: ttBavia, ng: ngBavia, ngPct: ttBavia ? ngBavia / ttBavia : null, ngMt: NG_MT.bavia, lines: lines, nguoi: 45,
      phunBi: [{ ten: 'Phun bi 1', st: 'run', me: r(f * 14) }, { ten: 'Phun bi 2', st: R() < 0.2 ? 'warn' : 'run', me: r(f * 11) }], mai: { dang: 5 - (R() < 0.3 ? 1 : 0), tong: 5 },
      kem: { kh: r(ducHomQua * share('Z') || 1800), tt: r((ducHomQua * share('Z') || 1800) * f * jit(0.9, 1.0)), ng: 0 } };
    bavia.kem.ng = r(bavia.kem.tt * NG.kem);

    // ---- Gia công: 30 máy, 15 người/ca, NG ≈1% ----
    var khGC = r(ducHomQua * Math.max(share('G'), 0.3) * 0.97), ttGC = r(khGC * f * jit(0.9, 1.0)), ngGC = r(ttGC * jit(0.006, 0.014));
    // mã Gia công: mã đang đúc đi tiếp Gia công + hàng tồn hôm trước (mã có OQC gần đây)
    var maG = maCo('G'); ['EXE-OUT-01', 'EXE-PLT-01', 'MIK-389-02', 'PRE-W99-01', 'EXE-CEN-01', 'MIK-399-01'].forEach(function (x) { if (maG.indexOf(x) < 0) maG.push(x); });
    var gcMay = [], k = 0, sucoMay = Math.floor(R() * 30);
    [['phay3', 'Phay 3 trục'], ['phay4', 'Phay 4 trục'], ['tien', 'Tiện'], ['chuot', 'Chuốt']].forEach(function (g) {
      GC_MAY[g[0]].forEach(function (ten) {
        var ma = maG[k % maG.length], pct = jit(0.8, 1.05), idle = R() < 0.12, warn = !idle && R() < 0.07, alarm = k === sucoMay;
        var khM = r(khGC / 26), st = idle ? 'idle' : alarm ? 'alarm' : warn ? 'warn' : 'run';
        gcMay.push({ may: ten, loai: g[1], sp: idle ? '' : ma, kh: idle ? 0 : khM, tt: idle ? 0 : r(khM * f * pct), pct: idle ? null : pct, st: st,
          nhan: idle ? 'Không có KH' : alarm ? 'Gãy dao ' + r(jit(8, 40)) + '′' : warn ? 'Đổi jig ' + r(jit(5, 25)) + '′' : 'Đang chạy', phut: alarm ? r(jit(8, 40)) : warn ? r(jit(5, 25)) : 0 });
        k++;
      });
    });
    var thuTu = { alarm: 0, warn: 1, run: 2, idle: 3 }; gcMay.sort(function (a, b) { return thuTu[a.st] - thuTu[b.st] || a.may.localeCompare(b.may, 'vi', { numeric: true }); });
    var dem = { run: 0, warn: 0, alarm: 0, idle: 0 }; gcMay.forEach(function (m) { dem[m.st]++; });
    var gc = { kh: khGC, tt: ttGC, ng: ngGC, ngPct: ttGC ? ngGC / ttGC : null, ngMt: NG_MT.gc, may: gcMay, dem: dem, nguoi: 15, vatMep: 3, ipqcTre: R() < 0.3 ? 1 : 0 };

    // ---- Sơn: 1 dây chuyền bán tự động, masking, NG ≈10%, hao sơn 20–60% ----
    var khSon = r(ducHomQua * Math.max(share('S'), 0.12) * 0.95), ttSon = r(khSon * f * jit(0.85, 1.0)), ngSon = r(ttSon * jit(0.07, 0.12));
    var maS = maCo('S'); if (!maS.length) maS = ['OKA-GMN-02', 'FCC-TAD-01', 'IWT-114-01'];
    var son = { kh: khSon, tt: ttSon, ng: ngSon, ngPct: ttSon ? ngSon / ttSon : null, ngMt: NG_MT.son, sp: maS[0], loai: R() < 0.5 ? 'Sơn bột tĩnh điện' : 'Sơn nước',
      tienXuLy: { tt: r(khSon * Math.min(1, f + 0.12) * 0.98), kh: khSon }, say: { nhiet: r(jit(178, 186)), st: 'run' },
      choSon: r(khSon * jit(0.25, 0.45)), masking: { cho: r(khSon * 0.3 * (1 - f) * jit(0.6, 1)), tt: r(khSon * 0.3 * f) },
      luotTreo: r(f * jit(38, 46)), nguoi: 4, haoSon: jit(0.28, 0.5), kgSon: r(ttSon * jit(0.018, 0.03)) };

    // ---- OQC: thật nếu có; demo thêm phần sau Sơn ----
    var oqcThat = M.oqc.n > 0;
    var oqcN = oqcThat ? M.oqc.n : r((ttGC + ttSon) * 0.9), oqcNG = oqcThat ? M.oqc.ng : r(oqcN * jit(0.025, 0.045));
    var oqc = { n: oqcN, ng: oqcNG, pct: oqcN ? oqcNG / oqcN : null, mt: M.oqc.mt, that: oqcThat, nguoi: 6, sauGC: r(oqcN * 0.6), sauSon: r(oqcN * 0.4), choKiem: r((ttGC + ttSon) * jit(0.05, 0.12)) };

    // ---- Kho thành phẩm & xuất hàng ----
    var nhapKho = M.nhapKho > 0 ? M.nhapKho : r((oqcN - oqcNG) * 0.85 + ttBavia * share('K') * 0.4 * (1 - share('G') - share('S')));
    var kho = { nhap: nhapKho, pallet: r(nhapKho / 720), xuat: r(nhapKho * jit(0.8, 1.1)), xeHomNay: 3 + Math.floor(R() * 3), ton: r(jit(118000, 142000)), tonNgay: 0,
      khach: [['FCC (VIETNAM)', r(nhapKho * 0.34)], ['OKAYA', r(nhapKho * 0.22)], ['TTI', r(nhapKho * 0.18)], ['EXEDY', r(nhapKho * 0.12)], ['ASTEMO', r(nhapKho * 0.08)], ['Khác', r(nhapKho * 0.06)]],
      ngoai: [{ ten: 'Mạ (ngoài)', sl: r(jit(800, 1500)), ngay: 2 }, { ten: 'In (ngoài)', sl: r(jit(300, 900)), ngay: 1 }] };
    kho.tonNgay = Math.round(kho.ton / Math.max(1, ducHomQua * 0.9) * 10) / 10; // ngày xuất = tồn / nhịp SX 1 ngày

    // ---- WIP giữa công đoạn (sọt/thùng chờ) ----
    var wip = [
      { tu: 'Đúc', den: 'Bavia', sl: r(ducHomQua * jit(0.9, 1.3)), mt: r(ducHomQua * 1.2) },
      { tu: 'Bavia', den: 'Gia công', sl: r(khGC * jit(0.5, 0.9)), mt: r(khGC * 0.8) },
      { tu: 'Gia công', den: 'Sơn', sl: r(khSon * 0.4 * jit(0.3, 0.8)), mt: r(khSon * 0.5) },
      { tu: 'Sơn', den: 'OQC', sl: oqc.choKiem, mt: r((ttGC + ttSon) * 0.1) },
    ];

    // ---- Việc đang mở thêm từ công đoạn demo ----
    var acts = [];
    gcMay.forEach(function (m) { if (m.st === 'alarm') acts.push({ muc: 0, t: m.may + ' dừng — gãy dao, chờ thay', s: m.sp, tuoi: m.phut + '′', w: m.phut }); });
    if (son.ngPct > NG_MT.son) acts.push({ muc: 1, t: 'NG Sơn ' + (son.ngPct * 100).toFixed(1).replace('.', ',') + '% > mục tiêu ' + (NG_MT.son * 100) + '%', s: son.sp + ' · ' + son.loai, tuoi: 'hôm nay', w: 0 });
    if (bavia.ngPct > NG_MT.bavia) acts.push({ muc: 2, t: 'NG Bavia ' + (bavia.ngPct * 100).toFixed(1).replace('.', ',') + '% > mục tiêu 3%', s: 'phần lớn là lỗi ngoại quan từ Đúc', tuoi: 'hôm nay', w: 0 });
    if (gc.ipqcTre) acts.push({ muc: 2, t: 'IPQC Gia công quá hạn kiểm: 1 máy', s: gcMay[0].may, tuoi: '', w: 0 });
    wip.forEach(function (w) { if (w.sl > w.mt) acts.push({ muc: 2, t: 'Tồn ' + w.tu + ' → ' + w.den + ' vượt mức: ' + w.sl.toLocaleString('vi-VN') + ' pcs', s: 'mức ' + w.mt.toLocaleString('vi-VN'), tuoi: '', w: 0 }); });
    if (nvl.iqc.choKiem) acts.push({ muc: 3, t: 'IQC: ' + nvl.iqc.choKiem + ' lô NVL chờ kiểm', s: 'ADC12-DAK', tuoi: '2h', w: 120 });
    nvl.ton.forEach(function (t) { if (t.ngay <= 3 && t.kg > 0) acts.push({ muc: 2, t: 'NVL ' + t.ma + ' còn ' + t.ngay + ' ngày', s: t.ten, tuoi: '', w: 0 }); });

    M.demo = { nvl: nvl, bavia: bavia, gc: gc, son: son, oqc: oqc, kho: kho, wip: wip, actions: acts, ducHomQua: ducHomQua, frac: f, share: { G: share('G'), S: share('S'), Z: share('Z') } };
    M.chuaTrienKhai = [];
    M.actions = acts.concat(M.actions).sort(function (a, b) { return a.muc - b.muc || b.w - a.w; });
    return M;
  }

  window.TongQuanDemo = { apply: apply, ROUTE: ROUTE };
})();
