/**
 * ============================================================================
 * bavia-ng-tem.js — T235: Chất lượng › Biểu đồ chất lượng › tab "NG theo tem Đúc"
 *   BaviaNgTem.mount(el) → Promise<{ taiLai() }>
 * Xu hướng NG Bavia theo TỪNG TEM ĐÚC (TKD…): mỗi điểm = 1 tem Đúc đã qua Bavia,
 *   % NG = NG khai trên tem ÷ (OK đóng thùng lấy từ tem + NG).
 * Trục ngang: giờ đúc (Đúc ghi nhận tem, không có thì giờ in) hoặc shot khuôn từ lần
 *   bảo dưỡng gần nhất (đồng hồ shot, phân bổ theo sản lượng tem — xem migration).
 * Vạch sự kiện khuôn: A2 sự cố khuôn · C3 đổi khuôn · F1 IPQC NG · BD bảo dưỡng.
 * Mặc định chỉ hiện tem xử lý ở ngày Bavia CÓ khai NG (quy tắc T233); bật
 *   "Hiện cả ngày chưa khai NG" để xem hết.
 * Dữ liệu: RPC bavia_ng_theo_tem(p_tu, p_den) (supabase/migration_phase_T235_bavia_ng_theo_tem.sql);
 *   mục tiêu: bavia_ng_cau_hinh (muc_tieu theo mã, '*' = chung, mặc định 2%).
 * ============================================================================
 */
