/**
 * ============================================================================
 * tong-quan.js — T160: số liệu "Toàn cảnh nhà máy hôm nay" dùng chung cho
 * index.html (trang chủ) và wallboard.html (Smart TV).
 *   TongQuan.load(khoa) → Promise<data thô>   (RPC tong_quan_hom_nay)
 *   TongQuan.compute(data, nowMs) → mô hình hiển thị (xem cuối hàm compute)
 * Viết kiểu ES2017 (không ?. / ??) để trình duyệt Smart TV cũ vẫn chạy.
 * Wallboard gọi REST thẳng bằng fetch + khoá (không cần đăng nhập, không phụ
 * thuộc supabase-js); trang chủ gọi sb.rpc bằng phiên đăng nhập.
 * Giả định tạm (user chưa chốt 23/10/2026): mục tiêu NG Đúc 2,5%; Bavia / Gia
 * công / Sơn chưa triển khai MES nên chỉ hiện "chưa triển khai".
 * ============================================================================
 */
(function () {
  // Cùng CONFIG.SHIFT_PLANS của duc-dashboard.html
  var SHIFT_PLANS = {
    '2 ca 12h': { 'Ca ngày': { s: [6, 0], e: [18, 0], x: false }, 'Ca đêm': { s: [18, 0], e: [6, 0], x: true } },
    '2 ca 8h': { 'Ca 1': { s: [6, 0], e: [14, 0], x: false }, 'Ca 2': { s: [14, 0], e: [22, 0], x: false } },
  };
  var MUC_TIEU_NG_DUC = 0.025;
  var CHUA_TRIEN_KHAI = ['Bavia', 'Gia công', 'Sơn'];

  function num(v) { var n = Number(v); return isFinite(n) ? n : 0; }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function hm(d) { return pad(d.getHours()) + ':' + pad(d.getMinutes()); }
  function ddmm(s) { return s.slice(8, 10) + '/' + s.slice(5, 7); }
  function addDays(s, k) { var d = new Date(s + 'T00:00:00'); d.setDate(d.getDate() + k); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function loaiCode(l) { return String(l || '').trim().slice(0, 2).toUpperCase(); }
  function loaiTen(l) { var s = String(l || '').trim(); return s || 'Khác'; }

  function shiftWindow(ngay, ca, pa) {
    var plan = (SHIFT_PLANS[pa] || {})[ca];
    if (!plan) { var k; for (k in SHIFT_PLANS) if (SHIFT_PLANS[k][ca]) plan = SHIFT_PLANS[k][ca]; }
    if (!plan) return null;
    var d = new Date(String(ngay).slice(0, 10) + 'T00:00:00');
    var st = new Date(d.getFullYear(), d.getMonth(), d.getDate(), plan.s[0], plan.s[1]);
    var en = new Date(d.getFullYear(), d.getMonth(), d.getDate() + (plan.x ? 1 : 0), plan.e[0], plan.e[1]);
    return { start: st, end: en };
  }

  function load(khoa) {
    // Gọi qua sb để mang phiên đăng nhập (T198: anon không còn quyền gọi RPC)
    return sb.rpc('tong_quan_hom_nay', khoa ? { p_khoa: khoa } : {}).then(function (res) {
      if (res.error) throw new Error(res.error.message);
      return chk(res.data);
    });
  }
  function chk(d) { if (!d || d.ok === false) throw new Error((d && d.error) || 'Không có dữ liệu'); return d; }

  // NG Đúc từ báo cáo ca chưa ổn định (ca ghi 0 = chưa nhập; có ca NG > 30% SL = số sai) →
  // chỉ tính các ca có NG trong khoảng (0; 30% SL]
  function ngHopLe(tt, ng) { return ng > 0 && ng <= tt * 0.3; }

  function compute(D, nowMs) {
    var now = new Date(nowMs || Date.now());
    var ngay = D.ngay;

    // ---- Máy Đúc: gộp các dòng của ca thật đang chạy mỗi máy ----
    var byMay = {};
    (D.dong || []).forEach(function (r) {
      var m = byMay[r.ma_may] || (byMay[r.ma_may] = { may: r.ma_may, kh: 0, tt: 0, ng: 0, ngay: r.ngay, ca: r.ca, pa: r.phuong_an_ca, sp: r.ma_sp, open: null });
      m.kh += num(r.kh_ca); m.tt += num(r.tt_ca); m.ng += num(r.so_luong_ng);
      m.sp = r.ma_sp || m.sp; // dòng sau (row_seq lớn hơn) = SP đang chạy
      if (r.open_gio_phat_sinh) m.open = { loai: r.open_loai_su_co, tu: new Date(r.open_gio_phat_sinh), van_de: r.open_van_de };
    });
    // Ca hiện tại = (ngày, ca, phương án) nhiều máy nhất
    var dem = {}, caKey = null;
    Object.keys(byMay).forEach(function (k) { var m = byMay[k]; var key = m.ngay + '|' + m.ca + '|' + (m.pa || ''); dem[key] = (dem[key] || 0) + 1; if (!caKey || dem[key] > dem[caKey]) caKey = key; });
    var ca = null;
    if (caKey) {
      var p = caKey.split('|'); var w = shiftWindow(p[0], p[1], p[2]);
      ca = { ngay: p[0], ten: p[1], pa: p[2], start: w && w.start, end: w && w.end };
      if (w) {
        ca.frac = Math.max(0, Math.min(1, (now - w.start) / (w.end - w.start)));
        ca.trangThai = now < w.start ? 'chua' : now > w.end ? 'qua_gio' : 'chay';
        ca.nhan = p[1] + ' · ' + hm(w.start) + '–' + hm(w.end);
      } else { ca.frac = 0; ca.trangThai = 'chay'; ca.nhan = p[1]; }
    }

    var machines = (D.may || []).map(function (ten) {
      var m = byMay[ten];
      if (!m) return { may: ten, st: 'idle', nhan: 'Không chạy', sp: '', tt: 0, kh: 0, khNow: 0, pct: null };
      var w = shiftWindow(m.ngay, m.ca, m.pa);
      var frac = w ? Math.max(0, Math.min(1, (now - w.start) / (w.end - w.start))) : 1;
      var khNow = m.kh * frac;
      var o = { may: ten, sp: m.sp, tt: m.tt, kh: m.kh, khNow: khNow, pct: khNow > 0 ? m.tt / khNow : null, ng: m.ng };
      if (m.open) {
        var phut = Math.max(0, Math.round((now - m.open.tu) / 60000));
        var c = loaiCode(m.open.loai);
        o.st = c.charAt(0) === 'C' ? 'warn' : 'alarm';
        o.phut = phut;
        o.nhan = loaiTen(m.open.loai).replace(/^[A-Z]\d\s*—\s*/, '') + ' ' + phut + '′';
        o.loai = m.open.loai; o.van_de = m.open.van_de;
      } else if (!m.kh) { o.st = 'idle'; o.nhan = 'Không có KH'; }
      else if (w && now < w.start) { o.st = 'cho'; o.nhan = 'Chờ vào ca ' + hm(w.start); }
      else { o.st = 'run'; o.nhan = 'Đang chạy'; }
      return o;
    });
    var thuTu = { alarm: 0, warn: 1, run: 2, cho: 3, idle: 4 };
    machines.sort(function (a, b) { return (thuTu[a.st] - thuTu[b.st]) || String(a.may).localeCompare(String(b.may), 'vi', { numeric: true }); });
    var dangDung = machines.filter(function (m) { return m.st === 'alarm' || m.st === 'warn'; }).sort(function (a, b) { return b.phut - a.phut; });
    var demSt = { run: 0, warn: 0, alarm: 0, idle: 0, cho: 0 };
    machines.forEach(function (m) { demSt[m.st]++; });

    // ---- Ca hiện tại: tổng ----
    var caTT = 0, caKH = 0, caKHNow = 0, caNG = 0;
    machines.forEach(function (m) { if (m.kh) { caTT += m.tt; caKH += m.kh; caKHNow += m.khNow; caNG += m.ng || 0; } });
    var pace = caKHNow > 0 ? caTT / caKHNow : null;
    var duBao = ca && ca.frac >= 0.08 && ca.trangThai !== 'chua' ? Math.round(caTT / ca.frac) : null;

    // ---- Theo ngày (báo cáo ca đã kết) ----
    var days = []; for (var i = 13; i >= 0; i--) days.push(addDays(ngay, -i));
    var dayAgg = {}; days.forEach(function (d) { dayAgg[d] = { kh: 0, tt: 0, ng: 0, ngTT: 0, oee: [], dung: 0, suCo: 0 }; });
    (D.bao_cao || []).forEach(function (b) {
      var a = dayAgg[b.ngay]; if (!a) return;
      a.kh += num(b.kh); a.tt += num(b.tt);
      if (ngHopLe(num(b.tt), num(b.ng))) { a.ng += num(b.ng); a.ngTT += num(b.tt); }
      var oe = num(b.oee); if (oe > 0.01 && oe <= 1.5) a.oee.push(oe);
    });
    (D.su_co || []).forEach(function (s) { var a = dayAgg[s.ngay]; if (!a) return; a.suCo++; a.dung += num(s.phut_may != null ? s.phut_may : s.phut); });   // T179: phút dừng máy đã trừ chồng giờ
    // Hôm nay = ca đã kết + ca đang chạy (nếu cùng ngày sản xuất)
    var T = dayAgg[ngay];
    var homNay = { kh: T.kh, tt: T.tt, ng: T.ng, ngTT: T.ngTT };
    if (ca && ca.ngay === ngay) { homNay.kh += caKH; homNay.tt += caTT; if (ngHopLe(caTT, caNG)) { homNay.ng += caNG; homNay.ngTT += caTT; } }
    var ngDuc = homNay.ngTT + homNay.ng > 0 ? homNay.ng / (homNay.ngTT + homNay.ng) : null;
    // Tiến độ cả ngày: KH các ca đã kết + KH đến giờ của ca đang chạy (cùng ngày SX)
    var cungNgay = ca && ca.ngay === ngay;
    var khDenGio = T.kh + (cungNgay ? caKHNow : 0);
    var pNgay = khDenGio > 0 ? homNay.tt / khDenGio : null;
    var xongNgay = !cungNgay; // ca đang chờ thuộc ngày sau → ngày SX hôm nay đã chạy xong

    // Dừng máy hôm nay: log đã xong + sự cố đang mở (tính đến giờ)
    var dungTheoLoai = {}, dungPhut = 0, suCoN = 0, tach = { xl: 0, cl: 0, n: 0 };
    (D.su_co || []).forEach(function (s) {
      if (s.ngay !== ngay || !s.xong) return;
      if (s.phut_xl != null) { tach.xl += num(s.phut_xl); tach.cl += num(s.phut_cl); tach.n++; }   // T180: sự cố cần IPQC đã giao QC
      var k = loaiTen(s.loai); var o = dungTheoLoai[k] || (dungTheoLoai[k] = { loai: k, phut: 0, n: 0 });
      o.phut += num(s.phut); o.n++; dungPhut += num(s.phut_may != null ? s.phut_may : s.phut); suCoN++;
    });
    dangDung.forEach(function (m) {
      var k = loaiTen(m.loai); var o = dungTheoLoai[k] || (dungTheoLoai[k] = { loai: k, phut: 0, n: 0 });
      o.phut += m.phut; o.n++; dungPhut += m.phut; suCoN++;
    });
    var dungList = Object.keys(dungTheoLoai).map(function (k) { return dungTheoLoai[k]; }).sort(function (a, b) { return b.phut - a.phut; });

    var trend = days.map(function (d) {
      var a = dayAgg[d], isToday = d === ngay;
      var kh = a.kh + (isToday ? (ca && ca.ngay === ngay ? caKH : 0) : 0);
      var tt = a.tt + (isToday ? (ca && ca.ngay === ngay ? caTT : 0) : 0);
      return { ngay: d, nhan: isToday ? 'Hôm nay' : ddmm(d), today: isToday,
        pct: kh > 0 ? tt / kh : null,
        oee: a.oee.length ? a.oee.reduce(function (s, x) { return s + x; }, 0) / a.oee.length : null,
        ng: a.ngTT + a.ng > 0 ? a.ng / (a.ngTT + a.ng) : null,
        dung: a.dung + (isToday ? dangDung.reduce(function (s, m) { return s + m.phut; }, 0) : 0) };
    });
    var bcSorted = (D.bao_cao || []).filter(function (b) { var o = num(b.oee); return o > 0.01 && o <= 1.5; });
    var oeeGanNhat = bcSorted.length ? bcSorted[bcSorted.length - 1] : null;
    var oeeTruoc = bcSorted.length > 1 ? bcSorted[bcSorted.length - 2] : null;

    // ---- OQC ----
    var oqcByDay = {}; (D.oqc || []).forEach(function (o) { oqcByDay[o.ngay] = o; });
    var oqcT = oqcByDay[ngay];
    var oqcMt = D.oqc_mt != null ? num(D.oqc_mt) : 0.03;
    var oqcNg = oqcT && num(oqcT.n) > 0 ? num(oqcT.ng) / num(oqcT.n) : null;
    var oqcUcl = (D.oqc_ma || []).filter(function (x) {
      var cl = x.cl == null ? null : num(x.cl), n = num(x.n); if (cl == null || n <= 0) return false;
      return num(x.ng) / n > cl + 3 * Math.sqrt(cl * (1 - cl) / n);
    }).map(function (x) { return { ma: x.ma, p: num(x.ng) / num(x.n) }; });

    // ---- Vấn đề mở ----
    var ncp = (D.ncp || []).map(function (n) { return { id: n.id, ma: n.ma, may: n.may, tt: n.tt, ngay: n.ngay, tuoi: Math.max(0, Math.floor((now - new Date(n.ngay + 'T00:00:00')) / 86400000)) }; });
    var ncpQuaHan = ncp.filter(function (n) { return n.tuoi >= 2; });
    var ipqc = (D.ipqc || []).map(function (k) { return { may: k.may, ma: k.ma, kq: k.kq, phut: Math.max(0, Math.round((now - new Date(k.luc)) / 60000)) }; });

    // ---- Cần xử lý ngay (xếp theo mức ảnh hưởng) ----
    var actions = [];
    dangDung.forEach(function (m) { actions.push({ muc: m.st === 'alarm' ? 0 : 2, t: m.may + ' dừng — ' + loaiTen(m.loai), s: (m.sp || '') + (m.van_de ? ' · ' + String(m.van_de).slice(0, 60) : ''), tuoi: m.phut + '′', w: m.phut }); });
    ipqc.forEach(function (k) { actions.push({ muc: k.kq === 'NG' ? 1 : 2, t: (k.may || '') + ' — IPQC ' + (k.kq === 'NG' ? 'NG' : 'cảnh báo') + ' chưa xử lý', s: k.ma || '', tuoi: fmtTuoi(k.phut), w: k.phut }); });
    if (num(D.ipqc_tre) > 0) actions.push({ muc: 2, t: 'IPQC quá hạn kiểm: ' + D.ipqc_tre + ' điểm', s: 'Ca đang chạy', tuoi: '', w: 0 });
    oqcUcl.forEach(function (x) { actions.push({ muc: 2, t: 'OQC ' + x.ma + ' vượt UCL', s: 'NG ' + pctTxt(x.p, 1) + ' hôm nay', tuoi: 'hôm nay', w: 0 }); });
    ncpQuaHan.forEach(function (n) { actions.push({ muc: 3, t: 'NCP ' + n.id + ' chưa đóng', s: (n.ma || '') + (n.may ? ' · ' + n.may : ''), tuoi: n.tuoi + ' ngày', w: n.tuoi * 1440 }); });
    if (ngDuc != null && ngDuc > MUC_TIEU_NG_DUC) actions.push({ muc: 3, t: 'NG Đúc ' + pctTxt(ngDuc, 1) + ' > mục tiêu ' + pctTxt(MUC_TIEU_NG_DUC, 1), s: 'Tính trên ca đã kết + ca đang chạy', tuoi: 'hôm nay', w: 0 });
    actions.sort(function (a, b) { return a.muc - b.muc || b.w - a.w; });

    // ---- Kết luận 1 dòng ----
    var ket;
    var mucP = function (p) { return p >= 0.95 ? 'run' : p >= 0.85 ? 'warn' : 'alarm'; };
    if (xongNgay && pNgay != null) ket = { muc: mucP(pNgay), text: 'Đúc đạt ' + Math.round(pNgay * 100) + '% kế hoạch ngày (' + fmtN(homNay.tt) + ' / ' + fmtN(khDenGio) + ')' };
    else if (!ca) ket = { muc: 'idle', text: 'chưa có ca đang chạy' };
    else if (ca.trangThai === 'chua') ket = { muc: 'idle', text: 'chờ vào ' + ca.ten + ' lúc ' + hm(ca.start) };
    else if (pace == null) ket = { muc: 'idle', text: 'chưa có kế hoạch ca' };
    else if (pace >= 0.95) ket = { muc: 'run', text: 'đúng kế hoạch' };
    else if (pace >= 0.85) ket = { muc: 'warn', text: 'chậm nhẹ so với kế hoạch' };
    else ket = { muc: 'alarm', text: 'chậm so với kế hoạch' };
    var flags = [];
    if (xongNgay && ca) flags.push({ muc: 'idle', text: ca.ten + ' ngày ' + ddmm(ca.ngay) + ' bắt đầu ' + hm(ca.start) });
    if (pace != null && ca && ca.trangThai !== 'chua') flags.push({ muc: pace >= 0.95 ? 'run' : pace >= 0.85 ? 'warn' : 'alarm', text: 'Đúc ' + Math.round(pace * 100) + '% tiến độ giờ' });
    if (dangDung.length) flags.push({ muc: 'alarm', text: dangDung.length + ' máy đang dừng' });
    if (ngDuc != null) flags.push({ muc: ngDuc > MUC_TIEU_NG_DUC ? 'alarm' : 'run', text: 'NG Đúc ' + pctTxt(ngDuc, 1) });
    if (oqcNg != null) flags.push({ muc: oqcNg > oqcMt ? 'alarm' : 'run', text: 'NG OQC ' + pctTxt(oqcNg, 1) });
    if (ipqc.length) flags.push({ muc: 'warn', text: 'IPQC chưa xử lý: ' + ipqc.length });
    if (ncpQuaHan.length) flags.push({ muc: 'warn', text: 'NCP quá hạn: ' + ncpQuaHan.length });

    return {
      now: now, ngay: ngay, ca: ca, ket: ket, flags: flags,
      duc: { caTT: caTT, caKH: caKH, caKHNow: caKHNow, pace: pace, duBao: duBao, khNgay: num(D.kh_ngay), homNay: homNay, ngPct: ngDuc, ngMt: MUC_TIEU_NG_DUC,
        khDenGio: khDenGio, pNgay: pNgay, xongNgay: xongNgay },
      oee: { ganNhat: oeeGanNhat, truoc: oeeTruoc },
      dung: { phut: dungPhut, n: suCoN, list: dungList, dangDung: dangDung, tach: tach },
      machines: machines, demSt: demSt,
      oqc: { n: oqcT ? num(oqcT.n) : 0, ng: oqcT ? num(oqcT.ng) : 0, pct: oqcNg, mt: oqcMt, ucl: oqcUcl, byDay: oqcByDay },
      ncp: ncp, ncpQuaHan: ncpQuaHan, ipqc: ipqc, ipqcTre: num(D.ipqc_tre), nhapKho: num(D.nhap_kho),
      trend: trend, actions: actions, chuaTrienKhai: CHUA_TRIEN_KHAI,
    };
  }

  function pctTxt(x, d) { return x == null || !isFinite(x) ? '—' : (x * 100).toFixed(d == null ? 0 : d).replace('.', ',') + '%'; }
  function fmtTuoi(phut) { return phut >= 1440 ? Math.floor(phut / 1440) + ' ngày' : phut >= 60 ? Math.floor(phut / 60) + 'h' + pad(phut % 60) : phut + '′'; }
  function fmtN(n) { return Math.round(num(n)).toLocaleString('vi-VN'); }

  window.TongQuan = { load: load, compute: compute, pct: pctTxt, fmtN: fmtN, hm: hm, ddmm: ddmm, tuoi: fmtTuoi };
})();
