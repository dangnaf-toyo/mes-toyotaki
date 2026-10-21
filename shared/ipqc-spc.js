/**
 * ============================================================================
 * ipqc-spc.js — T133: tính toán dùng chung cho bảng tuần kiểm kích thước IPQC
 * (ipqc.html + qc-manager.html): giới hạn tiêu chuẩn, giới hạn kiểm soát
 * I-MR / X̄-R, 4 quy tắc phát hiện sớm, Cp/Cpk, vẽ biểu đồ SVG.
 * Dữ liệu vào = kết quả RPC ipqc_do_du_lieu (btk, muc, gioi_han, lan[]).
 * ============================================================================
 */
(function () {
  const A2 = { 2: 1.880, 3: 1.023, 4: 0.729, 5: 0.577 };
  const D4 = { 2: 3.267, 3: 2.574, 4: 2.282, 5: 2.114 };

  function num(v) { return v === null || v === undefined || v === '' ? null : Number(v); }
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

  // Số chữ số thập phân hiển thị theo danh nghĩa/dung sai (tối thiểu 2).
  function soLe(m) {
    let d = 2;
    [m.danh_nghia, m.dung_sai_tren, m.dung_sai_duoi].forEach(v => {
      if (v === null || v === undefined) return;
      const s = String(v); const i = s.indexOf('.');
      if (i >= 0) d = Math.max(d, s.length - i - 1);
    });
    return Math.min(d, 4);
  }
  function fmt(v, d) { return v === null || v === undefined || !isFinite(v) ? '—' : Number(v).toFixed(d ?? 3); }

  function specMuc(m) {
    const dn = num(m.danh_nghia);
    const tren = num(m.dung_sai_tren), duoi = num(m.dung_sai_duoi);
    return { usl: dn !== null && tren !== null ? dn + tren : null, lsl: dn !== null && duoi !== null ? dn - duoi : null };
  }
  // "14.8 +0/−0.2", "Ø4.2 ±0.1"
  function chuanText(m) {
    if (m.kieu !== 'so') return m.tieu_chuan || '';
    const tren = num(m.dung_sai_tren), duoi = num(m.dung_sai_duoi);
    const dn = String(m.danh_nghia);
    if (tren !== null && duoi !== null && tren === duoi) return dn + ' ±' + tren;
    return dn + ' ' + (tren === null ? '' : '+' + tren) + (tren !== null && duoi !== null ? '/' : '') + (duoi === null ? '' : '−' + duoi);
  }
  function datGiaTri(v, sp) {
    if (v === null || !isFinite(v)) return null;
    return (sp.usl === null || v <= sp.usl + 1e-9) && (sp.lsl === null || v >= sp.lsl - 1e-9);
  }
  // Còn ≤10% bề rộng dung sai tới 1 giới hạn tiêu chuẩn.
  function satGioiHan(v, sp) {
    if (v === null || sp.usl === null || sp.lsl === null) return false;
    const band = (sp.usl - sp.lsl) * 0.1;
    return (v <= sp.usl && v > sp.usl - band) || (v >= sp.lsl && v < sp.lsl + band);
  }

  // Chuỗi điểm theo thời gian cho 1 hạng mục: x = giá trị (1 mẫu) hoặc trung bình nhóm.
  function chuoi(data, mucNo, loc) {
    return (data.lan || []).filter(l => !loc || loc(l)).map(l => {
      const vs = (l.kq || []).filter(k => k.muc_no === mucNo && k.gia_tri !== null).map(k => Number(k.gia_tri));
      if (!vs.length) return null;
      const x = vs.reduce((s, v) => s + v, 0) / vs.length;
      return { t: l.thoi_diem, may: l.ma_may, khuon: l.so_khuon, nguoi: l.nguoi, id: l.id_checkpoint, vals: vs, x, r: Math.max(...vs) - Math.min(...vs) };
    }).filter(Boolean);
  }

  // Giới hạn kiểm soát: đã khoá (gioi_han dang_dung) hoặc TẠM tính từ dữ liệu đang có (≥5 điểm).
  function gioiHan(data, mucNo, soMau, pts) {
    const h = (data.gioi_han || []).find(g => g.muc_no === mucNo);
    if (h) return { cl: +h.cl, ucl: +h.ucl, lcl: +h.lcl, clR: +h.cl_r, uclR: +h.ucl_r, n: h.n_lan, cach: h.cach, tam: false, raw: h };
    if (!pts || pts.length < 5) return null;
    const xs = pts.slice(0, 30).map(p => p.x);
    const cl = xs.reduce((s, v) => s + v, 0) / xs.length;
    if ((soMau || 1) <= 1) {
      const mr = xs.slice(1).map((v, i) => Math.abs(v - xs[i]));
      const mrb = mr.reduce((s, v) => s + v, 0) / mr.length;
      return { cl, ucl: cl + 2.66 * mrb, lcl: cl - 2.66 * mrb, clR: mrb, uclR: 3.267 * mrb, n: xs.length, tam: true };
    }
    const rb = pts.slice(0, 30).reduce((s, p) => s + p.r, 0) / Math.min(pts.length, 30);
    const k = Math.min(soMau, 5);
    return { cl, ucl: cl + A2[k] * rb, lcl: cl - A2[k] * rb, clR: rb, uclR: D4[k] * rb, n: xs.length, tam: true };
  }

  // 4 quy tắc phát hiện sớm. Trả [{i, quy_tac, msg}] — i = điểm kết thúc chuỗi vi phạm.
  function quyTac(xs, lim) {
    const out = [];
    if (!lim || !(lim.ucl > lim.lcl)) return out;
    const s = (lim.ucl - lim.cl) / 3;
    xs.forEach((x, i) => {
      if (x > lim.ucl || x < lim.lcl) out.push({ i, quy_tac: 1, msg: 'Vượt ' + (x > lim.ucl ? 'UCL' : 'LCL') });
      if (i >= 8) {
        const w = xs.slice(i - 8, i + 1);
        if (w.every(v => v > lim.cl) || w.every(v => v < lim.cl)) {
          const truoc = i >= 9 && (w.every(v => v > lim.cl) ? xs[i - 9] > lim.cl : xs[i - 9] < lim.cl);
          if (!truoc) out.push({ i, quy_tac: 2, msg: '9 điểm liên tiếp ' + (w[0] > lim.cl ? 'trên' : 'dưới') + ' đường trung tâm' });
        }
      }
      if (i >= 5) {
        const w = xs.slice(i - 5, i + 1);
        const tang = w.every((v, k) => k === 0 || v > w[k - 1]), giam = w.every((v, k) => k === 0 || v < w[k - 1]);
        if (tang || giam) out.push({ i, quy_tac: 3, msg: '6 điểm ' + (tang ? 'tăng' : 'giảm') + ' liên tục' });
      }
      if (i >= 2) {
        const w = xs.slice(i - 2, i + 1);
        const tren = w.filter(v => v > lim.cl + 2 * s).length, duoi = w.filter(v => v < lim.cl - 2 * s).length;
        if ((tren >= 2 && x > lim.cl + 2 * s) || (duoi >= 2 && x < lim.cl - 2 * s)) out.push({ i, quy_tac: 4, msg: '2/3 điểm vượt 2σ ' + (tren >= 2 ? 'phía trên' : 'phía dưới') });
      }
    });
    return out;
  }

  function nangLuc(vals, sp) {
    const n = vals.length;
    if (n < 2) return { n, tb: n ? vals[0] : null, sd: null, cp: null, cpk: null };
    const tb = vals.reduce((s, v) => s + v, 0) / n;
    const sd = Math.sqrt(vals.reduce((s, v) => s + (v - tb) ** 2, 0) / (n - 1));
    const cp = sp.usl !== null && sp.lsl !== null && sd > 0 ? (sp.usl - sp.lsl) / (6 * sd) : null;
    const k = [sp.usl !== null ? (sp.usl - tb) : null, sp.lsl !== null ? (tb - sp.lsl) : null].filter(v => v !== null);
    const cpk = sd > 0 && k.length ? Math.min(...k) / (3 * sd) : null;
    return { n, tb, sd, cp, cpk };
  }

  // Biểu đồ SVG. o: {pts:[{x, nhan, mau}], lim:{cl,ucl,lcl}, usl, lsl, d, h, nhanGH, vung:[{tu,den}]}
  function bieuDo(o) {
    const W = 820, H = o.h || 280, L = 56, R = 76, T = 10, B = 24;
    const pw = W - L - R, ph = H - T - B;
    const ys = o.pts.map(p => p.x);
    [o.usl, o.lsl, o.lim && o.lim.ucl, o.lim && o.lim.lcl, o.lim && o.lim.cl].forEach(v => { if (v !== null && v !== undefined && isFinite(v)) ys.push(v); });
    if (!ys.length) return '<div class="spc-empty">Chưa có dữ liệu</div>';
    let lo = Math.min(...ys), hi = Math.max(...ys);
    if (hi - lo < 1e-9) { hi += 0.01; lo -= 0.01; }
    const pad = (hi - lo) * 0.08; lo -= pad; hi += pad;
    const Y = v => T + (hi - v) / (hi - lo) * ph;
    const n = o.pts.length;
    const X = i => L + (n <= 1 ? pw / 2 : 10 + i * (pw - 20) / (n - 1));
    const d = o.d ?? 3;
    let s = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" role="img" aria-label="' + esc(o.aria || 'Biểu đồ kiểm soát') + '" style="display:block">';
    s += '<rect x="' + L + '" y="' + T + '" width="' + pw + '" height="' + ph + '" fill="#FBFCFE" stroke="#E2E8F0"/>';
    (o.vung || []).forEach(v => {
      const x1 = X(v.tu) - 8, x2 = X(v.den) + 8;
      s += '<rect x="' + x1.toFixed(1) + '" y="' + (T + 2) + '" width="' + (x2 - x1).toFixed(1) + '" height="' + (ph - 4) + '" fill="#F59E0B" fill-opacity="0.12"/>';
    });
    const line = (v, color, dash, w, label, bold) => {
      if (v === null || v === undefined || !isFinite(v)) return;
      const y = Y(v).toFixed(1);
      s += '<line x1="' + L + '" x2="' + (L + pw) + '" y1="' + y + '" y2="' + y + '" stroke="' + color + '" stroke-width="' + w + '"' + (dash ? ' stroke-dasharray="' + dash + '"' : '') + '/>';
      s += '<text x="' + (L + pw + 5) + '" y="' + (+y + 4) + '" font-size="11" font-weight="' + (bold ? 700 : 400) + '" fill="' + color + '">' + esc(label + ' ' + fmt(v, d)) + '</text>';
    };
    line(o.usl, '#B91C1C', '6 4', 1.5, 'USL', true);
    line(o.lsl, '#B91C1C', '6 4', 1.5, 'LSL', true);
    if (o.lim) {
      const nh = o.nhanGH || ['UCL', 'X̄', 'LCL'];
      line(o.lim.ucl, '#B45309', '3 3', 1.2, nh[0], true);
      line(o.lim.cl, '#475569', '', 1, nh[1], false);
      if (o.lim.lcl !== null && o.lim.lcl !== undefined) line(o.lim.lcl, '#B45309', '3 3', 1.2, nh[2], true);
    }
    s += '<text x="' + (L - 4) + '" y="' + (T + 10) + '" font-size="10.5" fill="#64748B" text-anchor="end">' + fmt(hi, d) + '</text>';
    s += '<text x="' + (L - 4) + '" y="' + (T + ph) + '" font-size="10.5" fill="#64748B" text-anchor="end">' + fmt(lo, d) + '</text>';
    if (n > 1) s += '<polyline points="' + o.pts.map((p, i) => X(i).toFixed(1) + ',' + Y(p.x).toFixed(1)).join(' ') + '" fill="none" stroke="#0F5FA5" stroke-width="1.5"/>';
    o.pts.forEach((p, i) => {
      s += '<circle cx="' + X(i).toFixed(1) + '" cy="' + Y(p.x).toFixed(1) + '" r="' + (p.mau && p.mau !== '#0F5FA5' ? 5 : 3.6) + '" fill="' + (p.mau || '#0F5FA5') + '" stroke="#fff" stroke-width="1.2">' +
        (p.nhan ? '<title>' + esc(p.nhan) + '</title>' : '') + '</circle>';
    });
    if (n) {
      s += '<text x="' + L + '" y="' + (H - 6) + '" font-size="10.5" fill="#64748B">' + esc(o.pts[0].tg || '') + '</text>';
      s += '<text x="' + (L + pw) + '" y="' + (H - 6) + '" font-size="10.5" fill="#64748B" text-anchor="end">' + esc(o.pts[n - 1].tg || '') + '</text>';
    }
    return s + '</svg>';
  }

  window.IpqcSpc = { num, esc, soLe, fmt, specMuc, chuanText, datGiaTri, satGioiHan, chuoi, gioiHan, quyTac, nangLuc, bieuDo, A2, D4 };
})();
