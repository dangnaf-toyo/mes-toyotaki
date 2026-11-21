/**
 * ============================================================================
 * su-co-lich-su.js — Lịch sử đầy đủ của 1 sự cố Đúc dạng dòng thời gian (T122).
 * Dùng ở ipqc.html khi IPQC kiểm sản phẩm đầu tiên sau xử lý sự cố, và ở
 * su-co-duc.html khi bấm 1 dòng sự cố.
 *
 * Nhúng SAU shared/supabase-client.js (cần `sb`).
 *
 *   SuCoLichSu.mount(el, 'SC-DC7-1019-1400')
 *
 * Dữ liệu: RPC duc_su_co_lich_su (migration T122) — nhật ký sự cố (ai báo / ai
 * sửa nội dung, ghi từ 20/10/2026), duc_su_co_log (từng phần theo ca, máy chạy
 * lại), lần IPQC phát hiện NG (F1), ảnh hiện trạng / sau xử lý, phiếu tổ khuôn,
 * linh kiện đã thay, các lần IPQC kiểm, đề nghị cho tiếp tục SX.
 *
 * T298 tinh gọn: đầu khung = trạng thái + thanh chia phút dừng (Xử lý / Chờ QC);
 * dòng thời gian chỉ mốc chính, mỗi mốc 1 dòng; vấn đề / xử lý mỗi thứ hiện 1 lần;
 * ảnh gom 1 dải Trước / Sau / IPQC; việc phụ (sửa nội dung, linh kiện, duyệt đề
 * nghị, xoá, bấm Xong bị chặn) gom vào "Khác (n)" bấm mới mở.
 * T300: dải ảnh đủ từ phát sinh đến khi đóng (cả phiếu IPQC khác cùng máy), giờ dưới mỗi ảnh.
 * Bấm ảnh mở trình xem phóng to (Qc02View.photo nếu có, không thì tab mới).
 * ============================================================================
 */
