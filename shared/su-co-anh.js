/**
 * ============================================================================
 * su-co-anh.js — ảnh sự cố Đúc (T87): ảnh HIỆN TRẠNG lúc phát sinh ('truoc')
 * và ảnh SAU XỬ LÝ ('sau'). Dùng chung cho duc-dashboard.html + mobile.html.
 *
 * Nhúng SAU shared/supabase-client.js (cần `sb`).
 *
 *   const p = SuCoAnh.picker(el, { kind: 'truoc' });            // chọn trước, tải sau
 *   ... await SuCoAnh.uploadPending(p, idSuCo)                   // sau khi có mã sự cố
 *   const p2 = SuCoAnh.picker(el, { kind: 'sau', idSuCo, existing, immediate: true })
 *                                                                // tải + lưu ngay khi chọn
 *
 * Ảnh nén JPEG ≤1280px trên trình duyệt, tải lên bucket "su-co-duc", gắn vào
 * sự cố qua RPC duc_su_co_them_anh (tối đa 10 ảnh mỗi loại); xoá qua
 * duc_su_co_xoa_anh (người tải / trưởng ca / quản lý / admin).
 * ============================================================================
 */
(function () {
  const BUCKET = 'su-co-duc';
  const MAX = 10;
  const LABEL = { truoc: 'Ảnh hiện trạng sự cố', sau: 'Ảnh sau khi xử lý' };

  function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  function injectCss(){
    if (document.getElementById('sca-css')) return;
    const st = document.createElement('style');
    st.id = 'sca-css';
    st.textContent =
      '.sca{border:1px dashed #B8C1CC;border-radius:8px;padding:8px 10px;background:#F8FAFC}' +
      '.sca-h{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:12px;font-weight:700;color:#475569}' +
      '.sca-h .cnt{font-weight:600;color:#94A3B8}' +
      '.sca-h .sp{flex:1}' +
      '.sca-b{border:1px solid #0F5FA5;background:#fff;color:#0F5FA5;border-radius:6px;padding:5px 10px;font:inherit;font-size:12px;font-weight:700;cursor:pointer}' +
      '.sca-b:disabled{opacity:.45;cursor:default}' +
      '.sca-g{display:grid;grid-template-columns:repeat(auto-fill,minmax(70px,1fr));gap:6px;margin-top:8px}' +
      '.sca-g:empty{display:none}' +
      '.sca-t{position:relative;aspect-ratio:1;border-radius:6px;overflow:hidden;background:#E2E8F0}' +
      '.sca-t img{width:100%;height:100%;object-fit:cover;display:block}' +
      '.sca-t.pending{outline:2px solid #F59E0B;outline-offset:-2px}' +
      '.sca-t .x{position:absolute;top:2px;right:2px;width:22px;height:22px;border-radius:50%;border:none;background:rgba(15,23,42,.7);color:#fff;font-size:12px;line-height:22px;cursor:pointer;padding:0}' +
      '.sca-busy{font-size:11.5px;color:#B45309;margin-top:6px}' +
      '.sca-note{font-size:11px;color:#94A3B8;margin-top:6px}';
    document.head.appendChild(st);
  }

  function compress(file){
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = reject;
      reader.onload = ev => {
        const img = new Image();
        img.onerror = reject;
        img.onload = () => {
          const scale = Math.min(1, 1280 / Math.max(img.width, img.height));
          const c = document.createElement('canvas');
          c.width = Math.round(img.width * scale);
          c.height = Math.round(img.height * scale);
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          c.toBlob(b => b ? resolve(b) : reject(new Error('Không nén được ảnh')), 'image/jpeg', 0.82);
        };
        img.src = ev.target.result;
      };
      reader.readAsDataURL(file);
    });
  }

  async function uploadBlob(blob, idSuCo, kind){
    const safe = String(idSuCo || 'su-co').replace(/[^a-zA-Z0-9_-]/g, '_');
    const path = safe + '/' + kind + '_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 6) + '.jpg';
    const { error } = await sb.storage.from(BUCKET).upload(path, blob, { contentType: 'image/jpeg', upsert: false });
    if (error) throw new Error(error.message);
    return sb.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
  }

  async function attach(idSuCo, kind, urls){
    const { data, error } = await sb.rpc('duc_su_co_them_anh', { p_id_su_co: idSuCo, p_loai: kind, p_urls: urls });
    if (error) throw new Error(error.message);
    if (!data || !data.ok) throw new Error((data && data.error) || 'Không lưu được ảnh');
    return data;
  }

  async function load(idSuCo){
    const out = { truoc: [], sau: [] };
    if (!idSuCo) return out;
    const { data, error } = await sb.from('duc_su_co_anh').select('id,loai,url,nguoi,thoi_diem').eq('id_su_co', idSuCo).order('id');
    if (error) throw new Error(error.message);
    (data || []).forEach(r => { (out[r.loai] || (out[r.loai] = [])).push(r); });
    return out;
  }

  async function remove(id){
    const { data, error } = await sb.rpc('duc_su_co_xoa_anh', { p_id: id });
    if (error) throw new Error(error.message);
    if (!data || !data.ok) throw new Error((data && data.error) || 'Không xoá được ảnh');
  }

  /**
   * opts: kind ('truoc'|'sau'), title, existing [{id,url}], idSuCo,
   *       immediate (true = tải + lưu ngay khi chọn, cần idSuCo),
   *       onError(msg), onChange()
   */
  function picker(container, opts){
    injectCss();
    const p = { kind: opts.kind, idSuCo: opts.idSuCo || null, existing: (opts.existing || []).slice(), pending: [], busy: false };
    const uid = 'sca' + Math.random().toString(36).slice(2, 8);
    const err = msg => (opts.onError ? opts.onError(msg) : alert(msg));
    container.innerHTML =
      '<div class="sca"><div class="sca-h"><span>📷 ' + esc(opts.title || LABEL[p.kind]) + ' <span class="cnt"></span></span><span class="sp"></span>' +
      '<button type="button" class="sca-b" data-pick="cam">📷 Chụp</button><button type="button" class="sca-b" data-pick="album">🖼 Chọn ảnh</button></div>' +
      '<input type="file" accept="image/*" capture="environment" hidden data-in="cam">' +
      '<input type="file" accept="image/*" multiple hidden data-in="album">' +
      '<div class="sca-g"></div><div class="sca-busy" hidden>⏳ Đang tải ảnh lên...</div>' +
      (opts.immediate ? '' : '<div class="sca-note">Ảnh viền vàng sẽ được tải lên khi bấm lưu.</div>') + '</div>';
    const root = container.querySelector('.sca');

    p.render = function(){
      const total = p.existing.length + p.pending.length;
      root.querySelector('.cnt').textContent = total + '/' + MAX;
      root.querySelector('.sca-g').innerHTML =
        p.existing.map(r => '<div class="sca-t"><a href="' + esc(r.url) + '" target="_blank" rel="noopener"><img src="' + esc(r.url) + '" loading="lazy" alt=""></a>' +
          (opts.canRemoveExisting ? '<button type="button" class="x" data-rm-id="' + r.id + '" title="Xoá ảnh">✕</button>' : '') + '</div>').join('') +
        p.pending.map((x, i) => '<div class="sca-t pending"><img src="' + x.preview + '" alt=""><button type="button" class="x" data-rm-p="' + i + '" title="Bỏ ảnh">✕</button></div>').join('');
      root.querySelector('.sca-busy').hidden = !p.busy;
      root.querySelectorAll('[data-pick]').forEach(b => { b.disabled = p.busy || total >= MAX; });
    };
    p.hasPending = () => p.pending.length > 0;

    root.addEventListener('click', async e => {
      const pk = e.target.closest('[data-pick]');
      if (pk) return root.querySelector('[data-in="' + pk.dataset.pick + '"]').click();
      const rp = e.target.closest('[data-rm-p]');
      if (rp) { const x = p.pending.splice(Number(rp.dataset.rmP), 1)[0]; if (x) URL.revokeObjectURL(x.preview); p.render(); if (opts.onChange) opts.onChange(); return; }
      const ri = e.target.closest('[data-rm-id]');
      if (ri) {
        if (!confirm('Xoá ảnh này khỏi sự cố?')) return;
        try { await remove(Number(ri.dataset.rmId)); p.existing = p.existing.filter(r => String(r.id) !== ri.dataset.rmId); p.render(); if (opts.onChange) opts.onChange(); }
        catch (er) { err('Lỗi xoá ảnh: ' + er.message); }
      }
    });
    root.querySelectorAll('input[type=file]').forEach(inp => inp.addEventListener('change', async () => {
      const files = Array.from(inp.files || []);
      inp.value = '';
      if (!files.length) return;
      const room = MAX - p.existing.length - p.pending.length;
      if (room <= 0) return err('Đã đủ tối đa ' + MAX + ' ảnh');
      if (files.length > room) err('Chỉ thêm được ' + room + ' ảnh nữa (tối đa ' + MAX + ')');
      p.busy = true; p.render();
      const blobs = [];
      for (const f of files.slice(0, room)) {
        try { blobs.push(await compress(f)); } catch (er) { err('Lỗi đọc ảnh ' + (f.name || '') + ': ' + er.message); }
      }
      if (opts.immediate) {
        try {
          const urls = [];
          for (const b of blobs) urls.push(await uploadBlob(b, p.idSuCo, p.kind));
          if (urls.length) { await attach(p.idSuCo, p.kind, urls); p.existing = (await load(p.idSuCo))[p.kind]; }
        } catch (er) { err('Lỗi tải ảnh: ' + er.message); }
      } else {
        blobs.forEach(b => p.pending.push({ blob: b, preview: URL.createObjectURL(b) }));
      }
      p.busy = false; p.render();
      if (opts.onChange) opts.onChange();
    }));
    p.render();
    return p;
  }

  // Tải các ảnh đang chờ của picker lên rồi gắn vào sự cố. Trả về số ảnh đã lưu.
  async function uploadPending(p, idSuCo){
    if (!p || !p.pending.length) return 0;
    if (!idSuCo) throw new Error('Chưa có mã sự cố để gắn ảnh');
    p.busy = true; p.render();
    try {
      const urls = [];
      for (const x of p.pending) urls.push(await uploadBlob(x.blob, idSuCo, p.kind));
      await attach(idSuCo, p.kind, urls);
      p.pending.forEach(x => URL.revokeObjectURL(x.preview));
      p.pending = [];
      return urls.length;
    } finally { p.busy = false; p.render(); }
  }

  window.SuCoAnh = { picker, uploadPending, load, remove, compress, MAX, LABEL };
})();