(function () {
  const BLUE = '#1F5FBF', RED = '#B42318', GRAY = '#9AA3B0', INK = '#14181F';
  const SK = {
    A2: { c: '#B42318', l: 'Sự cố khuôn', d: '' },
    C3: { c: '#1B7F5A', l: 'Đổi khuôn', d: '' },
    F1: { c: '#C2410C', l: 'IPQC NG', d: '' },
    BD: { c: '#14181F', l: 'Bảo dưỡng', d: '4 3' },
  };
  const SHOT_BUCKET = [[0, 2000], [2000, 5000], [5000, 10000], [10000, 15000], [15000, 20000], [20000, Infinity]];
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fp = (x, d) => (x == null || !isFinite(x)) ? '—' : (x * 100).toFixed(d == null ? 2 : d).replace('.', ',') + '%';
  const fn = n => n == null ? '—' : Math.round(Number(n) || 0).toLocaleString('vi-VN');
  const pad = n => String(n).padStart(2, '0');
  const ymd = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const addDays = (s, k) => { const d = new Date(s + 'T00:00:00'); d.setDate(d.getDate() + k); return ymd(d); };
  // Giờ Việt Nam = UTC+7 cố định: cộng 7h rồi đọc theo UTC → "dd/MM HH:mm"
  const vn = iso => new Date(new Date(iso).getTime() + 7 * 3600e3);
  const fd = iso => { const d = vn(iso); return pad(d.getUTCDate()) + '/' + pad(d.getUTCMonth() + 1); };
  const fdt = iso => { if (!iso) return '—'; const d = vn(iso); return fd(iso) + ' ' + pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()); };
  const PRESETS = [
    { k: 'd7', l: '7 ngày', n: 7 }, { k: 'd16', l: '16 ngày', n: 16 }, { k: 'd28', l: '4 tuần', n: 28 }, { k: 'd91', l: '3 tháng', n: 91 },
  ];
  const loiChinh = m => { const e = Object.entries(m || {}).sort((a, b) => b[1] - a[1]); return e.length ? e[0][0] : ''; };
  const loaiTxt = m => Object.entries(m || {}).sort((a, b) => b[1] - a[1]).map(([k, v]) => k + ' ' + fn(v)).join(', ');

  function css() {
    if (document.getElementById('bnt-css')) return;
    const st = document.createElement('style'); st.id = 'bnt-css';
    st.textContent =
      '.bnt{display:flex;flex-direction:column;gap:10px;font-size:12px;color:#14181F}' +
      '.bnt .bx{background:#fff;border:1px solid #DDE2EA;border-radius:8px;padding:10px 14px;min-width:0}' +
      '.bnt .bar{display:flex;flex-wrap:wrap;align-items:center;gap:8px}' +
      '.bnt .bar label{display:inline-flex;align-items:center;gap:6px;font-weight:600;color:#5B6472}' +
      '.bnt input,.bnt select{font:inherit;font-size:13px;padding:6px 8px;border:1px solid #C9D0DA;border-radius:6px;background:#fff;min-height:34px;box-sizing:border-box}' +
      '.bnt input[type=checkbox]{min-height:0;width:16px;height:16px}' +
      '.bnt .btn{font:inherit;font-size:12.5px;font-weight:600;padding:6px 12px;min-height:34px;border-radius:6px;border:1px solid #C9D0DA;background:#fff;color:#14181F;cursor:pointer;white-space:nowrap}' +
      '.bnt .btn.on{background:#14181F;border-color:#14181F;color:#fff}.bnt .btn.sm{min-height:28px;padding:3px 9px;font-size:12px}' +
      '.bnt .seg{display:inline-flex}.bnt .seg .btn{border-radius:0}.bnt .seg .btn:first-child{border-radius:6px 0 0 6px}.bnt .seg .btn:last-child{border-radius:0 6px 6px 0;border-left:0}' +
      '.bnt h3{margin:0;font-size:13px;font-weight:700}' +
      '.bnt .mono{font-family:"JetBrains Mono",ui-monospace,monospace}.bnt .mut{color:#5B6472}' +
      '.bnt .row{display:flex;flex-wrap:wrap;gap:10px}.bnt .row>.bx{flex:1 1 320px}' +
      '.bnt .row>.bx.kpi{flex:1 1 140px;padding:8px 12px}.bnt .kpi .v{font-size:20px;font-weight:700;font-family:"JetBrains Mono",ui-monospace,monospace}.bnt .kpi .l{color:#5B6472;font-weight:600}' +
      '.bnt .lg{display:inline-flex;align-items:center;gap:5px;color:#3A4250}' +
      '.bnt .dot{width:10px;height:10px;border-radius:99px;display:inline-block;box-sizing:border-box}' +
      '.bnt svg text{font-family:Inter,Arial,sans-serif}' +
      '.bnt svg circle{cursor:pointer}' +
      '.bnt table{border-collapse:collapse;width:100%}.bnt th,.bnt td{padding:5px 8px;text-align:left;border-top:1px solid #EEF1F5;white-space:nowrap}' +
      '.bnt th{background:#F6F8FA;color:#3A4250;font-weight:600;border-top:0}.bnt td.r,.bnt th.r{text-align:right}' +
      '.bnt tr.out td.p{color:#B42318;font-weight:700}.bnt tr.sel td{background:#EFF6FF}' +
      '.bnt .tw{overflow-x:auto}' +
      '.bnt .msg{font-weight:600;padding:8px 10px;border-radius:6px}.bnt .msg.err{background:#FEF2F2;color:#B42318}.bnt .msg.info{background:#EFF6FF;color:#1F5FBF}' +
      '.bnt .note{color:#5B6472;font-size:11.5px;line-height:1.5}';
    document.head.appendChild(st);
  }

  async function mount(el) {
    css();
    const today = ymd(new Date());
    const st = { start: addDays(today, -15), end: today, sp: '', khuon: '', may: '', x: 'tg', tatCa: false, suKien: true,
      data: { tem: [], su_kien: [], ngay_co_ng: [] }, cfg: {}, sel: null, err: null, loading: false };
    el.innerHTML =
      '<div class="bnt">' +
      '<div class="bar">' +
      '<label>Từ ngày <input type="date" data-k="start" value="' + st.start + '" max="' + today + '"></label>' +
      '<label>Đến ngày <input type="date" data-k="end" value="' + st.end + '" max="' + today + '"></label>' +
      '<span style="display:inline-flex;flex-wrap:wrap;gap:4px">' +
      PRESETS.map(p => '<button type="button" class="btn sm' + (p.k === 'd16' ? ' on' : '') + '" data-act="preset" data-n="' + p.n + '">' + p.l + '</button>').join('') +
      '</span>' +
      '<label>Mã SP <select data-k="sp"></select></label>' +
      '<label>Khuôn <select data-k="khuon"></select></label>' +
      '<label>Máy <select data-k="may"></select></label>' +
      '</div>' +
      '<div class="bar">' +
      '<span class="seg"><button type="button" class="btn sm on" data-act="x" data-x="tg">Theo giờ đúc</button><button type="button" class="btn sm" data-act="x" data-x="shot">Theo shot từ bảo dưỡng</button></span>' +
      '<label style="font-weight:500"><input type="checkbox" data-k="suKien" checked> Vạch sự kiện khuôn</label>' +
      '<label style="font-weight:500"><input type="checkbox" data-k="tatCa"> Hiện cả ngày chưa khai NG</label>' +
      '<span style="flex:1"></span><span class="mut" data-o="sum"></span>' +
      '</div>' +
      '<div data-o="msg"></div>' +
      '<div class="row" data-o="kpi"></div>' +
      '<div class="bx">' +
      '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 14px;margin-bottom:6px">' +
      '<h3 style="margin-right:auto" data-o="ctitle">% NG Bavia từng tem Đúc</h3>' +
      '<span class="lg"><span class="dot" style="background:' + BLUE + '"></span>Dưới mục tiêu</span>' +
      '<span class="lg"><span class="dot" style="background:' + RED + '"></span>Từ mục tiêu trở lên</span>' +
      '<span class="lg"><span class="dot" style="background:#fff;border:1.5px solid ' + GRAY + '"></span>0 NG</span>' +
      '<span class="lg"><span style="width:16px;border-top:2px solid ' + INK + '"></span>TB trượt 5 tem</span>' +
      '<span class="lg"><span style="width:16px;border-top:2px dashed ' + RED + '"></span>Mục tiêu</span>' +
      '<span data-o="sklg" style="display:inline-flex;gap:10px"></span>' +
      '</div>' +
      '<div data-o="chart" style="width:100%"></div>' +
      '<div class="note">Điểm to = tem nhiều sản phẩm qua Bavia. Bấm vào điểm để xem tem đó trong bảng chi tiết.</div>' +
      '</div>' +
      '<div class="row" data-o="groups"></div>' +
      '<div class="bx"><h3 style="margin-bottom:6px">Chi tiết từng tem Đúc</h3><div class="tw" data-o="detail"></div></div>' +
      '<div class="note">% NG = NG Bavia khai trên tem ÷ (OK đóng thùng lấy từ tem + NG). NG chờ sửa không tính vào % NG. ' +
      'Giờ đúc = lúc Đúc ghi nhận tem (không có thì giờ in tem). Shot từ bảo dưỡng = đồng hồ shot khuôn tại giờ đúc trừ shot lúc bảo dưỡng gần nhất; ' +
      'giữa 2 mốc đồng hồ (lần bảo dưỡng, kết ca) phân bổ theo sản lượng tem — số có dấu ~ là ước tính sau mốc đồng hồ cuối. ' +
      'Ngày Bavia chưa khai NG nào thì mặc định không hiện (tránh 0% giả).</div>' +
      '</div>';
    const $ = k => el.querySelector('[data-o="' + k + '"]');
    const inp = k => el.querySelector('[data-k="' + k + '"]');

    async function loadCfg() {
      try {
        const { data } = await sb.from('bavia_ng_cau_hinh').select('ma_sp,muc_tieu');
        st.cfg = {}; (data || []).forEach(r => { st.cfg[r.ma_sp] = r.muc_tieu == null ? null : Number(r.muc_tieu); });
      } catch (e) { st.cfg = {}; }
    }
    const mtChung = () => st.cfg['*'] != null ? st.cfg['*'] : 0.02;
    const mtSp = sp => st.cfg[sp] != null ? st.cfg[sp] : mtChung();

    async function load() {
      st.loading = true; st.err = null; $('msg').innerHTML = '<div class="msg info">Đang tải…</div>';
      try {
        const { data, error } = await sb.rpc('bavia_ng_theo_tem', { p_tu: st.start, p_den: st.end });
        if (error) throw error;
        st.data = data || { tem: [], su_kien: [], ngay_co_ng: [] };
      } catch (e) {
        st.err = (e && e.message) || String(e); st.data = { tem: [], su_kien: [], ngay_co_ng: [] };
      }
      st.loading = false;
      fillSelects(); render();
    }

    function fillSelects() {
      const all = st.data.tem || [];
      const opt = (k, label) => {
        const vals = [...new Set(all.map(t => t[k]).filter(Boolean))].sort();
        const cur = st[k === 'sp' ? 'sp' : k];
        if (cur && !vals.includes(cur)) vals.unshift(cur);
        inp(k === 'sp' ? 'sp' : k).innerHTML = '<option value="">' + label + '</option>' + vals.map(v => '<option' + (v === cur ? ' selected' : '') + '>' + esc(v) + '</option>').join('');
      };
      opt('sp', 'Tất cả'); opt('khuon', 'Tất cả'); opt('may', 'Tất cả');
    }

    function rows() {
      const ngayNg = new Set(st.data.ngay_co_ng || []);
      return (st.data.tem || []).map(t => {
        const ok = Number(t.ok) || 0, ng = Number(t.ng) || 0, n = ok + ng;
        return Object.assign({}, t, { okN: ok, ngN: ng, n, p: n > 0 ? ng / n : null, mt: mtSp(t.sp), ms: t.tg ? new Date(t.tg).getTime() : null, shotN: t.shot == null ? null : Number(t.shot) });
      }).filter(t => (st.tatCa || t.ngN > 0 || (t.d && ngayNg.has(t.d)))
        && (!st.sp || t.sp === st.sp) && (!st.khuon || t.khuon === st.khuon) && (!st.may || t.may === st.may));
    }

    function render() {
      const all = st.data.tem || [];
      const R = rows();
      const pts = R.filter(t => t.n > 0);
      const an = all.length - R.length;
      $('sum').textContent = all.length ? (R.length + ' tem hiển thị' + (an > 0 ? ' · ẩn ' + an + ' tem' : '')) : '';
      if (st.err) $('msg').innerHTML = '<div class="msg err">Lỗi: ' + esc(st.err) + '</div>';
      else if (!all.length) $('msg').innerHTML = '<div class="msg info">Không có tem Đúc nào qua Bavia trong khoảng ngày này.</div>';
      else if (!R.length && !st.tatCa) $('msg').innerHTML = '<div class="msg info">Trong khoảng ngày này Bavia chưa khai NG trên MES — ' + all.length + ' tem Đúc chỉ có số OK. Tick "Hiện cả ngày chưa khai NG" để xem.</div>';
      else $('msg').innerHTML = '';

      // KPI
      const sN = pts.reduce((s, t) => s + t.n, 0), sNg = pts.reduce((s, t) => s + t.ngN, 0);
      const sSua = R.reduce((s, t) => s + (Number(t.sua) || 0), 0);
      const vuot = pts.filter(t => t.p >= t.mt && t.ngN > 0).length, coNg = pts.filter(t => t.ngN > 0).length;
      const k = (l, v, sub) => '<div class="bx kpi"><div class="l">' + l + '</div><div class="v">' + v + '</div>' + (sub ? '<div class="mut">' + sub + '</div>' : '') + '</div>';
      $('kpi').innerHTML = k('Tem Đúc', fn(R.length), coNg + ' tem có NG') + k('SL qua Bavia', fn(sN), 'OK + NG') + k('NG Bavia', fn(sNg), 'NG chờ sửa ' + fn(sSua)) +
        k('% NG', fp(sN ? sNg / sN : null), 'Mục tiêu ' + fp(st.sp ? mtSp(st.sp) : mtChung(), 1) + (st.sp ? '' : ' (chung)')) + k('Tem ≥ mục tiêu', fn(vuot), pts.length ? fp(vuot / pts.length, 0) + ' số tem' : '');

      drawChart(pts);
      renderGroups(pts);
      renderDetail(R);
    }

    // ---------- biểu đồ ----------
    function niceStep(range, n) {
      const raw = range / n, p = Math.pow(10, Math.floor(Math.log10(raw))), m = raw / p;
      return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p;
    }
    function drawChart(pts) {
      const box = $('chart');
      const W = Math.max(320, box.clientWidth || 800), H = 300, ml = 46, mr = 14, mt = 22, mb = 30;
      const iw = W - ml - mr, ih = H - mt - mb;
      const isShot = st.x === 'shot';
      $('ctitle').textContent = '% NG Bavia từng tem Đúc — ' + (isShot ? 'theo shot khuôn từ lần bảo dưỡng' : 'theo giờ đúc');
      const P = pts.filter(t => isShot ? t.shotN != null : t.ms != null).slice().sort((a, b) => isShot ? a.shotN - b.shotN : a.ms - b.ms);
      const motMa = st.sp || ([...new Set(P.map(t => t.sp))].length === 1 && P.length ? P[0].sp : '');
      const mtLine = motMa ? mtSp(motMa) : mtChung();
      if (!P.length) { box.innerHTML = '<div class="mut" style="padding:30px 0;text-align:center">' + (isShot && pts.length ? 'Các tem đang lọc chưa có mốc bảo dưỡng khuôn để tính shot.' : 'Không có điểm để vẽ.') + '</div>'; $('sklg').innerHTML = ''; return; }
      let x0, x1;
      if (isShot) { x0 = 0; x1 = Math.max(...P.map(t => t.shotN)) * 1.05 || 1000; }
      else { x0 = P[0].ms; x1 = P[P.length - 1].ms; const padx = Math.max((x1 - x0) * 0.03, 3600e3); x0 -= padx; x1 += padx; }
      const yMax = Math.max(mtLine * 1.4, ...P.map(t => t.p * 1.15), 0.01);
      const ystep = niceStep(yMax, 5), y1 = Math.ceil(yMax / ystep) * ystep;
      const X = v => ml + (v - x0) / (x1 - x0) * iw, Y = v => mt + ih - v / y1 * ih;
      let s = '<svg viewBox="0 0 ' + W + ' ' + H + '" width="100%" height="' + H + '" role="img" aria-label="% NG Bavia từng tem Đúc">';
      for (let v = 0; v <= y1 + 1e-9; v += ystep) {
        s += '<line x1="' + ml + '" x2="' + (W - mr) + '" y1="' + Y(v) + '" y2="' + Y(v) + '" stroke="#EEF1F5"/>' +
          '<text x="' + (ml - 6) + '" y="' + (Y(v) + 3) + '" font-size="10" fill="#5B6472" text-anchor="end">' + fp(v, ystep < 0.01 ? 1 : 0) + '</text>';
      }
      // trục x
      if (isShot) {
        const xs = niceStep(x1, 6);
        for (let v = 0; v <= x1; v += xs) s += '<text x="' + X(v) + '" y="' + (H - 10) + '" font-size="10" fill="#5B6472" text-anchor="middle">' + fn(v) + '</text><line x1="' + X(v) + '" x2="' + X(v) + '" y1="' + (mt + ih) + '" y2="' + (mt + ih + 4) + '" stroke="#C9D0DA"/>';
        s += '<text x="' + (W - mr) + '" y="' + (mt - 8) + '" font-size="10" fill="#5B6472" text-anchor="end">shot từ lần bảo dưỡng</text>';
      } else {
        // Việt Nam = UTC+7 cố định → nửa đêm VN = floor((ms + 7h) / ngày) · ngày − 7h
        const day = 86400e3, h7 = 7 * 3600e3, span = x1 - x0, stepD = Math.max(1, Math.ceil(span / day / 8));
        const d0 = Math.floor((x0 + h7) / day) * day - h7;
        for (let t = d0 + day; t < x1; t += day * stepD) {
          s += '<line x1="' + X(t) + '" x2="' + X(t) + '" y1="' + mt + '" y2="' + (mt + ih) + '" stroke="#F3F5F8"/>' +
            '<text x="' + X(t) + '" y="' + (H - 10) + '" font-size="10" fill="#5B6472" text-anchor="middle">' + fd(new Date(t).toISOString()) + '</text>';
        }
      }
      s += '<line x1="' + ml + '" x2="' + ml + '" y1="' + mt + '" y2="' + (mt + ih) + '" stroke="#C9D0DA"/><line x1="' + ml + '" x2="' + (W - mr) + '" y1="' + (mt + ih) + '" y2="' + (mt + ih) + '" stroke="#C9D0DA"/>';
      // sự kiện khuôn (chỉ theo giờ đúc)
      const khuons = new Set(P.map(t => t.khuon));
      const evs = (!isShot && st.suKien) ? (st.data.su_kien || []).filter(e => khuons.has(e.k) && SK[e.loai] && (!st.may || !e.may || e.may === st.may)).map(e => Object.assign({}, e, { ms: new Date(e.t).getTime() })).filter(e => e.ms >= x0 && e.ms <= x1) : [];
      evs.forEach(e => {
        const m = SK[e.loai], x = X(e.ms);
        s += '<g style="pointer-events:all"><title>' + esc(m.l + ' · ' + e.k + (e.may ? ' · ' + e.may : '') + ' · ' + fdt(e.t) + (e.ph ? ' · dừng ' + fn(e.ph) + ' ph' : '') + (e.nd ? '\n' + e.nd : '')) + '</title>' +
          '<line x1="' + x + '" x2="' + x + '" y1="' + mt + '" y2="' + (mt + ih) + '" stroke="' + m.c + '" stroke-width="1.2" opacity=".55"' + (m.d ? ' stroke-dasharray="' + m.d + '"' : '') + '/>' +
          '<text x="' + x + '" y="' + (mt - 6) + '" font-size="9" font-weight="700" fill="' + m.c + '" text-anchor="middle">' + e.loai + '</text></g>';
      });
      const coLoai = [...new Set(evs.map(e => e.loai))];
      $('sklg').innerHTML = coLoai.map(l => '<span class="lg"><span style="width:14px;border-top:2px ' + (SK[l].d ? 'dashed' : 'solid') + ' ' + SK[l].c + '"></span>' + l + ' ' + SK[l].l + '</span>').join('');
      // mục tiêu
      s += '<line x1="' + ml + '" x2="' + (W - mr) + '" y1="' + Y(mtLine) + '" y2="' + Y(mtLine) + '" stroke="' + RED + '" stroke-width="1.5" stroke-dasharray="6 4"/>' +
        '<text x="' + (W - mr - 2) + '" y="' + (Y(mtLine) - 4) + '" font-size="10" fill="' + RED + '" text-anchor="end">' + (motMa ? 'Mục tiêu ' + esc(motMa) + ' ' : 'Mục tiêu chung ') + fp(mtLine, 1) + (motMa ? '' : ' — màu điểm theo mục tiêu từng mã') + '</text>';
      // TB trượt 5 tem (có trọng số SL)
      if (P.length >= 3) {
        const line = P.map((t, i) => { const w = P.slice(Math.max(0, i - 4), i + 1); const a = w.reduce((x, r) => x + r.ngN, 0), b = w.reduce((x, r) => x + r.n, 0); return X(isShot ? t.shotN : t.ms).toFixed(1) + ',' + Y(b ? a / b : 0).toFixed(1); });
        s += '<polyline points="' + line.join(' ') + '" fill="none" stroke="' + INK + '" stroke-width="1.6" opacity=".8"/>';
      }
      // điểm
      const maxN = Math.max(...P.map(t => t.n));
      P.forEach(t => {
        const r = 3 + 4 * Math.sqrt(t.n / maxN), cx = X(isShot ? t.shotN : t.ms), cy = Y(t.p);
        const fill = t.ngN === 0 ? '#fff' : (t.p >= t.mt ? RED : BLUE), stroke = t.ngN === 0 ? GRAY : '#fff';
        const tip = t.tag + ' · ' + t.sp + '\nKhuôn ' + (t.khuon || '—') + ' · ' + (t.may || '—') + ' · đúc ' + fdt(t.tg) + (t.nguoi ? ' · ' + t.nguoi : '') +
          '\nShot từ BD: ' + (t.shotN == null ? '—' : (t.shot_dh ? '' : '~') + fn(t.shotN)) +
          '\nQua Bavia ' + fn(t.n) + ' · NG ' + fn(t.ngN) + ' (' + fp(t.p) + ')' + (t.ngN ? '\n' + loaiTxt(t.loai) : '');
        s += '<circle data-tag="' + esc(t.tag) + '" cx="' + cx.toFixed(1) + '" cy="' + cy.toFixed(1) + '" r="' + r.toFixed(1) + '" fill="' + fill + '" stroke="' + stroke + '" stroke-width="1.5"' + (st.sel === t.tag ? ' style="stroke:#14181F;stroke-width:3"' : '') + '><title>' + esc(tip) + '</title></circle>';
      });
      s += '</svg>';
      box.innerHTML = s;
    }

    // ---------- bảng gộp ----------
    function gop(pts, keyFn) {
      const m = {};
      pts.forEach(t => { const k = keyFn(t); if (k == null) return; const g = m[k] || (m[k] = { k, tem: 0, n: 0, ng: 0, loai: {} }); g.tem++; g.n += t.n; g.ng += t.ngN; Object.entries(t.loai || {}).forEach(([l, v]) => { g.loai[l] = (g.loai[l] || 0) + Number(v); }); });
      return Object.values(m);
    }
    function bangGop(title, list, sortKeep) {
      if (!sortKeep) list.sort((a, b) => (b.ng / (b.n || 1)) - (a.ng / (a.n || 1)) || b.n - a.n);
      return '<div class="bx"><h3 style="margin-bottom:6px">' + title + '</h3><div class="tw"><table data-bang-dai="tat"><thead><tr><th></th><th class="r">Tem</th><th class="r">SL</th><th class="r">NG</th><th class="r">% NG</th><th>Lỗi chính</th></tr></thead><tbody>' +
        (list.length ? list.map(g => '<tr><td><b>' + esc(g.k) + '</b></td><td class="r mono">' + fn(g.tem) + '</td><td class="r mono">' + fn(g.n) + '</td><td class="r mono">' + fn(g.ng) + '</td><td class="r mono">' + (g.n ? fp(g.ng / g.n) : '—') + '</td><td>' + esc(loiChinh(g.loai)) + '</td></tr>').join('') : '<tr><td colspan="6" class="mut">—</td></tr>') +
        '</tbody></table></div></div>';
    }
    function renderGroups(pts) {
      const shot = SHOT_BUCKET.map(([a, b]) => {
        const w = pts.filter(t => t.shotN != null && t.shotN >= a && t.shotN < b);
        const g = gop(w, () => 'x')[0] || { tem: 0, n: 0, ng: 0, loai: {} };
        return Object.assign(g, { k: b === Infinity ? '≥ ' + fn(a) : fn(a) + ' – ' + fn(b) });
      }).filter(g => g.tem);
      $('groups').innerHTML = bangGop('Theo khuôn', gop(pts, t => t.khuon || '—')) + bangGop('Theo shot từ bảo dưỡng', shot, true) +
        bangGop('Theo máy', gop(pts, t => t.may || '—')) + bangGop('Theo người đúc', gop(pts, t => t.nguoi || '—'));
    }

    // ---------- chi tiết ----------
    function renderDetail(R) {
      const L = R.slice().sort((a, b) => (b.ms || 0) - (a.ms || 0));
      $('detail').innerHTML = '<table><thead><tr><th>Tem Đúc</th><th>Mã SP</th><th>Khuôn</th><th>Máy</th><th>Giờ đúc</th><th>Người đúc</th><th class="r">Shot từ BD</th><th>Bảo dưỡng gần nhất</th><th class="r">Qua Bavia</th><th class="r">NG</th><th class="r">% NG</th><th>Loại lỗi</th><th class="r">NG chờ sửa</th></tr></thead><tbody>' +
        (L.length ? L.map(t => '<tr data-tag="' + esc(t.tag) + '" class="' + (t.ngN > 0 && t.p >= t.mt ? 'out' : '') + (st.sel === t.tag ? ' sel' : '') + '">' +
          '<td class="mono">' + esc(t.tag) + '</td><td>' + esc(t.sp) + '</td><td>' + esc(t.khuon || '—') + '</td><td>' + esc(t.may || '—') + '</td>' +
          '<td class="mono">' + fdt(t.tg) + '</td><td>' + esc(t.nguoi || '—') + '</td>' +
          '<td class="r mono">' + (t.shotN == null ? '—' : (t.shot_dh ? '' : '~') + fn(t.shotN)) + '</td>' +
          '<td class="mono">' + (t.bd_luc ? fdt(t.bd_luc) : '<span class="mut">chưa có</span>') + '</td>' +
          '<td class="r mono">' + fn(t.n) + '</td><td class="r mono">' + fn(t.ngN) + '</td><td class="r mono p">' + fp(t.p) + '</td>' +
          '<td>' + esc(loaiTxt(t.loai)) + '</td><td class="r mono">' + (Number(t.sua) ? fn(t.sua) : '') + '</td></tr>').join('')
          : '<tr><td colspan="13" class="mut">Không có tem.</td></tr>') +
        '</tbody></table>';
    }

    // ---------- sự kiện ----------
    el.addEventListener('change', e => {
      const k = e.target.dataset && e.target.dataset.k; if (!k) return;
      if (k === 'start' || k === 'end') {
        st[k] = e.target.value || st[k];
        if (st.start > st.end) { if (k === 'start') st.end = st.start; else st.start = st.end; inp('start').value = st.start; inp('end').value = st.end; }
        if ((new Date(st.end) - new Date(st.start)) / 86400000 > 92) { st.start = addDays(st.end, -92); inp('start').value = st.start; }
        el.querySelectorAll('[data-act="preset"]').forEach(b => b.classList.remove('on'));
        load();
      } else if (k === 'tatCa' || k === 'suKien') { st[k] = e.target.checked; render(); }
      else { st[k] = e.target.value; render(); }
    });
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (b && b.dataset.act === 'preset') {
        st.start = addDays(st.end, -(Number(b.dataset.n) - 1)); inp('start').value = st.start;
        el.querySelectorAll('[data-act="preset"]').forEach(x => x.classList.toggle('on', x === b));
        load(); return;
      }
      if (b && b.dataset.act === 'x') {
        st.x = b.dataset.x; el.querySelectorAll('[data-act="x"]').forEach(x => x.classList.toggle('on', x === b)); render(); return;
      }
      const c = e.target.closest('circle[data-tag]');
      if (c) {
        st.sel = c.dataset.tag; render();
        const tr = el.querySelector('tr[data-tag="' + CSS.escape(st.sel) + '"]');
        if (tr) tr.scrollIntoView({ block: 'center', behavior: 'smooth' });
        return;
      }
      const tr = e.target.closest('tr[data-tag]');
      if (tr) { st.sel = st.sel === tr.dataset.tag ? null : tr.dataset.tag; render(); }
    });
    let rz; window.addEventListener('resize', () => { clearTimeout(rz); rz = setTimeout(() => { if (el.offsetParent) drawChart(rows().filter(t => t.n > 0)); }, 150); });

    await loadCfg();
    await load();
    return { taiLai: () => load() };
  }

  window.BaviaNgTem = { mount };
})();
