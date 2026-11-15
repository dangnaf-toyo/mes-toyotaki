// T261: Hộp xác nhận duyệt có ô ghi chú — dùng chung cho mọi màn phê duyệt.
// hoiGhiChuDuyet(noiDung, { tieuDe, nutOk, nguyHiem, batBuoc, goiY, giaTri })
//   → Promise<string|null>: chuỗi ghi chú đã cắt khoảng trắng ('' nếu bỏ trống), null nếu bấm Huỷ / Esc.
//   batBuoc: true → phải nhập mới bấm được (vd lý do từ chối / trả lại).
(function () {
  if (window.hoiGhiChuDuyet) return;
  let css = false;
  function napCss() {
    if (css) return; css = true;
    const st = document.createElement('style');
    st.textContent =
      'dialog.gcd{border:0;border-radius:12px;padding:18px;width:min(440px,calc(100vw - 32px));box-shadow:0 12px 40px rgba(0,0,0,.25);font:500 14px/1.45 Inter,system-ui,sans-serif;color:#14181F;background:#fff}' +
      'dialog.gcd::backdrop{background:rgba(15,23,42,.45)}' +
      'dialog.gcd h3{margin:0 0 6px;font-size:16px;font-weight:700}' +
      'dialog.gcd .nd{white-space:pre-line;margin:0 0 10px;color:#334155}' +
      'dialog.gcd textarea{display:block;width:100%;box-sizing:border-box;min-height:72px;padding:8px 10px;border:1px solid #CBD5E1;border-radius:8px;font:inherit;resize:vertical}' +
      'dialog.gcd textarea:focus{outline:2px solid #3B82F6;outline-offset:0;border-color:#3B82F6}' +
      'dialog.gcd .nut{display:flex;gap:8px;justify-content:flex-end;margin-top:12px}' +
      'dialog.gcd button{font:600 14px Inter,system-ui,sans-serif;border-radius:8px;padding:8px 16px;cursor:pointer;border:1px solid #CBD5E1;background:#fff;color:#14181F}' +
      'dialog.gcd button.ok{background:#16A34A;border-color:#16A34A;color:#fff}' +
      'dialog.gcd button.ok.xau{background:#DC2626;border-color:#DC2626}' +
      'dialog.gcd button:disabled{opacity:.45;cursor:not-allowed}';
    document.head.appendChild(st);
  }
  window.hoiGhiChuDuyet = function (noiDung, o) {
    o = o || {};
    napCss();
    return new Promise((res) => {
      const d = document.createElement('dialog');
      d.className = 'gcd';
      d.innerHTML = (o.tieuDe ? '<h3></h3>' : '') + '<p class="nd"></p><textarea maxlength="1000"></textarea>' +
        '<div class="nut"><button type="button" class="huy">Huỷ</button><button type="button" class="ok"></button></div>';
      if (o.tieuDe) d.querySelector('h3').textContent = o.tieuDe;
      d.querySelector('.nd').textContent = noiDung || '';
      const ta = d.querySelector('textarea'), ok = d.querySelector('.ok');
      ta.placeholder = o.goiY || (o.batBuoc ? 'Lý do (bắt buộc)' : 'Ghi chú (không bắt buộc)');
      ta.value = o.giaTri || '';
      ok.textContent = o.nutOk || 'Duyệt';
      if (o.nguyHiem) ok.classList.add('xau');
      const kiem = () => { ok.disabled = !!o.batBuoc && !ta.value.trim(); };
      ta.addEventListener('input', kiem); kiem();
      let xong = false;
      const dong = (v) => { if (xong) return; xong = true; try { d.close(); } catch (e) {} d.remove(); res(v); };
      ok.onclick = () => { if (!ok.disabled) dong(ta.value.trim()); };
      d.querySelector('.huy').onclick = () => dong(null);
      d.addEventListener('cancel', (e) => { e.preventDefault(); dong(null); });
      ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) ok.onclick(); });
      document.body.appendChild(d);
      d.showModal();
      setTimeout(() => ta.focus(), 30);
    });
  };
})();
