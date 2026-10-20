/**
 * ============================================================================
 * ipqc-text.js — rút gọn mô tả sự cố / vấn đề khuôn do IPQC tự sinh (T125).
 *
 * Hàm SQL duc_build_ipqc_issue_text ghi chuỗi dài vào duc_su_co_log.van_de,
 * duc_ca_hien_tai.open_van_de, duc_van_de_khuon.mo_ta:
 *   "IPQC phát hiện NG khi kiểm tra — loại kiểm: sau_su_co — Hạng mục không đạt:
 *    Ngoại quan — Cào xước; dính nhôm; Ngoại quan — Bong nhôm; phồng rộp —
 *    Ghi chú IPQC: Yêu cầu bộ phận đúc xử lý"
 * Chỉ rút gọn khi HIỂN THỊ (dữ liệu lưu giữ nguyên):
 *   "IPQC NG (sau sự cố): Cào xước, dính nhôm · Bong nhôm, phồng rộp"
 * Ghi chú IPQC dạng "Yêu cầu bộ phận đúc xử lý" bị bỏ; ghi chú khác giữ sau " — ".
 * Chuỗi không theo mẫu IPQC → trả về nguyên văn.
 *
 *   IpqcText.gon(text)                       // chuỗi gọn (text thuần, tự escape khi chèn HTML)
 *   IpqcText.gon(text, { boHangMuc: true })  // bỏ phần hạng mục (màn hình đã hiện riêng)
 *   IpqcText.tach(text)                      // { kq, loai, hangMuc[], ghiChu } hoặc null
 * ============================================================================
 */
(function () {
  const DAU = /^IPQC (phát hiện NG khi kiểm tra|cảnh báo NG \(cho sản xuất tiếp\) lúc kiểm tra)/;
  const NHAN = { loai: ' — loại kiểm: ', hm: ' — Hạng mục không đạt: ', gc: ' — Ghi chú IPQC: ' };
  const LOAI = { dinh_ky: 'định kỳ', sau_su_co: 'sau sự cố', doi_khuon: 'đổi khuôn' };
  const GC_THUA = /^(yêu cầu |đề nghị )?(bộ phận |bp |bộ )?(đúc )?(xử|sử) lý( giúp| ạ| nhé)?[.!]*$/i;

  function doan(s, nhan){
    const i = s.indexOf(nhan);
    if (i < 0) return '';
    let r = s.slice(i + nhan.length);
    Object.values(NHAN).forEach(n => { if (n !== nhan) { const j = r.indexOf(n); if (j >= 0) r = r.slice(0, j); } });
    return r.trim();
  }

  // "Ngoại quan — Cào xước; dính nhôm; Ngoại quan — Bong nhôm; phồng rộp; Kích thước (theo bảng tuần kiểm)"
  // → ["Cào xước, dính nhôm", "Bong nhôm, phồng rộp", "Kích thước"]. Mục mới bắt đầu bằng "Nhóm — "
  // hoặc tên mục không nhóm (Kích thước…, Điều kiện máy…); phần sau ";" còn lại là chi tiết của mục trước.
  function tachHangMuc(hm){
    const out = [];
    hm.split(/;\s*/).forEach(t => {
      if (!t) return;
      const moi = t.includes(' — ') || /^(Kích thước|Điều kiện máy|Toàn bộ)/i.test(t) || !out.length;
      if (moi) out.push(t.replace(/^[^—]{1,40} — /, '').replace(/\s*\(theo bảng tuần kiểm\)/i, '').trim());
      else out[out.length - 1] += ', ' + t.trim();
    });
    return out.filter(Boolean);
  }

  function tach(text){
    const s = String(text || '').trim();
    const m = s.match(DAU);
    if (!m) return null;
    const ghiChu = doan(s, NHAN.gc);
    return {
      kq: m[1].startsWith('phát hiện') ? 'NG' : 'Cảnh báo',
      loai: LOAI[doan(s, NHAN.loai)] || doan(s, NHAN.loai),
      hangMuc: tachHangMuc(doan(s, NHAN.hm)),
      ghiChu: GC_THUA.test(ghiChu) ? '' : ghiChu,
    };
  }

  function gon(text, opt){
    const t = tach(text);
    if (!t) return text == null ? '' : String(text);
    const hm = opt && opt.boHangMuc ? [] : t.hangMuc;
    return 'IPQC ' + t.kq + (t.loai ? ' (' + t.loai + ')' : '') + (hm.length ? ': ' + hm.join(' · ') : '') + (t.ghiChu ? ' — ' + t.ghiChu : '');
  }

  window.IpqcText = { gon, tach };
})();
