// T307: Điểm thay đổi chủ động Đúc — dùng chung cho duc-dashboard.html, mobile.html, ipqc.html, diem-thay-doi.html.
// Danh mục: duc_thay_doi_mau (sửa ở Danh mục → tab "Thay đổi Đúc"). Phiếu: duc_thay_doi. Chuẩn ±%: duc_thay_doi_chuan.
//
// Bảng điều khiển:
//   ThayDoi.batDau({ onDoi, layDong(idDong) → row, layDongMay(maMay) → row đang chạy })
//   ThayDoi.badge(maMay)  → html biểu tượng ⏳ / ✋ / ⚠ (bấm mở hộp phiếu của máy)
//   ThayDoi.nut(row, cls) → html nút "± Thay đổi" (chỉ trưởng ca)
// IPQC:
//   await ThayDoi.ipqcMount(box, idCheckpoint) · ThayDoi.ipqcKiemTra() → '' | lỗi · ThayDoi.ipqcChecklist() → mục checklist
(function () {
  if (window.ThayDoi) return;

  const NHOM = { dieu_kien: 'Điều kiện', khuon: 'Khuôn', may: 'Máy', vat_lieu: 'NVL', khac: 'Khác' };
  const NHOM_DAY = { dieu_kien: 'Điều kiện đúc', khuon: 'Khuôn', may: 'Máy', vat_lieu: 'Vật liệu', khac: 'Người & khác' };
  const DUYET = { khong: 'Không cần', ky_thuat: 'Kỹ thuật', thiet_bi: 'Thiết bị', to_truong_khuon: 'Tổ trưởng khuôn', qlbp_duc: 'QLBP Đúc', qa: 'QA' };
  const LY_DO = ['Khắc phục lỗi', 'Ổn định chất lượng', 'Tăng năng suất', 'Theo yêu cầu kỹ thuật', 'Theo yêu cầu khách', 'Thử nghiệm'];
  const TT = {
    cho_duyet: '⏳ Chờ duyệt', cho_ap_dung: '✋ Chờ chỉnh', cho_ipqc: '⚠ Chờ IPQC', ok: '✅ OK', ng: '⛔ NG',
    khong_kiem: 'Không kiểm', ghi_nhan: 'Ghi nhận', khong_duyet: 'Không duyệt', huy: 'Đã huỷ',
  };
  const MO = ['cho_duyet', 'cho_ap_dung', 'cho_ipqc'];
  const MAX_ANH = 5;

  let mau = null, quyen = null, mo = [], opt = {}, timer = null, dangTai = null;

  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const soVi = v => (v == null || v === '') ? '' : String(v).replace('.', ',');
  const docSo = s => { const t = String(s ?? '').trim().replace(/\s/g, '').replace(',', '.'); return t === '' || isNaN(Number(t)) ? null : Number(t); };
  const gio = ts => {
    if (!ts) return '';
    const p = {}; new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Ho_Chi_Minh', hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', hourCycle: 'h23' })
      .formatToParts(new Date(ts)).forEach(x => { p[x.type] = x.value; });
    return p.hour + ':' + p.minute + ' ' + p.day + '/' + p.month;
  };
  function bao(msg, loi) {
    if (typeof window.showToast === 'function') window.showToast(msg, loi);
    else alert(msg);
  }
  function loiRpc(error) { return (error && (error.message || error.details)) || 'Lỗi không rõ'; }

  // Tóm tắt 1 phiếu: "Tốc độ pha 2 2,8→3,2 m/s; …"
  function tomTat(ct) {
    return (ct || []).map(e => e.ten + ' ' + (e.truoc != null && e.truoc !== '' ? soVi(e.truoc) : '') + '→' + soVi(e.sau) + (e.don_vi ? ' ' + e.don_vi : '')).join('; ');
  }

  // ── CSS ────────────────────────────────────────────────────────────────────
  let css = false;
  function napCss() {
    if (css) return; css = true;
    const st = document.createElement('style');
    st.textContent =
      '.td-b{display:inline-block;margin-left:4px;padding:1px 6px;border-radius:10px;font-size:11px;font-weight:600;cursor:pointer;white-space:nowrap;border:1px solid}' +
      '.td-b.cho_duyet{background:#FEF3C7;color:#92400E;border-color:#FCD34D}' +
      '.td-b.cho_ap_dung{background:#DBEAFE;color:#1E40AF;border-color:#93C5FD}' +
      '.td-b.cho_ipqc{background:#FFEDD5;color:#9A3412;border-color:#FDBA74}' +
      '.td-nut{margin-top:4px;padding:3px 8px;font:600 11px inherit;font-family:inherit;border:1px solid #CBD5E1;border-radius:6px;background:#fff;color:#334155;cursor:pointer}' +
      '.td-nut:hover{border-color:#2563EB;color:#2563EB}' +
      'dialog.tdg{position:fixed;inset:0;margin:auto;height:fit-content;max-height:calc(100vh - 24px);overflow:auto;border:0;border-radius:12px;padding:0;width:min(560px,calc(100vw - 16px));box-shadow:0 12px 40px rgba(0,0,0,.25);font:500 13px/1.45 Inter,system-ui,sans-serif;color:#14181F;background:#fff}' +
      'dialog.tdg::backdrop{background:rgba(15,23,42,.45)}' +
      '.tdg .hd{position:sticky;top:0;background:#fff;z-index:2;padding:12px 14px 8px;border-bottom:1px solid #E2E8F0;display:flex;align-items:center;gap:8px}' +
      '.tdg .hd b{font-size:15px}.tdg .hd .sub{color:#64748B;font-size:12px;flex:1;min-width:0}' +
      '.tdg .hd .x{border:0;background:none;font-size:18px;cursor:pointer;color:#64748B}' +
      '.tdg .bd{padding:10px 14px;display:flex;flex-direction:column;gap:10px}' +
      '.tdg .ft{position:sticky;bottom:0;background:#F8FAFC;border-top:1px solid #E2E8F0;padding:10px 14px;display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap}' +
      '.tdg button.b{font:600 13px Inter,system-ui,sans-serif;border-radius:8px;padding:8px 14px;cursor:pointer;border:1px solid #CBD5E1;background:#fff;color:#14181F}' +
      '.tdg button.b.ok{background:#16A34A;border-color:#16A34A;color:#fff}' +
      '.tdg button.b.xanh{background:#2563EB;border-color:#2563EB;color:#fff}' +
      '.tdg button.b.khan{background:#EA580C;border-color:#EA580C;color:#fff}' +
      '.tdg button.b.do{color:#DC2626;border-color:#FCA5A5}' +
      '.tdg button.b:disabled{opacity:.45;cursor:not-allowed}' +
      '.tdg .nhom{display:flex;gap:4px;flex-wrap:wrap}' +
      '.tdg .nhom button{flex:1 1 auto;padding:6px 8px;border:1px solid #CBD5E1;border-radius:6px;background:#fff;font:600 12px Inter,system-ui,sans-serif;cursor:pointer}' +
      '.tdg .nhom button.on{background:#1E293B;color:#fff;border-color:#1E293B}' +
      '.tdg .nhom button .n{display:inline-block;min-width:16px;margin-left:3px;border-radius:8px;background:#2563EB;color:#fff;font-size:11px}' +
      '.tdg .ds{border:1px solid #E2E8F0;border-radius:8px;max-height:210px;overflow:auto}' +
      '.tdg .ds button{display:flex;gap:6px;width:100%;text-align:left;padding:6px 10px;border:0;border-bottom:1px solid #F1F5F9;background:#fff;font:500 12px Inter,system-ui,sans-serif;cursor:pointer}' +
      '.tdg .ds button:last-child{border-bottom:0}.tdg .ds button:hover{background:#F8FAFC}' +
      '.tdg .ds button.on{background:#EFF6FF;font-weight:700}' +
      '.tdg .ds .tk{width:14px;flex:none;color:#2563EB}.tdg .ds .ma{color:#64748B;flex:none;width:30px}' +
      '.tdg .ds .dv{margin-left:auto;color:#94A3B8;flex:none}' +
      '.tdg .muc{border:1px solid #CBD5E1;border-radius:8px;padding:8px 10px;display:flex;flex-direction:column;gap:6px}' +
      '.tdg .muc .t{display:flex;gap:6px;align-items:center;font-weight:700}.tdg .muc .t .xoa{margin-left:auto;border:0;background:none;color:#94A3B8;cursor:pointer;font-size:15px}' +
      '.tdg .muc .v{display:flex;gap:6px;align-items:center}' +
      '.tdg .muc input,.tdg select,.tdg textarea{font:500 13px Inter,system-ui,sans-serif;padding:6px 8px;border:1px solid #CBD5E1;border-radius:6px;min-width:0;box-sizing:border-box}' +
      '.tdg .muc .v input{flex:1}.tdg .muc .v .dv{color:#64748B;flex:none}' +
      '.tdg .muc .kq{font-size:11px;font-weight:600}.tdg .kq.tu{color:#15803D}.tdg .kq.duyet{color:#B45309}' +
      '.tdg .muc .zz{display:flex;gap:6px;flex-wrap:wrap}.tdg .muc .zz select{flex:1}' +
      '.tdg label.l{font-size:11px;font-weight:700;color:#475569;margin-bottom:-6px}' +
      '.tdg .dong{display:flex;gap:6px}.tdg .dong>*{flex:1}' +
      '.tdg textarea{width:100%;min-height:44px;resize:vertical}' +
      '.tdg .tom{background:#F8FAFC;border:1px solid #E2E8F0;border-radius:8px;padding:8px 10px;font-size:12px;color:#334155}' +
      '.tdg .tom b{color:#14181F}.tdg .tom .xn{color:#64748B;margin-top:2px}' +
      '.tdg .trong{color:#94A3B8;font-size:12px;text-align:center;padding:6px}' +
      '.tdg .anh{display:flex;gap:6px;flex-wrap:wrap;align-items:center}.tdg .anh img{width:48px;height:48px;object-fit:cover;border-radius:6px;border:1px solid #E2E8F0}' +
      '.tdg .the{border:1px solid #E2E8F0;border-radius:8px;padding:8px 10px;display:flex;flex-direction:column;gap:4px}' +
      '.tdg .the .h{display:flex;gap:6px;align-items:center;flex-wrap:wrap}.tdg .the .h .id{font-weight:700}' +
      '.tdg .the .m{color:#64748B;font-size:11px}.tdg .the .nut{display:flex;gap:6px;flex-wrap:wrap;margin-top:2px}' +
      '.tdg .the .nut button,.tdg .the .nut a{font:600 12px Inter,system-ui,sans-serif;padding:5px 10px;border-radius:6px;border:1px solid #CBD5E1;background:#fff;color:#14181F;cursor:pointer;text-decoration:none}' +
      '.tdg .the .nut .xanh{background:#2563EB;border-color:#2563EB;color:#fff}.tdg .the .nut .do{color:#DC2626;border-color:#FCA5A5}' +
      '.td-ipqc .p{border-top:1px solid #FED7AA;padding-top:6px;margin-top:6px}.td-ipqc .p:first-of-type{border-top:0;margin-top:0;padding-top:0}' +
      '.td-ipqc .tt{font-size:12px;color:#334155;margin-bottom:4px}' +
      '.td-ipqc .xn{display:flex;gap:6px;align-items:center;padding:4px 0;flex-wrap:wrap}.td-ipqc .xn span{flex:1 1 160px;font-size:13px}' +
      '.td-ipqc .xn button{padding:5px 10px;border:1px solid #CBD5E1;border-radius:6px;background:#fff;font:600 12px inherit;font-family:inherit;cursor:pointer}' +
      '.td-ipqc .xn button.on.d{background:#16A34A;border-color:#16A34A;color:#fff}.td-ipqc .xn button.on.k{background:#DC2626;border-color:#DC2626;color:#fff}' +
      '.td-ipqc .xn.need span{color:#DC2626;font-weight:700}';
    document.head.appendChild(st);
  }

  // ── Dữ liệu ────────────────────────────────────────────────────────────────
  async function taiMau() {
    if (mau) return mau;
    const { data, error } = await sb.from('duc_thay_doi_mau').select('*').eq('hieu_luc', true).order('nhom').order('thu_tu');
    if (error) { console.warn('duc_thay_doi_mau:', error.message); mau = []; } else mau = data || [];
    return mau;
  }
  async function taiQuyen() {
    if (quyen) return quyen;
    try {
      const { data: s } = await sb.auth.getSession();
      if (!s || !s.session) return (quyen = { ghi: false, duyet: [], huy_moi: false, chuaDangNhap: true });
      const { data, error } = await sb.rpc('duc_td_quyen');
      quyen = Object.assign(error ? { ghi: false, duyet: [], huy_moi: false } : data, { uid: s.session.user.id });
    } catch (e) { quyen = { ghi: false, duyet: [], huy_moi: false }; }
    return quyen;
  }
  async function taiMo() {
    const { data, error } = await sb.from('duc_thay_doi')
      .select('id,ma_may,ma_sp,id_dong,trang_thai,chi_tiet,khan,can_duyet,da_duyet,ket_qua_duyet,thoi_diem_ghi,nguoi_ghi,nguoi_ghi_id,ly_do,ca')
      .in('trang_thai', MO).order('id').limit(500);
    if (error) { console.warn('duc_thay_doi:', error.message); return false; }
    const cu = JSON.stringify(mo.map(p => [p.id, p.trang_thai]));
    mo = data || [];
    return cu !== JSON.stringify(mo.map(p => [p.id, p.trang_thai]));
  }
  async function lamMoi(bat) {
    const doi = await taiMo();
    if ((doi || bat) && typeof opt.onDoi === 'function') opt.onDoi();
  }

  function batDau(o) {
    opt = o || {};
    napCss();
    if (dangTai) return dangTai;
    dangTai = Promise.all([taiMau(), taiQuyen(), taiMo()]).then(() => { if (typeof opt.onDoi === 'function') opt.onDoi(); });
    if (!timer) {
      timer = setInterval(() => lamMoi(false), 60000);
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') lamMoi(false); });
    }
    return dangTai;
  }

  // ── Bảng điều khiển: biểu tượng + nút ───────────────────────────────────────
  function badge(maMay) {
    const ds = mo.filter(p => p.ma_may === maMay);
    if (!ds.length) return '';
    const dem = {};
    ds.forEach(p => { dem[p.trang_thai] = (dem[p.trang_thai] || 0) + 1; });
    const tip = { cho_duyet: 'Thay đổi chờ duyệt', cho_ap_dung: 'Đã duyệt — chờ trưởng ca chỉnh', cho_ipqc: 'Thay đổi chờ IPQC kiểm' };
    const arg = esc(JSON.stringify(maMay));
    return MO.filter(t => dem[t]).map(t =>
      '<span class="td-b ' + t + '" title="' + tip[t] + '" onclick="event.stopPropagation();ThayDoi.xemMay(' + arg + ')">' +
      TT[t].split(' ')[0] + (dem[t] > 1 ? dem[t] : '') + ' Thay đổi</span>').join('');
  }
  function nut(row, cls) {
    if (!quyen || !quyen.ghi || !row || !row.ma_sp) return '';
    return '<button type="button" class="' + (cls || 'td-nut') + '" onclick="event.stopPropagation();ThayDoi.moGhi(' + esc(JSON.stringify(row.id_dong)) + ')">± Thay đổi</button>';
  }

  // ── Hộp ghi phiếu ──────────────────────────────────────────────────────────
  function taoHop(html) {
    napCss();
    const d = document.createElement('dialog');
    d.className = 'tdg';
    d.innerHTML = html;
    document.body.appendChild(d);
    d.addEventListener('close', () => d.remove());
    d.showModal();
    return d;
  }

  async function moGhi(idDong) {
    const row = typeof opt.layDong === 'function' ? opt.layDong(idDong) : null;
    if (!row || !row.ma_sp) return bao('Máy chưa chạy mã nào.', true);
    await taiQuyen();
    if (!quyen.ghi) return bao('⛔ Chỉ trưởng ca được ghi phiếu thay đổi.', true);
    const ds = await taiMau();
    if (!ds.length) return bao('Chưa có danh mục thay đổi (chưa chạy SQL T307?).', true);

    // Giá trị chuẩn + giá trị "Sau" lần gần nhất (tự điền ô Trước)
    const [chuanRes, cuRes] = await Promise.all([
      sb.from('duc_thay_doi_chuan').select('ma_muc,gia_tri').eq('ma_may', row.ma_may).eq('ma_sp', row.ma_sp),
      sb.from('duc_thay_doi').select('chi_tiet,trang_thai').eq('ma_may', row.ma_may).eq('ma_sp', row.ma_sp)
        .in('trang_thai', ['cho_ipqc', 'ok', 'ng', 'ghi_nhan', 'khong_kiem']).order('id', { ascending: false }).limit(60),
    ]);
    const chuan = {}; (chuanRes.data || []).forEach(c => { chuan[c.ma_muc] = Number(c.gia_tri); });
    const ganNhat = {};
    (cuRes.data || []).forEach(p => (p.chi_tiet || []).forEach(e => { if (!(e.ma in ganNhat) && e.sau != null) ganNhat[e.ma] = e.sau; }));

    const st = { nhom: 'dieu_kien', chon: [], lyDo: '', maLoi: '', anh: [] };
    const byMa = {}; ds.forEach(m => { byMa[m.ma] = m; });
    const demLoi = window.LoiChung ? null : napLoiChung();

    const d = taoHop(
      '<div class="hd"><b>Thay đổi</b><span class="sub">' + esc(row.ma_may) + ' · ' + esc(row.ma_sp) + (row.so_khuon ? ' · ' + esc(row.so_khuon) : '') + ' · ' + esc(row.ca || '') + '</span>' +
        '<button class="x" type="button" title="Đóng">✕</button></div>' +
      '<div class="bd"><div class="nhom"></div><div class="ds"></div><div class="chon"></div>' +
        '<label class="l">Lý do *</label><div class="dong"><select class="lydo"><option value="">— Chọn lý do —</option>' +
          LY_DO.map(x => '<option>' + esc(x) + '</option>').join('') + '</select><select class="maloi" hidden></select></div>' +
        '<textarea class="gc" maxlength="500" placeholder="Ghi chú (không bắt buộc)"></textarea>' +
        '<div class="anh"><button type="button" class="b chupanh">📷 Ảnh</button><input type="file" accept="image/*" multiple hidden></div>' +
        '<div class="tom"></div></div>' +
      '<div class="ft"><button type="button" class="b huy">Huỷ</button><button type="button" class="b khan" hidden title="Ca đêm không có người duyệt: áp dụng ngay, IPQC bắt buộc, duyệt bù sau">⚡ Khẩn</button><button type="button" class="b ok luu" disabled>Lưu</button></div>');
    const $ = s => d.querySelector(s);
    $('.x').onclick = $('.huy').onclick = () => d.close();

    function tinh(c) {   // → { duyet: nhóm | null, pct, ipqc }
      const m = byMa[c.ma];
      if (m.tu_chon) return { duyet: c.nguoi_duyet && c.nguoi_duyet !== 'khong' ? c.nguoi_duyet : null, ipqc: !!c.can_ipqc };
      let duyet = m.nguoi_duyet !== 'khong' ? m.nguoi_duyet : null, pct = null;
      if (m.kieu_nhap === 'so' && m.nguong_pct != null) {
        const truoc = docSo(c.truoc), sau = docSo(c.sau);
        const ch = (m.ma in chuan) ? chuan[m.ma] : truoc;
        if (ch != null && sau != null) {
          pct = ch === 0 ? 100 : Math.round(Math.abs(sau - ch) / Math.abs(ch) * 1000) / 10;
          if (pct <= Number(m.nguong_pct)) duyet = null;
        }
      }
      return { duyet, pct, ipqc: m.can_ipqc };
    }

    function veNhom() {
      const dem = {}; st.chon.forEach(c => { const n = byMa[c.ma].nhom; dem[n] = (dem[n] || 0) + 1; });
      $('.nhom').innerHTML = Object.keys(NHOM).map(n => '<button type="button" data-n="' + n + '" class="' + (st.nhom === n ? 'on' : '') + '">' +
        NHOM[n] + (dem[n] ? '<span class="n">' + dem[n] + '</span>' : '') + '</button>').join('');
      const daChon = new Set(st.chon.map(c => c.ma));
      $('.ds').innerHTML = ds.filter(m => m.nhom === st.nhom).map(m =>
        '<button type="button" data-ma="' + esc(m.ma) + '" class="' + (daChon.has(m.ma) ? 'on' : '') + '">' +
          '<span class="tk">' + (daChon.has(m.ma) ? '✓' : '') + '</span><span class="ma">' + esc(m.ma) + '</span><span>' + esc(m.ten) + '</span>' +
          (m.don_vi ? '<span class="dv">' + esc(m.don_vi) + '</span>' : '') + '</button>').join('') || '<div class="trong">Nhóm này chưa có mục.</div>';
    }

    function veChon() {
      $('.chon').innerHTML = st.chon.map((c, i) => {
        const m = byMa[c.ma], so = m.kieu_nhap === 'so';
        const kieu = so ? ' type="text" inputmode="decimal"' : ' type="text" maxlength="200"';
        return '<div class="muc" data-i="' + i + '"><div class="t"><span>' + esc(m.ma) + ' ' + esc(m.ten) + '</span><button type="button" class="xoa" title="Bỏ mục">✕</button></div>' +
          '<div class="v"><input class="truoc"' + kieu + ' placeholder="Trước" value="' + esc(c.truoc) + '"><span>→</span>' +
            '<input class="sau"' + kieu + ' placeholder="Sau *" value="' + esc(c.sau) + '">' + (m.don_vi ? '<span class="dv">' + esc(m.don_vi) + '</span>' : '') + '</div>' +
          (m.tu_chon ? '<div class="zz"><select class="zipqc"><option value="0">Không cần IPQC</option><option value="1"' + (c.can_ipqc ? ' selected' : '') + '>Cần IPQC</option></select>' +
            '<select class="zduyet">' + Object.keys(DUYET).map(k => '<option value="' + k + '"' + ((c.nguoi_duyet || 'khong') === k ? ' selected' : '') + '>Duyệt: ' + DUYET[k] + '</option>').join('') + '</select></div>' : '') +
          '<div class="kq"></div></div>';
      }).join('');
      veKq();
    }

    function veKq() {
      let duyet = new Set(), ipqc = false, xn = [], du = st.chon.length > 0;
      d.querySelectorAll('.muc').forEach(el => {
        const c = st.chon[Number(el.dataset.i)], m = byMa[c.ma], r = tinh(c);
        const kq = el.querySelector('.kq');
        let t = '';
        if (r.pct != null) t = (r.pct > 0 ? '±' : '') + soVi(r.pct) + '% so với chuẩn' + ((m.ma in chuan) ? ' ' + soVi(chuan[m.ma]) : '') + ' · ';
        kq.className = 'kq ' + (r.duyet ? 'duyet' : 'tu');
        kq.textContent = t + (r.duyet ? '⏳ ' + DUYET[r.duyet] + ' duyệt' : '✓ Trưởng ca tự chỉnh');
        if (r.duyet) duyet.add(r.duyet);
        if (r.ipqc) { ipqc = true; xn = xn.concat(m.tu_chon ? ['Theo nội dung thay đổi'] : (m.xac_nhan || [])); }
        if (m.kieu_nhap === 'so') { if (docSo(c.truoc) == null || docSo(c.sau) == null || docSo(c.truoc) === docSo(c.sau)) du = false; }
        else if (!String(c.sau || '').trim()) du = false;
      });
      const lyDo = $('.lydo').value;
      if (!lyDo || (lyDo === 'Khắc phục lỗi' && !$('.maloi').value)) du = false;
      const canDuyet = duyet.size > 0;
      const tom = $('.tom');
      tom.hidden = !st.chon.length;
      tom.innerHTML = st.chon.length ? (
        (canDuyet ? '<div>⏳ Cần duyệt: <b>' + [...duyet].map(k => DUYET[k]).join(', ') + '</b> — chỉnh máy SAU khi được duyệt</div>' : '<div>✓ Không cần duyệt — lưu là áp dụng</div>') +
        (ipqc ? '<div>🔍 IPQC kiểm sau thay đổi</div><div class="xn">ⓘ ' + esc([...new Set(xn)].join(' · ')) + '</div>' : '<div>Chỉ ghi nhận, không cần IPQC</div>')) : '';
      const luu = $('.luu');
      luu.disabled = !du;
      luu.textContent = canDuyet ? 'Gửi duyệt' : 'Lưu';
      $('.khan').hidden = !(canDuyet && row.ca === 'Ca đêm');
      $('.khan').disabled = !du;
    }

    d.addEventListener('click', e => {
      const bn = e.target.closest('.nhom button');
      if (bn) { st.nhom = bn.dataset.n; veNhom(); return; }
      const bm = e.target.closest('.ds button[data-ma]');
      if (bm) {
        const ma = bm.dataset.ma, i = st.chon.findIndex(c => c.ma === ma);
        if (i >= 0) st.chon.splice(i, 1);
        else {
          const m = byMa[ma];
          const truoc = ma in ganNhat ? ganNhat[ma] : (ma in chuan ? chuan[ma] : '');
          st.chon.push({ ma, truoc: m.kieu_nhap === 'so' ? soVi(truoc) : (truoc || ''), sau: '', can_ipqc: false, nguoi_duyet: 'khong' });
        }
        veNhom(); veChon(); return;
      }
      const bx = e.target.closest('.muc .xoa');
      if (bx) { st.chon.splice(Number(bx.closest('.muc').dataset.i), 1); veNhom(); veChon(); }
    });
    d.addEventListener('input', e => {
      const el = e.target.closest('.muc');
      if (!el) return;
      const c = st.chon[Number(el.dataset.i)];
      if (e.target.classList.contains('truoc')) c.truoc = e.target.value;
      if (e.target.classList.contains('sau')) c.sau = e.target.value;
      veKq();
    });
    d.addEventListener('change', e => {
      const el = e.target.closest('.muc');
      if (el) {
        const c = st.chon[Number(el.dataset.i)];
        if (e.target.classList.contains('zipqc')) c.can_ipqc = e.target.value === '1';
        if (e.target.classList.contains('zduyet')) c.nguoi_duyet = e.target.value;
      }
      if (e.target.classList.contains('lydo')) {
        const ml = $('.maloi'), can = e.target.value === 'Khắc phục lỗi';
        ml.hidden = !can;
        if (can && ml.options.length === 0) veMaLoi(ml);
      }
      veKq();
    });

    async function veMaLoi(ml) {
      if (demLoi) await demLoi;
      let ds2 = [];
      if (window.LoiChung) {
        const seen = new Set();
        ['DUC', 'BAVIA', 'OQC'].forEach(cd => (LoiChung.ds(cd) || []).forEach(x => { if (!seen.has(x.ma)) { seen.add(x.ma); ds2.push(x); } }));
        const thuTu = m => ('DBGSTZ'.indexOf(m[0]) + 1 || 9) + m;   // lỗi đúc lên đầu
        ds2.sort((a, b) => thuTu(a.ma).localeCompare(thuTu(b.ma)));
      }
      ml.innerHTML = '<option value="">— Lỗi cần khắc phục * —</option>' + ds2.map(x => '<option value="' + esc(x.ma) + '">' + esc(x.nhan || x.ma) + '</option>').join('') +
        (ds2.length ? '' : '<option value="Z99">Z99 Khác</option>');
      veKq();
    }

    // Ảnh
    const fi = $('.anh input');
    $('.chupanh').onclick = () => fi.click();
    fi.onchange = () => {
      [...fi.files].forEach(f => { if (st.anh.length < MAX_ANH) st.anh.push(f); });
      fi.value = '';
      d.querySelectorAll('.anh img').forEach(x => x.remove());
      st.anh.forEach(f => { const im = document.createElement('img'); im.src = URL.createObjectURL(f); $('.anh').appendChild(im); });
    };

    async function guiAnh() {
      const urls = [];
      for (const f of st.anh) {
        const blob = window.SuCoAnh ? await SuCoAnh.compress(f) : f;
        const path = 'thay-doi/' + String(row.ma_may).replace(/[^a-zA-Z0-9_-]/g, '_') + '_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 6) + '.jpg';
        const { error } = await sb.storage.from('su-co-duc').upload(path, blob, { contentType: 'image/jpeg', upsert: false });
        if (error) throw new Error('Tải ảnh lỗi: ' + error.message);
        urls.push(sb.storage.from('su-co-duc').getPublicUrl(path).data.publicUrl);
      }
      return urls;
    }

    async function luu(khan) {
      let lyDoKhan = null;
      if (khan) {
        lyDoKhan = window.hoiGhiChuDuyet
          ? await hoiGhiChuDuyet('Ca đêm không có người duyệt: áp dụng ngay, IPQC bắt buộc kiểm, người duyệt sẽ duyệt bù.', { tieuDe: '⚡ Áp dụng khẩn', nutOk: 'Áp dụng', batBuoc: true, goiY: 'Lý do khẩn (bắt buộc)' })
          : prompt('Lý do áp dụng khẩn (bắt buộc):');
        if (!lyDoKhan) return;
      }
      const btns = d.querySelectorAll('.ft button'); btns.forEach(b => { b.disabled = true; });
      try {
        const anh = await guiAnh();
        const ct = st.chon.map(c => {
          const m = byMa[c.ma], o = { ma: c.ma, truoc: m.kieu_nhap === 'so' ? docSo(c.truoc) : String(c.truoc || '').trim(), sau: m.kieu_nhap === 'so' ? docSo(c.sau) : String(c.sau || '').trim() };
          if (m.tu_chon) { o.can_ipqc = !!c.can_ipqc; o.nguoi_duyet = c.nguoi_duyet || 'khong'; }
          return o;
        });
        const { data, error } = await sb.rpc('duc_td_ghi', {
          p_id_dong: row.id_dong, p_chi_tiet: ct, p_ly_do: $('.lydo').value,
          p_ma_loi: $('.lydo').value === 'Khắc phục lỗi' ? ($('.maloi').value || null) : null,
          p_ghi_chu: $('.gc').value.trim() || null, p_anh: anh, p_khan: !!khan, p_ly_do_khan: lyDoKhan,
        });
        if (error) throw new Error(loiRpc(error));
        d.close();
        const tt = data && data.trang_thai;
        bao(tt === 'cho_duyet' ? '⏳ Đã gửi duyệt TD-' + data.id + ' — chỉnh máy sau khi được duyệt.'
          : tt === 'cho_ipqc' ? '✓ Đã ghi TD-' + data.id + (data.khan ? ' (khẩn)' : '') + ' — IPQC sẽ kiểm sau thay đổi.'
          : '✓ Đã ghi nhận TD-' + data.id + '.');
        await lamMoi(true);
      } catch (e) {
        bao('⛔ ' + e.message, true);
        btns.forEach(b => { b.disabled = false; });
        veKq();
      }
    }
    $('.luu').onclick = () => luu(false);
    $('.khan').onclick = () => luu(true);

    veNhom(); veChon();
  }

  let napLoi = null;
  function napLoiChung() {
    if (window.LoiChung) return Promise.resolve();
    if (napLoi) return napLoi;
    const src = (document.querySelector('script[src*="thay-doi.js"]') || {}).src || 'shared/thay-doi.js';
    napLoi = new Promise(res => {
      const s = document.createElement('script');
      s.src = src.replace(/thay-doi\.js(\?.*)?$/, 'loi-chung.js');
      s.onload = () => { try { (LoiChung.nap ? LoiChung.nap() : Promise.resolve()).then(res, res); } catch (e) { res(); } };
      s.onerror = () => res();
      document.head.appendChild(s);
    });
    return napLoi;
  }

  // ── Hộp phiếu đang mở của 1 máy ────────────────────────────────────────────
  function theHtml(p, row) {
    const coTheHuy = quyen && (quyen.huy_moi || (p.nguoi_ghi_id && quyen.uid === p.nguoi_ghi_id));
    const choDuyet = (p.can_duyet || []).filter(g => !(p.da_duyet || []).some(x => x.nhom === g && x.dong_y));
    const duocDuyet = quyen && (p.trang_thai === 'cho_duyet' || (p.khan && !p.ket_qua_duyet)) && choDuyet.some(g => (quyen.duyet || []).includes(g));
    return '<div class="the"><div class="h"><span class="id">TD-' + p.id + '</span><span class="td-b ' + p.trang_thai + '">' + TT[p.trang_thai] + '</span>' +
        (p.khan ? '<span class="td-b cho_ipqc">⚡ Khẩn' + (p.ket_qua_duyet ? '' : ' · chờ duyệt bù') + '</span>' : '') + '</div>' +
      '<div>' + esc(tomTat(p.chi_tiet)) + '</div>' +
      '<div class="m">' + esc(gio(p.thoi_diem_ghi)) + ' · ' + esc(p.nguoi_ghi || '') + ' · ' + esc(p.ly_do || '') +
        (choDuyet.length && (p.trang_thai === 'cho_duyet' || p.khan) ? ' · chờ ' + esc(choDuyet.map(g => DUYET[g] || g).join(', ')) : '') + '</div>' +
      '<div class="nut">' +
        (p.trang_thai === 'cho_ap_dung' && quyen && quyen.ghi ? '<button type="button" class="xanh" data-chinh="' + p.id + '">✓ Đã chỉnh</button>' : '') +
        (duocDuyet ? '<a class="xanh" href="diem-thay-doi.html?id=' + p.id + '">Duyệt</a>' : '') +
        (coTheHuy ? '<button type="button" class="do" data-huy="' + p.id + '">Huỷ phiếu</button>' : '') +
        '<a href="diem-thay-doi.html?id=' + p.id + '" target="_blank" rel="noopener">Chi tiết ↗</a>' +
      '</div></div>';
  }

  async function xemMay(maMay) {
    await taiQuyen();
    const row = typeof opt.layDongMay === 'function' ? opt.layDongMay(maMay) : null;
    const d = taoHop('<div class="hd"><b>Thay đổi</b><span class="sub">' + esc(maMay) + '</span><button class="x" type="button">✕</button></div>' +
      '<div class="bd"></div><div class="ft"><button type="button" class="b huy">Đóng</button>' +
      (quyen.ghi && row && row.ma_sp ? '<button type="button" class="b ok moi">± Ghi thay đổi</button>' : '') + '</div>');
    const bd = d.querySelector('.bd');
    const ve = () => {
      const ds = mo.filter(p => p.ma_may === maMay);
      bd.innerHTML = ds.length ? ds.map(p => theHtml(p, row)).join('') : '<div class="trong">Máy không có thay đổi đang mở.</div>';
    };
    ve();
    d.querySelector('.x').onclick = d.querySelector('.huy').onclick = () => d.close();
    const moi = d.querySelector('.moi');
    if (moi) moi.onclick = () => { d.close(); moGhi(row.id_dong); };
    bd.addEventListener('click', async e => {
      const bc = e.target.closest('[data-chinh]'), bh = e.target.closest('[data-huy]');
      if (bc) {
        const r = typeof opt.layDongMay === 'function' ? opt.layDongMay(maMay) : null;
        if (!r) return bao('Không tìm thấy dòng máy đang chạy.', true);
        bc.disabled = true;
        const { error } = await sb.rpc('duc_td_da_chinh', { p_id: Number(bc.dataset.chinh), p_id_dong: r.id_dong });
        if (error) { bc.disabled = false; return bao('⛔ ' + loiRpc(error), true); }
        bao('✓ Đã xác nhận chỉnh máy — IPQC sẽ kiểm sau thay đổi.');
        await lamMoi(true); ve();
      } else if (bh) {
        const lyDo = window.hoiGhiChuDuyet
          ? await hoiGhiChuDuyet('Huỷ phiếu TD-' + bh.dataset.huy + ' (ghi nhầm / không làm nữa).', { tieuDe: 'Huỷ phiếu', nutOk: 'Huỷ phiếu', nguyHiem: true, batBuoc: true, goiY: 'Lý do huỷ (bắt buộc)' })
          : prompt('Lý do huỷ phiếu:');
        if (!lyDo) return;
        const { error } = await sb.rpc('duc_td_huy', { p_id: Number(bh.dataset.huy), p_ly_do: lyDo });
        if (error) return bao('⛔ ' + loiRpc(error), true);
        bao('Đã huỷ phiếu TD-' + bh.dataset.huy + '.');
        await lamMoi(true); ve();
      }
    });
  }

  // ── IPQC: nội dung xác nhận của phiếu gắn với lần kiểm ─────────────────────
  let ip = null;   // { box, idCheckpoint, ds: [{id, tom, muc: [{t, dat}]}], need }
  async function ipqcMount(box, idCheckpoint) {
    napCss();
    ip = null;
    box.classList.add('hidden'); box.innerHTML = '';
    if (!idCheckpoint || String(idCheckpoint).startsWith('virtual:')) return;
    const { data, error } = await sb.from('duc_thay_doi').select('id,chi_tiet,ly_do,nguoi_ghi,thoi_diem_ap_dung,khan')
      .eq('id_checkpoint', idCheckpoint).eq('trang_thai', 'cho_ipqc').order('id');
    if (error || !data || !data.length) return;
    ip = {
      box, idCheckpoint, need: false,
      ds: data.map(p => {
        let muc = [];
        (p.chi_tiet || []).forEach(e => (e.xac_nhan || []).forEach(t => { if (!muc.some(x => x.t === t)) muc.push({ t, dat: null }); }));
        if (!muc.length) muc = [{ t: 'Kiểm SP sau thay đổi', dat: null }];
        return { id: p.id, tom: tomTat(p.chi_tiet), meta: [gio(p.thoi_diem_ap_dung), p.nguoi_ghi, p.ly_do].filter(Boolean).join(' · '), khan: p.khan, muc };
      }),
    };
    box.addEventListener('click', ipqcClick);
    ipqcVe();
  }
  function ipqcClick(e) {
    const b = e.target.closest('button[data-p]');
    if (!b || !ip) return;
    const m = ip.ds[Number(b.dataset.p)].muc[Number(b.dataset.m)];
    const v = b.dataset.v === '1';
    m.dat = m.dat === v ? null : v;
    ipqcVe();
  }
  function ipqcVe() {
    if (!ip) return;
    ip.box.innerHTML = '<div class="ii-title">🔄 Thay đổi — xác nhận từng nội dung</div>' +
      '<div class="td-ipqc">' + ip.ds.map((p, i) =>
        '<div class="p"><div class="tt"><b>TD-' + p.id + (p.khan ? ' ⚡ khẩn' : '') + ':</b> ' + esc(p.tom) + (p.meta ? '<br><span style="color:#64748B">' + esc(p.meta) + '</span>' : '') + '</div>' +
        p.muc.map((m, j) => '<div class="xn' + (ip.need && m.dat == null ? ' need' : '') + '"><span>' + esc(m.t) + '</span>' +
          '<button type="button" class="d' + (m.dat === true ? ' on' : '') + '" data-p="' + i + '" data-m="' + j + '" data-v="1">Đạt</button>' +
          '<button type="button" class="k' + (m.dat === false ? ' on' : '') + '" data-p="' + i + '" data-m="' + j + '" data-v="0">Không đạt</button></div>').join('') +
        '</div>').join('') + '</div>';
    ip.box.classList.remove('hidden');
  }
  function ipqcKiemTra() {
    if (!ip) return '';
    const thieu = ip.ds.reduce((s, p) => s + p.muc.filter(m => m.dat == null).length, 0);
    if (!thieu) return '';
    ip.need = true; ipqcVe();
    ip.box.scrollIntoView({ behavior: 'smooth', block: 'start' });
    return 'Còn ' + thieu + ' nội dung xác nhận thay đổi chưa chọn Đạt / Không đạt.';
  }
  function ipqcChecklist() {
    if (!ip) return [];
    const out = [];
    ip.ds.forEach(p => p.muc.forEach(m => out.push({ code: 'thay_doi', td_id: String(p.id), muc: 'Thay đổi TD-' + p.id + ': ' + m.t, dat: m.dat === true })));
    return out;
  }

  window.ThayDoi = {
    batDau, badge, nut, moGhi, xemMay, lamMoi: () => lamMoi(true), tomTat, taiMau, taiQuyen,
    ipqcMount, ipqcKiemTra, ipqcChecklist,
    NHOM, NHOM_DAY, DUYET, LY_DO, TT, MO,
    get mo() { return mo; }, get quyen() { return quyen; },
  };
})();