(function () {
  const COT = { loai: 'Loại', gio_phat_sinh: 'Giờ phát sinh', gio_tro_lai: 'Giờ trở lại', van_de: 'Vấn đề',
    noi_dung_xu_ly: 'Xử lý', dam_nhiem: 'Đảm nhiệm' };
  const KQ = { OK: ['OK', 'ok'], NG: ['NG', 'ng'], CANH_BAO: ['Cảnh báo', 'cb'] };
  const LOAI_KIEM = { dinh_ky: 'định kỳ', sau_su_co: 'sau sự cố', doi_khuon: 'đổi khuôn' };
  const LK_LOAI = { xuat_thay: 'Thay', thao_ra: 'Tháo', nhap: 'Nhập kho', dieu_chinh: 'Điều chỉnh' };

  function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  const gonIpqc = t => (window.IpqcText ? IpqcText.gon(t) : (t || ''));
  function pad(n){ return String(n).padStart(2, '0'); }
  function tg(ts){ if (!ts) return '—'; const d = new Date(ts); return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ' ' + pad(d.getDate()) + '/' + pad(d.getMonth() + 1); }
  function giaTri(k, v){ if (v == null || v === '') return '(trống)'; return (k === 'gio_phat_sinh' || k === 'gio_tro_lai') ? tg(v) : (sach(v) || '(trống)'); }
  // Bỏ các dòng hệ thống tự nối khi kết ca: "[Chuyển tiếp từ …]", "[Phần 2/5 — …]".
  const sach = t => String(t || '').split('\n').filter(s => !/^\s*\[(Chuyển tiếp|Phần \d+\/\d+)[^\]]*\]\s*$/.test(s)).join('\n').trim();
  const chuan = t => sach(t).replace(/[—–]/g, '-').replace(/\s+/g, ' ').trim().toLowerCase();
  const giongNhau = (a, b) => chuan(a) === chuan(b);

  // Các phần log theo ca. Máy khuôn kép ghi 1 sự cố thành nhiều dòng CÙNG ca (mỗi
  // mã SP 1 dòng, cùng giờ) → gom theo (ngày, ca), phút dừng lấy max, không cộng.
  function theoCa(log){
    const m = new Map();
    (log || []).forEach(l => {
      const k = l.ngay + '|' + l.ca;
      const g = m.get(k);
      const xl = l.phut_xu_ly != null ? Number(l.phut_xu_ly) : null, cl = l.phut_xac_nhan_cl != null ? Number(l.phut_xac_nhan_cl) : null;
      if (!g) m.set(k, { ...l, phut: Number(l.thoi_gian_dung_phut) || 0, xl, cl, ma_sps: [l.ma_sp] });
      else {
        g.phut = Math.max(g.phut, Number(l.thoi_gian_dung_phut) || 0);
        if (xl != null) { g.xl = Math.max(g.xl || 0, xl); g.cl = Math.max(g.cl || 0, cl || 0); }   // T180
        if (!g.ma_sps.includes(l.ma_sp)) g.ma_sps.push(l.ma_sp);
        if (l.gio_tro_lai && (!g.gio_tro_lai || l.gio_tro_lai > g.gio_tro_lai)) g.gio_tro_lai = l.gio_tro_lai;
        ['noi_dung_xu_ly', 'dam_nhiem', 'ghi_chu'].forEach(f => { if (l[f]) g[f] = l[f]; });
      }
    });
    return [...m.values()].sort((a, b) => new Date(a.gio_phat_sinh) - new Date(b.gio_phat_sinh));
  }

  function injectCss(){
    if (document.getElementById('sclh-css')) return;
    const st = document.createElement('style');
    st.id = 'sclh-css';
    st.textContent =
      '.sclh{font-size:.85rem;color:#0F172A}' +
      '.sclh-top{display:flex;flex-wrap:wrap;align-items:baseline;gap:.25rem .6rem;margin-bottom:.35rem}' +
      '.sclh-st{font-weight:700;font-size:.95rem}.sclh-st.dung{color:#B91C1C}.sclh-st.chay{color:#047857}' +
      '.sclh-id{font-family:"JetBrains Mono",monospace;font-size:.75rem;color:#64748B}' +
      '.sclh-bar{display:flex;height:.5rem;border-radius:.25rem;overflow:hidden;background:#E2E8F0;max-width:420px}' +
      '.sclh-bar i{display:block;height:100%}.sclh-bar .xl{background:#F59E0B}.sclh-bar .cl{background:#3B82F6}' +
      '.sclh-leg{display:flex;flex-wrap:wrap;gap:.2rem .8rem;font-size:.75rem;color:#475569;margin:.25rem 0 .6rem}' +
      '.sclh-leg b{font-weight:600}.sclh-leg b:before{content:"";display:inline-block;width:.55rem;height:.55rem;border-radius:.15rem;margin-right:.25rem}' +
      '.sclh-leg .xl:before{background:#F59E0B}.sclh-leg .cl:before{background:#3B82F6}' +
      '.sclh-tl{position:relative;margin-left:.55rem;padding-left:1.1rem;border-left:2px solid #E2E8F0}' +
      '.sclh-ev{position:relative;margin-bottom:.5rem}' +
      '.sclh-ev:before{content:"";position:absolute;left:-1.52rem;top:.2rem;width:.7rem;height:.7rem;border-radius:50%;background:#fff;border:2px solid #94A3B8}' +
      '.sclh-ev.do:before{border-color:#DC2626;background:#FEE2E2}.sclh-ev.xanh:before{border-color:#059669;background:#D1FAE5}' +
      '.sclh-ev.cam:before{border-color:#D97706;background:#FEF3C7}.sclh-ev.lam:before{border-color:#2563EB;background:#DBEAFE}' +
      '.sclh-h{display:flex;flex-wrap:wrap;gap:.35rem;align-items:baseline}' +
      '.sclh-h .t{font-family:"JetBrains Mono",monospace;font-size:.75rem;color:#64748B;white-space:nowrap}' +
      '.sclh-h .ti{font-weight:700}' +
      '.sclh-h .ng{color:#64748B;font-size:.78rem;font-weight:400}' +
      '.sclh-b{margin-top:.1rem;color:#334155;white-space:pre-wrap;word-break:break-word}' +
      '.sclh-b .lb{color:#64748B}' +
      '.sclh-diff{margin-top:.1rem;font-size:.8rem}' +
      '.sclh-diff .lb{color:#64748B}.sclh-diff del{color:#94A3B8}.sclh-diff ins{text-decoration:none;color:#0F172A;font-weight:600}' +
      '.sclh-tag{display:inline-block;font-size:.72rem;font-weight:700;padding:.05rem .4rem;border-radius:.3rem;background:#E2E8F0;color:#334155}' +
      '.sclh-tag.ok{background:#D1FAE5;color:#065F46}.sclh-tag.ng{background:#FEE2E2;color:#991B1B}.sclh-tag.cb{background:#FEF3C7;color:#92400E}' +
      '.sclh-ngl{display:flex;flex-wrap:wrap;gap:.25rem;margin-top:.2rem}' +
      '.sclh-ngl span{font-size:.72rem;background:#FEE2E2;color:#991B1B;border-radius:.3rem;padding:.05rem .35rem}' +
      '.sclh-anh{display:flex;flex-wrap:wrap;gap:.4rem 1rem;margin:.3rem 0 .4rem}' +
      '.sclh-anh>div{display:flex;align-items:center;gap:.35rem;flex-wrap:wrap}.sclh-anh .lb{font-size:.75rem;color:#64748B;font-weight:600}' +
      '.sclh-ph{display:flex;flex-wrap:wrap;gap:.3rem}' +
      '.sclh-ph img{width:56px;height:56px;object-fit:cover;border-radius:.4rem;border:1px solid #CBD5E1;cursor:zoom-in;display:block}' +
      '.sclh-ph figure{margin:0;text-align:center}.sclh-ph figcaption{font-size:11px;color:#94A3B8;line-height:1.2;margin-top:1px}' +
      '.sclh-khac{margin-top:.2rem}.sclh-khac>summary{cursor:pointer;font-size:.8rem;color:#475569;font-weight:600;padding:.2rem 0;list-style:none}' +
      '.sclh-khac>summary::-webkit-details-marker{display:none}.sclh-khac[open]>summary .mu{display:inline-block;transform:rotate(90deg)}' +
      '.sclh-khac .sclh-tl{margin-top:.4rem}' +
      '.sclh-note{font-size:.75rem;color:#94A3B8;margin-top:.4rem}' +
      '.sclh-err{color:#B91C1C}';
    document.head.appendChild(st);
  }

  // T300: ds = [{url, ts, ng}] — mỗi ảnh kèm giờ chụp/kiểm bên dưới, giữ thứ tự thời gian.
  function anhHtml(ds, gio){
    ds = (ds || []).filter(a => a && a.url);
    if (!ds.length) return '';
    const urls = esc(JSON.stringify(ds.map(a => a.url)));
    return '<div class="sclh-ph">' + ds.map((a, i) => '<figure><img src="' + esc(a.url) + '" alt="" loading="lazy" data-sclh-i="' + i + '" data-sclh-urls="' + urls + '"' +
      (a.ng ? ' title="' + esc(String(a.ng).replace(/^\d+_/, '')) + '"' : '') + '>' +
      (a.ts ? '<figcaption>' + esc(gio(a.ts)) + '</figcaption>' : '') + '</figure>').join('') + '</div>';
  }
  function ngHtml(checklist){
    const ng = (Array.isArray(checklist) ? checklist : []).filter(x => x && x.dat === false).map(x => x.muc);
    return ng.length ? '<div class="sclh-ngl">' + ng.map(m => '<span>✗ ' + esc(m) + '</span>').join('') + '</div>' : '';
  }
  // Chỉ các trường đổi thật (bỏ đổi do hệ thống nối dòng chuyển ca / đổi dấu gạch).
  const doiThat = td => Object.keys(td || {}).filter(k => !giongNhau(td[k].cu, td[k].moi));
  function diffHtml(td){
    if (!td) return '';
    return '<div class="sclh-diff">' + doiThat(td).map(k =>
      '<div><span class="lb">' + esc(COT[k] || k) + ':</span> <del>' + esc(giaTri(k, td[k].cu)) + '</del> → <ins>' + esc(giaTri(k, td[k].moi)) + '</ins></div>').join('') + '</div>';
  }
  // 1 dòng nội dung, nhãn ngắn chỉ khi cần phân biệt.
  function dong(lb, v){ return v ? '<div class="sclh-b">' + (lb ? '<span class="lb">' + esc(lb) + ':</span> ' : '') + esc(v) + '</div>' : ''; }
  const tagKq = kq => '<span class="sclh-tag ' + kq[1] + '">' + esc(kq[0]) + '</span>';

  // Gom dữ liệu RPC thành danh sách sự kiện {t, cls, ti, ng, body, phu}.
  // phu = việc phụ → gom vào "Khác (n)". Ảnh không thành mốc riêng (xem daiAnh).
  function suKien(d){
    const ev = [];
    // Tên người bỏ mã NV phía trước ("210202_Nguyễn Thị Bình" → "Nguyễn Thị Bình").
    const add = (t, cls, ti, ng, body, phu) => ev.push({ t: t ? new Date(t).getTime() : 0, ts: t, cls, ti, ng: String(ng || '').replace(/^\d+_/, ''), body: body || '', phu: !!phu });
    const log = theoCa(d.log);
    const goc = log[0] || d.dang_mo || {};
    const cuoi = d.dang_mo || log[log.length - 1] || {};
    const nk = d.nhat_ky || [];
    const nkMo = nk.find(k => k.su_kien === 'mo');
    const moDl = (nkMo && nkMo.du_lieu) || {};

    const ph = d.phat_hien_ipqc;
    if (ph) add(ph.thoi_diem_kiem_thuc_te, 'do', '🔍 IPQC phát hiện ' + tagKq(KQ[ph.ket_qua] || [ph.ket_qua || '?', '']),
      ph.nguoi_kiem, ngHtml(ph.checklist_json) + dong('', ph.ghi_chu));

    // Vấn đề: bản mới nhất (đã sửa), chỉ hiện 1 lần ở mốc phát sinh.
    add(goc.gio_phat_sinh || moDl.gio_phat_sinh, 'do', '🚨 Phát sinh', nkMo ? nkMo.nguoi : '',
      dong('', gonIpqc(cuoi.van_de || moDl.van_de || goc.van_de)));

    nk.filter(k => k.su_kien === 'giao_qc').forEach(k => add(k.thoi_diem, 'lam',
      '📦 Giao QC' + (k.du_lieu && k.du_lieu.lan > 1 ? ' (lần ' + k.du_lieu.lan + ')' : ''), k.nguoi, ''));
    nk.filter(k => k.su_kien === 'cap_nhat' && doiThat(k.thay_doi).length).forEach(k => add(k.thoi_diem, 'lam', '✏️ Sửa nội dung', k.nguoi, diffHtml(k.thay_doi), true));
    nk.filter(k => k.su_kien === 'sua_sau_dong' && doiThat(k.thay_doi).length).forEach(k => add(k.thoi_diem, 'lam', '✏️ Sửa sau khi đóng', k.nguoi, diffHtml(k.thay_doi), true));
    // T232: lần bấm "Xong" bị hệ thống chặn (chưa đủ điều kiện đóng).
    const LY_DO_TC = { can_thiep: 'chưa duyệt can thiệp khuôn', giao_qc: 'chưa giao QC', ipqc: 'IPQC chưa đạt', thieu_noi_dung: 'thiếu nội dung xử lý / đảm nhiệm', khac: 'khác' };
    // T299: IPQC kiểm NG trên máy trong lúc sự cố này đang mở (phiếu định kỳ / sự cố khác).
    nk.filter(k => k.su_kien === 'ipqc_ng').forEach(k => {
      const dl = k.du_lieu || {};
      add(k.thoi_diem, 'do', '🧪 IPQC ' + tagKq(KQ.NG) +
        (dl.loai_kiem && dl.loai_kiem !== 'sau_su_co' ? ' <span class="ng">' + esc(LOAI_KIEM[dl.loai_kiem] || dl.loai_kiem) + '</span>' : ''),
        k.nguoi, dong('', gonIpqc(dl.noi_dung)));
    });
    nk.filter(k => k.su_kien === 'tu_choi_dong').forEach(k => add(k.thoi_diem, 'do',
      '⛔ Bấm Xong bị chặn — ' + esc(LY_DO_TC[(k.du_lieu || {}).ly_do] || 'khác'), k.nguoi, '', true));
    nk.filter(k => k.su_kien === 'xoa').forEach(k => add(k.thoi_diem, 'do', '🗑 Xoá 1 phần (' + esc(k.ca || '') + ')', k.nguoi, '', true));

    const x = d.to_khuon;
    if (x) {
      add(x.bat_dau || x.cap_nhat_luc, 'lam', '🔧 Tổ khuôn nhận', [x.nguoi_dam_nhiem, x.nguoi_dam_nhiem_phu].filter(Boolean).join(' + '),
        x.trang_thai === 'hoan_thanh' ? '' : dong('', sach(x.noi_dung_xu_ly)));
      if (x.trang_thai === 'hoan_thanh') add(x.ket_thuc || x.hoan_thanh_luc, 'xanh',
        '✅ Tổ khuôn xong' + (x.bat_dau && x.ket_thuc ? ' (' + Math.round((new Date(x.ket_thuc) - new Date(x.bat_dau)) / 60000) + 'p)' : ''),
        x.nguoi_hoan_thanh, dong('', sach(x.noi_dung_xu_ly)));
    }

    (d.linh_kien || []).forEach(g => add(g.thoi_diem, 'lam',
      '🔩 ' + esc(LK_LOAI[g.loai] || g.loai) + ' ' + esc(g.ten_lk || g.ma_lk || '') + (g.so_luong != null ? ' ×' + esc(g.so_luong) : ''), g.nguoi,
      dong('', [g.ma_khuon, g.vi_tri, g.muc_dich, g.ket_qua_thao, g.ghi_chu].filter(Boolean).join(' · ')), true));

    // Sự cố vắt ca: mỗi phần log trừ phần cuối = kết ca chuyển tiếp (việc phụ — hệ thống tự ghi).
    const xong = !d.dang_mo;
    log.forEach((l, i) => {
      if (xong && i === log.length - 1) return;
      add(l.gio_tro_lai, '', '🔁 Chuyển ca' + (l.ca ? ' · ' + esc(l.ca) : '') + ' · ' + Math.round(l.phut) + 'p', l.truong_ca || '', '', true);
    });

    (d.ipqc || []).filter(c => c.trang_thai === 'da_kiem').forEach(c => {
      const kq = KQ[c.ket_qua] || [c.ket_qua || '?', ''];
      add(c.thoi_diem_kiem_thuc_te, kq[1] === 'ok' ? 'xanh' : 'do',
        '🧪 IPQC ' + tagKq(kq) + (c.loai_kiem && c.loai_kiem !== 'sau_su_co' ? ' <span class="ng">' + esc(LOAI_KIEM[c.loai_kiem] || c.loai_kiem) + '</span>' : ''),
        c.nguoi_kiem, ngHtml(c.checklist_json) + dong('', c.ghi_chu));
    });
    // T300: phiếu IPQC khác cùng máy trong lúc dừng (định kỳ / đổi khuôn / sự cố khác).
    // NG đã có mốc 'ipqc_ng' (T299) thì không lặp; OK gom vào "Khác".
    const daNg = new Set(nk.filter(k => k.su_kien === 'ipqc_ng').map(k => (k.du_lieu || {}).id_checkpoint));
    (d.ipqc_khac || []).filter(c => !daNg.has(c.id_checkpoint)).forEach(c => {
      const kq = KQ[c.ket_qua] || [c.ket_qua || '?', ''];
      add(c.thoi_diem_kiem_thuc_te, kq[1] === 'ok' ? 'xanh' : 'do',
        '🧪 IPQC ' + tagKq(kq) + ' <span class="ng">' + esc(LOAI_KIEM[c.loai_kiem] || c.loai_kiem || '') +
        (c.id_su_co_goc ? ' · ' + esc(c.id_su_co_goc) : '') + '</span>',
        c.nguoi_kiem, kq[1] === 'ok' ? '' : ngHtml(c.checklist_json) + dong('', c.ghi_chu), kq[1] === 'ok');
    });

    (d.tiep_tuc || []).forEach(r => {
      add(r.created_at, 'cam', '📝 Đề nghị tiếp tục SX <span class="sclh-tag">' + esc(r.status || '') + '</span>', r.requester_name,
        dong('', [r.reason_detail || r.reason_type, r.allowed_until ? 'đến ' + tg(r.allowed_until) : '', r.allowed_qty ? r.allowed_qty + ' cái' : ''].filter(Boolean).join(' · ')));
      // Bỏ "TẠO YÊU CẦU" (đã có mốc trên) và "CẬP NHẬT SẢN LƯỢNG" (tự động, nhiều dòng).
      (r.audit || []).filter(a => a.action && !['TẠO YÊU CẦU', 'CẬP NHẬT SẢN LƯỢNG'].includes(a.action)).forEach(a => {
        const dt = a.detail && typeof a.detail === 'object' ? a.detail : {};
        add(a.created_at, 'cam', '📝 ' + esc(a.action.charAt(0) + a.action.slice(1).toLowerCase()) + ' đề nghị', a.actor_name,
          dong('', [dt.from || dt.to ? [dt.from, dt.to].filter(Boolean).join(' → ') : '', dt.note || dt.reason].filter(Boolean).join(' · ')), true);
      });
    });

    if (xong && log.length) {
      const l = log[log.length - 1];
      const nkDong = nk.filter(k => k.su_kien === 'dong').pop();
      // Nội dung xử lý chỉ hiện khi khác nội dung tổ khuôn đã ghi.
      const xlSx = x && x.trang_thai === 'hoan_thanh' && giongNhau(x.noi_dung_xu_ly, l.noi_dung_xu_ly) ? '' : sach(l.noi_dung_xu_ly);
      add(l.gio_tro_lai, 'xanh', '▶ Chạy lại', l.dam_nhiem || (nkDong ? nkDong.nguoi : '') || l.truong_ca || '',
        dong('', xlSx) + dong('Ghi chú', l.ghi_chu));
    }
    return ev.sort((a, b) => a.t - b.t);
  }

  // Đầu khung: trạng thái + thanh chia phút dừng (T180: Xử lý đến lần giao QC cuối / sau đó
  // là chờ - xác nhận chất lượng). Máy, SP, loại đã có ở dòng danh sách → chỉ còn mã nhỏ.
  function dauKhung(d){
    const log = theoCa(d.log), m = d.dang_mo, goc = log[0] || m || {};
    const phut = Math.round(log.reduce((s, l) => s + l.phut, 0) +
      (m && m.gio_phat_sinh ? Math.max(0, (Date.now() - new Date(m.gio_phat_sinh)) / 60000) : 0));
    const st = m ? '<span class="sclh-st dung">⛔ Đang dừng ' + phut + ' phút</span>'
      : '<span class="sclh-st chay">▶ Dừng ' + phut + ' phút</span>';
    let xl = null, cl = null;
    const giao = (d.nhat_ky || []).filter(k => k.su_kien === 'giao_qc').pop();
    if (m && giao && m.gio_phat_sinh) {
      const t0 = new Date(m.gio_phat_sinh), t1 = new Date(giao.thoi_diem);
      xl = Math.max(0, Math.round((t1 - t0) / 60000)); cl = Math.max(0, Math.round((Date.now() - t1) / 60000));
    } else if (!m && log.some(l => l.xl != null)) {
      xl = Math.round(log.reduce((s, l) => s + (l.xl || 0), 0)); cl = Math.round(log.reduce((s, l) => s + (l.cl || 0), 0));
    }
    let bar = '';
    if (xl != null && xl + cl > 0) {
      const p = Math.round(xl / (xl + cl) * 100);
      bar = '<div class="sclh-bar"><i class="xl" style="width:' + p + '%"></i><i class="cl" style="width:' + (100 - p) + '%"></i></div>' +
        '<div class="sclh-leg"><b class="xl">Xử lý ' + xl + 'p</b><b class="cl">' + (m ? 'Chờ QC ' : 'Xác nhận CL ') + cl + 'p</b></div>';
    }
    return '<div class="sclh-top">' + st + '<span class="sclh-id">' + esc(d.id_su_co) + (goc.ma_may ? ' · ' + esc(goc.ma_may) : '') +
      (goc.so_khuon ? ' · ' + esc(goc.so_khuon) : '') + '</span></div>' + (bar || '<div style="height:.3rem"></div>');
  }

  // Dải ảnh Trước / Sau / IPQC — thay cho mỗi nhóm ảnh 1 mốc. T300: đủ ảnh từ phát sinh đến
  // khi đóng (cả phiếu IPQC khác cùng máy trong lúc dừng), mỗi nhóm xếp theo giờ.
  function daiAnh(d, gio){
    const truoc = [], sau = [], qc = [];
    (d.anh || []).forEach(a => (a.loai === 'sau' ? sau : truoc).push({ url: a.url, ts: a.thoi_diem, ng: a.nguoi }));
    const daCo = new Set();
    [d.phat_hien_ipqc, ...(d.ipqc || []).filter(c => c.trang_thai === 'da_kiem'), ...(d.ipqc_khac || [])].filter(Boolean)
      .forEach(c => {
        if (daCo.has(c.id_checkpoint)) return; daCo.add(c.id_checkpoint);
        (Array.isArray(c.anh_bang_chung_url) ? c.anh_bang_chung_url : []).forEach(u => qc.push({ url: u, ts: c.thoi_diem_kiem_thuc_te, ng: c.nguoi_kiem }));
      });
    const theoGio = a => a.sort((x, y) => (x.ts ? new Date(x.ts) : 0) - (y.ts ? new Date(y.ts) : 0));
    const nhom = [['Trước', truoc], ['Sau', sau], ['IPQC', qc]].map(n => [n[0], theoGio(n[1].filter(a => a.url))]).filter(n => n[1].length);
    return nhom.length ? '<div class="sclh-anh">' + nhom.map(n => '<div><span class="lb">📷 ' + n[0] + ' (' + n[1].length + ')</span>' + anhHtml(n[1], gio) + '</div>').join('') + '</div>' : '';
  }

  // Giờ chỉ HH:MM; khác ngày phát sinh mới kèm ngày.
  const gioFn = ngay0 => ts => { if (!ts) return '—'; const t = new Date(ts); return pad(t.getHours()) + ':' + pad(t.getMinutes()) +
    (ngay0 && t.toDateString() !== ngay0 ? ' ' + pad(t.getDate()) + '/' + pad(t.getMonth() + 1) : ''); };
  function tlHtml(ev, ngay0){
    const gio = gioFn(ngay0);
    return '<div class="sclh-tl">' + ev.map(e =>
      '<div class="sclh-ev ' + e.cls + '"><div class="sclh-h"><span class="t">' + gio(e.ts) + '</span><span class="ti">' + e.ti + '</span>' +
      (e.ng ? '<span class="ng">· ' + esc(e.ng) + '</span>' : '') + '</div>' + e.body + '</div>').join('') + '</div>';
  }

  async function mount(el, idSuCo){
    injectCss();
    if (!el) return;
    if (!idSuCo) { el.innerHTML = ''; return; }
    el.innerHTML = '<div class="sclh"><div class="sclh-note">Đang tải…</div></div>';
    let d;
    try {
      const { data, error } = await sb.rpc('duc_su_co_lich_su', { p_id_su_co: idSuCo });
      if (error) throw new Error(error.message);
      if (!data || !data.ok) throw new Error((data && data.error) || 'Không tải được lịch sử sự cố');
      d = data;
    } catch (e) {
      el.innerHTML = '<div class="sclh"><div class="sclh-err">Không tải được: ' + esc(e.message) + '</div></div>';
      return;
    }
    const ev = suKien(d), chinh = ev.filter(e => !e.phu), phu = ev.filter(e => e.phu);
    const e0 = ev.find(e => e.ts), ngay0 = e0 ? new Date(e0.ts).toDateString() : '';
    el.innerHTML = '<div class="sclh">' + dauKhung(d) + tlHtml(chinh, ngay0) + daiAnh(d, gioFn(ngay0)) +
      (phu.length ? '<details class="sclh-khac"><summary><span class="mu">▸</span> Khác (' + phu.length + ')</summary>' + tlHtml(phu, ngay0) + '</details>' : '') +
      (!(d.nhat_ky || []).length ? '<div class="sclh-note" title="Sự cố trước 20/10/2026 chưa có nhật ký nên không có tên người báo / các lần sửa nội dung.">ⓘ Chưa có nhật ký (trước 20/10/2026)</div>' : '') +
      '</div>';
    if (!el.dataset.sclhBound) {
      el.dataset.sclhBound = '1';
      el.addEventListener('click', e => {
        const img = e.target.closest('img[data-sclh-urls]');
        if (!img) return;
        const urls = JSON.parse(img.dataset.sclhUrls), u = urls[Number(img.dataset.sclhI) || 0];
        if (typeof Qc02View !== 'undefined' && typeof Qc02View.photo === 'function') Qc02View.photo(u, urls);
        else window.open(u, '_blank', 'noopener');
      });
    }
  }

  window.SuCoLichSu = { mount };
})();
