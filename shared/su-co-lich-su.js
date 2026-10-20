/**
 * ============================================================================
 * su-co-lich-su.js — Lịch sử đầy đủ của 1 sự cố Đúc dạng dòng thời gian (T122).
 * Dùng ở ipqc.html khi IPQC kiểm sản phẩm đầu tiên sau xử lý sự cố.
 *
 * Nhúng SAU shared/supabase-client.js (cần `sb`).
 *
 *   SuCoLichSu.mount(el, 'SC-DC7-1019-1400')
 *
 * Dữ liệu: RPC duc_su_co_lich_su (migration T122) — nhật ký sự cố (ai báo / ai
 * sửa nội dung, ghi từ 20/10/2026), duc_su_co_log (từng phần theo ca, máy chạy
 * lại), lần IPQC phát hiện NG (F1), ảnh hiện trạng / sau xử lý, phiếu tổ khuôn,
 * linh kiện đã thay, các lần IPQC kiểm, đề nghị cho tiếp tục SX.
 * Bấm ảnh mở trình xem phóng to (Qc02View.photo nếu có, không thì tab mới).
 * ============================================================================
 */
(function () {
  const COT = { loai: 'Loại', gio_phat_sinh: 'Giờ phát sinh', gio_tro_lai: 'Giờ trở lại', van_de: 'Vấn đề',
    noi_dung_xu_ly: 'Nội dung xử lý', dam_nhiem: 'Đảm nhiệm' };
  const KQ = { OK: ['OK', 'ok'], NG: ['NG', 'ng'], CANH_BAO: ['Cảnh báo', 'cb'] };
  const LOAI_KIEM = { dinh_ky: 'định kỳ', sau_su_co: 'sau xử lý sự cố', doi_khuon: 'lên khuôn / SP mới' };
  const LK_LOAI = { xuat_thay: 'Xuất thay', thao_ra: 'Tháo ra', nhap: 'Nhập kho', dieu_chinh: 'Điều chỉnh' };

  function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function pad(n){ return String(n).padStart(2, '0'); }
  function tg(ts){ if (!ts) return '—'; const d = new Date(ts); return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ' ' + pad(d.getDate()) + '/' + pad(d.getMonth() + 1); }
  function giaTri(k, v){ if (v == null || v === '') return '(trống)'; return (k === 'gio_phat_sinh' || k === 'gio_tro_lai') ? tg(v) : String(v); }

  // Các phần log theo ca. Máy khuôn kép ghi 1 sự cố thành nhiều dòng CÙNG ca (mỗi
  // mã SP 1 dòng, cùng giờ) → gom theo (ngày, ca), phút dừng lấy max, không cộng.
  function theoCa(log){
    const m = new Map();
    (log || []).forEach(l => {
      const k = l.ngay + '|' + l.ca;
      const g = m.get(k);
      if (!g) m.set(k, { ...l, phut: Number(l.thoi_gian_dung_phut) || 0, ma_sps: [l.ma_sp] });
      else {
        g.phut = Math.max(g.phut, Number(l.thoi_gian_dung_phut) || 0);
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
      '.sclh-sum{display:grid;gap:.25rem;padding:.6rem .7rem;border-radius:.6rem;background:#FFF7ED;border:1px solid #FDBA74;margin-bottom:.6rem}' +
      '.sclh-sum .code{font-family:"JetBrains Mono",monospace;font-weight:700;background:#FDBA74;color:#7C2D12;padding:.05rem .4rem;border-radius:.3rem}' +
      '.sclh-sum b{font-weight:700}' +
      '.sclh-st{font-weight:700}.sclh-st.dung{color:#B91C1C}.sclh-st.chay{color:#047857}' +
      '.sclh-tl{position:relative;margin-left:.55rem;padding-left:1.1rem;border-left:2px solid #E2E8F0}' +
      '.sclh-ev{position:relative;margin-bottom:.75rem}' +
      '.sclh-ev:before{content:"";position:absolute;left:-1.52rem;top:.2rem;width:.7rem;height:.7rem;border-radius:50%;background:#fff;border:2px solid #94A3B8}' +
      '.sclh-ev.do:before{border-color:#DC2626;background:#FEE2E2}.sclh-ev.xanh:before{border-color:#059669;background:#D1FAE5}' +
      '.sclh-ev.cam:before{border-color:#D97706;background:#FEF3C7}.sclh-ev.lam:before{border-color:#2563EB;background:#DBEAFE}' +
      '.sclh-h{display:flex;flex-wrap:wrap;gap:.35rem;align-items:baseline}' +
      '.sclh-h .t{font-family:"JetBrains Mono",monospace;font-size:.75rem;color:#64748B;white-space:nowrap}' +
      '.sclh-h .ti{font-weight:700}' +
      '.sclh-h .ng{color:#475569;font-size:.78rem}' +
      '.sclh-b{margin-top:.2rem;color:#334155;white-space:pre-wrap;word-break:break-word}' +
      '.sclh-b .lb{color:#64748B;font-weight:600}' +
      '.sclh-diff{margin-top:.2rem;font-size:.8rem}' +
      '.sclh-diff del{color:#94A3B8}.sclh-diff ins{text-decoration:none;color:#0F172A;font-weight:600}' +
      '.sclh-tag{display:inline-block;font-size:.7rem;font-weight:700;padding:.05rem .4rem;border-radius:.3rem;background:#E2E8F0;color:#334155}' +
      '.sclh-tag.ok{background:#D1FAE5;color:#065F46}.sclh-tag.ng{background:#FEE2E2;color:#991B1B}.sclh-tag.cb{background:#FEF3C7;color:#92400E}' +
      '.sclh-ngl{display:flex;flex-wrap:wrap;gap:.25rem;margin-top:.25rem}' +
      '.sclh-ngl span{font-size:.72rem;background:#FEE2E2;color:#991B1B;border-radius:.3rem;padding:.05rem .35rem}' +
      '.sclh-ph{display:flex;flex-wrap:wrap;gap:.35rem;margin-top:.35rem}' +
      '.sclh-ph img{width:64px;height:64px;object-fit:cover;border-radius:.4rem;border:1px solid #CBD5E1;cursor:zoom-in;display:block}' +
      '.sclh-note{font-size:.75rem;color:#94A3B8;margin-top:.4rem}' +
      '.sclh-err{color:#B91C1C}';
    document.head.appendChild(st);
  }

  function anhHtml(urls){
    const ds = (urls || []).filter(Boolean);
    if (!ds.length) return '';
    return '<div class="sclh-ph">' + ds.map((u, i) => '<img src="' + esc(u) + '" alt="" loading="lazy" data-sclh-i="' + i + '" data-sclh-urls="' + esc(JSON.stringify(ds)) + '">').join('') + '</div>';
  }
  function ngHtml(checklist){
    const ng = (Array.isArray(checklist) ? checklist : []).filter(x => x && x.dat === false).map(x => x.muc);
    return ng.length ? '<div class="sclh-ngl">' + ng.map(m => '<span>✗ ' + esc(m) + '</span>').join('') + '</div>' : '';
  }
  function diffHtml(td){
    if (!td) return '';
    return '<div class="sclh-diff">' + Object.keys(td).map(k =>
      '<div><span class="lb">' + esc(COT[k] || k) + ':</span> <del>' + esc(giaTri(k, td[k].cu)) + '</del> → <ins>' + esc(giaTri(k, td[k].moi)) + '</ins></div>').join('') + '</div>';
  }
  function dong(lb, v){ return v ? '<div class="sclh-b"><span class="lb">' + esc(lb) + ':</span> ' + esc(v) + '</div>' : ''; }

  // Gom dữ liệu RPC thành danh sách sự kiện {t, cls, ti, ng, body}.
  function suKien(d){
    const ev = [];
    const add = (t, cls, ti, ng, body) => ev.push({ t: t ? new Date(t).getTime() : 0, ts: t, cls, ti, ng: ng || '', body: body || '' });
    const log = theoCa(d.log);
    const goc = log[0] || d.dang_mo || {};
    const nk = d.nhat_ky || [];
    const nkMo = nk.find(k => k.su_kien === 'mo');

    const ph = d.phat_hien_ipqc;
    if (ph) add(ph.thoi_diem_kiem_thuc_te, 'do', '🔍 IPQC phát hiện ' + (KQ[ph.ket_qua] ? KQ[ph.ket_qua][0] : ph.ket_qua) + ' (kiểm ' + (LOAI_KIEM[ph.loai_kiem] || ph.loai_kiem) + ')',
      ph.nguoi_kiem, ngHtml(ph.checklist_json) + dong('Ghi chú IPQC', ph.ghi_chu) + anhHtml(ph.anh_bang_chung_url));

    const moDl = (nkMo && nkMo.du_lieu) || {};
    add(goc.gio_phat_sinh || moDl.gio_phat_sinh, 'do', '🚨 Phát sinh sự cố — ' + esc(goc.loai_su_co || goc.loai || moDl.loai || ''),
      nkMo ? 'Báo bởi ' + nkMo.nguoi + ' lúc ' + tg(nkMo.thoi_diem) : '',
      dong('Vấn đề / hiện trạng', moDl.van_de || goc.van_de) +
      dong('Xử lý ban đầu', moDl.noi_dung_xu_ly) + dong('Đảm nhiệm', moDl.dam_nhiem));

    // Ảnh: gom theo loại + người + phút
    const nhomAnh = {};
    (d.anh || []).forEach(a => {
      const k = a.loai + '|' + (a.nguoi || '') + '|' + String(a.thoi_diem || '').slice(0, 16);
      (nhomAnh[k] = nhomAnh[k] || { a, urls: [] }).urls.push(a.url);
    });
    Object.values(nhomAnh).forEach(({ a, urls }) => add(a.thoi_diem, a.loai === 'sau' ? 'xanh' : 'cam',
      a.loai === 'sau' ? '📷 Ảnh sau xử lý' : '📷 Ảnh hiện trạng', a.nguoi, anhHtml(urls)));

    nk.filter(k => k.su_kien === 'cap_nhat').forEach(k => add(k.thoi_diem, 'lam', '✏️ Cập nhật nội dung sự cố', k.nguoi, diffHtml(k.thay_doi)));
    nk.filter(k => k.su_kien === 'sua_sau_dong').forEach(k => add(k.thoi_diem, 'lam', '✏️ Sửa sự cố sau khi đã đóng', k.nguoi, diffHtml(k.thay_doi)));
    nk.filter(k => k.su_kien === 'xoa').forEach(k => add(k.thoi_diem, 'do', '🗑 Xoá 1 phần sự cố (ca ' + esc(k.ca || '') + ')', k.nguoi, ''));

    const x = d.to_khuon;
    if (x) {
      add(x.bat_dau || x.cap_nhat_luc, 'lam', '🔧 Tổ khuôn nhận xử lý', [x.nguoi_dam_nhiem, x.nguoi_dam_nhiem_phu].filter(Boolean).join(' + '),
        x.trang_thai === 'hoan_thanh' ? '' : dong('Nội dung', x.noi_dung_xu_ly));
      if (x.trang_thai === 'hoan_thanh') add(x.ket_thuc || x.hoan_thanh_luc, 'xanh', '✅ Tổ khuôn hoàn thành xử lý', x.nguoi_hoan_thanh,
        dong('Nội dung xử lý', x.noi_dung_xu_ly) + (x.bat_dau && x.ket_thuc ? dong('Thời gian', Math.round((new Date(x.ket_thuc) - new Date(x.bat_dau)) / 60000) + ' phút') : ''));
    }

    (d.linh_kien || []).forEach(g => add(g.thoi_diem, 'lam', '🔩 ' + esc(LK_LOAI[g.loai] || g.loai) + ' linh kiện ' + esc(g.ma_lk || ''), g.nguoi,
      dong('Linh kiện', (g.ten_lk || '') + ' × ' + (g.so_luong ?? '')) + dong('Khuôn / vị trí', [g.ma_khuon, g.vi_tri].filter(Boolean).join(' · ')) +
      dong('Mục đích', g.muc_dich) + dong('Tình trạng cái tháo ra', g.ket_qua_thao) + dong('Ghi chú', g.ghi_chu)));

    // Sự cố vắt ca: mỗi phần log trừ phần cuối = kết ca chuyển tiếp.
    const xong = !d.dang_mo;
    log.forEach((l, i) => {
      const cuoi = xong && i === log.length - 1;
      if (cuoi) return;
      add(l.gio_tro_lai, '', '🔁 Kết ca — sự cố chuyển sang ca sau', l.truong_ca ? 'Trưởng ca ' + l.truong_ca : '',
        dong('Phần trong ' + (l.ca || 'ca') + ' ' + String(l.ngay || '').split('-').reverse().join('/'), Math.round(l.phut) + ' phút dừng') + dong('Đã xử lý', l.noi_dung_xu_ly));
    });

    (d.ipqc || []).filter(c => c.trang_thai === 'da_kiem').forEach(c => {
      const kq = KQ[c.ket_qua] || [c.ket_qua || '?', ''];
      add(c.thoi_diem_kiem_thuc_te, kq[1] === 'ok' ? 'xanh' : 'do',
        '🧪 IPQC kiểm ' + esc(LOAI_KIEM[c.loai_kiem] || c.loai_kiem) + ' <span class="sclh-tag ' + kq[1] + '">' + esc(kq[0]) + '</span>', c.nguoi_kiem,
        ngHtml(c.checklist_json) + dong('Ghi chú', c.ghi_chu) + anhHtml(c.anh_bang_chung_url));
    });

    (d.tiep_tuc || []).forEach(r => {
      add(r.created_at, 'cam', '📝 Đề nghị cho tiếp tục SX ' + esc(r.request_code || '') + ' <span class="sclh-tag">' + esc(r.status || '') + '</span>', r.requester_name,
        dong('Lý do', [r.reason_type, r.reason_detail].filter(Boolean).join(' — ')) + dong('Biện pháp', r.treatment_content) +
        (r.allowed_until ? dong('Cho phép đến', tg(r.allowed_until)) : '') + (r.allowed_qty ? dong('Số lượng cho phép', r.allowed_qty) : ''));
      // Bỏ "TẠO YÊU CẦU" (đã hiện ở trên) và "CẬP NHẬT SẢN LƯỢNG" (tự động, nhiều dòng).
      (r.audit || []).filter(a => a.action && !['TẠO YÊU CẦU', 'CẬP NHẬT SẢN LƯỢNG'].includes(a.action)).forEach(a => {
        const dt = a.detail && typeof a.detail === 'object' ? a.detail : {};
        add(a.created_at, 'cam', '📝 ' + esc(a.action.charAt(0) + a.action.slice(1).toLowerCase()) + ' — đề nghị ' + esc(r.request_code || ''), a.actor_name,
          (dt.from || dt.to ? dong('Trạng thái', [dt.from, dt.to].filter(Boolean).join(' → ')) : '') + dong('Ghi chú', dt.note || dt.reason));
      });
    });

    if (xong && log.length) {
      const l = log[log.length - 1];
      const nkDong = nk.filter(k => k.su_kien === 'dong').pop();
      add(l.gio_tro_lai, 'xanh', '▶ Máy chạy lại — kết thúc sự cố',
        [nkDong ? 'Ghi bởi ' + nkDong.nguoi : '', l.truong_ca ? 'Trưởng ca ' + l.truong_ca : ''].filter(Boolean).join(' · '),
        dong('Nội dung xử lý', l.noi_dung_xu_ly) + dong('Đảm nhiệm', l.dam_nhiem) + dong('Ghi chú', l.ghi_chu));
    }
    return ev.sort((a, b) => a.t - b.t);
  }

  function tomTat(d){
    const log = theoCa(d.log), m = d.dang_mo, goc = log[0] || m || {};
    const cuoi = m || log[log.length - 1] || {};
    const phatSinh = goc.gio_phat_sinh;
    const sps = [...new Set([...(d.log || []).map(l => l.ma_sp), m && m.ma_sp].filter(Boolean))];
    const phut = log.reduce((s, l) => s + l.phut, 0) +
      (m && m.gio_phat_sinh ? Math.max(0, Math.round((Date.now() - new Date(m.gio_phat_sinh)) / 60000)) : 0);
    const st = m ? '<span class="sclh-st dung">⛔ Máy đang dừng — ' + Math.round(phut) + ' phút</span>'
      : '<span class="sclh-st chay">▶ Đã chạy lại ' + tg(log.length ? log[log.length - 1].gio_tro_lai : null) + ' — dừng ' + Math.round(phut) + ' phút</span>';
    return '<div class="sclh-sum">' +
      '<div><span class="code">' + esc(d.id_su_co) + '</span> ' + esc(goc.loai_su_co || goc.loai || '') + '</div>' +
      '<div><b>Máy</b> ' + esc(goc.ma_may || '') + ' · <b>SP</b> ' + esc(sps.join(', ') || goc.ma_sp || '') + (goc.so_khuon ? ' · <b>Khuôn</b> ' + esc(goc.so_khuon) : '') +
        ' · <b>Phát sinh</b> ' + tg(phatSinh) + '</div>' +
      '<div>' + st + '</div>' +
      '<div><b>Vấn đề / nguyên nhân:</b> ' + esc(cuoi.van_de || goc.van_de || '—') + '</div>' +
      '<div><b>Nội dung xử lý:</b> ' + esc(cuoi.noi_dung_xu_ly || '—') + '</div>' +
      '<div><b>Đảm nhiệm:</b> ' + esc(cuoi.dam_nhiem || '—') + '</div>' +
    '</div>';
  }

  async function mount(el, idSuCo){
    injectCss();
    if (!el) return;
    if (!idSuCo) { el.innerHTML = ''; return; }
    el.innerHTML = '<div class="sclh"><div class="sclh-note">Đang tải lịch sử sự cố ' + esc(idSuCo) + '…</div></div>';
    let d;
    try {
      const { data, error } = await sb.rpc('duc_su_co_lich_su', { p_id_su_co: idSuCo });
      if (error) throw new Error(error.message);
      if (!data || !data.ok) throw new Error((data && data.error) || 'Không tải được lịch sử sự cố');
      d = data;
    } catch (e) {
      el.innerHTML = '<div class="sclh"><div class="sclh-err">Không tải được lịch sử sự cố: ' + esc(e.message) + '</div></div>';
      return;
    }
    const ev = suKien(d);
    el.innerHTML = '<div class="sclh">' + tomTat(d) +
      '<div class="sclh-tl">' + ev.map(e =>
        '<div class="sclh-ev ' + e.cls + '"><div class="sclh-h"><span class="t">' + tg(e.ts) + '</span><span class="ti">' + e.ti + '</span>' +
        (e.ng ? '<span class="ng">· ' + esc(e.ng) + '</span>' : '') + '</div>' + e.body + '</div>').join('') + '</div>' +
      (!(d.nhat_ky || []).length ? '<div class="sclh-note">Sự cố này phát sinh trước khi có nhật ký (20/10/2026) nên không có tên người báo / các lần sửa nội dung.</div>' : '') +
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
