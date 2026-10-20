/**
 * ============================================================================
 * khuon-nam-van-de.js — T127 bước 1: trưởng ca lên khuôn phải xác nhận "Đã nắm
 * thông tin" các vấn đề của lần sản xuất trước (duc_van_de_khuon chưa đóng).
 * Dùng ở duc-dashboard.html + mobile.html. Nhúng SAU supabase-client.js (cần sb),
 * nên có ipqc-text.js để rút gọn mô tả.
 *
 *   if (!(await KhuonNamVanDe.damBao(soKhuon, maMay))) return;   // trước khi gửi lưu
 *
 * Không có vấn đề / khuôn chạy tiếp trên cùng máy / đã xác nhận còn hiệu lực (12h)
 * → trả true ngay. Ngược lại hiện hộp danh sách; tích + bấm "Đã nắm thông tin"
 * → RPC duc_khuon_xac_nhan_nam_van_de → true; Huỷ → false. Server (trigger
 * trg_duc_ca_hien_tai_chan_khuon_chua_nam_vd) vẫn chặn nếu bỏ qua bước này.
 * ============================================================================
 */
(function () {
  function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function gon(t){ return window.IpqcText ? IpqcText.gon(t) : String(t || ''); }
  function dm(d){ if (!d) return ''; const [y, m, dd] = String(d).slice(0, 10).split('-'); return dd + '/' + m + '/' + y; }

  function injectCss(){
    if (document.getElementById('knvd-css')) return;
    const st = document.createElement('style');
    st.id = 'knvd-css';
    st.textContent =
      '.knvd-mask{position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:100000;display:flex;align-items:center;justify-content:center;padding:12px}' +
      '.knvd{background:#fff;border-radius:12px;width:min(640px,100%);max-height:92vh;display:flex;flex-direction:column;box-shadow:0 12px 32px rgba(15,23,42,.3);font-family:inherit;color:#0F172A}' +
      '.knvd-h{padding:12px 16px;border-bottom:1px solid #E2E8F0;font-weight:700;font-size:15px;color:#9A3412;background:#FFF7ED;border-radius:12px 12px 0 0}' +
      '.knvd-h small{display:block;font-weight:500;font-size:12px;color:#7C2D12;margin-top:2px}' +
      '.knvd-b{padding:10px 16px;overflow:auto;display:flex;flex-direction:column;gap:8px}' +
      '.knvd-it{border:1px solid #E2E8F0;border-radius:8px;padding:8px 10px;font-size:13px}' +
      '.knvd-it a{color:#0F5FA5;font-weight:700;text-decoration:underline;text-underline-offset:2px}' +
      '.knvd-it .m{font-size:11.5px;color:#64748B;margin-top:2px}' +
      '.knvd-it .xl{font-size:12px;color:#065F46;margin-top:3px;white-space:pre-wrap}' +
      '.knvd-it .tp{font-size:11px;font-weight:700;color:#B91C1C}' +
      '.knvd-f{padding:10px 16px;border-top:1px solid #E2E8F0;display:flex;flex-direction:column;gap:8px}' +
      '.knvd-f label{display:flex;gap:8px;align-items:flex-start;font-size:13px;font-weight:700;cursor:pointer}' +
      '.knvd-f label input{width:20px;height:20px;flex:none;margin-top:1px}' +
      '.knvd-f .act{display:flex;gap:8px;justify-content:flex-end;flex-wrap:wrap}' +
      '.knvd-f button{border:none;border-radius:6px;padding:9px 14px;font:inherit;font-size:13px;font-weight:700;cursor:pointer}' +
      '.knvd-f .huy{background:#fff;border:1.5px solid #B8C1CC;color:#0F172A}' +
      '.knvd-f .ok{background:#047857;color:#fff}' +
      '.knvd-f .ok:disabled{opacity:.45;cursor:not-allowed}' +
      '.knvd-err{color:#B91C1C;font-size:12.5px;font-weight:600}';
    document.head.appendChild(st);
  }

  async function damBao(maKhuon, maMay){
    const mk = String(maKhuon || '').trim(), may = String(maMay || '').trim();
    if (!mk || !may) return true;
    let d;
    try {
      const { data, error } = await sb.rpc('duc_khuon_vd_lan_truoc', { p_ma_khuon: mk, p_ma_may: may });
      if (error || !data || !data.ok) return true;   // lỗi mạng → để server quyết định
      d = data;
    } catch (e) { return true; }
    const ds = d.van_de || [];
    if (!d.bat || d.chay_tiep || d.da_nam || !ds.length) return true;
    injectCss();
    return new Promise(resolve => {
      const mask = document.createElement('div');
      mask.className = 'knvd-mask';
      mask.innerHTML = '<div class="knvd" role="dialog" aria-modal="true">' +
        '<div class="knvd-h">⚠ Khuôn ' + esc(mk) + ' — ' + ds.length + ' vấn đề của lần sản xuất trước' +
          '<small>Lên máy ' + esc(may) + '. Đọc kỹ để lưu ý khi sản xuất — IPQC sẽ xác nhận có tái phát hay không ở lần kiểm sản phẩm đầu.</small></div>' +
        '<div class="knvd-b">' + ds.map(v => '<div class="knvd-it">' +
          '<a href="van-de-khuon.html?khuon=' + encodeURIComponent(mk) + '&tab=chua-dong&vd=' + encodeURIComponent(v.id_van_de) + '" target="_blank" rel="noopener">' + esc(gon(v.mo_ta) || '(không mô tả)') + ' ↗</a>' +
          (Number(v.lan_tai_phat) ? ' <span class="tp">· tái phát ' + v.lan_tai_phat + ' lần</span>' : '') +
          '<div class="m">' + [dm(v.ngay_phat_hien), v.ca, v.ma_may, v.ma_sp, v.trang_thai].filter(Boolean).map(esc).join(' · ') + '</div>' +
          (v.noi_dung_xu_ly ? '<div class="xl">✔ Đã xử lý: ' + esc(v.noi_dung_xu_ly) + (v.nguoi_xu_ly ? ' — ' + esc(v.nguoi_xu_ly) : '') + (v.ngay_xu_ly ? ' (' + dm(v.ngay_xu_ly) + ')' : '') + '</div>'
            : '<div class="xl" style="color:#B45309">Chưa ghi nội dung xử lý</div>') +
        '</div>').join('') + '</div>' +
        '<div class="knvd-f"><label><input type="checkbox" class="knvd-cb"> Tôi đã nắm các vấn đề trên và biện pháp xử lý, sẽ lưu ý khi sản xuất.</label>' +
          '<div class="knvd-err" hidden></div>' +
          '<div class="act"><button type="button" class="huy">Huỷ — chưa lên khuôn</button>' +
          '<button type="button" class="ok" disabled>✅ Đã nắm thông tin — lên khuôn</button></div></div>' +
      '</div>';
      document.body.appendChild(mask);
      const cb = mask.querySelector('.knvd-cb'), ok = mask.querySelector('.ok'), err = mask.querySelector('.knvd-err');
      const xong = v => { mask.remove(); resolve(v); };
      cb.onchange = () => { ok.disabled = !cb.checked; };
      mask.querySelector('.huy').onclick = () => xong(false);
      ok.onclick = async () => {
        ok.disabled = true; err.hidden = true;
        try {
          const { data, error } = await sb.rpc('duc_khuon_xac_nhan_nam_van_de', { p_ma_khuon: mk, p_ma_may: may, p_ids: ds.map(v => v.id_van_de) });
          if (error || !data || !data.ok) throw new Error(error ? error.message : (data && data.error) || 'Không lưu được xác nhận');
          xong(true);
        } catch (e) {
          err.textContent = e.message; err.hidden = false; ok.disabled = !cb.checked;
        }
      };
    });
  }

  window.KhuonNamVanDe = { damBao };
})();
