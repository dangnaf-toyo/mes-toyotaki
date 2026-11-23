/**
 * dk-xac-nhan.js — T324 (Điều kiện đúc Bước 8): trưởng ca lên khuôn / bắt đầu SX mã SP trên máy
 * có phiếu ĐK đúc Hiệu lực → xác nhận dụng cụ + thông số ★ đang cài trên máy.
 * Dùng ở duc-dashboard.html + mobile.html, nhúng sau supabase-client.js.
 *
 *   if (!(await DkXacNhan.damBao(maMay, maSp))) return;   // sau KhuonNamVanDe.damBao (T127)
 *
 * Chưa có phiếu / SP chạy tiếp trên máy / đã xác nhận còn hạn (12h) → true ngay.
 * Server (trigger trg_duc_ca_hien_tai_dk_xac_nhan) vẫn chặn nếu bỏ qua bước này.
 */
(function () {
  if (window.DkXacNhan) return;
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const so = v => { const t = String(v ?? '').trim().replace(',', '.'); return /^-?\d+(\.\d+)?$/.test(t) ? Number(t) : null; };
  const fmt = n => (Math.round(n * 1000) / 1000).toLocaleString('vi-VN');
  const NHOM = { VL: 'Vật liệu', PE: 'Ép', NT: 'Nhiệt', PT: 'Phụ trợ' };
  const LOAI = { DT: 'Đầu típ', OL: 'Ống liệu', PK: 'Piston', XM: 'Xi lanh', CN: 'Cổ ngỗng', VP: 'Vòi phun' };

  function css() {
    if (document.getElementById('dkxn-css')) return;
    const st = document.createElement('style'); st.id = 'dkxn-css';
    st.textContent =
      '.dkxn-mask{position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:100001;display:flex;align-items:center;justify-content:center;padding:10px}' +
      '.dkxn{background:#fff;border-radius:12px;width:min(640px,100%);max-height:94vh;display:flex;flex-direction:column;box-shadow:0 12px 32px rgba(15,23,42,.3);color:#0F172A;font-family:inherit}' +
      '.dkxn-h{padding:10px 14px;border-bottom:1px solid #E2E8F0;background:#EFF6FF;border-radius:12px 12px 0 0;font-weight:700;font-size:15px;color:#1D4ED8}' +
      '.dkxn-h small{display:block;font-weight:500;font-size:12px;color:#334155;margin-top:2px}' +
      '.dkxn-h a{color:#1D4ED8;font-size:12px;font-weight:600;margin-left:6px}' +
      '.dkxn-b{padding:8px 14px;overflow:auto;display:flex;flex-direction:column;gap:6px}' +
      '.dkxn-g{font-size:11px;font-weight:700;color:#64748B;text-transform:uppercase;margin-top:6px}' +
      '.dkxn-r{display:grid;grid-template-columns:minmax(0,1fr) 108px;gap:8px;align-items:center;border:1px solid #E2E8F0;border-radius:8px;padding:6px 8px;font-size:13px}' +
      '.dkxn-r .t{font-weight:600}.dkxn-r .m{font-size:11px;color:#64748B;margin-top:1px}' +
      '.dkxn-r input[type=text],.dkxn-r select{width:100%;box-sizing:border-box;font:inherit;font-size:14px;padding:6px 7px;border:1.5px solid #B8C1CC;border-radius:6px;text-align:right}' +
      '.dkxn-r select{text-align:left;font-size:12px}' +
      '.dkxn-r label{display:flex;gap:6px;align-items:center;justify-content:flex-end;font-weight:700;cursor:pointer}' +
      '.dkxn-r label input{width:20px;height:20px}' +
      '.dkxn-r.dat{border-color:#6EE7B7;background:#ECFDF5}.dkxn-r.dat input[type=text],.dkxn-r.dat select{border-color:#10B981}' +
      '.dkxn-r.lech{border-color:#FCA5A5;background:#FEF2F2}.dkxn-r.lech input[type=text],.dkxn-r.lech select{border-color:#EF4444}' +
      '.dkxn-r .ms{font-size:11px;font-weight:700;color:#B91C1C;margin-top:2px}.dkxn-r.dat .ms{color:#047857}' +
      '.dkxn-f{padding:8px 14px;border-top:1px solid #E2E8F0;display:flex;flex-direction:column;gap:6px}' +
      '.dkxn-f .nh{font-size:12px;color:#B91C1C;font-weight:600}' +
      '.dkxn-f .act{display:flex;gap:8px;justify-content:flex-end}' +
      '.dkxn-f button{border:none;border-radius:6px;padding:9px 14px;font:inherit;font-size:13px;font-weight:700;cursor:pointer}' +
      '.dkxn-f .huy{background:#fff;border:1.5px solid #B8C1CC;color:#0F172A}' +
      '.dkxn-f .ok{background:#047857;color:#fff}.dkxn-f .ok:disabled{opacity:.45;cursor:not-allowed}';
    document.head.appendChild(st);
  }

  function hop(d) {
    css();
    const p = d.phieu, ts = d.thong_so || [], dc = d.dung_cu || [];
    let html = '';
    if (dc.length) {
      html += '<div class="dkxn-g">Dụng cụ đang lắp</div>';
      dc.forEach(x => {
        html += '<div class="dkxn-r" data-dc="' + esc(x.loai) + '" data-can="' + esc(x.ma) + '" data-dang="' + esc(x.dang || '') + '"><div><div class="t">' + esc(LOAI[x.loai] || x.loai) + '</div>' +
          '<div class="m">Phiếu: ' + esc(x.ma) + (x.dang ? ' · đang lắp ' + esc(x.dang) : '') + '</div><div class="ms"></div></div>' +
          '<select><option value="">— chọn —</option>' + (x.chon || []).map(o => '<option value="' + esc(o.ma) + '"' + (o.ma === x.dang ? ' selected' : '') + '>' + esc(o.ma) +
            (o.pct != null ? ' · ' + o.pct + '%' : '') + (o.may && o.may !== p.ma_may ? ' · ở ' + esc(o.may) : o.may ? ' · đang lắp' : '') + '</option>').join('') + '</select></div>';
      });
    }
    let nhom = '';
    ts.forEach(t => {
      if (t.nhom !== nhom) { nhom = t.nhom; html += '<div class="dkxn-g">' + esc(NHOM[nhom] || nhom) + '</div>'; }
      if (t.kieu === 'so') {
        const c = Number(t.chuan), b = Math.abs(c) * Number(t.nguong ?? 5) / 100;
        const td = (t.td || []).map(x => fmt(Number(x.gia_tri)));
        html += '<div class="dkxn-r" data-ts="' + esc(t.ma_ts) + '" data-k="so"><div><div class="t">' + esc(t.ten) + '</div>' +
          '<div class="m">Chuẩn ' + fmt(c) + (t.don_vi ? ' ' + esc(t.don_vi) : '') + ' · cho phép ' + fmt(c - b) + ' – ' + fmt(c + b) +
          (td.length ? ' · thay đổi đã duyệt: ' + td.join(', ') : '') + '</div><div class="ms"></div></div>' +
          '<input type="text" inputmode="decimal" placeholder="Đang cài"></div>';
      } else {
        const chu = t.kieu === 'co_khong' ? (t.chu === 'co' ? 'Có' : t.chu === 'khong' ? 'Không' : t.chu) : t.chu;
        html += '<div class="dkxn-r" data-ts="' + esc(t.ma_ts) + '" data-k="chu"><div><div class="t">' + esc(t.ten) + '</div>' +
          '<div class="m">Phiếu: ' + esc(chu) + '</div><div class="ms"></div></div>' +
          '<label><input type="checkbox"> Đúng</label></div>';
      }
    });
    if (!html) html = '<div style="font-size:13px;color:#64748B">Phiếu không có thông số bắt buộc ★ — bấm Xác nhận để lên khuôn.</div>';

    const mask = document.createElement('div'); mask.className = 'dkxn-mask';
    mask.innerHTML = '<div class="dkxn" role="dialog" aria-modal="true">' +
      '<div class="dkxn-h">📋 Xác nhận ĐK đúc <small>' + esc(p.ma_may) + ' · ' + esc(p.ma_sp) + ' · lần ' + esc(p.lan) +
      '<a href="dieu-kien-duc.html?id=' + encodeURIComponent(p.id) + '" target="_blank" rel="noopener">Xem phiếu</a></small></div>' +
      '<div class="dkxn-b">' + html + '</div>' +
      '<div class="dkxn-f"><div class="nh"></div><div class="act"><button type="button" class="huy">Huỷ</button>' +
      '<button type="button" class="ok" disabled>✓ Xác nhận</button></div></div></div>';
    document.body.appendChild(mask);

    const btn = mask.querySelector('.ok'), nh = mask.querySelector('.nh');
    function kiem() {
      let du = true, lech = 0;
      mask.querySelectorAll('.dkxn-r').forEach(r => {
        const ms = r.querySelector('.ms'); r.classList.remove('dat', 'lech'); ms.textContent = '';
        if (r.dataset.dc) {
          const v = r.querySelector('select').value;
          if (!v) { du = false; return; }
          if (v.split('/')[0] === r.dataset.can) { r.classList.add('dat'); if (v.includes('/') && v !== r.dataset.dang) ms.textContent = 'Sẽ lắp ' + v + (r.dataset.dang ? ', tháo ' + r.dataset.dang : ''); }
          else { r.classList.add('lech'); ms.textContent = 'Khác phiếu (' + r.dataset.can + ')'; du = false; lech++; }
        } else if (r.dataset.k === 'so') {
          const t = ts.find(x => x.ma_ts === r.dataset.ts), v = so(r.querySelector('input').value);
          if (v === null) { du = false; return; }
          const ng = Number(t.nguong ?? 5) / 100, trong = c => Math.abs(v - c) <= Math.abs(c) * ng + 1e-9;
          const c = Number(t.chuan);
          if (trong(c)) r.classList.add('dat');
          else if ((t.td || []).some(x => trong(Number(x.gia_tri)))) { r.classList.add('dat'); ms.textContent = 'Theo thay đổi đã duyệt'; }
          else { r.classList.add('lech'); ms.textContent = 'Ngoài khoảng — chỉnh máy'; du = false; lech++; }
        } else {
          if (r.querySelector('input').checked) r.classList.add('dat'); else du = false;
        }
      });
      btn.disabled = !du;
      nh.textContent = lech ? lech + ' mục lệch phiếu. Chỉnh máy về khoảng cho phép; cần đổi chuẩn → báo Kỹ thuật.' : '';
    }
    mask.addEventListener('input', kiem); mask.addEventListener('change', kiem);

    return new Promise(resolve => {
      const dong = v => { mask.remove(); resolve(v); };
      mask.querySelector('.huy').onclick = () => dong(false);
      btn.onclick = async () => {
        const gt = {}, dcv = {};
        mask.querySelectorAll('.dkxn-r').forEach(r => {
          if (r.dataset.dc) dcv[r.dataset.dc] = r.querySelector('select').value;
          else if (r.dataset.k === 'so') gt[r.dataset.ts] = r.querySelector('input').value.trim();
          else gt[r.dataset.ts] = r.querySelector('input').checked ? 'dung' : '';
        });
        btn.disabled = true; btn.textContent = 'Đang lưu…';
        const { data, error } = await sb.rpc('duc_dk_xac_nhan_luu', { p_ma_may: p.ma_may, p_ma_sp: p.ma_sp, p_gia_tri: gt, p_dung_cu: dcv });
        if (error || !data || !data.ok) {
          nh.textContent = (error && error.message) || (data && data.error) || 'Lưu không được';
          btn.disabled = false; btn.textContent = '✓ Xác nhận';
          return;
        }
        dong(true);
      };
      kiem();
      const first = mask.querySelector('select, input'); if (first) first.focus();
    });
  }

  async function damBao(maMay, maSp) {
    if (!maMay || !maSp) return true;
    const { data, error } = await sb.rpc('duc_dk_len_khuon', { p_ma_may: maMay, p_ma_sp: String(maSp).trim().toUpperCase() });
    if (error || !data || !data.ok) return true;   // lỗi đọc: để trigger DB quyết định
    if (!data.co_phieu || !data.bat || data.chay_tiep || data.da_xac_nhan) return true;
    return hop(data);
  }

  window.DkXacNhan = { damBao };
})();
