// T258: Gợi ý mã mới theo "Quy tắc đặt tên" (Quản trị danh mục → tab Quy tắc đặt tên).
// Chỉ gợi ý + cảnh báo sai mẫu; mã trùng thì trang gọi tự chặn. Không đổi DB.
//   GoiYMa.sp / spKiem      — KHÁCH-SẢN PHẨM-STT   (EXE-OUT-01)
//   GoiYMa.nvl / nvlKiem    — N-LLL-QQ-STT         (K-NHN-12-001)
//   GoiYMa.khuon / khuonKiem — Tên ngắn #Số khuôn  (OUT #3)
//   GoiYMa.dao / daoKiem    — N-LOẠI-KÍCH THƯỚC-STT (D-PNG-0800-001) — T272 dao cụ Gia công
// Kết quả gợi ý: { ma, note } hoặc { loi }. Kết quả kiểm: { muc: 'ok'|'canh'|'loi', text }.
(function () {
  const khongDau = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D');
  const hoa = s => khongDau(s).toUpperCase();
  const tu = s => hoa(s).replace(/\(.*?\)/g, ' ').split(/[^A-Z0-9]+/).filter(Boolean);
  const pad = (n, k) => String(n).padStart(k, '0');
  function sttTiep(dsMa, pre, k){
    let max = 0;
    dsMa.forEach(m => {
      m = String(m || '').toUpperCase();
      if (m.startsWith(pre)) { const n = Number(m.slice(pre.length)); if (Number.isInteger(n) && n > max) max = n; }
    });
    return pre + pad(max + 1, k);
  }

  // ── Sản phẩm ─────────────────────────────────────────────────────────────
  const SP_RE = /^[A-Z]{3}-[A-Z0-9]{3}-\d{2}$/;
  const tuChinh = s => tu(s).filter(w => w.length >= 3);   // bỏ "CL", "P"… đứng đầu tên
  function viTat3(s){
    const w = tuChinh(s)[0] || tu(s)[0] || '';
    return /^\d+$/.test(w) ? w.slice(0, 3) : w.replace(/[^A-Z0-9]/g, '').slice(0, 3);
  }
  // ds: [{ ma_sp, ten_sp, ten_khach_hang }]
  function sp(inp, ds){
    const maGo = hoa(inp.maGo).trim();
    let kh = '';
    const m1 = maGo.match(/^([A-Z]{3})(?![A-Z])/);
    const mk = hoa(inp.maKh).replace(/[^A-Z]/g, '');
    if (m1) kh = m1[1];
    else if (mk.length === 3) kh = mk;
    else if (inp.tenKh) {
      const t = hoa(inp.tenKh).trim();
      const cung = ds.find(r => r.ten_khach_hang && hoa(r.ten_khach_hang).trim() === t && SP_RE.test(String(r.ma_sp || '')));
      kh = cung ? cung.ma_sp.slice(0, 3) : t.replace(/[^A-Z]/g, '').slice(0, 3);
    }
    if (kh.length !== 3) return { loi: 'Gõ 3 chữ mã khách vào ô Mã SP (VD EXE) hoặc nhập Tên khách hàng' };

    let giua = '';
    const m2 = maGo.match(/^[A-Z]{3}-([A-Z0-9]{3})(?![A-Z0-9])/);
    if (m2) giua = m2[1];
    else {
      const ten = inp.tenSp || inp.maSpKh || '';
      if (!tu(ten).length) return { loi: 'Nhập Tên SP để gợi ý mã' };
      // Cùng khách đã có SP cùng họ tên (VD "P PLLY FIX" → PLY) thì dùng lại phần SẢN PHẨM của mã đó.
      const w = tuChinh(ten);
      const ung = [];
      ds.forEach(r => {
        const ma = String(r.ma_sp || '').toUpperCase();
        if (!SP_RE.test(ma) || !ma.startsWith(kh + '-') || !r.ten_sp) return;
        const w2 = tuChinh(r.ten_sp);
        let c = 0; while (c < w.length && c < w2.length && w[c] === w2[c]) c++;
        if (c) ung.push({ c, giua: ma.slice(4, 7) });
      });
      const best = Math.max(0, ...ung.map(u => u.c));
      const loai = new Set(ung.filter(u => u.c === best).map(u => u.giua));
      giua = best && loai.size === 1 ? [...loai][0] : viTat3(ten);
      if (giua.length < 3) giua = (giua + 'XXX').slice(0, 3);
    }
    const ma = sttTiep(ds.map(r => r.ma_sp), kh + '-' + giua + '-', 2);
    return { ma, note: '' };
  }
  function spKiem(ma, ds){
    ma = String(ma || '').trim();
    if (!ma) return { muc: 'ok', text: '' };
    if (ds.some(r => String(r.ma_sp || '').toUpperCase() === ma.toUpperCase())) return { muc: 'loi', text: '⛔ Mã đã có' };
    if (!SP_RE.test(ma)) return { muc: 'canh', text: '⚠ Sai mẫu KHÁCH-SẢN PHẨM-STT, VD EXE-OUT-01' };
    const dsKh = new Set(ds.map(r => String(r.ma_sp || '').slice(0, 3).toUpperCase()));
    if (!dsKh.has(ma.slice(0, 3))) return { muc: 'canh', text: '⚠ Khách mới "' + ma.slice(0, 3) + '" — kiểm lại 3 chữ' };
    return { muc: 'ok', text: '✓ Đúng mẫu' };
  }

  // ── Nguyên vật liệu ──────────────────────────────────────────────────────
  const NVL_RE = /^[KCSB]-[A-Z]{3}-[A-Z0-9]{2}-\d{3}$/;
  const NHOM_CHU = { kim_loai: 'K', linh_kien: 'C', son_hoa_chat: 'S', bao_bi: 'B' };
  const MAC_QQ = { ADC12: '12', ADC6: '06', EZDA3: 'A3', HD2: 'S1' };
  const CO = { SS: 'SS', LL: 'LL', S: 'OS', L: 'OL', OS: 'OS', OL: 'OL', M: 'OM' };
  function nhomTuTen(t){
    if (/\b(NHOM|KEM|ADC|EZDA|HOP KIM)\b/.test(t) && !/\bONG\b/.test(t)) return 'K';
    if (/\b(SON|HOA CHAT|DUNG MOI|BOT)\b/.test(t)) return 'S';
    if (/\b(THUNG|TUI|HOP|BAO|CARTON|NILON|PALLET|XOP|TEM)\b/.test(t)) return 'B';
    return 'C';
  }
  // ds: [{ ma_nvl, ten_nvl }] ; mac: mã mác đang chọn ; macKem: true nếu mác là kẽm
  function nvl(inp, ds){
    const ten = String(inp.ten || '').trim();
    if (!ten) return { loi: 'Nhập Tên NVL để gợi ý mã' };
    const t = ' ' + tu(ten).join(' ') + ' ';
    const n = NHOM_CHU[inp.nhom] || nhomTuTen(t);
    const mac = hoa(inp.mac).replace(/[^A-Z0-9]/g, '');
    let lll = '', qq = '', note = '';
    if (n === 'K') {
      lll = (inp.macKem || /\bKEM\b|EZDA/.test(t)) ? 'KEN' : 'NHN';
      const m = mac || (t.match(/\b(ADC\d+|EZDA\d+|HD\d+)\b/) || [])[1] || '';
      qq = MAC_QQ[m] || (m.match(/(\d+)$/) ? pad(m.match(/(\d+)$/)[1].slice(-2), 2) : m.slice(-2));
    } else {
      const w = tu(ten).filter(x => !CO[x] && !/^\d+$/.test(x));
      // Cùng nhóm đã có NVL trùng 2 chữ đầu tên (VD "Ống nhôm phía ngoài") thì dùng lại LLL của mã đó.
      const cung = ds.find(r => NVL_RE.test(String(r.ma_nvl || '')) && r.ma_nvl[0] === n &&
        tu(r.ten_nvl).filter(x => !CO[x]).slice(0, 3).join(' ') === w.slice(0, 3).join(' '));
      if (cung) lll = cung.ma_nvl.slice(2, 5);
      else if (w.length >= 3) lll = w.slice(0, 3).map(x => x[0]).join('');
      else if (w.length === 2) lll = w[0].slice(0, 2) + w[1][0];
      else lll = (w[0] || '').slice(0, 3);
      const co = tu(ten).find(x => CO[x]);
      const so = ten.match(/(\d+(?:[.,]\d+)?)/);
      if (co) qq = CO[co];
      else if (so) qq = pad(String(Math.round(Number(so[1].replace(',', '.')))).slice(-2), 2);
    }
    lll = lll.replace(/[^A-Z]/g, '');
    if (lll.length < 3) lll = (lll + 'XXX').slice(0, 3);
    if (!/^[A-Z0-9]{2}$/.test(qq)) { qq = 'XX'; note = 'Thay XX bằng đặc tính (mác / cỡ / đường kính)'; }
    const ma = sttTiep(ds.map(r => r.ma_nvl), n + '-' + lll + '-' + qq + '-', 3);
    return { ma, note };
  }
  function nvlKiem(ma, ds, maCu){
    ma = String(ma || '').trim();
    if (!ma || (maCu && ma === maCu)) return { muc: 'ok', text: '' };
    if (ds.some(r => String(r.ma_nvl || '').toUpperCase() === ma.toUpperCase())) return { muc: 'loi', text: '⛔ Mã đã có' };
    if (!NVL_RE.test(ma)) return { muc: 'canh', text: '⚠ Sai mẫu N-LLL-QQ-STT, VD K-NHN-12-001' };
    if (ma.includes('-XX-')) return { muc: 'canh', text: '⚠ Thay XX bằng đặc tính' };
    return { muc: 'ok', text: '✓ Đúng mẫu' };
  }

  // ── Khuôn ────────────────────────────────────────────────────────────────
  const KHUON_RE = /^[A-Z0-9]+ #[A-Z0-9]+(-[A-Z0-9]+)?$/;
  const tenNgan = ma => String(ma || '').split('#')[0].trim().toUpperCase();
  // molds: [{ ma_khuon, ma_sp }] ; inp: { maSp, tenSp, maGo }
  function khuon(inp, molds){
    const maSp = String(inp.maSp || '').trim();
    if (!maSp) return { loi: 'Chọn Mã sản phẩm trước' };
    const anhEm = molds.filter(m => m.ma_sp === maSp && m.ma_khuon);
    let ngan = '';
    if (anhEm.length) {
      const dem = {};
      anhEm.forEach(m => { const k = tenNgan(m.ma_khuon); if (k) dem[k] = (dem[k] || 0) + 1; });
      ngan = Object.keys(dem).sort((a, b) => dem[b] - dem[a])[0] || '';
    }
    if (!ngan) {
      const w = tu(inp.tenSp).filter(x => /\d/.test(x) && /^[A-Z0-9]{3,5}$/.test(x));
      const tach = hoa(inp.tenSp).match(/\b([A-Z]{2})\s+(\d{2})\b/);   // "MT 77" → MT77
      ngan = w[0] || (tach ? tach[1] + tach[2] : '') || (maSp.split('-')[1] || '').toUpperCase();
    }
    if (!ngan) return { loi: 'Không tìm được tên ngắn — gõ tay, VD OUT #3' };
    const go = hoa(inp.maGo).trim();
    let so = (go.match(/#\s*([A-Z0-9]+(?:-[A-Z0-9]+)?)\s*$/) || go.match(/^([0-9]+(?:-[0-9]+)?)$/) || [])[1] || '';
    if (!so) {
      const daCo = molds.filter(m => tenNgan(m.ma_khuon) === ngan).map(m => Number(String(m.ma_khuon).split('#')[1]));
      so = String(Math.max(0, ...daCo.filter(Number.isInteger)) + 1);
    }
    return { ma: ngan + ' #' + so, note: anhEm.length ? '' : 'Tên ngắn lấy từ tên SP — kiểm lại số khắc trên khuôn' };
  }
  function khuonKiem(ma, molds, maSp, maCu){
    ma = String(ma || '').trim();
    if (!ma || (maCu && ma === maCu)) return { muc: 'ok', text: '' };
    if (molds.some(m => String(m.ma_khuon || '').trim().toUpperCase() === ma.toUpperCase())) return { muc: 'loi', text: '⛔ Mã khuôn đã có' };
    if (!KHUON_RE.test(ma)) return { muc: 'canh', text: '⚠ Sai mẫu "Tên ngắn #Số", VD OUT #3' };
    const anhEm = maSp ? [...new Set(molds.filter(m => m.ma_sp === maSp).map(m => tenNgan(m.ma_khuon)))] : [];
    if (anhEm.length && !anhEm.includes(tenNgan(ma))) return { muc: 'canh', text: '⚠ Khuôn cùng SP đang dùng tên "' + anhEm.join('", "') + '"' };
    return { muc: 'ok', text: '✓ Đúng mẫu' };
  }

  // ── Dao cụ Gia công (T272) — N-LOẠI-KÍCH THƯỚC-STT ───────────────────────
  const DAO_NHOM = { D: 'Dao cắt', M: 'Mảnh cắt', H: 'Đầu kẹp BT', C: 'Collet / áo kẹp', K: 'Cán dao', P: 'Phụ trợ' };
  const DAO_LOAI = {
    D: { PNG: 'Dao phay ngón', PCA: 'Dao phay cầu', PCT: 'Dao phay chữ T', PDH: 'Dao phay định hình', PVM: 'Dao vát mép',
         PRE: 'Dao phay ren', KHO: 'Mũi khoan', KTA: 'Mũi khoan tâm', DOA: 'Mũi doa', TRO: 'Mũi taro', CHU: 'Dao chuốt' },
    M: { TIE: 'Mảnh tiện', TTR: 'Mảnh tiện trong', MLO: 'Mảnh móc lỗ', RAN: 'Mảnh cắt rãnh', PHA: 'Mảnh dao phay', PRE: 'Mảnh phay ren', DEM: 'Mảnh đệm' },
    K: { TIE: 'Cán dao tiện ngoài', MLO: 'Cán móc lỗ', RAN: 'Cán dao cắt rãnh', PRE: 'Thân dao phay ren' },
    P: { CHM: 'Chấu mềm', SGO: 'Thiết bị set gốc dao', BGO: 'Đầu dò bổ gốc' },
  };
  const DAO_RE = {
    D: /^D-(PNG|PCA|PCT|PDH|PVM|PRE|KHO|KTA|DOA|TRO|CHU)-[0-9P][0-9]{3}-\d{3}$/,
    M: /^M-(TIE|TTR|MLO|RAN|PHA|PRE|DEM)-[A-Z]{4}-\d{3}$/,
    H: /^H-[A-Z0-9]{2,7}-\d{3}-\d{3}$/,
    C: /^C-[A-Z0-9]{2,7}-\d{4}-\d{3}$/,
    K: /^K-(TIE|MLO|RAN|PRE)-\d{4}-\d{3}$/,
    P: /^P-(CHM|SGO|BGO)-[0-9]{4}-\d{3}$/,
  };
  // Kích thước: Ø8 → 0800, 2.76 → 0276, M3 → 0300, PT1/4 → P014; nhóm H = chiều dài 3 số; nhóm M = 4 chữ hình dạng mảnh.
  function daoKt(nhom, raw){
    const t = hoa(raw).replace(/\s+/g, '');
    if (!t) return nhom === 'P' ? '0000' : '';
    if (nhom === 'M') { const m = t.match(/[A-Z]{4}/); return m ? m[0] : ''; }
    const pt = t.match(/PT(\d+)\/(\d+)/);
    if (pt) return 'P' + pad(pt[1] + pt[2], 3).slice(-3);
    const so = t.replace(',', '.').match(/(\d+(?:\.\d+)?)/);
    if (!so) return '';
    const n = Number(so[1]);
    if (nhom === 'H') return pad(Math.round(n), 3).slice(-3);
    return pad(Math.round(n * 100), 4).slice(-4);
  }
  // inp: { nhom, loai, kt } ; dsMa: mảng mã đã có
  function dao(inp, dsMa){
    const nhom = String(inp.nhom || '').toUpperCase();
    if (!DAO_NHOM[nhom]) return { loi: 'Chọn nhóm' };
    const loai = hoa(inp.loai).replace(/[^A-Z0-9]/g, '');
    if (!loai) return { loi: nhom === 'H' || nhom === 'C' ? 'Nhập kiểu kẹp, VD ER20' : 'Chọn loại' };
    const kt = daoKt(nhom, inp.kt);
    if (!kt) return { loi: nhom === 'M' ? 'Nhập mã mảnh, VD DCMT070204' : nhom === 'H' ? 'Nhập chiều dài, VD 70' : 'Nhập kích thước, VD Ø8 / M3' };
    const ma = sttTiep(dsMa, nhom + '-' + loai + '-' + kt + '-', 3);
    let ten = (DAO_LOAI[nhom] && DAO_LOAI[nhom][loai]) || (nhom === 'H' ? 'Đầu kẹp BT30 ' + loai : nhom === 'C' ? 'Collet ' + loai : '');
    const kx = String(inp.kt || '').trim();
    if (ten && kx && nhom !== 'H' && nhom !== 'P') ten += nhom === 'M' ? ' ' + hoa(kx) : /^M|^PT/i.test(kx) ? ' ' + kx.toUpperCase() : ' Ø' + kx.replace(/^[ØD]/i, '');
    return { ma, ten, note: '' };
  }
  function daoKiem(ma, dsMa, maCu){
    ma = String(ma || '').trim().toUpperCase();
    if (!ma || (maCu && ma === String(maCu).toUpperCase())) return { muc: 'ok', text: '' };
    if (dsMa.some(m => String(m || '').toUpperCase() === ma)) return { muc: 'loi', text: '⛔ Mã đã có' };
    const re = DAO_RE[ma[0]];
    if (!re || !re.test(ma)) return { muc: 'canh', text: '⚠ Sai mẫu N-LOẠI-KÍCH THƯỚC-STT, VD D-PNG-0800-001' };
    return { muc: 'ok', text: '✓ Đúng mẫu' };
  }

  // ── Hiển thị ─────────────────────────────────────────────────────────────
  function hien(el, kq, note){
    if (!el) return;
    const text = [kq && kq.text, note].filter(Boolean).join(' · ');
    el.textContent = text;
    el.hidden = !text;
    el.style.color = kq && kq.muc === 'loi' ? 'var(--alarm-fg)' : kq && kq.muc === 'canh' ? 'var(--warn-fg, #B45309)' : 'var(--run-fg, #047857)';
  }
  if (!document.getElementById('goi-y-ma-css')) {
    const st = document.createElement('style');
    st.id = 'goi-y-ma-css';
    st.textContent = '.gy-row{display:flex;gap:6px;align-items:stretch}.gy-row>input{flex:1;min-width:0}' +
      '.gy-btn{flex:none;padding:0 10px;border:1px solid var(--accent,#2563EB);border-radius:6px;background:transparent;color:var(--accent,#2563EB);font:600 12px inherit;font-family:inherit;cursor:pointer;white-space:nowrap}' +
      '.gy-btn:hover{background:var(--accent,#2563EB);color:#fff}.gy-note{font-size:11.5px;margin-top:3px;font-weight:600}';
    document.head.appendChild(st);
  }

  window.GoiYMa = { sp, spKiem, nvl, nvlKiem, khuon, khuonKiem, dao, daoKiem, DAO_NHOM, DAO_LOAI, hien, khongDau };
})();
