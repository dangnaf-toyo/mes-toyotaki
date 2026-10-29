/* T182: báo IPQC khi trưởng ca Đúc bấm "📦 Hoàn thành mẫu & giao QC" (bảng duc_su_co_giao_qc, T180).
 * Mỗi 15 giây hỏi lần giao mới → kêu chuông + rung + dải cảnh báo đầu trang + thông báo hệ thống của trình duyệt
 * (nếu đã bấm "🔔 Bật thông báo"). Cần: sb (supabase-client.js). Gọi IpqcBaoMau.start({ onMoi }) sau khi trang tải.
 */
const IpqcBaoMau = (() => {
  const POLL_MS = 15000;
  const KEY_BAT = 'ipqc_bao_mau_bat';
  // Chỉ báo lần giao SAU lúc mở trang (lần cũ đã hiện ở thẻ hàng đợi). Mốc lấy theo giờ máy chủ của lần giao
  // mới nhất (không dùng đồng hồ điện thoại — có thể lệch).
  let moc = null;
  let timer = null, busy = false, audio = null, onMoi = null;
  const daBao = new Set();

  const pad = n => String(n).padStart(2, '0');
  const hm = t => { const d = new Date(t); return pad(d.getHours()) + ':' + pad(d.getMinutes()); };
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function batRoi() { try { return localStorage.getItem(KEY_BAT) === '1'; } catch (e) { return false; } }

  // Chuông 3 tiếng bằng WebAudio (không cần file âm thanh). Trình duyệt chỉ cho phát sau 1 lần chạm/bấm trên trang.
  function keu() {
    try {
      audio = audio || new (window.AudioContext || window.webkitAudioContext)();
      if (audio.state === 'suspended') audio.resume();
      [0, 0.35, 0.7].forEach(t => {
        const o = audio.createOscillator(), g = audio.createGain();
        o.type = 'square'; o.frequency.value = 880;
        g.gain.setValueAtTime(0.25, audio.currentTime + t);
        g.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + t + 0.28);
        o.connect(g); g.connect(audio.destination);
        o.start(audio.currentTime + t); o.stop(audio.currentTime + t + 0.3);
      });
    } catch (e) { /* máy không hỗ trợ âm thanh — vẫn còn dải cảnh báo */ }
    try { if (navigator.vibrate) navigator.vibrate([300, 150, 300, 150, 300]); } catch (e) { /* bỏ qua */ }
  }

  function bannerEl() {
    let el = document.getElementById('ipqc-bao-mau');
    if (!el) {
      el = document.createElement('div');
      el.id = 'ipqc-bao-mau';
      el.className = 'bao-mau hidden';
      el.setAttribute('role', 'alert');
      const list = document.getElementById('queue-list');
      list.parentNode.insertBefore(el, list);
      el.addEventListener('click', e => { if (e.target.closest('[data-bm-tat]')) { el.classList.add('hidden'); el.innerHTML = ''; } });
    }
    return el;
  }
  function hienBanner(ds) {
    const el = bannerEl();
    const cu = el.classList.contains('hidden') ? '' : el.querySelector('.bm-ds').innerHTML;
    el.innerHTML = '<div class="bm-ti">📦 Sản xuất đã giao mẫu — mời IPQC đến máy kiểm ngay</div><div class="bm-ds">' +
      ds.map(g => '<div><b>' + esc(g.ma_may) + '</b> · giao lúc ' + hm(g.thoi_diem) + (g.nguoi ? ' · ' + esc(g.nguoi) : '') + '</div>').join('') + cu +
      '</div><button type="button" data-bm-tat>Đã nắm</button>';
    el.classList.remove('hidden');
  }

  function thongBaoHeThong(ds) {
    if (!batRoi() || !('Notification' in window) || Notification.permission !== 'granted') return;
    const noiDung = ds.map(g => g.ma_may + ' (' + hm(g.thoi_diem) + ')').join(', ');
    try {
      const n = new Notification('📦 Đã giao mẫu — đến máy kiểm IPQC', { body: noiDung, tag: 'ipqc-giao-mau', renotify: true, requireInteraction: true });
      n.onclick = () => { window.focus(); n.close(); };
    } catch (e) {
      // Android Chrome chỉ cho tạo thông báo qua service worker — đã có chuông + rung + dải cảnh báo thay thế.
    }
  }

  async function kiem() {
    if (busy) return;
    busy = true;
    try {
      if (moc === null) {
        const { data, error } = await sb.from('duc_su_co_giao_qc').select('thoi_diem').order('thoi_diem', { ascending: false }).limit(1);
        if (error) return;
        moc = (data && data[0] && data[0].thoi_diem) || '2000-01-01T00:00:00Z';
        return;
      }
      const { data, error } = await sb.from('duc_su_co_giao_qc').select('id,id_su_co,ma_may,thoi_diem,nguoi')
        .gt('thoi_diem', moc).order('thoi_diem');
      if (error || !data || !data.length) return;
      moc = data[data.length - 1].thoi_diem;
      const moi = data.filter(g => !daBao.has(g.id));
      if (!moi.length) return;
      moi.forEach(g => daBao.add(g.id));
      keu(); hienBanner(moi); thongBaoHeThong(moi);
      if (onMoi) onMoi(moi);
    } catch (e) { /* lỗi mạng — lần sau hỏi lại */ } finally { busy = false; }
  }

  // Nút "🔔 Bật thông báo": xin quyền thông báo hệ thống + mở khoá âm thanh (cần 1 lần bấm của người dùng).
  async function bat(btn) {
    try { localStorage.setItem(KEY_BAT, '1'); } catch (e) { /* bỏ qua */ }
    keu();
    if ('Notification' in window && Notification.permission === 'default') {
      try { await Notification.requestPermission(); } catch (e) { /* bỏ qua */ }
    }
    capNhatNut(btn);
  }
  function capNhatNut(btn) {
    if (!btn) return;
    const coQuyen = !('Notification' in window) || Notification.permission === 'granted';
    btn.textContent = batRoi() && coQuyen ? '🔔 Đang bật báo mẫu' : '🔔 Bật thông báo';
    btn.title = batRoi() ? 'Có mẫu sản xuất giao: kêu chuông, rung, hiện thông báo. Bấm để thử chuông.'
      : 'Bấm để bật chuông + thông báo khi sản xuất giao mẫu sau sự cố';
  }

  function start(opts) {
    onMoi = (opts && opts.onMoi) || null;
    const btn = document.getElementById('btn-bao-mau');
    if (btn) { capNhatNut(btn); btn.onclick = () => bat(btn); }
    // Trình duyệt chỉ phát âm thanh sau lần chạm đầu tiên — mở khoá sẵn để khi có mẫu thì kêu được.
    document.addEventListener('pointerdown', () => {
      try { audio = audio || new (window.AudioContext || window.webkitAudioContext)(); if (audio.state === 'suspended') audio.resume(); } catch (e) { /* bỏ qua */ }
    }, { once: true });
    if (timer) clearInterval(timer);
    timer = setInterval(kiem, POLL_MS);
    kiem();   // lấy mốc ngay
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') kiem(); });
  }

  return { start, kiem };
})();
