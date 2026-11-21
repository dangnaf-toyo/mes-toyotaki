// T302: nút chọn sự cố Đúc — chọn Loại → nút Vấn đề → nút Xử lý (điền vào ô chữ, vẫn sửa / gõ thêm được).
// Danh mục: bảng duc_su_co_mau (ma, loai[], thu_tu, van_de, xu_ly[]). Bảng lỗi / chưa chạy SQL → không hiện nút, form như cũ.
//
// SuCoMau.gan({ loai, vanDe, xuLy, vanDeText })
//   loai      : <select> loại sự cố, hoặc chuỗi loại cố định ("F1 — ...")
//   vanDe     : <textarea> vấn đề (null = không ghi vấn đề, nút vấn đề chỉ để lọc cách xử lý)
//   xuLy      : <textarea> nội dung xử lý
//   vanDeText : vấn đề có sẵn (khi vanDe = null) để tự chọn sẵn nút khớp
// B1/F1 cho chọn nhiều vấn đề. Gọi lại mỗi lần mở hộp (dùng lại khung nút đã tạo).
(function () {
  if (window.SuCoMau) return;
  let cache = null, dang = null;
  function tai() {
    if (cache) return Promise.resolve(cache);
    if (dang) return dang;
    dang = (async () => {
      try {
        const { data, error } = await sb.from('duc_su_co_mau').select('ma,loai,thu_tu,van_de,xu_ly').eq('hieu_luc', true).order('thu_tu');
        if (error) throw error;
        cache = data || [];
      } catch (e) { console.warn('duc_su_co_mau:', e.message || e); cache = []; }
      dang = null;
      return cache;
    })();
    return dang;
  }

  let css = false;
  function napCss() {
    if (css) return; css = true;
    const st = document.createElement('style');
    st.textContent =
      '.scm{margin:2px 0 6px}.scm:empty{display:none}' +
      '.scm-h{font-size:11px;color:var(--text-muted,#64748B);margin:2px 0 4px}' +
      '.scm button.scm-c{display:inline-block;margin:0 4px 4px 0;padding:4px 10px;border:1px solid var(--border-strong,#CBD5E1);border-radius:14px;' +
        'background:var(--bg-panel,#fff);color:var(--text,#14181F);font-family:inherit;font-size:12px;font-weight:500;line-height:1.35;cursor:pointer;text-align:left;max-width:100%}' +
      '.scm button.scm-c:hover{border-color:var(--accent,#2563EB)}' +
      '.scm button.scm-c.on{background:#DBEAFE;border-color:#2563EB;color:#1E3A8A;font-weight:600}' +
      '.scm button.scm-c.on::before{content:"✓ "}' +
      '.scm button.scm-c.khac{border-style:dashed;color:var(--text-muted,#64748B)}';
    document.head.appendChild(st);
  }

  const maLoai = (v) => String(v || '').trim().split(/[\s—–-]/)[0].toUpperCase();
  const NHIEU = { B1: 1, F1: 1 };
  const chuan = (s) => String(s || '').toLowerCase().normalize('NFC');
  const coChu = (txt, cum) => chuan(txt).indexOf(chuan(cum)) >= 0;

  function hop(el) {
    if (!el) return null;
    if (el._scmHop) return el._scmHop;
    const d = document.createElement('div');
    d.className = 'scm';
    el.parentNode.insertBefore(d, el);
    el._scmHop = d;
    return d;
  }
  function nut(text, on, click, khac) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'scm-c' + (on ? ' on' : '') + (khac ? ' khac' : '');
    b.textContent = text;
    b.onclick = click;
    return b;
  }
  function batInput(ta) { ta.dispatchEvent(new Event('input', { bubbles: true })); }
  // Thêm / bỏ 1 cụm trong ô chữ, giữ nguyên phần người dùng tự gõ.
  function themCum(ta, cum, sep) {
    const v = ta.value.trim();
    ta.value = v ? v.replace(/[,;.\s]*$/, sep === ', ' ? '' : '.') + (sep === ', ' ? ', ' : ' ') + cum : cum;
    batInput(ta);
  }
  function boCum(ta, cum) {
    const i = chuan(ta.value).indexOf(chuan(cum));
    if (i < 0) return;
    ta.value = (ta.value.slice(0, i) + ta.value.slice(i + cum.length))
      .replace(/^[\s,;]+/, '').replace(/\s*,\s*,\s*/g, ', ').replace(/[\s,;]+$/, '').replace(/\s{2,}/g, ' ');
    batInput(ta);
  }

  function gan(o) {
    napCss();
    const ta = o.xuLy;
    if (!ta) return;
    const st = ta._scm || (ta._scm = {});
    st.o = o;
    st.chon = null;   // null = chưa chọn tay → tự khớp theo chữ vấn đề
    st.moRong = false; // ô vấn đề cố định: chỉ hiện vấn đề đã khớp, bấm "Vấn đề khác…" mới hiện hết
    const hopVd = hop(o.vanDe || ta), hopXl = o.vanDe ? hop(ta) : (st.hopXl || (st.hopXl = (() => {
      const d = document.createElement('div'); d.className = 'scm'; hopVd.after(d); return d;
    })()));
    if (!o.vanDe) hopVd.classList.add('scm-vd');
    const loaiNow = () => maLoai(typeof o.loai === 'string' ? o.loai : (o.loai && o.loai.value));

    function ve(list) {
      const code = loaiNow();
      const ds = list.filter((x) => (x.loai || []).indexOf(code) >= 0);
      hopVd.innerHTML = ''; hopXl.innerHTML = '';
      if (!ds.length) return;
      const nhieu = !!NHIEU[code];
      const txtVd = o.vanDe ? o.vanDe.value : (o.vanDeText || '');
      if (!st.chon) st.chon = ds.filter((x) => txtVd && coChu(txtVd, x.van_de)).map((x) => x.ma);
      if (!nhieu && st.chon.length > 1) st.chon = st.chon.slice(0, 1);

      const h = document.createElement('div');
      h.className = 'scm-h';
      h.textContent = o.vanDe ? (nhieu ? 'Chọn vấn đề (chọn nhiều được):' : 'Chọn vấn đề:') : 'Vấn đề để gợi ý cách xử lý:';
      hopVd.appendChild(h);
      const gon = !o.vanDe && !st.moRong && st.chon.length > 0;
      ds.forEach((x) => {
        const on = st.chon.indexOf(x.ma) >= 0;
        if (gon && !on) return;
        hopVd.appendChild(nut(x.van_de, on, () => {
          if (on) {
            st.chon = st.chon.filter((m) => m !== x.ma);
            if (o.vanDe) boCum(o.vanDe, x.van_de);
          } else {
            if (!nhieu) {
              const cu = ds.find((y) => y.ma === st.chon[0]);
              if (cu && o.vanDe) boCum(o.vanDe, cu.van_de);
              st.chon = [];
            }
            st.chon.push(x.ma);
            if (o.vanDe && !coChu(o.vanDe.value, x.van_de)) themCum(o.vanDe, x.van_de, ', ');
          }
          ve(list);
        }));
      });
      if (o.vanDe) hopVd.appendChild(nut('Khác…', false, () => o.vanDe.focus(), true));
      else if (gon) hopVd.appendChild(nut('Vấn đề khác…', false, () => { st.moRong = true; ve(list); }, true));

      const xl = [];
      st.chon.forEach((m) => { const x = ds.find((y) => y.ma === m); (x && x.xu_ly || []).forEach((t) => { if (xl.indexOf(t) < 0) xl.push(t); }); });
      if (!xl.length) return;
      const h2 = document.createElement('div');
      h2.className = 'scm-h';
      h2.textContent = 'Chọn cách xử lý (chọn nhiều được):';
      hopXl.appendChild(h2);
      xl.forEach((t) => {
        const on = coChu(ta.value, t);
        hopXl.appendChild(nut(t, on, () => { on ? boCum(ta, t) : themCum(ta, t, ' '); ve(list); }));
      });
      hopXl.appendChild(nut('Khác…', false, () => ta.focus(), true));
    }

    const veLai = () => tai().then(ve);
    if (o.loai && typeof o.loai !== 'string' && !o.loai._scmNghe) {
      o.loai._scmNghe = true;
      o.loai.addEventListener('change', () => { if (ta._scm.o.loai === o.loai) { ta._scm.chon = null; tai().then(ta._scm.ve); } });
    }
    if (!ta._scmNghe) {   // gõ tay → cập nhật dấu ✓ trên nút
      ta._scmNghe = true;
      let hen = null;
      ta.addEventListener('input', () => { clearTimeout(hen); hen = setTimeout(() => tai().then(ta._scm.ve), 250); });
    }
    st.ve = ve;
    veLai();
  }

  window.SuCoMau = { tai, gan };
})();
