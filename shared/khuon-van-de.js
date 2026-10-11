/**
 * ============================================================================
 * khuon-van-de.js — bảng LỊCH SỬ VẤN ĐỀ của 1 khuôn (T88/T89/T90): sự cố (kèm
 * ảnh hiện trạng / sau xử lý) + IPQC NG / Cảnh báo (kèm ảnh, hạng mục không
 * đạt), gộp theo thời gian, cột kết quả xử lý. Nguồn: RPC duc_khuon_van_de_lich_su.
 * Dùng ở quan-ly-khuon.html (nút 🔎 Vấn đề).
 *
 *   KhuonVanDe.mount(el, { maKhuon, lanBd: 'YYYY-MM-DD'|null, mocNgay: 'YYYY-MM-DD' })
 * Cần `sb` (shared/supabase-client.js).
 * ============================================================================
 */
(function () {
  const CSS = `.vd-bar{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px}
.vd-bar select{border:1.5px solid var(--border-strong);border-radius:6px;padding:5px 8px;font-family:inherit;font-size:12.5px}
.vd-tabs{display:flex;gap:4px}
.vd-tabs button{border:1px solid var(--border-strong);background:#fff;border-radius:100px;padding:5px 12px;font-family:inherit;font-size:12px;font-weight:700;cursor:pointer;color:var(--text-muted)}
.vd-tabs button.on{background:var(--text);color:#fff;border-color:var(--text)}
.vd-top{font-size:12px;background:var(--bg-sunken);border-radius:6px;padding:7px 10px;margin-bottom:8px;line-height:1.6}
.vd-top b{color:var(--alarm-fg)}
.vd-wrap{overflow:auto;max-height:620px;border:1px solid var(--border);border-radius:6px}
.vd-tbl{width:100%;border-collapse:separate;border-spacing:0;font-size:12px}
.vd-tbl th{position:sticky;top:0;z-index:1;background:var(--bg-sunken);color:var(--text-muted);font-size:10.5px;text-transform:uppercase;letter-spacing:.04em;text-align:left;padding:7px 8px;border-bottom:1px solid var(--border);white-space:nowrap}
.vd-tbl td{padding:7px 8px;border-bottom:1px solid var(--border);vertical-align:top}
.vd-tbl td.tg{white-space:nowrap;font-family:'JetBrains Mono',monospace;font-size:11.5px}
.vd-tbl td.tg small,.vd-tbl td small{display:block;font-family:'Inter',sans-serif;color:var(--text-muted);font-size:10.5px}
.vd-tbl td.may{white-space:nowrap;font-weight:700}
.vd-tbl td.loi{min-width:200px}
.vd-tbl td.loi b{display:block}
.vd-tbl td.dung{white-space:nowrap;text-align:right}
.vd-tbl td.xl{min-width:160px;white-space:pre-line}
.vd-tbl td.kq{min-width:120px}
.vd-tbl tr.src-ipqc td.may{box-shadow:inset 3px 0 0 #7C3AED}
.vd-tbl tr.src-su_co td.may{box-shadow:inset 3px 0 0 var(--warn-fg)}
.vd-src{display:inline-block;font-size:10px;font-weight:700;padding:1px 6px;border-radius:100px;margin-bottom:3px}
.vd-src.su_co{background:var(--warn-bg);color:var(--warn-fg)}
.vd-src.ipqc{background:#F3E8FF;color:#6B21A8}
.vd-ng{display:flex;flex-wrap:wrap;gap:3px;margin-top:3px}
.vd-ng span{font-size:10.5px;background:var(--alarm-bg);color:var(--alarm-fg);border-radius:4px;padding:1px 5px}
.vd-kq{font-weight:700;font-size:11.5px}
.vd-kq.ok{color:var(--run-fg)}.vd-kq.ng{color:var(--alarm-fg)}.vd-kq.cb{color:var(--warn-fg)}.vd-kq.cho{color:var(--text-muted)}
.vd-ph{display:flex;gap:4px;flex-wrap:wrap;align-items:center;min-width:110px}
.vd-ph + .vd-ph{margin-top:4px}
.vd-ph img{width:46px;height:46px;object-fit:cover;border-radius:5px;border:1px solid var(--border);display:block}
.vd-ph .lb{font-size:10px;font-weight:700;color:var(--text-muted);width:100%}
.kq-ng{color:var(--alarm-fg);font-weight:700}.kq-cb{color:var(--warn-fg);font-weight:700}
`;
  function injectCss(){
    if (document.getElementById('kvd-css')) return;
    const st = document.createElement('style');
    st.id = 'kvd-css';
    st.textContent = CSS;
    document.head.appendChild(st);
  }
  function escapeHtml(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function fmtNum(n){ return (Number(n) || 0).toLocaleString('vi-VN'); }
  function parseDate(s){ const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d); }
  function fmtDateVN(s){ const d = parseDate(s); return String(d.getDate()).padStart(2, '0') + '/' + String(d.getMonth() + 1).padStart(2, '0') + '/' + d.getFullYear(); }
  function isoDate(d){ return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); }

  function mount(el, opt){
    injectCss();
    let vdData = null, vdTab = 'all', vdChiAnh = false;
    // Mặc định: từ lần bảo dưỡng gần nhất; chưa từng BD thì 90 ngày.
    let vdTu = opt.lanBd ? 'bd' : '90';
    function vdTuNgay(v){
      if (v === 'bd') return String(opt.lanBd).slice(0, 10);
      const d = opt.mocNgay ? parseDate(opt.mocNgay) : new Date();
      d.setDate(d.getDate() - Number(v));
      return isoDate(d);
    }
    async function loadVanDe(){
      el.innerHTML = '<div style="color:var(--text-dim,#94A3B8)">Đang tải...</div>';
      const { data, error } = await sb.rpc('duc_khuon_van_de_lich_su', { p_ma_khuon: opt.maKhuon, p_tu_ngay: vdTuNgay(vdTu) });
      if (error) { el.innerHTML = '<div style="color:#B91C1C;padding:8px">Lỗi tải: ' + escapeHtml(error.message) + '</div>'; return; }
      vdData = data || { su_co: [], ipqc: [] };
      renderVanDe();
    }
    function vdAnh(urls, label){
      if (!urls || !urls.length) return '';
      return '<div class="vd-ph"><span class="lb">' + label + ' (' + urls.length + ')</span>' + urls.map(u => '<a href="' + escapeHtml(u) + '" target="_blank" rel="noopener"><img src="' + escapeHtml(u) + '" loading="lazy" alt=""></a>').join('') + '</div>';
    }
    function vdDem(arr, keyFn){
      const m = {};
      arr.forEach(x => [].concat(keyFn(x)).forEach(k => { if (k) m[k] = (m[k] || 0) + 1; }));
      return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 6);
    }
    function vdTg(ts){ return ts ? new Date(ts).toLocaleString('vi-VN', { hour12: false, day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' }) : ''; }
    function vdGio(ts){ return ts ? new Date(ts).toLocaleTimeString('vi-VN', { hour12: false, hour: '2-digit', minute: '2-digit' }) : ''; }
    const VD_KQ = { OK: ['ok', '✓ OK'], NG: ['ng', '✗ NG'], CANH_BAO: ['cb', '⚠ Cảnh báo'] };
    function vdKq(k){ return VD_KQ[k] || ['cho', String(k || '')]; }
    const VD_LOAI_KIEM = { dinh_ky: 'Định kỳ', sau_su_co: 'Sau sự cố', doi_khuon: 'Đổi khuôn', dau_ca: 'Đầu ca' };
    // Gộp sự cố + IPQC thành các dòng bảng, mới nhất trước.
    function vdRows(){
      const sc = (vdData.su_co || []).map(x => {
        const ip = x.ipqc_sau;
        let kq;
        if (x.dang_mo) kq = '<span class="vd-kq ng">Đang xử lý</span>';
        else if (ip && ip.ket_qua) kq = '<span class="vd-kq ' + vdKq(ip.ket_qua)[0] + '">IPQC sau sự cố: ' + vdKq(ip.ket_qua)[1] + '</span><small>' + vdTg(ip.thoi_diem) + (ip.nguoi_kiem ? ' · ' + escapeHtml(ip.nguoi_kiem) : '') + '</small>';
        else if (ip) kq = '<span class="vd-kq cho">Đã SX lại — chờ IPQC kiểm</span>';
        else kq = '<span class="vd-kq cho">Đã SX lại</span>';
        return { src: 'su_co', t: x.gio_phat_sinh, ca: x.ca, may: x.ma_may,
          nguon: '<span class="vd-src su_co">⚠ Sự cố</span>' + (x.id_su_co ? '<small>' + escapeHtml(x.id_su_co) + '</small>' : ''),
          loi: '<b>' + escapeHtml(x.loai || '—') + '</b>' + escapeHtml(x.van_de || ''),
          dung: x.dang_mo ? '<span class="vd-kq ng">đang dừng</span>' : (x.phut != null ? '<b>' + x.phut + "'</b>" : '—') + (x.gio_tro_lai ? '<small>SX lại ' + vdGio(x.gio_tro_lai) + '</small>' : ''),
          xl: String(x.xu_ly || '').trim(), kq,
          anh: vdAnh(x.anh_truoc, 'Hiện trạng') + vdAnh(x.anh_sau, 'Sau xử lý'),
          soAnh: (x.anh_truoc || []).length + (x.anh_sau || []).length };
      });
      const iq = (vdData.ipqc || []).map(x => {
        const kl = x.kiem_lai, kk = x.khuon_khac || [];
        return { src: 'ipqc', t: x.thoi_diem, ca: x.ca, may: x.ma_may,
          nguon: '<span class="vd-src ipqc">🔍 IPQC ' + escapeHtml(VD_LOAI_KIEM[x.loai_kiem] || String(x.loai_kiem || '').replace(/_/g, ' ')) + '</span>' +
            (x.nguoi_kiem ? '<small>' + escapeHtml(x.nguoi_kiem) + '</small>' : '') +
            (kk.length ? '<small class="vd-kq cb" title="Cùng ngày/ca máy này còn chạy khuôn khác">⚠ có thể là khuôn ' + escapeHtml(kk.join(', ')) + '</small>' : ''),
          loi: '<span class="vd-kq ' + (x.ket_qua === 'NG' ? 'ng' : 'cb') + '">' + (x.ket_qua === 'NG' ? 'NG' : 'Cảnh báo') + '</span>' +
            ((x.hang_muc_ng || []).length ? '<div class="vd-ng">' + x.hang_muc_ng.map(m => '<span>' + escapeHtml(m) + '</span>').join('') + '</div>' : ''),
          dung: x.phut_dung != null ? '<b>' + x.phut_dung + "'</b><small>theo sự cố gốc</small>" : '—',
          xl: String(x.ghi_chu || '').trim(),
          kq: kl && kl.ket_qua ? '<span class="vd-kq ' + vdKq(kl.ket_qua)[0] + '">Kiểm lại: ' + vdKq(kl.ket_qua)[1] + '</span><small>' + vdTg(kl.thoi_diem) + (kl.loai_kiem ? ' · ' + escapeHtml(VD_LOAI_KIEM[kl.loai_kiem] || kl.loai_kiem) : '') + '</small>'
            : '<span class="vd-kq cho">Chưa có lần kiểm lại</span>',
          anh: vdAnh(x.anh, 'Ảnh IPQC'), soAnh: (x.anh || []).length };
      });
      return sc.concat(iq).sort((a, b) => new Date(b.t || 0) - new Date(a.t || 0));
    }
    function renderVanDe(){
      const body = el;
      if (!vdData) return;
      const sc = vdData.su_co || [], iq = vdData.ipqc || [];
      const lan = opt.lanBd || null;
      const opts = (lan ? [['bd', 'Từ lần BD gần nhất (' + fmtDateVN(lan) + ')']] : []).concat([['30', '30 ngày'], ['90', '90 ngày'], ['180', '180 ngày'], ['365', '1 năm']]);
      const all = vdRows();
      const rows = all.filter(r => (vdTab === 'all' || r.src === vdTab) && (!vdChiAnh || r.soAnh > 0));
      let h = '<div class="vd-bar"><select id="vdTu">' + opts.map(([v, l]) => '<option value="' + v + '"' + (v === vdTu ? ' selected' : '') + '>' + l + '</option>').join('') + '</select>' +
        '<div class="vd-tabs">' + [['all', 'Tất cả (' + all.length + ')'], ['su_co', '⚠ Sự cố (' + sc.length + ')'], ['ipqc', '🔍 IPQC NG / Cảnh báo (' + iq.length + ')']]
          .map(([k, l]) => '<button type="button" data-vdtab="' + k + '" class="' + (vdTab === k ? 'on' : '') + '">' + l + '</button>').join('') + '</div>' +
        '<label style="font-size:12px;display:flex;gap:4px;align-items:center"><input type="checkbox" id="vdChiAnh"' + (vdChiAnh ? ' checked' : '') + '> Chỉ dòng có ảnh (' + all.filter(r => r.soAnh > 0).length + ')</label></div>';
      // Tóm tắt hay gặp — gợi ý đối sách
      const topSc = vdDem(sc, x => x.loai), topNg = vdDem(iq, x => x.hang_muc_ng || []);
      const tongDung = sc.reduce((t, x) => t + (Number(x.phut) || 0), 0);
      if (topSc.length || topNg.length) h += '<div class="vd-top">' +
        (topSc.length ? '<div>Sự cố hay gặp: ' + topSc.map(([k, n]) => escapeHtml(k) + ' <b>×' + n + '</b>').join(' · ') + ' — tổng dừng <b>' + fmtNum(tongDung) + "'</b></div>" : '') +
        (topNg.length ? '<div>Lỗi IPQC hay gặp: ' + topNg.map(([k, n]) => escapeHtml(k) + ' <b>×' + n + '</b>').join(' · ') + '</div>' : '') + '</div>';
      h += '<div class="vd-wrap"><table class="vd-tbl"><thead><tr><th>Ngày giờ</th><th>Máy</th><th>Nguồn</th><th>Lỗi phát hiện</th><th style="text-align:right">TG dừng</th><th>Nội dung xử lý</th><th>Kết quả xử lý</th><th>Hình ảnh</th></tr></thead><tbody>';
      if (!rows.length) h += '<tr><td colspan="8" style="text-align:center;color:var(--text-dim);padding:14px">Không có vấn đề nào trong khoảng thời gian này.</td></tr>';
      rows.forEach(r => {
        h += '<tr class="src-' + r.src + '"><td class="tg">' + vdTg(r.t) + '<small>' + escapeHtml(r.ca || '') + '</small></td>' +
          '<td class="may">' + escapeHtml(r.may || '—') + '</td><td>' + r.nguon + '</td><td class="loi">' + r.loi + '</td>' +
          '<td class="dung">' + r.dung + '</td><td class="xl">' + (r.xl ? escapeHtml(r.xl) : '<span style="color:var(--text-dim)">—</span>') + '</td>' +
          '<td class="kq">' + r.kq + '</td><td>' + (r.anh || '<span style="color:var(--text-dim)">—</span>') + '</td></tr>';
      });
      h += '</tbody></table></div>';
      body.innerHTML = h;
      body.querySelector('#vdTu').onchange = e => { vdTu = e.target.value; loadVanDe(); };
      body.querySelectorAll('[data-vdtab]').forEach(b => { b.onclick = () => { vdTab = b.dataset.vdtab; renderVanDe(); }; });
      body.querySelector('#vdChiAnh').onchange = e => { vdChiAnh = e.target.checked; renderVanDe(); };
    }


    loadVanDe();
    return { reload: loadVanDe };
  }

  window.KhuonVanDe = { mount };
})();
