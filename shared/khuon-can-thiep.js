/**
 * ============================================================================
 * khuon-can-thiep.js — T210: phân cấp phê duyệt công việc can thiệp khuôn
 * (QĐ bảo dưỡng khuôn 04/11/2026). Dùng chung cho Dashboard tổ khuôn,
 * check sheet bảo dưỡng và màn điều khiển đúc.
 *
 * Nhúng SAU shared/supabase-client.js (cần `sb`).
 *
 *   KhuonCT.mount(el, { nguon: 'xlbt'|'cs', nguonId, choPhepKhongTacDong, onChange })
 *       → khối "Cấp công việc & phê duyệt" (chọn hạng mục → tự ra cấp → gửi duyệt
 *         → duyệt / từ chối; T210d bỏ cam kết an toàn). Trả { reload(), state() }.
 *   KhuonCT.queue(el, { onChange })   → danh sách chờ duyệt + duyệt thay ca đêm chờ QLBP xác nhận.
 *   KhuonCT.lichSu(el, { maKhuon })   → lịch sử can thiệp theo khuôn.
 *   KhuonCT.modal({ nguon, nguonId, tieuDe, choPhepKhongTacDong, onChange }) → mở khối trong hộp thoại.
 *
 * Mọi chặn cứng nằm ở server (duc_khuon_ct_kiem) — giao diện chỉ hướng dẫn.
 * ============================================================================
 */
(function () {
  const CAP = {
    0: { ten: 'Cấp 0 · Được tự làm', duyet: 'Không cần duyệt — ghi phiếu', mau: '#047857', nen: '#ECFDF5' },
    1: { ten: 'Cấp 1 · Tổ trưởng duyệt', duyet: 'Tổ trưởng khuôn (hoặc trưởng ca chỉ thị)', mau: '#B45309', nen: '#FFFBEB' },
    2: { ten: 'Cấp 2 · QLBP Đúc duyệt', duyet: 'Quản lý bộ phận Đúc', mau: '#C2410C', nen: '#FFF7ED' },
    3: { ten: 'Cấp 3 · Giám đốc SX duyệt', duyet: 'Giám đốc sản xuất', mau: '#B91C1C', nen: '#FEF2F2' },
  };
  let dmCache = null;

  function esc(s){ return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function ts(t){ return t ? new Date(t).toLocaleString('vi-VN', { hour12: false, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : ''; }
  function phut(t){ return t ? Math.max(0, Math.round((Date.now() - new Date(t)) / 60000)) : 0; }
  function err(data, error){ return error ? error.message : (data && data.error) || 'không rõ'; }
  function capChip(cap){
    const c = CAP[cap]; if (!c) return '';
    return '<span class="kct-cap" style="color:' + c.mau + ';background:' + c.nen + ';border-color:' + c.mau + '">' + esc(c.ten) + '</span>';
  }

  function injectCss(){
    if (document.getElementById('kct-css')) return;
    const st = document.createElement('style');
    st.id = 'kct-css';
    st.textContent =
      '.kct{border:1.5px solid #B8C1CC;border-radius:8px;padding:10px 12px;background:#fff;font-size:12.5px;color:#0F172A}' +
      '.kct-h{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-weight:800;font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:#475569}' +
      '.kct-h .sp{flex:1}' +
      '.kct-cap{display:inline-block;border:1px solid;border-radius:6px;padding:1px 7px;font-size:11px;font-weight:800;text-transform:none;letter-spacing:0;white-space:nowrap}' +
      '.kct-st{display:inline-block;border-radius:6px;padding:2px 8px;font-size:11px;font-weight:800;text-transform:none;letter-spacing:0}' +
      '.kct-st.cho{background:#FEF3C7;color:#92400E}.kct-st.ok{background:#ECFDF5;color:#047857}.kct-st.no{background:#FEF2F2;color:#B91C1C}.kct-st.ktd{background:#EFF6FF;color:#1D4ED8}.kct-st.chua{background:#F1F5F9;color:#475569}' +
      '.kct-note{margin-top:6px;font-size:11.5px;color:#64748B}' +
      '.kct-warn{margin-top:6px;padding:6px 9px;border-radius:6px;background:#FEF2F2;color:#B91C1C;font-weight:700;font-size:12px}' +
      '.kct-okbox{margin-top:6px;padding:6px 9px;border-radius:6px;background:#ECFDF5;color:#047857;font-weight:600;font-size:12px}' +
      '.kct-grp{margin-top:8px;border-left:3px solid;border-radius:4px;padding:4px 8px}' +
      '.kct-grp-h{font-size:11px;font-weight:800;margin-bottom:2px}' +
      '.kct-it{display:flex;gap:7px;align-items:flex-start;padding:3px 0;cursor:pointer;line-height:1.35}' +
      '.kct-it input{margin-top:2px;flex:none;width:16px;height:16px}' +
      '.kct-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px}' +
      '.kct-row .sp{flex:1}' +
      '.kct input[type=text]{border:1.5px solid #B8C1CC;border-radius:6px;padding:6px 8px;font:inherit;font-size:12.5px;flex:1;min-width:180px}' +
      '.kct-b{border:1.5px solid #0F5FA5;background:#0F5FA5;color:#fff;border-radius:6px;padding:6px 12px;font:inherit;font-size:12.5px;font-weight:700;cursor:pointer;white-space:nowrap}' +
      '.kct-b.o{background:#fff;color:#0F5FA5}.kct-b.g{background:#047857;border-color:#047857}.kct-b.r{background:#fff;color:#B91C1C;border-color:#FCA5A5}' +
      '.kct-b:disabled{opacity:.45;cursor:default}' +
      '.kct-tinh{font-weight:800}' +
      '.kct-nk{margin-top:6px;font-size:11px;color:#64748B;display:none}.kct-nk.open{display:block}' +
      '.kct-nk div{padding:2px 0;border-top:1px dashed #E2E8F0}' +
      '.kct-lnk{border:none;background:none;color:#0F5FA5;font:inherit;font-size:11px;font-weight:700;cursor:pointer;padding:0;text-transform:none;letter-spacing:0}' +
      '.kct-q{display:flex;flex-direction:column;gap:6px}' +
      '.kct-qi{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;border:1px solid #D9DFE5;border-radius:8px;padding:8px 10px;background:#fff}' +
      '.kct-qi .m{font-weight:800;font-size:13px;white-space:nowrap}' +
      '.kct-qi .d{font-size:12px}.kct-qi .d small{display:block;color:#64748B;font-size:11px}' +
      '.kct-qi .a{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}' +
      '.kct-wait{font-weight:800;color:#B45309;white-space:nowrap}' +
      '.kct-empty{color:#047857;font-weight:600;font-size:12px;padding:4px 0}' +
      '.kct-ls{width:100%;border-collapse:collapse;font-size:12px}' +
      '.kct-ls th{background:#F5F7FA;text-align:left;font-size:11px;color:#64748B;padding:5px 6px;border-bottom:1px solid #D9DFE5;position:sticky;top:0}' +
      '.kct-ls td{padding:5px 6px;border-bottom:1px solid #EEF1F5;vertical-align:top}' +
      '.kct-mask{position:fixed;inset:0;background:rgba(15,23,42,.45);display:flex;align-items:flex-start;justify-content:center;z-index:9000;padding:24px 10px;overflow:auto}' +
      '.kct-dlg{background:#fff;border-radius:10px;max-width:720px;width:100%;box-shadow:0 12px 32px rgba(15,23,42,.25)}' +
      '.kct-dlg-h{display:flex;align-items:center;gap:8px;padding:10px 14px;border-bottom:1px solid #D9DFE5;font-weight:800;font-size:14px}' +
      '.kct-dlg-h .sp{flex:1}.kct-dlg-h button{border:none;background:none;font-size:18px;cursor:pointer;color:#64748B}' +
      '.kct-dlg-b{padding:12px 14px}' +
      '@media (max-width:700px){.kct-qi{grid-template-columns:1fr}.kct-qi .a{justify-content:flex-start}}';
    document.head.appendChild(st);
  }

  async function taiDanhMuc(){
    if (dmCache) return dmCache;
    const { data, error } = await sb.from('duc_khuon_ct_danh_muc').select('*').eq('hieu_luc', true).order('thu_tu');
    if (error) throw new Error('Lỗi tải danh mục cấp công việc: ' + error.message);
    dmCache = { cv: data.filter(d => d.loai === 'cong_viec'), at: data.filter(d => d.loai === 'an_toan') };
    return dmCache;
  }

  function trangThaiHtml(ct){
    if (!ct) return '<span class="kct-st chua">Chưa khai</span>';
    if (ct.trang_thai === 'khong_tac_dong') return '<span class="kct-st ktd">Không tác động khuôn</span>';
    if (ct.trang_thai === 'cho_duyet') return capChip(ct.cap) + ' <span class="kct-st cho">⏳ Chờ ' + esc(CAP[ct.cap].duyet) + ' duyệt · ' + phut(ct.de_nghi_luc) + ' ph</span>';
    if (ct.trang_thai === 'tu_choi') return capChip(ct.cap) + ' <span class="kct-st no">❌ Bị từ chối</span>';
    return capChip(ct.cap) + ' <span class="kct-st ok">✓ ' + (ct.cap === 0 ? 'Không cần duyệt' : 'Đã duyệt') + '</span>';
  }
  function jsonbLen(a){ return Array.isArray(a) ? a.length : 0; }

  const SU_KIEN = { khai: 'Khai hạng mục', duyet: '✅ Duyệt', tu_choi: '❌ Từ chối', an_toan: '🦺 Cam kết an toàn', qlbp_xac_nhan: '🌙 QLBP xác nhận duyệt ca đêm', khong_tac_dong: 'Không tác động khuôn' };
  function nkText(k){
    const d = k.du_lieu || {};
    let t = SU_KIEN[k.su_kien] || k.su_kien;
    if (k.su_kien === 'khai') t += ' — cấp ' + d.cap + ': ' + (d.hang_muc || []).map(h => h.noi_dung).join('; ') + (d.khong_chac ? ' (không chắc → nâng 1 cấp)' : '');
    if (d.vai_tro) t += ' (' + d.vai_tro + ')';
    if (d.ly_do) t += ': ' + d.ly_do;
    if (d.ghi_chu) t += ': ' + d.ghi_chu;
    return t;
  }

  // ── Khối khai / duyệt cho 1 phiếu ─────────────────────────────────────────
  function mount(el, opts){
    injectCss();
    let st = null, dm = null, busy = false;
    const o = Object.assign({ choPhepKhongTacDong: false, onChange: null }, opts);

    async function reload(){
      el.innerHTML = '<div class="kct"><div class="kct-note">Đang tải cấp công việc…</div></div>';
      try {
        dm = await taiDanhMuc();
        const { data, error } = await sb.rpc('duc_khuon_ct_lay', { p_nguon: o.nguon, p_nguon_id: String(o.nguonId) });
        if (error || !data || !data.ok) throw new Error(err(data, error));
        st = data;
      } catch (e) { el.innerHTML = '<div class="kct"><div class="kct-warn">' + esc(e.message) + '</div></div>'; return; }
      render();
    }

    function chon(){ return [...el.querySelectorAll('input[data-cv]:checked')].map(i => i.dataset.cv); }
    function capTinh(){
      const ds = chon(); if (!ds.length) return null;
      let c = Math.max(...ds.map(m => (dm.cv.find(d => d.ma === m) || {}).cap || 0));
      if (el.querySelector('#kct-kc') && el.querySelector('#kct-kc').checked) c = Math.min(3, c + 1);
      const ct = st && st.ct;   // T210b: phiếu không hạ cấp — giữ cấp cao nhất từng khai (trừ khi khai lại trong phạm vi đã duyệt)
      if (ct && ct.cap_max > c && !(ct.trang_thai === 'da_duyet' && ds.every(m => (ct.hang_muc_duyet || []).some(h => h.ma === m)))) c = ct.cap_max;
      return c;
    }
    function capNhatTinh(){
      const c = capTinh(), box = el.querySelector('.kct-tinh'), btn = el.querySelector('[data-a=gui]');
      if (!box) return;
      const ct = st && st.ct;
      box.innerHTML = c == null ? '<span style="color:#64748B">Chưa chọn hạng mục</span>' : capChip(c) + ' → ' + esc(CAP[c].duyet) +
        (ct && ct.cap_max === c && c > 0 && ct.trang_thai !== 'da_duyet' ? ' <span style="color:#64748B;font-weight:600">(giữ cấp cao nhất đã khai — không hạ cấp)</span>' : '');
      if (btn) { btn.disabled = c == null; btn.textContent = c === 0 ? '💾 Lưu (cấp 0 — làm ngay)' : '📤 Gửi duyệt'; }
    }

    function render(){
      const ct = st.ct, n = st.nguon || {};
      const xong = !!n.xong;
      const sua = st.duoc_khai && !xong;
      const daChon = new Set(ct ? (ct.hang_muc || []).map(h => h.ma) : []);
      let h = '<div class="kct"><div class="kct-h">🔧 Cấp công việc & phê duyệt <span class="sp"></span>' + trangThaiHtml(ct) + '</div>';
      if (!st.ap_dung) h += '<div class="kct-note">Sự cố phát sinh trước khi áp dụng quy định phân cấp — không bắt buộc khai.</div>';

      if (ct && ct.trang_thai === 'cho_duyet') {
        h += '<div class="kct-note">Đề nghị bởi <b>' + esc(ct.nguoi_de_nghi) + '</b> lúc ' + ts(ct.de_nghi_luc) + '. Chưa được bắt đầu xử lý, giao QC hay đóng sự cố tới khi duyệt.</div>';
        if (!st.quyen_duyet && st.ct.de_nghi_uid && !st.tu_duyet_duoc && st.duoc_khai)
          h += '<div class="kct-note">Người khai không tự duyệt việc của mình ngoài khung 22:00–08:00 — chuông đã gửi người duyệt.</div>';
        if (st.quyen_duyet) h += '<div class="kct-row"><span>Bạn duyệt với vai trò <b>' + esc(st.quyen_duyet) + '</b>:</span><span class="sp"></span>' +
          '<button type="button" class="kct-b g" data-a="duyet">✅ Duyệt</button><button type="button" class="kct-b r" data-a="tuchoi">❌ Từ chối</button></div>';
      }
      if (ct && ct.trang_thai === 'tu_choi') h += '<div class="kct-warn">❌ ' + esc(ct.nguoi_duyet) + ' từ chối lúc ' + ts(ct.duyet_luc) + ': ' + esc(ct.ly_do_tu_choi) + ' — chọn lại hạng mục rồi gửi duyệt lại.</div>';
      if (ct && ct.trang_thai === 'da_duyet' && ct.cap > 0) {
        h += '<div class="kct-okbox">✓ Duyệt bởi ' + esc(ct.nguoi_duyet) + ' (' + esc(ct.vai_tro_duyet) + ') lúc ' + ts(ct.duyet_luc) + '</div>';
        if (ct.duyet_thay_ca_dem) h += '<div class="kct-note">🌙 Trưởng ca duyệt thay ca đêm — ' + (ct.qlbp_xac_nhan ? 'QLBP Đúc ' + esc(ct.qlbp_xac_nhan) + ' đã xác nhận ' + ts(ct.qlbp_xac_nhan_luc) : 'chờ QLBP Đúc xác nhận') + '.</div>';
      }
      if (ct && ct.trang_thai === 'khong_tac_dong') h += '<div class="kct-note">Khai bởi <b>' + esc(ct.nguoi_de_nghi) + '</b> lúc ' + ts(ct.de_nghi_luc) + (ct.mo_ta ? ': ' + esc(ct.mo_ta) : '') + '.</div>';

      // Chọn hạng mục
      if (sua) {
        const moSan = !ct || ct.trang_thai === 'tu_choi' || ct.trang_thai === 'khong_tac_dong';
        h += '<div class="kct-sel"' + (moSan ? '' : ' style="display:none"') + '>' +
          [0, 1, 2, 3].map(c => '<div class="kct-grp" style="border-color:' + CAP[c].mau + ';background:' + CAP[c].nen + '">' +
            '<div class="kct-grp-h" style="color:' + CAP[c].mau + '">' + esc(CAP[c].ten) + ' — ' + esc(CAP[c].duyet) + '</div>' +
            dm.cv.filter(d => d.cap === c).map(d => '<label class="kct-it"><input type="checkbox" data-cv="' + esc(d.ma) + '"' + (daChon.has(d.ma) ? ' checked' : '') + '><span>' + esc(d.noi_dung) + '</span></label>').join('') +
            '</div>').join('') +
          '<label class="kct-it" style="margin-top:6px"><input type="checkbox" id="kct-kc"' + (ct && ct.khong_chac ? ' checked' : '') + '><span><b>Không chắc việc thuộc cấp nào</b> → hệ thống nâng lên 1 cấp (hỏi trước khi làm)</span></label>' +
          '<div class="kct-row"><input type="text" id="kct-mt" maxlength="300" placeholder="Mô tả thêm (vị trí, tình trạng…)" value="' + esc(ct ? ct.mo_ta : '') + '"></div>' +
          '<div class="kct-row"><span>Cấp tính được:</span><span class="kct-tinh"></span><span class="sp"></span>' +
            (o.choPhepKhongTacDong && st.duoc_khong_tac_dong && n.loai !== 'A2' && !ct ? '<button type="button" class="kct-b o" data-a="ktd" title="Chỉ chỉnh thông số / máy, không đụng vào khuôn">Không tác động vào khuôn</button>' : '') +
            '<button type="button" class="kct-b" data-a="gui">📤 Gửi duyệt</button></div></div>';
        if (!moSan) h += '<div class="kct-row"><span class="kct-note" style="margin:0">Hạng mục: ' + esc((ct.hang_muc || []).map(x => x.noi_dung).join('; ')) + '</span><span class="sp"></span>' +
          '<button type="button" class="kct-b o" data-a="sua">✎ Đổi hạng mục</button></div>';
      } else if (ct && jsonbLen(ct.hang_muc)) {
        h += '<div class="kct-note">Hạng mục: ' + esc(ct.hang_muc.map(x => x.noi_dung).join('; ')) + (ct.mo_ta ? ' — ' + esc(ct.mo_ta) : '') + '</div>';
      } else if (!ct && !st.duoc_khai) h += '<div class="kct-note">🔒 Tổ khuôn / QLBP Đúc / trưởng ca (sự cố) mới khai được.</div>';

      const nk = st.nhat_ky || [];
      if (nk.length) h += '<div style="margin-top:6px"><button type="button" class="kct-lnk" data-a="nk">📜 Lịch sử phiếu (' + nk.length + ')</button><div class="kct-nk">' +
        nk.map(k => '<div>' + ts(k.thoi_diem) + ' · <b>' + esc(k.nguoi) + '</b> — ' + esc(nkText(k)) + '</div>').join('') + '</div></div>';
      h += '</div>';
      el.innerHTML = h;
      el.querySelectorAll('input[data-cv], #kct-kc').forEach(i => i.addEventListener('change', capNhatTinh));
      el.querySelectorAll('[data-a]').forEach(b => b.addEventListener('click', () => act(b.dataset.a)));
      capNhatTinh();
    }

    async function goi(fn, args, okMsg){
      if (busy) return false;
      busy = true;
      el.querySelectorAll('.kct-b').forEach(b => { b.disabled = true; });
      const { data, error } = await sb.rpc(fn, args);
      busy = false;
      if (error || !data || !data.ok) { alert('⚠ ' + err(data, error)); render(); return false; }
      if (okMsg && window.showToast) window.showToast(okMsg);
      await reload();
      if (o.onChange) o.onChange(st);
      return true;
    }

    async function act(a){
      const ct = st.ct;
      if (a === 'nk') { el.querySelector('.kct-nk').classList.toggle('open'); return; }
      if (a === 'sua') { el.querySelector('.kct-sel').style.display = ''; el.querySelector('[data-a=sua]').parentElement.style.display = 'none'; return; }
      if (a === 'gui') {
        const ds = chon(), c = capTinh();
        if (!ds.length) return alert('Chọn ít nhất 1 hạng mục công việc');
        if (c >= 1 && !confirm('Công việc thuộc CẤP ' + c + ' — cần ' + CAP[c].duyet + ' duyệt trên MES trước khi làm.\n\nGửi duyệt?')) return;
        return goi('duc_khuon_ct_luu', { p_nguon: o.nguon, p_nguon_id: String(o.nguonId), p_hang_muc: ds,
          p_khong_chac: !!(el.querySelector('#kct-kc') || {}).checked, p_mo_ta: (el.querySelector('#kct-mt') || {}).value || '' });
      }
      if (a === 'ktd') {
        const g = prompt('Xác nhận lần xử lý này KHÔNG tác động vào khuôn (chỉ chỉnh thông số / máy).\nGhi rõ đã xử lý gì:');
        if (g == null) return;
        if (!g.trim()) return alert('Ghi rõ đã xử lý gì');
        return goi('duc_khuon_ct_khong_tac_dong', { p_id_su_co: String(o.nguonId), p_ghi_chu: g.trim() });
      }
      if (a === 'duyet') {
        if (!confirm('Duyệt công việc cấp ' + ct.cap + ' trên khuôn ' + (ct.ma_khuon || '') + '?\n\n' + (ct.hang_muc || []).map(x => '• ' + x.noi_dung).join('\n'))) return;
        return goi('duc_khuon_ct_duyet', { p_id: ct.id, p_dong_y: true, p_ly_do: '', p_cap_nhat_luc: ct.cap_nhat_luc }, '✓ Đã duyệt');
      }
      if (a === 'tuchoi') {
        const l = (prompt('Lý do từ chối (bắt buộc):') || '').trim();
        if (!l) return;
        return goi('duc_khuon_ct_duyet', { p_id: ct.id, p_dong_y: false, p_ly_do: l, p_cap_nhat_luc: ct.cap_nhat_luc }, '✓ Đã từ chối');
      }
      if (a === 'antoan') {
        const ma = [...el.querySelectorAll('input[data-at]:checked')].map(i => i.dataset.at);
        if (ma.length < dm.at.length) return alert('Tick đủ ' + dm.at.length + ' cam kết an toàn trước khi bắt đầu');
        return goi('duc_khuon_ct_an_toan', { p_id: ct.id, p_ma: ma }, '✓ Đã cam kết an toàn');
      }
    }

    reload();
    return { reload, state: () => st };
  }

  // ── Danh sách chờ duyệt (Dashboard tổ khuôn) ──────────────────────────────
  function queue(el, opts){
    injectCss();
    const o = Object.assign({ onChange: null, onCount: null }, opts);
    let rows = [];
    async function reload(){
      const { data, error } = await sb.rpc('duc_khuon_ct_cho_duyet');
      if (error || !data || !data.ok) { el.innerHTML = '<div class="kct-warn">Lỗi tải danh sách chờ duyệt: ' + esc(err(data, error)) + '</div>'; return; }
      rows = data.rows || [];
      if (o.onCount) o.onCount(rows.filter(r => r.trang_thai === 'cho_duyet').length, rows.length);
      if (!rows.length) { el.innerHTML = '<div class="kct-empty">✓ Không có công việc can thiệp khuôn nào chờ duyệt.</div>'; return; }
      el.innerHTML = '<div class="kct-q">' + rows.map(r => {
        const cho = r.trang_thai === 'cho_duyet';
        const nguon = r.nguon === 'xlbt' ? 'Sự cố ' + esc(r.loai_nguon || '') + ' ' + esc(r.nguon_id) : 'Check sheet · ' + esc(r.loai_nguon || 'KH bảo dưỡng');
        const a = cho
          ? (r.quyen_duyet ? '<button type="button" class="kct-b g" data-a="duyet" data-id="' + r.id + '">✅ Duyệt</button><button type="button" class="kct-b r" data-a="tuchoi" data-id="' + r.id + '">❌ Từ chối</button>'
                           : '<span class="kct-note" style="margin:0">Chờ ' + esc(CAP[r.cap].duyet) + '</span>')
          : (r.quyen_xac_nhan ? '<button type="button" class="kct-b" data-a="xn" data-id="' + r.id + '">🌙 Đã nắm — xác nhận</button>'
                              : '<span class="kct-note" style="margin:0">Chờ QLBP Đúc xác nhận</span>');
        return '<div class="kct-qi"><div><div class="m">' + esc(r.ma_khuon || '—') + '</div>' + capChip(r.cap) + '</div>' +
          '<div class="d"><b>' + esc((r.hang_muc || []).map(x => x.noi_dung).join('; ')) + '</b>' + (r.khong_chac ? ' <i>(không chắc → nâng cấp)</i>' : '') +
            (r.mo_ta ? '<small>' + esc(r.mo_ta) + '</small>' : '') +
            '<small>' + nguon + (r.ma_may ? ' · ' + esc(r.ma_may) : '') + ' · đề nghị: ' + esc(r.nguoi_de_nghi) + ' ' + ts(r.de_nghi_luc) +
            (cho ? ' · <span class="kct-wait">⏱ chờ ' + phut(r.de_nghi_luc) + ' ph</span>'
                 : ' · 🌙 trưởng ca <b>' + esc(r.nguoi_duyet) + '</b> duyệt thay lúc ' + ts(r.duyet_luc)) + '</small></div>' +
          '<div class="a">' + a + '</div></div>';
      }).join('') + '</div>';
      el.querySelectorAll('[data-a]').forEach(b => b.addEventListener('click', () => act(b.dataset.a, +b.dataset.id)));
    }
    async function act(a, id){
      const r = rows.find(x => x.id === id); if (!r) return;
      let fn, args;
      if (a === 'duyet') {
        if (!confirm('Duyệt công việc cấp ' + r.cap + ' trên khuôn ' + (r.ma_khuon || '') + '?\n\n' + (r.hang_muc || []).map(x => '• ' + x.noi_dung).join('\n'))) return;
        fn = 'duc_khuon_ct_duyet'; args = { p_id: id, p_dong_y: true, p_ly_do: '', p_cap_nhat_luc: r.cap_nhat_luc };
      } else if (a === 'tuchoi') {
        const l = (prompt('Lý do từ chối (bắt buộc):') || '').trim(); if (!l) return;
        fn = 'duc_khuon_ct_duyet'; args = { p_id: id, p_dong_y: false, p_ly_do: l, p_cap_nhat_luc: r.cap_nhat_luc };
      } else {
        fn = 'duc_khuon_ct_qlbp_xac_nhan'; args = { p_id: id, p_ghi_chu: '' };
      }
      el.querySelectorAll('.kct-b').forEach(b => { b.disabled = true; });
      const { data, error } = await sb.rpc(fn, args);
      if (error || !data || !data.ok) alert('⚠ ' + err(data, error));
      await reload();
      if (o.onChange) o.onChange();
    }
    reload();
    return { reload };
  }

  // ── Lịch sử can thiệp theo khuôn ─────────────────────────────────────────
  async function lichSu(el, opts){
    injectCss();
    const o = Object.assign({ maKhuon: null, tu: null }, opts);
    el.innerHTML = '<div class="kct-note">Đang tải lịch sử…</div>';
    const { data, error } = await sb.rpc('duc_khuon_ct_lich_su', { p_ma_khuon: o.maKhuon || null, p_tu: o.tu || null });
    if (error || !data || !data.ok) { el.innerHTML = '<div class="kct-warn">Lỗi: ' + esc(err(data, error)) + '</div>'; return []; }
    const rows = data.rows || [];
    if (!rows.length) { el.innerHTML = '<div class="kct-note">Chưa có lần can thiệp nào được ghi' + (o.maKhuon ? ' cho khuôn ' + esc(o.maKhuon) : '') + '.</div>'; return rows; }
    const TT = { cho_duyet: '<span class="kct-st cho">Chờ duyệt</span>', da_duyet: '<span class="kct-st ok">Đã duyệt</span>', tu_choi: '<span class="kct-st no">Từ chối</span>', khong_tac_dong: '<span class="kct-st ktd">Không tác động</span>' };
    el.innerHTML = '<table class="kct-ls"><thead><tr><th>Thời điểm</th><th>Khuôn / máy</th><th>Nguồn</th><th>Cấp · hạng mục</th><th>Đề nghị</th><th>Duyệt</th><th>Xử lý (ai làm, nội dung)</th><th>Kết quả</th></tr></thead><tbody>' +
      rows.map(r => {
        const x = r.xl || {};
        const kq = r.qc ? 'IPQC ' + esc(r.qc.ket_qua) + ' · ' + ts(r.qc.thoi_diem) : x.ket_luan ? (x.ket_luan === 'dat' ? '✓ Đạt' : '✗ Không đạt') : '—';
        return '<tr><td style="white-space:nowrap">' + ts(r.tao_luc) + '</td>' +
          '<td><b>' + esc(r.ma_khuon || '—') + '</b><div style="color:#64748B">' + esc(r.ma_may || '') + '</div></td>' +
          '<td>' + (r.nguon === 'xlbt' ? 'Sự cố ' + esc(r.nguon_id) : 'Check sheet' + (x.loai ? ' · ' + esc(x.loai) : '')) + '</td>' +
          '<td>' + (r.cap != null ? capChip(r.cap) + '<br>' : '') + esc((r.hang_muc || []).map(h => h.noi_dung).join('; ') || r.mo_ta || '') + '</td>' +
          '<td>' + esc(r.nguoi_de_nghi || '') + '<div style="color:#64748B">' + ts(r.de_nghi_luc) + '</div></td>' +
          '<td>' + (TT[r.trang_thai] || '') + (r.nguoi_duyet ? '<div>' + esc(r.nguoi_duyet) + '</div><div style="color:#64748B">' + esc(r.vai_tro_duyet || '') + ' · ' + ts(r.duyet_luc) + '</div>' : '') +
            (r.duyet_thay_ca_dem ? '<div style="color:#64748B">🌙 ' + (r.qlbp_xac_nhan ? 'QLBP ' + esc(r.qlbp_xac_nhan) + ' đã xác nhận' : 'chờ QLBP xác nhận') + '</div>' : '') + '</td>' +
          '<td>' + (x.nguoi ? '<b>' + esc(x.nguoi) + '</b> · ' : '') + (x.bat_dau ? ts(x.bat_dau) + ' → ' + ts(x.ket_thuc) : '') + '<div>' + esc(x.noi_dung || '') + '</div></td>' +
          '<td>' + kq + '</td></tr>';
      }).join('') + '</tbody></table>';
    return rows;
  }

  // ── Ô chọn hạng mục gọn (form thêm sự cố — T210f) ─────────────────────────
  //   const p = await KhuonCT.picker(el); p.giaTri() → { hang_muc:[], khong_chac, mo_ta, cap }
  async function picker(el){
    injectCss();
    const dm = await taiDanhMuc();
    el.innerHTML = [0, 1, 2, 3].map(c => '<div class="kct-grp" style="border-color:' + CAP[c].mau + ';background:' + CAP[c].nen + '">' +
        '<div class="kct-grp-h" style="color:' + CAP[c].mau + '">' + esc(CAP[c].ten) + ' — ' + esc(CAP[c].duyet) + '</div>' +
        dm.cv.filter(d => d.cap === c).map(d => '<label class="kct-it"><input type="checkbox" data-cv="' + esc(d.ma) + '"><span>' + esc(d.noi_dung) + '</span></label>').join('') +
      '</div>').join('') +
      '<label class="kct-it" style="margin-top:6px"><input type="checkbox" data-kc><span><b>Không chắc việc thuộc cấp nào</b> → nâng lên 1 cấp</span></label>' +
      '<div class="kct-row"><input type="text" data-mt maxlength="300" placeholder="Mô tả thêm (vị trí, tình trạng…)"></div>' +
      '<div class="kct-row" style="font-size:12px"><span>Cấp:</span><span class="kct-tinh"><span style="color:#64748B">Chưa chọn hạng mục</span></span></div>';
    const chon = () => [...el.querySelectorAll('input[data-cv]:checked')].map(i => i.dataset.cv);
    const cap = () => {
      const ds = chon(); if (!ds.length) return null;
      let c = Math.max(...ds.map(m => (dm.cv.find(d => d.ma === m) || {}).cap || 0));
      if (el.querySelector('input[data-kc]').checked) c = Math.min(3, c + 1);
      return c;
    };
    const ve = () => {
      const c = cap();
      el.querySelector('.kct-tinh').innerHTML = c == null ? '<span style="color:#64748B">Chưa chọn hạng mục</span>'
        : capChip(c) + ' → ' + esc(c === 0 ? 'làm ngay, không cần duyệt' : CAP[c].duyet + ' duyệt');
    };
    el.querySelectorAll('input[type=checkbox]').forEach(i => i.addEventListener('change', ve));
    return {
      giaTri: () => ({ hang_muc: chon(), khong_chac: el.querySelector('input[data-kc]').checked,
                       mo_ta: el.querySelector('input[data-mt]').value.trim(), cap: cap() }),
    };
  }

  // ── Hộp thoại (màn điều khiển đúc) ────────────────────────────────────────
  function modal(opts){
    injectCss();
    const mask = document.createElement('div');
    mask.className = 'kct-mask';
    mask.innerHTML = '<div class="kct-dlg"><div class="kct-dlg-h">' + esc(opts.tieuDe || 'Can thiệp khuôn') + '<span class="sp"></span><button type="button" aria-label="Đóng">✕</button></div><div class="kct-dlg-b"></div></div>';
    document.body.appendChild(mask);
    const close = () => { mask.remove(); if (opts.onClose) opts.onClose(); };
    mask.querySelector('.kct-dlg-h button').onclick = close;
    mask.addEventListener('click', e => { if (e.target === mask) close(); });
    return mount(mask.querySelector('.kct-dlg-b'), opts);
  }

  window.KhuonCT = { mount, queue, lichSu, modal, picker, CAP, capChip };
})();
