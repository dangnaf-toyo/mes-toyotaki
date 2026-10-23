/**
 * ============================================================================
 * oqc-ng-dash.js — T135: QC Manager › tab "NG OQC"
 *   OqcNgDash.mount(el) → Promise<{ taiLai() }>
 * Đọc oqc_daily_inspection (NG theo ngày/mã/loại lỗi) + oqc_ng_cau_hinh (CL
 * mỗi mã do QC Manager đặt/khoá, mục tiêu chung '*' + riêng). Ghi cấu hình
 * qua RPC oqc_ng_dat (supabase/migration_phase_T135_oqc_ng_dashboard.sql).
 * Khoảng xem: "Từ ngày" → "Đến ngày" (tối đa 366 ngày) + nút chọn nhanh; biểu đồ,
 * Pareto "cả khoảng", thẻ từng mã và bảng chi tiết theo khoảng này.
 * T150: lọc theo phạm vi kiểm (oqc_inspection_context) — mặc định "Sau gia công" (gồm phiếu cũ
 * chưa phân loại), "Sau Sơn", "Sau gia công ngoài", "Tất cả phạm vi".
 * T153: phạm vi Sau Sơn thêm lọc "Lần sơn" (mặc định lần 1 — P-chart chỉ so hàng sơn mới) và bảng
 * "Hiệu quả sơn theo lần sơn": % NG lần 1, OK ngay lần đầu, % sơn lại cứu được, NG chưa sơn lại, tỷ lệ đạt cuối.
 * Trạng thái mã (cửa sổ 7 ngày đến "Đến ngày"):
 *   Bất thường  = có lần kiểm vượt UCL = CL + 3·√(CL(1−CL)/n)
 *   Tăng        = NG% 7 ngày ≥ 7 ngày trước × 1,3 (và +0,5 điểm %)
 *   Cảnh báo    = có lần kiểm trong vùng 2σ–3σ
 *   Chưa đặt CL / Giảm (≤ ×0,7) / Trên mục tiêu / Bình thường / Không kiểm
 * ============================================================================
 */
(function () {
  const BLUE = '#1F5FBF', LBLUE = '#AFC6E9', RED = '#B42318', GRAY = '#9AA3B0', INK = '#14181F';
  const SHADES = ['#0B3D7A', '#1F5FBF', '#4A86D4', '#86AEE3', '#C3D6F1'];
  const OTHER = '#D9DEE6';
  const TREND = 0.3;
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fp = (x, d) => (x == null || !isFinite(x)) ? '—' : (x * 100).toFixed(d == null ? 1 : d).replace('.', ',') + '%';
  const f1 = x => (x * 100).toFixed(1).replace('.', ',');
  const fn = n => Math.round(Number(n) || 0).toLocaleString('vi-VN');
  const pad = n => String(n).padStart(2, '0');
  const ymd = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  const addDays = (s, k) => { const d = new Date(s + 'T00:00:00'); d.setDate(d.getDate() + k); return ymd(d); };
  const dl = s => s.slice(8, 10) + '/' + s.slice(5, 7);
  const pct = x => (Math.max(0, Math.min(1, x)) * 100).toFixed(3) + '%';
  const soNgay = (a, b) => Math.round((new Date(b + 'T00:00:00') - new Date(a + 'T00:00:00')) / 86400000) + 1;
  const MAX_NGAY = 366;
  // Chọn nhanh khoảng ngày: trả về [từ, đến]; loại theo số ngày giữ nguyên "Đến ngày" đang chọn
  const PRESETS = [
    { k: 'd7', l: '7 ngày', f: e => [addDays(e, -6), e] },
    { k: 'd16', l: '16 ngày', f: e => [addDays(e, -15), e] },
    { k: 'd28', l: '4 tuần', f: e => [addDays(e, -27), e] },
    { k: 'd91', l: '3 tháng', f: e => [addDays(e, -90), e] },
    { k: 'thang', l: 'Tháng này', f: (e, t) => [t.slice(0, 8) + '01', t] },
    { k: 'thang_truoc', l: 'Tháng trước', f: (e, t) => { const dau = t.slice(0, 8) + '01'; const cuoi = addDays(dau, -1); return [cuoi.slice(0, 8) + '01', cuoi]; } },
  ];
  // Phạm vi kiểm (oqc_inspection_context.inspection_scope). Phiếu chưa phân loại ('') là dữ liệu sau gia công cũ.
  const SCOPES = [
    { k: 'MACHINING', l: 'Sau gia công', ok: sc => sc === 'FULL_POST_MACHINING' || sc === '' },
    { k: 'POST_PAINTING', l: 'Sau Sơn', ok: sc => sc === 'POST_PAINTING' },
    { k: 'POST_OUTSOURCED_MACHINING', l: 'Sau gia công ngoài', ok: sc => sc === 'POST_OUTSOURCED_MACHINING' },
    { k: 'ALL', l: 'Tất cả phạm vi', ok: () => true },
  ];
  // T153: lần sơn (chỉ phạm vi Sau Sơn). Phiếu sau sơn chưa ghi lần = lần 1.
  const LANS = [
    { k: '1', l: 'Lần 1 (sơn mới)', ok: lan => lan === 1 },
    { k: 'R', l: 'Sơn lại (lần 2+)', ok: lan => lan >= 2 },
    { k: 'ALL', l: 'Tất cả lần sơn', ok: () => true },
  ];
  const parsePct = v => { const t = String(v == null ? '' : v).trim().replace(',', '.'); if (t === '') return null; const n = Number(t); return isFinite(n) ? n / 100 : NaN; };

  const META = {
    bat_thuong: { l: 'Bất thường', c: RED, bd: RED, rank: 0 },
    tang: { l: 'Tăng', c: '#FFFFFF', bd: RED, rank: 1 },
    canh_bao: { l: 'Cảnh báo', c: '#FFFFFF', bd: INK, rank: 2 },
    cao: { l: 'Trên mục tiêu', c: INK, bd: INK, rank: 3 },
    binh_thuong: { l: 'Bình thường', c: GRAY, bd: GRAY, rank: 4 },
    giam: { l: 'Giảm', c: BLUE, bd: BLUE, rank: 5 },
    chua_cl: { l: 'Chưa đặt CL', c: '#FFFFFF', bd: GRAY, rank: 6 },
    khong_kiem: { l: 'Không kiểm 7 ngày', c: '#E4E8EE', bd: '#E4E8EE', rank: 7 },
  };

  function css() {
    if (document.getElementById('ond-css')) return;
    const st = document.createElement('style'); st.id = 'ond-css';
    st.textContent =
      '.ond{display:flex;flex-direction:column;gap:10px;font-size:12px;color:#14181F}' +
      '.ond .bx{background:#fff;border:1px solid #DDE2EA;border-radius:8px;padding:10px 14px;min-width:0}' +
      '.ond .bar{display:flex;flex-wrap:wrap;align-items:center;gap:8px}' +
      '.ond .bar label{display:inline-flex;align-items:center;gap:6px;font-weight:600;color:#5B6472}' +
      '.ond input,.ond select{font:inherit;font-size:13px;padding:6px 8px;border:1px solid #C9D0DA;border-radius:6px;background:#fff;min-height:34px;box-sizing:border-box}' +
      '.ond .btn{font:inherit;font-size:12.5px;font-weight:600;padding:6px 12px;min-height:34px;border-radius:6px;border:1px solid #C9D0DA;background:#fff;color:#14181F;cursor:pointer;white-space:nowrap}' +
      '.ond .btn.p{background:#0F5FA5;border-color:#0F5FA5;color:#fff}.ond .btn.on{background:#14181F;border-color:#14181F;color:#fff}' +
      '.ond .btn.sm{min-height:28px;padding:3px 9px;font-size:12px}.ond .btn:disabled{opacity:.5;cursor:not-allowed}' +
      '.ond h3{margin:0;font-size:13px;font-weight:700}' +
      '.ond .mono{font-family:"JetBrains Mono",ui-monospace,monospace}' +
      '.ond .mut{color:#5B6472}' +
      '.ond .row{display:flex;flex-wrap:wrap;gap:10px}' +
      '.ond .lg{display:inline-flex;align-items:center;gap:5px;color:#3A4250}' +
      '.ond .sw{width:10px;height:10px;border-radius:2px;display:inline-block}' +
      '.ond .dot{width:10px;height:10px;border-radius:99px;display:inline-block;box-sizing:border-box}' +
      '.ond .hatch{background:repeating-linear-gradient(45deg,#E9EDF2 0 3px,#F7F8FA 3px 6px)}' +
      '.ond .plot{position:relative;border-left:1px solid #C9D0DA;border-bottom:1px solid #C9D0DA}' +
      '.ond .plot svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}' +
      '.ond .ax{display:flex;flex-direction:column;justify-content:space-between;font-size:10px;color:#5B6472;text-align:right;transform:translateY(-6px)}' +
      '.ond .cols{position:absolute;inset:0;display:grid;align-items:end;grid-auto-rows:100%}' +
      '.ond .xl{display:grid;font-size:10px;color:#5B6472;text-align:center}' +
      '.ond .cards{display:flex;flex-wrap:wrap;gap:10px}' +
      '.ond .card{flex:1 1 calc(50% - 5px);min-width:min(100%,560px);box-sizing:border-box;background:#fff;border:1px solid #DDE2EA;border-radius:8px;padding:10px 12px;display:flex;flex-direction:column;gap:6px}' +
      '.ond table{border-collapse:collapse;width:100%}.ond th,.ond td{padding:5px 8px;text-align:left;border-top:1px solid #EEF1F5;white-space:nowrap}' +
      '.ond th{background:#F6F8FA;color:#3A4250;font-weight:600;border-top:0}.ond td.r,.ond th.r{text-align:right}' +
      '.ond .msg{font-weight:600;padding:6px 10px;border-radius:6px}.ond .msg.err{background:#FEF2F2;color:#B42318}.ond .msg.ok{background:#EFF6FF;color:#1F5FBF}' +
      '.ond .card[data-card]{cursor:pointer}.ond .card[data-card]:hover{box-shadow:0 0 0 2px #C3D6F1}.ond .card.sel{box-shadow:0 0 0 2px #1F5FBF}' +
      '.ond .dt{flex:1 1 100%;box-sizing:border-box}.ond .dt td{font-size:12px}.ond .dt tr.sub td{background:#F6F8FA;font-weight:700}' +
      '.ond .dt tr.out td.ngp{color:#B42318;font-weight:700}.ond .tagd{font-size:10.5px;font-weight:700;border:1px solid #14181F;border-radius:4px;padding:0 5px;margin-left:4px}' +
      '@media (max-width:640px){.ond .card{min-width:100%}}';
    document.head.appendChild(st);
  }

  async function mount(el) {
    css();
    const today = ymd(new Date());
    const st = { start: addDays(today, -15), end: today, range: 16, kh: '', scope: 'MACHINING', lan: '1', pareto: '7', cfgOpen: false, rows: [], prods: {}, cfg: {}, canEdit: false, msg: null, sel: null, work: {} };
    el.innerHTML =
      '<div class="ond">' +
      '<div class="bar">' +
      '<label>Từ ngày <input type="date" data-k="start" value="' + st.start + '" max="' + today + '"></label>' +
      '<label>Đến ngày <input type="date" data-k="end" value="' + today + '" max="' + today + '"></label>' +
      '<span style="display:inline-flex;flex-wrap:wrap;gap:4px">' +
      PRESETS.map(p => '<button type="button" class="btn sm' + (p.k === 'd16' ? ' on' : '') + '" data-act="preset" data-p="' + p.k + '">' + p.l + '</button>').join('') +
      '</span>' +
      '<label title="Sau gia công gồm cả phiếu cũ chưa phân loại phạm vi">Phạm vi <select data-k="scope">' +
      SCOPES.map(s => '<option value="' + s.k + '">' + s.l + '</option>').join('') + '</select></label>' +
      '<label data-o="lanbox" hidden title="Sơn lại = hàng NG lần trước đem sơn lại (lần 2, 3…)">Lần sơn <select data-k="lan">' +
      LANS.map(x => '<option value="' + x.k + '">' + x.l + '</option>').join('') + '</select></label>' +
      '<label>Khách hàng <select data-k="kh"><option value="">Tất cả</option></select></label>' +
      '<span style="flex:1"></span><span data-o="msg"></span>' +
      '<button type="button" class="btn" data-act="cfg">🔒 CL &amp; mục tiêu</button>' +
      '</div>' +
      '<div data-o="cfg" style="display:none"></div>' +
      '<div class="row" data-o="kpi"></div>' +
      '<div class="row" data-o="charts"></div>' +
      '<div style="display:flex;justify-content:flex-end;gap:0;margin-top:-4px" data-o="ptog"></div>' +
      '<div data-o="hieuqua"></div>' +
      '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 14px;margin-top:2px">' +
      '<h3 style="margin-right:auto">Kết quả kiểm tra hằng ngày từng mã</h3>' +
      '<span class="lg"><span class="dot" style="background:' + BLUE + '"></span>NG%</span>' +
      '<span class="lg"><span style="width:14px;border-top:2px solid #8A93A3"></span>CL</span>' +
      '<span class="lg"><span style="width:14px;border-top:2px solid ' + RED + '"></span>UCL</span>' +
      '<span class="lg"><span style="width:14px;border-top:2px dashed ' + INK + '"></span>Mục tiêu</span>' +
      '<span class="lg"><span class="sw" style="background:' + BLUE + '"></span>Tổng NG/ngày</span>' +
      '</div>' +
      '<div class="cards" data-o="cards"></div>' +
      '</div>';
    const $ = k => el.querySelector('[data-o="' + k + '"]');

    // ---------- tải dữ liệu ----------
    async function loadRole() {
      try {
        const s = await MesAuth.getSession();
        if (!s) return;
        const { data } = await sb.from('user_roles').select('role').eq('user_id', s.user.id).maybeSingle();
        st.canEdit = !!data && ['admin', 'qc_manager'].includes(data.role);
      } catch (e) { st.canEdit = false; }
    }
    async function loadCfg() {
      const { data, error } = await sb.from('oqc_ng_cau_hinh').select('*');
      if (error) throw error;
      st.cfg = {}; (data || []).forEach(r => { st.cfg[r.ma_sp] = r; });
    }
    async function loadRows() {
      // Lấy thêm 4 tuần trước "Đến ngày" để luôn tính được trạng thái 7 ngày / TB 4 tuần dù khoảng chọn ngắn
      const lui = addDays(st.end, -27);
      const from = st.start < lui ? st.start : lui;
      const out = [];
      for (let off = 0; ; off += 1000) {
        const { data, error } = await sb.from('oqc_daily_inspection')
          .select('id,inspection_date,shift,inspection_time,product_code,product_name,customer_name,inspector_code,inspector_name,total_qty,ok_qty,ng_qty,defects,note,lot_no,task_no')
          .gte('inspection_date', from).lte('inspection_date', st.end).order('id').range(off, off + 999);
        if (error) throw error;
        out.push(...(data || []));
        if (!data || data.length < 1000) break;
      }
      // Phạm vi từng phiếu; chỉ tin khi ngày/mã khớp phiếu (phiếu sửa ngày/mã sau khi lưu phạm vi → coi như chưa phân loại)
      const ctx = {};
      for (let off = 0; ; off += 1000) {
        const { data, error } = await sb.from('oqc_inspection_context')
          .select('inspection_id,inspection_scope,source_date,source_product_code,lan_son')
          .gte('source_date', from).lte('source_date', st.end).order('inspection_id').range(off, off + 999);
        if (error) throw error;
        (data || []).forEach(c => { ctx[c.inspection_id] = c; });
        if (!data || data.length < 1000) break;
      }
      st.rows = out.map(r => {
        const c = ctx[r.id];
        const sc = c && c.source_date === r.inspection_date && c.source_product_code === r.product_code ? c.inspection_scope || '' : '';
        const lan = sc === 'POST_PAINTING' ? Number(c.lan_son) || 1 : null;
        const defs = {};
        (Array.isArray(r.defects) ? r.defects : []).forEach(x => {
          const q = Number(x && x.qty) || 0; if (q <= 0) return;
          const l = String((x.label || x.code || 'Khác')).trim();
          defs[l] = (defs[l] || 0) + q;
        });
        return { id: r.id, d: r.inspection_date, p: r.product_code, n: Number(r.total_qty) || 0, ng: Number(r.ng_qty) || 0,
          ok: r.ok_qty != null ? Number(r.ok_qty) : (Number(r.total_qty) || 0) - (Number(r.ng_qty) || 0), defs, kh: r.customer_name || '',
          ca: r.shift || '', gio: r.inspection_time ? String(r.inspection_time).slice(0, 5) : '',
          nguoi: r.inspector_name || r.inspector_code || '', maNguoi: r.inspector_code || '', ghiChu: r.note || '', lot: r.lot_no || '', task: r.task_no || '', sc, lan };
      }).filter(r => r.n > 0);
    }
    async function loadProds() {
      const { data } = await sb.from('master_products').select('ma_sp,ten_sp,ten_khach_hang');
      st.prods = {}; (data || []).forEach(p => { st.prods[p.ma_sp] = p; });
    }
    async function taiLai() {
      setMsg('Đang tải…', 'ok');
      try {
        await Promise.all([loadRows(), loadCfg(), Object.keys(st.prods).length ? null : loadProds(), loadRole()]);
        fillKh();
        setMsg(null);
        render();
      } catch (e) { setMsg('Lỗi tải dữ liệu: ' + (e.message || e), 'err'); }
    }
    function datKhoang(tu, den) {
      const n = soNgay(tu, den);
      const inTu = el.querySelector('[data-k="start"]'), inDen = el.querySelector('[data-k="end"]');
      if (n > MAX_NGAY) {
        inTu.value = st.start; inDen.value = st.end;
        setMsg('Khoảng ngày tối đa ' + MAX_NGAY + ' ngày (đang chọn ' + n + ' ngày). Thu hẹp lại giúp nhé.', 'err');
        return;
      }
      st.start = tu; st.end = den; st.range = n;
      st.pareto = 'all'; // chọn khoảng để phân tích → Pareto theo cả khoảng (vẫn bấm lại được "Pareto 7 ngày")
      inTu.value = tu; inDen.value = den;
      el.querySelectorAll('[data-act="preset"]').forEach(btn => {
        const p = PRESETS.find(x => x.k === btn.dataset.p);
        const [a, b] = p.f(den, ymd(new Date()));
        btn.classList.toggle('on', a === tu && b === den);
      });
      taiLai();
    }
    function setMsg(t, cls) { const m = $('msg'); m.className = t ? 'msg ' + cls : ''; m.textContent = t || ''; }
    function khOf(r) { const p = st.prods[r.p]; return (p && p.ten_khach_hang) || r.kh || ''; }
    const scopeOk = r => SCOPES.find(s => s.k === st.scope).ok(r.sc);
    const lanOk = r => st.scope !== 'POST_PAINTING' || LANS.find(x => x.k === st.lan).ok(r.lan);
    function fillKh() {
      const sel = el.querySelector('[data-k="kh"]');
      const list = [...new Set(st.rows.filter(scopeOk).map(khOf).filter(Boolean))].sort((a, b) => a.localeCompare(b, 'vi'));
      if (st.kh && !list.includes(st.kh)) st.kh = ''; // khách hàng không có trong phạm vi mới → về "Tất cả"
      sel.innerHTML = '<option value="">Tất cả</option>' + list.map(k => '<option' + (k === st.kh ? ' selected' : '') + '>' + esc(k) + '</option>').join('');
    }

    // ---------- tính toán ----------
    function compute() {
      const end = st.end, N = st.range, start = st.start;
      const cut = addDays(end, -6), pStart = addDays(end, -13), avgFrom = addDays(end, -27);
      const all = st.rows.filter(r => scopeOk(r) && lanOk(r) && (!st.kh || khOf(r) === st.kh));
      const inD = all.filter(r => r.d >= start && r.d <= end);
      const days = []; for (let i = 0; i < N; i++) days.push(addDays(start, i));
      const gTarget = st.cfg['*'] && st.cfg['*'].muc_tieu != null ? Number(st.cfg['*'].muc_tieu) : 0.03;
      const agg = rs => rs.reduce((a, r) => ({ n: a.n + r.n, ng: a.ng + r.ng }), { n: 0, ng: 0 });
      const addTo = (o, r) => { o.n += r.n; o.ng += r.ng; Object.entries(r.defs).forEach(([l, q]) => o.defs[l] = (o.defs[l] || 0) + q); };
      const byDay = {}, byPD = {}, tot = {};
      inD.forEach(r => {
        addTo(byDay[r.d] || (byDay[r.d] = { n: 0, ng: 0, defs: {}, byP: {} }), r);
        byDay[r.d].byP[r.p] = (byDay[r.d].byP[r.p] || 0) + r.ng;
        addTo(byPD[r.p + '|' + r.d] || (byPD[r.p + '|' + r.d] = { n: 0, ng: 0, defs: {} }), r);
        addTo(tot[r.p] || (tot[r.p] = { n: 0, ng: 0, defs: {} }), r);
      });
      const info = Object.keys(tot).map(code => {
        const c = st.cfg[code] || {};
        const cl = c.cl != null ? Number(c.cl) : null;
        const tg = c.muc_tieu != null ? Number(c.muc_tieu) : gTarget;
        const pts = [];
        days.forEach((d, i) => {
          const v = byPD[code + '|' + d]; if (!v) return;
          const p = v.ng / v.n;
          if (cl == null) { pts.push({ d, i, n: v.n, ng: v.ng, p, ucl: null, out: false, w: false }); return; }
          const s = Math.sqrt(cl * (1 - cl) / v.n);
          pts.push({ d, i, n: v.n, ng: v.ng, p, ucl: cl + 3 * s, out: p > cl + 3 * s, w: p > cl + 2 * s && p <= cl + 3 * s });
        });
        const a2 = agg(all.filter(r => r.p === code && r.d >= cut && r.d <= end));
        const a1 = agg(all.filter(r => r.p === code && r.d >= pStart && r.d < cut));
        const r2 = a2.n ? a2.ng / a2.n : null, r1 = a1.n ? a1.ng / a1.n : null;
        const last7 = pts.filter(x => x.d >= cut);
        let s;
        if (!last7.length) s = 'khong_kiem';
        else if (last7.some(x => x.out)) s = 'bat_thuong';
        else if (r1 != null && r1 > 0 && r2 >= r1 * (1 + TREND) && r2 - r1 >= 0.005) s = 'tang';
        else if (last7.some(x => x.w)) s = 'canh_bao';
        else if (cl == null) s = 'chua_cl';
        else if (r1 != null && r2 <= r1 * (1 - TREND)) s = 'giam';
        else if (r2 > tg) s = 'cao';
        else s = 'binh_thuong';
        let delta = '', dColor = '#5B6472';
        if (r1 != null && r2 != null && r1 > 0) { const k = r2 / r1 - 1; delta = (k >= 0 ? '▲' : '▼') + Math.abs(Math.round(k * 100)) + '%'; dColor = k >= TREND ? RED : (k <= -TREND ? BLUE : '#5B6472'); }
        return { code, name: (st.prods[code] && st.prods[code].ten_sp) || '', cl, tg, tgOwn: c.muc_tieu != null, pts, r1, r2, st: s, delta, dColor, total: tot[code] };
      }).sort((a, b) => META[a.st].rank - META[b.st].rank || (b.r2 || 0) - (a.r2 || 0));
      return { end, N, days, cut, pStart, avgFrom, all, inD, byDay, info, gTarget, agg };
    }

    // ---------- vẽ ----------
    function niceMax(v) { const p = v * 100; const steps = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60, 80, 100]; const m = steps.find(s => s >= p * 1.15) || 100; return m / 100; }
    function axis(ymax, h) {
      const top = ymax * 100, step = top <= 8 ? 1 : top <= 20 ? (top <= 12 ? 2 : 5) : 10;
      const ticks = []; for (let t = top; t >= -0.001; t -= step) ticks.push(t === 0 ? '0' : (Math.round(t * 10) / 10) + '%');
      if (ticks[ticks.length - 1] !== '0') ticks.push('0');
      return '<div class="ax mono" style="height:' + h + 'px;width:30px">' + ticks.map(t => '<span>' + t + '</span>').join('') + '</div>';
    }
    function gridStyle(N) { const g = N > 40 ? 1 : N > 20 ? 2 : 4; return 'grid-template-columns:repeat(' + N + ',minmax(0,1fr));gap:' + g + 'px;padding:0 ' + (g / 2) + 'px'; }
    function xLabels(days, every, endDay) {
      return days.map((d, i) => '<div' + (d === endDay ? ' style="font-weight:700;color:#14181F"' : '') + '>' + ((i % every === 0 || d === endDay) ? dl(d) : '') + '</div>').join('');
    }

    function render() {
      const C = compute();
      const { days, N, byDay, info, gTarget } = C;
      const every = Math.ceil(N / 16);

      // KPI + trạng thái
      const T = byDay[C.end];
      const w2 = C.agg(C.all.filter(r => r.d >= C.cut && r.d <= C.end)), w1 = C.agg(C.all.filter(r => r.d >= C.pStart && r.d < C.cut));
      const kAll = C.agg(C.inD);
      const pw2 = w2.n ? w2.ng / w2.n : null, pw1 = w1.n ? w1.ng / w1.n : null, pAll = kAll.n ? kAll.ng / kAll.n : null;
      const pt = T ? T.ng / T.n : null;
      const arr = (a, b) => (a == null || b == null || !b) ? '' : (a >= b ? '▲' : '▼') + Math.abs(Math.round((a / b - 1) * 100)) + '%';
      const nAbn = info.filter(x => x.st === 'bat_thuong' || x.st === 'tang').length;
      const soNgayCoBc = days.filter(d => byDay[d]).length;
      const kpi = [
        { t: 'NG ' + (st.scope === 'POST_PAINTING' && st.lan === 'R' ? 'sơn lại ' :
          (st.scope === 'ALL' ? '' : SCOPES.find(s => s.k === st.scope).l.toLowerCase() + ' ') +
          (st.scope === 'POST_PAINTING' && st.lan === '1' ? 'lần 1 ' : '')) + dl(days[0]) + ' → ' + dl(C.end) + ' (' + N + ' ngày)', v: fp(pAll, 2), vc: pAll != null && pAll > gTarget ? RED : INK, d: '', dc: '',
          s: kAll.n ? fn(kAll.ng) + ' / ' + fn(kAll.n) + ' · ' + soNgayCoBc + ' ngày có báo cáo' : 'không có báo cáo' },
        { t: 'NG ngày ' + dl(C.end), v: pt == null ? '—' : fp(pt, 2), vc: pt != null && pt > gTarget ? RED : INK, d: arr(pt, pAll), dc: pt != null && pAll != null && pt > pAll ? RED : BLUE, s: T ? fn(T.ng) + ' / ' + fn(T.n) + ' · MT ' + fp(gTarget) : 'chưa có báo cáo' },
        { t: 'NG 7 ngày', v: fp(pw2, 2), vc: pw2 != null && pw2 > gTarget ? RED : INK, d: arr(pw2, pw1), dc: pw2 != null && pw1 != null && pw2 > pw1 ? RED : BLUE, s: '7 ngày trước ' + fp(pw1, 2) },
        { t: 'Mã bất thường / tăng', v: String(nAbn), vc: nAbn ? RED : INK, d: '', dc: '', s: '/ ' + info.filter(x => x.st !== 'khong_kiem').length + ' mã có kiểm 7 ngày' },
      ];
      $('kpi').innerHTML = kpi.map(k => '<div class="bx" style="flex:1 1 200px;display:flex;flex-direction:column;gap:2px"><div class="mut" style="font-size:11.5px;font-weight:600">' + esc(k.t) + '</div>' +
        '<div style="display:flex;align-items:baseline;gap:8px;flex-wrap:wrap"><span class="mono" style="font-size:26px;font-weight:700;color:' + k.vc + '">' + esc(k.v) + '</span><span class="mono" style="font-size:13px;font-weight:700;color:' + k.dc + '">' + esc(k.d) + '</span></div>' +
        '<div class="mut mono" style="font-size:11.5px">' + esc(k.s) + '</div></div>').join('') +
        '<div class="bx" style="flex:2 1 420px;display:flex;flex-wrap:wrap;align-content:center;gap:6px 16px">' +
        Object.keys(META).map(k => '<span class="lg"><span class="dot" style="width:11px;height:11px;background:' + META[k].c + ';border:2px solid ' + META[k].bd + '"></span>' + META[k].l + ' <b class="mono" style="font-size:14px">' + info.filter(x => x.st === k).length + '</b></span>').join('') + '</div>';

      // Biểu đồ NG% theo ngày — chồng theo mã
      const topP = Object.entries(info.reduce((o, x) => (o[x.code] = x.total.ng, o), {})).sort((a, b) => b[1] - a[1]).slice(0, 5).map(x => x[0]);
      const pcol = c => { const i = topP.indexOf(c); return i >= 0 ? SHADES[i] : OTHER; };
      const flag = {}; info.forEach(x => x.pts.forEach(p => { if (p.out) flag[p.d] = true; }));
      const maxDay = Math.max(gTarget, ...days.map(d => byDay[d] ? byDay[d].ng / byDay[d].n : 0));
      const YM = niceMax(maxDay), H = 230;
      const cols = days.map(d => {
        const v = byDay[d];
        if (!v) return '<div class="hatch" style="height:100%;border-radius:2px" title="' + dl(d) + ': không có báo cáo"></div>';
        const p = v.ng / v.n;
        const order = topP.filter(c => v.byP[c]).concat(Object.keys(v.byP).filter(c => !topP.includes(c)));
        const segs = order.filter(c => v.byP[c] > 0).map(c => '<div title="' + esc(dl(d) + ' · ' + c + ': ' + fn(v.byP[c]) + ' NG') + '" style="height:' + (v.byP[c] / v.ng * 100) + '%;background:' + pcol(c) + ';border-top:1px solid #fff;box-sizing:border-box"></div>').join('');
        return '<div style="height:100%;display:flex;flex-direction:column;justify-content:flex-end">' +
          (N <= 31 ? '<div class="mono" style="font-size:9.5px;font-weight:700;text-align:center;color:#3A4250;margin-bottom:9px">' + f1(p) + '</div>' : '') +
          '<div style="height:' + pct(p / YM) + ';display:flex;flex-direction:column-reverse;border-radius:2px 2px 0 0;overflow:hidden">' + segs + '</div></div>';
      }).join('');
      const dayPts = days.map((d, i) => byDay[d] ? { i, d, p: byDay[d].ng / byDay[d].n, v: byDay[d] } : null).filter(Boolean);
      const line = dayPts.map(o => ((o.i + 0.5) / N * 1000).toFixed(1) + ',' + (H - Math.min(1, o.p / YM) * H).toFixed(1)).join(' ');
      const dots = dayPts.map(o => '<div title="' + esc(dl(o.d) + ': ' + fn(o.v.ng) + '/' + fn(o.v.n) + ' · ' + fp(o.p, 2)) + '" style="position:absolute;left:' + ((o.i + 0.5) / N * 100) + '%;bottom:' + pct(o.p / YM) + ';width:11px;height:11px;transform:translate(-50%,50%);border-radius:99px;background:' + (flag[o.d] ? RED : INK) + ';border:2px solid #fff"></div>').join('');
      const daily = '<div class="bx" style="flex:1.5 1 560px;display:flex;flex-direction:column;gap:8px">' +
        '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 12px"><h3 style="margin-right:auto">NG% theo ngày — chồng theo mã</h3>' +
        topP.map(c => '<span class="lg mono" style="font-size:11px"><span class="sw" style="background:' + pcol(c) + '"></span>' + esc(c) + '</span>').join('') +
        '<span class="lg"><span class="sw" style="background:' + OTHER + '"></span>Mã khác</span>' +
        '<span class="lg"><span class="dot" style="background:' + INK + '"></span>NG% ngày</span>' +
        '<span class="lg"><span style="width:16px;border-top:2px dashed ' + INK + '"></span>Mục tiêu</span>' +
        '<span class="lg"><span class="dot" style="background:' + RED + '"></span>có mã &gt; UCL</span></div>' +
        '<div style="display:flex;gap:6px">' + axis(YM, H) +
        '<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:4px">' +
        '<div class="plot" style="height:' + H + 'px">' +
        '<div style="position:absolute;left:0;right:0;bottom:' + pct(gTarget / YM) + ';border-top:2px dashed ' + INK + '"></div>' +
        '<div class="cols" style="' + gridStyle(N) + '">' + cols + '</div>' +
        '<svg viewBox="0 0 1000 ' + H + '" preserveAspectRatio="none" aria-hidden="true"><polyline points="' + line + '" fill="none" stroke="#5B6472" stroke-width="1" vector-effect="non-scaling-stroke"></polyline></svg>' + dots +
        '</div><div class="xl mono" style="' + gridStyle(N) + '">' + xLabels(days, every, C.end) + '</div></div></div></div>';

      // 2 Pareto
      const p7 = st.pareto === '7';
      const win = p7 ? C.all.filter(r => r.d >= C.cut && r.d <= C.end) : C.inD;
      const prevWin = C.all.filter(r => r.d >= C.pStart && r.d < C.cut);
      const sumBy = (rs, key) => { const o = {}; rs.forEach(r => { if (key === 'p') { if (r.ng) o[r.p] = (o[r.p] || 0) + r.ng; } else Object.entries(r.defs).forEach(([l, q]) => o[l] = (o[l] || 0) + q); }); return o; };
      const pareto = (title, key, mono) => {
        const cur = Object.entries(sumBy(win, key)).sort((a, b) => b[1] - a[1]);
        const prev = sumBy(prevWin, key);
        const total = cur.reduce((s, x) => s + x[1], 0), totPrev = Object.values(prev).reduce((s, x) => s + x, 0) || 1;
        const PH = 200, K = 10;
        if (!cur.length) return '<div class="bx" style="flex:1 1 340px"><h3>' + title + '</h3><div class="mut" style="padding:30px 0;text-align:center">Không có NG</div></div>';
        let cum = 0;
        const bars = cur.slice(0, K).map(([l, q], i) => {
          cum += q;
          let delta = '', dc = '#5B6472';
          if (p7) { const s2 = q / total, s1 = (prev[l] || 0) / totPrev; if (!prev[l]) { delta = 'mới'; dc = RED; } else if (s2 > s1 * 1.2) { delta = '▲'; dc = RED; } else if (s2 < s1 * 0.8) { delta = '▼'; dc = BLUE; } }
          return { l, q, i, h: q / cur[0][1] * 0.85, cum: cum / total, delta, dc };
        });
        const ln = bars.map(b => (((b.i + 0.5) / K) * 1000).toFixed(1) + ',' + (PH - b.cum * PH).toFixed(1)).join(' ');
        return '<div class="bx" style="flex:1 1 340px;display:flex;flex-direction:column;gap:6px">' +
          '<div style="display:flex;align-items:center;gap:8px"><h3 style="margin-right:auto">' + title + '</h3><span class="mono mut">' + fn(total) + ' pcs NG</span></div>' +
          '<div style="display:flex;gap:6px"><div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:4px">' +
          '<div class="plot" style="height:' + PH + 'px;border-right:1px solid #C9D0DA">' +
          '<div style="position:absolute;left:0;right:0;bottom:80%;border-top:1px dashed #8A93A3"></div>' +
          '<div class="cols" style="grid-template-columns:repeat(' + K + ',minmax(0,1fr));gap:6px;padding:0 3px">' +
          bars.map(b => '<div style="height:100%;display:flex;flex-direction:column;justify-content:flex-end"><div class="mono" style="font-size:10px;text-align:center;color:#3A4250">' + fn(b.q) + '</div><div title="' + esc(b.l + ': ' + fn(b.q) + ' pcs · ' + fp(b.q / total, 0)) + '" style="height:' + pct(b.h) + ';background:' + (b.i < 3 ? BLUE : LBLUE) + ';border-radius:2px 2px 0 0"></div></div>').join('') +
          '</div><svg viewBox="0 0 1000 ' + PH + '" preserveAspectRatio="none" aria-hidden="true"><polyline points="' + ln + '" fill="none" stroke="' + INK + '" stroke-width="1.5" vector-effect="non-scaling-stroke"></polyline></svg>' +
          bars.map(b => '<div style="position:absolute;left:' + ((b.i + 0.5) / K * 100) + '%;bottom:' + pct(b.cum) + ';width:7px;height:7px;transform:translate(-50%,50%);border-radius:99px;background:' + INK + '"></div>').join('') +
          '</div><div class="xl" style="grid-template-columns:repeat(' + K + ',minmax(0,1fr));gap:6px;padding:0 3px;line-height:1.15;overflow-wrap:anywhere;color:#3A4250' + (mono ? ';font-family:\'JetBrains Mono\',monospace' : '') + '">' +
          bars.map(b => '<div>' + esc(b.l) + '<div style="font-weight:700;color:' + b.dc + '">' + b.delta + '</div></div>').join('') +
          '</div></div><div class="ax mono" style="height:' + PH + 'px;text-align:left"><span>100%</span><span>80%</span><span>60%</span><span>40%</span><span>20%</span><span>0</span></div></div></div>';
      };
      $('charts').innerHTML = daily + pareto('Pareto theo mã sản phẩm', 'p', true) + pareto('Pareto theo loại lỗi', 'def', false);
      $('ptog').innerHTML = '<button type="button" class="btn sm' + (p7 ? ' on' : '') + '" data-act="p7" style="border-radius:6px 0 0 6px">Pareto 7 ngày</button><button type="button" class="btn sm' + (p7 ? '' : ' on') + '" data-act="pall" style="border-radius:0 6px 6px 0;margin-left:-1px">Cả khoảng ' + dl(days[0]) + ' → ' + dl(C.end) + '</button>';

      // Thẻ từng mã
      const PC = 120;
      const cardHtml = info.map(x => {
        const m = META[x.st];
        const ymax = Math.max(x.tg, x.cl || 0, ...x.pts.map(p => Math.max(p.p, p.ucl || 0))) * 1.15 || 0.01;
        const ln = x.pts.map(p => (((p.i + 0.5) / N) * 1000).toFixed(1) + ',' + (PC - Math.min(1, p.p / ymax) * PC).toFixed(1)).join(' ');
        const ptsHtml = x.pts.map(p => {
          const c = p.out ? RED : (x.cl == null ? '#5B6472' : BLUE);
          const L = ((p.i + 0.5) / N * 100) + '%';
          return (p.ucl != null ? '<div style="position:absolute;left:' + L + ';bottom:' + pct(p.ucl / ymax) + ';width:' + (N > 31 ? 8 : 18) + 'px;transform:translateX(-50%);border-top:2px solid ' + RED + '"></div>' : '') +
            '<div title="' + esc(dl(p.d) + ': ' + fn(p.ng) + '/' + fn(p.n) + ' · ' + fp(p.p) + (p.ucl != null ? ' · UCL ' + fp(p.ucl) : '')) + '" style="position:absolute;left:' + L + ';bottom:' + pct(p.p / ymax) + ';width:' + (p.out ? 11 : 8) + 'px;height:' + (p.out ? 11 : 8) + 'px;transform:translate(-50%,50%);border-radius:99px;background:' + c + ';border:1.5px solid #fff"></div>' +
            (N <= 31 ? '<div class="mono" style="position:absolute;left:' + L + ';bottom:' + pct(p.p / ymax) + ';transform:translate(-50%,-9px);font-size:9.5px;font-weight:' + (p.out ? 700 : 500) + ';color:' + c + ';white-space:nowrap">' + f1(p.p) + '</div>' : '');
        }).join('');
        const maxNg = Math.max(1, ...x.pts.map(p => p.ng));
        const bars = days.map(d => { const p = x.pts.find(t => t.d === d); return '<div title="' + (p ? esc(dl(d) + ': NG ' + fn(p.ng) + ' / kiểm ' + fn(p.n)) : '') + '" style="height:' + (p ? pct(p.ng / maxNg) : '0') + ';background:' + BLUE + ';border-radius:1px 1px 0 0;align-self:end"></div>'; }).join('');
        const ticks = days.map(d => '<span>' + (x.pts.find(t => t.d === d) && N <= 31 ? d.slice(8, 10) : '') + '</span>').join('');
        const dEnt = Object.entries(x.total.defs).sort((a, b) => b[1] - a[1]);
        const dMax = dEnt.length ? dEnt[0][1] : 1;
        const defs = dEnt.slice(0, 6).map(([l, q], i) => '<div style="display:grid;grid-template-columns:96px minmax(0,1fr) 36px;align-items:center;gap:6px"><span title="' + esc(l) + '" style="overflow:hidden;text-overflow:ellipsis;color:#3A4250">' + esc(l) + '</span><span style="height:10px;background:#EEF1F5;border-radius:2px;position:relative"><span style="position:absolute;left:0;top:0;bottom:0;width:' + pct(q / dMax) + ';background:' + (i === 0 ? BLUE : LBLUE) + ';border-radius:2px"></span></span><span class="mono" style="text-align:right;font-weight:700">' + fn(q) + '</span></div>').join('') || '<div class="mut">Không có NG</div>';
        const w2c = x.r2 != null && x.r2 > x.tg ? RED : INK;
        return '<div class="card' + (st.sel === x.code ? ' sel' : '') + '" data-card="' + esc(x.code) + '" role="button" tabindex="0" title="Bấm để xem số liệu kiểm tra chi tiết" style="border-left:4px solid ' + (m.bd === '#E4E8EE' ? '#DDE2EA' : m.bd) + '">' +
          '<div style="display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 10px">' +
          '<span class="mono" style="font-weight:700;font-size:13px">' + esc(x.code) + '</span><span class="mut" style="font-size:11.5px">' + esc(x.name) + '</span>' +
          '<span style="font-size:11px;font-weight:700;color:' + ((x.st === 'bat_thuong' || x.st === 'tang') ? RED : '#5B6472') + '">' + m.l + '</span><span style="flex:1"></span>' +
          '<span class="mono mut" style="font-size:11px">CL ' + (x.cl != null ? fp(x.cl) : '—') + ' · MT ' + fp(x.tg) + (x.tgOwn ? '' : '*') + '</span>' +
          '<span class="mono" style="font-weight:700;font-size:15px;color:' + w2c + '" title="NG 7 ngày">' + fp(x.r2) + '</span>' +
          '<span class="mono" style="font-weight:700;font-size:11.5px;color:' + x.dColor + '">' + x.delta + '</span></div>' +
          '<div style="display:flex;flex-wrap:wrap;gap:14px">' +
          '<div style="flex:1 1 360px;min-width:0;display:flex;flex-direction:column;gap:3px">' +
          '<div class="plot" style="height:' + PC + 'px;margin-top:12px;border-color:#DDE2EA">' +
          (x.cl != null ? '<div style="position:absolute;left:0;right:0;bottom:' + pct(x.cl / ymax) + ';border-top:2px solid #8A93A3"></div>' : '<div style="position:absolute;right:4px;top:2px;font-size:10px;font-weight:700;color:#5B6472;border:1px dashed #8A93A3;border-radius:4px;padding:1px 6px;background:#fff">chưa đặt CL</div>') +
          '<div style="position:absolute;left:0;right:0;bottom:' + pct(x.tg / ymax) + ';border-top:2px dashed ' + INK + '"></div>' +
          '<svg viewBox="0 0 1000 ' + PC + '" preserveAspectRatio="none" aria-hidden="true"><polyline points="' + ln + '" fill="none" stroke="#9DB7DE" stroke-width="1.5" vector-effect="non-scaling-stroke"></polyline></svg>' + ptsHtml + '</div>' +
          '<div style="display:grid;' + gridStyle(N) + ';grid-auto-rows:100%;height:40px;align-items:end;border-bottom:1px solid #DDE2EA">' + bars + '</div>' +
          '<div class="xl mono" style="' + gridStyle(N) + ';font-size:9px;color:#8A93A3">' + ticks + '</div>' +
          '</div><div style="flex:1 1 200px;min-width:0;display:flex;flex-direction:column;gap:5px;padding-top:8px">' +
          '<div class="mut" style="font-size:11px;font-weight:600;display:flex;justify-content:space-between"><span>Loại lỗi</span><span class="mono">' + fn(x.total.ng) + ' / ' + fn(x.total.n) + '</span></div>' + defs +
          '</div></div></div>';
      });
      const selIdx = info.findIndex(x => x.code === st.sel);
      if (selIdx >= 0) {
        // 2 thẻ/hàng: bảng chi tiết chèn ngay sau hàng chứa thẻ được chọn
        const twoCols = $('cards').clientWidth >= 1130;
        const after = twoCols ? Math.min(cardHtml.length - 1, selIdx | 1) : selIdx;
        cardHtml.splice(after + 1, 0, detailHtml(info[selIdx], C));
      } else if (st.sel) st.sel = null;
      $('cards').innerHTML = info.length ? cardHtml.join('') : '<div class="bx mut" style="flex:1;text-align:center;padding:30px">Không có báo cáo OQC trong khoảng đã chọn.</div>';

      renderHieuQua(C);
      renderCfg(C);
    }

    // ---------- bảng chi tiết kết quả kiểm tra của 1 mã ----------
    function detailRows(x, C) {
      const rs = C.inD.filter(r => r.p === x.code).sort((a, b) => b.d.localeCompare(a.d) || String(b.gio).localeCompare(String(a.gio)) || b.id - a.id);
      const seen = {}; rs.slice().reverse().forEach(r => { const k = r.d + '|' + r.n; r.dup = !!seen[k]; seen[k] = true; });
      return rs;
    }
    function nguoiKiem(r) {
      const w = st.work[r.id];
      const extra = w && Array.isArray(w.labor) ? w.labor.filter(l => l && l.employee_code && l.employee_code !== r.maNguoi).map(l => l.employee_name || l.employee_code) : [];
      return [r.nguoi].concat(extra).filter(Boolean).join(', ');
    }
    function gioKiem(r) {
      const w = st.work[r.id];
      if (!w || !Array.isArray(w.labor) || !w.labor.length) return '';
      return String(Math.round(w.labor.reduce((s, l) => s + (Number(l.hours) || 0), 0) * 100) / 100).replace('.', ',');
    }
    function loiText(r) { return Object.entries(r.defs).sort((a, b) => b[1] - a[1]).map(([l, q]) => l + ' ' + q).join(', '); }
    function detailHtml(x, C) {
      const rs = detailRows(x, C);
      const outDays = {}; x.pts.forEach(p => { if (p.out) outDays[p.d] = p.ucl; });
      const T = C.agg(rs);
      const byD = {}; rs.forEach(r => (byD[r.d] = byD[r.d] || []).push(r));
      let body = '';
      Object.keys(byD).sort().reverse().forEach(d => {
        const list = byD[d];
        list.forEach(r => {
          body += '<tr class="' + (outDays[d] != null ? 'out' : '') + '"><td class="mono">' + dl(d) + '</td><td>' + esc(r.ca) + (r.lan ? ' · lần ' + r.lan : '') + '</td><td class="mono">' + esc(r.gio) + '</td>' +
            '<td>' + esc(nguoiKiem(r)) + '</td><td class="r mono">' + esc(gioKiem(r)) + '</td>' +
            '<td class="r mono">' + fn(r.n) + '</td><td class="r mono">' + fn(r.ok) + '</td><td class="r mono" style="font-weight:700">' + fn(r.ng) + '</td>' +
            '<td class="r mono ngp">' + fp(r.n ? r.ng / r.n : null, 2) + '</td>' +
            '<td style="white-space:normal;min-width:220px">' + esc(loiText(r)) + '</td>' +
            '<td class="mono">' + esc([r.lot, r.task].filter(Boolean).join(' / ')) + '</td>' +
            '<td style="white-space:normal;min-width:140px">' + esc(r.ghiChu) + (r.dup ? '<span class="tagd" title="Cùng ngày, cùng SL kiểm với phiếu khác">nghi trùng</span>' : '') + '</td></tr>';
        });
        if (list.length > 1) {
          const a = C.agg(list);
          body += '<tr class="sub' + (outDays[d] != null ? ' out' : '') + '"><td class="mono">' + dl(d) + '</td><td colspan="4">Cộng ngày (' + list.length + ' phiếu)</td><td class="r mono">' + fn(a.n) + '</td><td class="r mono">' + fn(list.reduce((s, r) => s + r.ok, 0)) + '</td><td class="r mono">' + fn(a.ng) + '</td><td class="r mono ngp">' + fp(a.ng / a.n, 2) + '</td><td colspan="3"></td></tr>';
        }
      });
      return '<div class="bx dt" data-o="detail" style="border:2px solid #1F5FBF;display:flex;flex-direction:column;gap:8px">' +
        '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 14px">' +
        '<h3><span class="mono">' + esc(x.code) + '</span> <span class="mut" style="font-weight:500">' + esc(x.name) + '</span> — kết quả kiểm tra ' + dl(C.days[0]) + ' → ' + dl(C.end) + '</h3>' +
        '<span class="mono mut">' + rs.length + ' phiếu · kiểm ' + fn(T.n) + ' · OK ' + fn(rs.reduce((s, r) => s + r.ok, 0)) + ' · NG ' + fn(T.ng) + ' · ' + fp(T.n ? T.ng / T.n : null, 2) + '</span>' +
        '<span style="flex:1"></span>' +
        '<button type="button" class="btn sm" data-act="xls">Xuất Excel</button>' +
        '<button type="button" class="btn sm" data-act="close" aria-label="Đóng bảng chi tiết">Đóng ✕</button></div>' +
        '<div style="overflow-x:auto;max-height:520px;overflow-y:auto"><table><thead><tr>' +
        '<th>Ngày</th><th>Ca</th><th>Giờ</th><th>Người kiểm</th><th class="r">Giờ kiểm</th><th class="r">SL kiểm</th><th class="r">OK</th><th class="r">NG</th><th class="r">NG%</th><th>Loại lỗi (pcs)</th><th>Lot / Task</th><th>Ghi chú</th>' +
        '</tr></thead><tbody>' + (body || '<tr><td colspan="12" class="mut" style="text-align:center;padding:20px">Không có phiếu</td></tr>') + '</tbody></table></div>' +
        '<div class="mut" style="font-size:11px">NG% đỏ = ngày vượt UCL. Giờ kiểm và người kiểm phụ chỉ có ở phiếu nhập bằng màn hình OQC mới.</div></div>';
    }
    async function loadWork(code) {
      const C = compute();
      const ids = C.inD.filter(r => r.p === code).map(r => r.id).filter(id => !(id in st.work));
      for (let i = 0; i < ids.length; i += 200) {
        const part = ids.slice(i, i + 200);
        const { data } = await sb.from('oqc_inspection_work').select('inspection_id,labor').in('inspection_id', part);
        part.forEach(id => { st.work[id] = null; });
        (data || []).forEach(w => { st.work[w.inspection_id] = w; });
      }
    }
    async function moChiTiet(code) {
      st.sel = st.sel === code ? null : code;
      render();
      if (!st.sel) return;
      const d = $('cards').querySelector('[data-o="detail"]');
      if (d && d.scrollIntoView) d.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      try { await loadWork(code); if (st.sel === code) render(); } catch (e) { /* giờ kiểm / người kiểm phụ không bắt buộc */ }
    }
    function xuatExcel() {
      if (!window.XLSX) return alert('Chưa tải thư viện Excel');
      const C = compute(); const x = C.info.find(i => i.code === st.sel); if (!x) return;
      const rs = detailRows(x, C);
      const aoa = [['Ngày', 'Ca', 'Giờ', 'Người kiểm', 'Giờ kiểm', 'SL kiểm', 'OK', 'NG', 'NG%', 'Loại lỗi (pcs)', 'Lot', 'Task', 'Ghi chú']]
        .concat(rs.map(r => [dl(r.d) + '/' + r.d.slice(0, 4), r.ca, r.gio, nguoiKiem(r), gioKiem(r), r.n, r.ok, r.ng, r.n ? Math.round(r.ng / r.n * 10000) / 100 : '', loiText(r), r.lot, r.task, r.ghiChu]));
      const ws = XLSX.utils.aoa_to_sheet(aoa); ws['!cols'] = [10, 8, 7, 28, 9, 9, 9, 8, 7, 50, 14, 14, 30].map(w => ({ wch: w }));
      const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, x.code.slice(0, 31));
      XLSX.writeFile(wb, 'OQC_' + x.code + '_' + C.days[0] + '_' + C.end + '.xlsx');
    }

    // ---------- T153: hiệu quả sơn theo lần sơn (chỉ phạm vi Sau Sơn) ----------
    function renderHieuQua(C) {
      const box = $('hieuqua');
      if (st.scope !== 'POST_PAINTING') { box.innerHTML = ''; return; }
      // Mọi lần sơn trong khoảng đã chọn (không theo ô "Lần sơn"), theo khách hàng đang lọc
      const rs = st.rows.filter(r => r.sc === 'POST_PAINTING' && r.d >= C.days[0] && r.d <= C.end && (!st.kh || khOf(r) === st.kh));
      const by = {};
      rs.forEach(r => {
        const m = by[r.p] || (by[r.p] = {});
        const v = m[r.lan] || (m[r.lan] = { n: 0, ng: 0 });
        v.n += r.n; v.ng += r.ng;
      });
      const tinh = m => {
        const l1 = m[1] || { n: 0, ng: 0 };
        let nLai = 0, okLai = 0, ok = 0, cho = 0;
        Object.keys(m).map(Number).forEach(L => {
          ok += m[L].n - m[L].ng;
          if (L >= 2) { nLai += m[L].n; okLai += m[L].n - m[L].ng; }
          cho += Math.max(0, m[L].ng - ((m[L + 1] || {}).n || 0)); // NG lần L chưa đem sơn lần L+1
        });
        return { n1: l1.n, ng1: l1.ng, p1: l1.n ? l1.ng / l1.n : null, fpy: l1.n ? (l1.n - l1.ng) / l1.n : null,
          nLai, okLai, cuu: nLai ? okLai / nLai : null, cho, dat: l1.n ? ok / l1.n : null };
      };
      const ma = Object.keys(by).sort();
      const tong = {};
      ma.forEach(p => Object.entries(by[p]).forEach(([L, v]) => { const t = tong[L] || (tong[L] = { n: 0, ng: 0 }); t.n += v.n; t.ng += v.ng; }));
      const dong = (ten, x, dam) => '<tr' + (dam ? ' class="sub"' : '') + '><td>' + ten + '</td>' +
        '<td class="r mono">' + fn(x.n1) + '</td><td class="r mono">' + fn(x.ng1) + '</td>' +
        '<td class="r mono" style="color:' + (x.p1 != null && x.p1 > C.gTarget ? RED : INK) + '">' + fp(x.p1) + '</td>' +
        '<td class="r mono">' + fp(x.fpy) + '</td><td class="r mono">' + fn(x.nLai) + '</td><td class="r mono">' + fn(x.okLai) + '</td>' +
        '<td class="r mono">' + fp(x.cuu) + '</td><td class="r mono" style="font-weight:700;color:' + (x.cho ? RED : INK) + '">' + fn(x.cho) + '</td>' +
        '<td class="r mono" style="font-weight:700">' + fp(x.dat) + '</td></tr>';
      box.innerHTML = '<div class="bx" style="display:flex;flex-direction:column;gap:6px">' +
        '<div style="display:flex;flex-wrap:wrap;align-items:baseline;gap:6px 12px"><h3 style="margin-right:auto">Hiệu quả sơn theo lần sơn — ' + dl(C.days[0]) + ' → ' + dl(C.end) + '</h3>' +
        '<span class="mut" style="font-size:11.5px">Tính mọi lần sơn trong khoảng, không theo ô "Lần sơn"</span></div>' +
        (ma.length ? '<div style="overflow-x:auto"><table><thead><tr><th>Mã</th>' +
          '<th class="r" title="Số kiểm hàng sơn mới">Kiểm lần 1</th><th class="r">NG lần 1</th><th class="r" title="NG lần 1 / Kiểm lần 1">% NG lần 1</th>' +
          '<th class="r" title="Tỷ lệ OK ngay lần đầu = OK lần 1 / Kiểm lần 1">OK ngay lần đầu</th>' +
          '<th class="r" title="Tổng số kiểm các lần sơn lại (lần 2+)">Đã sơn lại</th><th class="r">OK sau sơn lại</th>' +
          '<th class="r" title="OK sau sơn lại / Đã sơn lại">% sơn lại cứu được</th>' +
          '<th class="r" title="NG mỗi lần chưa đem sơn lần kế tiếp (trong khoảng)">NG chưa sơn lại</th>' +
          '<th class="r" title="(OK lần 1 + OK các lần sơn lại) / Kiểm lần 1">Tỷ lệ đạt cuối</th></tr></thead><tbody>' +
          ma.map(p => dong('<span class="mono" style="font-weight:700">' + esc(p) + '</span> <span class="mut">' + esc((st.prods[p] && st.prods[p].ten_sp) || '') + '</span>', tinh(by[p]))).join('') +
          (ma.length > 1 ? dong('Tổng ' + ma.length + ' mã', tinh(tong), true) : '') +
          '</tbody></table></div>' : '<div class="mut" style="padding:12px 0;text-align:center">Không có phiếu sau sơn trong khoảng đã chọn.</div>') +
        '<div class="mut" style="font-size:11px">Sơn lại thường làm sau vài ngày: NG cuối khoảng có thể chưa kịp sơn lại — xem khoảng dài (≥ 1 tháng) để đánh giá. Phiếu sau sơn cũ chưa ghi lần sơn được tính là lần 1.</div></div>';
    }

    // ---------- bảng CL & mục tiêu ----------
    function renderCfg(C) {
      const box = $('cfg');
      box.style.display = st.cfgOpen ? '' : 'none';
      if (!st.cfgOpen) return;
      const codes = [...new Set(C.all.map(r => r.p).concat(Object.keys(st.cfg).filter(k => k !== '*')))].sort();
      const ro = st.canEdit ? '' : ' disabled';
      const g = st.cfg['*'] || {};
      box.innerHTML = '<div class="bx" style="display:flex;flex-direction:column;gap:8px">' +
        '<div style="display:flex;flex-wrap:wrap;align-items:center;gap:8px 14px"><h3 style="margin-right:auto">Mức thường (CL) &amp; mục tiêu NG</h3>' +
        (st.canEdit ? '' : '<span class="mut">Chỉ QC Manager / admin được sửa</span>') +
        '<label style="display:inline-flex;align-items:center;gap:6px;font-weight:600">Mục tiêu chung <input class="mono" data-in="mt|*" value="' + (g.muc_tieu != null ? f1(Number(g.muc_tieu)) : '') + '" style="width:64px;text-align:right"' + ro + '>%</label>' +
        '<button type="button" class="btn p sm" data-act="mt" data-ma="*"' + ro + '>Lưu</button></div>' +
        '<div style="overflow-x:auto"><table style="min-width:900px"><thead><tr><th>Mã</th><th>Tên</th><th class="r">CL hiện tại</th><th>Đặt bởi</th><th class="r">TB 4 tuần</th><th class="r">CL mới</th><th></th><th class="r">Mục tiêu riêng</th><th></th></tr></thead><tbody>' +
        codes.map(code => {
          const c = st.cfg[code] || {};
          const a = C.agg(C.all.filter(r => r.p === code && r.d >= C.avgFrom && r.d <= C.end));
          const avg = a.n ? a.ng / a.n : null;
          return '<tr><td class="mono" style="font-weight:700">' + esc(code) + '</td><td class="mut">' + esc((st.prods[code] && st.prods[code].ten_sp) || '') + '</td>' +
            '<td class="r mono" style="font-weight:700;color:' + (c.cl != null ? INK : RED) + '">' + (c.cl != null ? fp(Number(c.cl), 2) : 'chưa đặt') + '</td>' +
            '<td class="mut">' + esc(c.cl_nguoi || '—') + (c.cl_luc ? ' · ' + new Date(c.cl_luc).toLocaleDateString('vi-VN') : '') + '</td>' +
            '<td class="r mono mut">' + fp(avg, 2) + (a.n ? ' <span style="font-size:10.5px">(' + fn(a.n) + ')</span>' : '') + '</td>' +
            '<td class="r"><input class="mono" data-in="cl|' + esc(code) + '" placeholder="' + (avg != null ? f1(avg) : '') + '" style="width:64px;text-align:right"' + ro + '></td>' +
            '<td><button type="button" class="btn sm' + (c.cl == null ? ' p' : '') + '" data-act="cl" data-ma="' + esc(code) + '"' + ro + '>' + (c.cl == null ? 'Đặt CL' : 'Đặt lại') + '</button></td>' +
            '<td class="r"><input class="mono" data-in="mt|' + esc(code) + '" value="' + (c.muc_tieu != null ? f1(Number(c.muc_tieu)) : '') + '" placeholder="chung" style="width:64px;text-align:right"' + ro + '></td>' +
            '<td><button type="button" class="btn sm" data-act="mt" data-ma="' + esc(code) + '"' + ro + '>Lưu</button></td></tr>';
        }).join('') + '</tbody></table></div>' +
        '<div class="mut" style="font-size:11px">CL mới để trống = lấy TB 4 tuần (số mờ trong ô). Mục tiêu riêng để trống = dùng mục tiêu chung.</div></div>';
    }

    async function luu(loai, ma) {
      const inp = el.querySelector('[data-in="' + (loai === 'cl' ? 'cl' : 'mt') + '|' + ma + '"]');
      let v = parsePct(inp.value);
      if (loai === 'cl' && v === null && inp.placeholder) v = parsePct(inp.placeholder);
      if (Number.isNaN(v) || (v != null && (v < 0 || v >= 1))) return alert('Nhập % hợp lệ (0–100), dùng dấu phẩy hoặc chấm.');
      if (loai === 'cl' && v == null) return alert('Nhập CL (%)');
      let lyDo = null;
      const cur = st.cfg[ma] || {};
      if (loai === 'cl' && cur.cl != null && Number(cur.cl) !== v) {
        lyDo = prompt('CL của ' + ma + ' đang khoá ở ' + fp(Number(cur.cl), 2) + '. Lý do đặt lại thành ' + fp(v, 2) + ':');
        if (lyDo == null) return;
      }
      const { data, error } = await sb.rpc('oqc_ng_dat', { p_ma_sp: ma, p_loai: loai, p_gia_tri: v, p_ly_do: lyDo });
      if (error) return alert('Lỗi: ' + error.message);
      if (data && data.ok === false) return alert(data.error);
      await loadCfg();
      render();
      setMsg('✓ Đã lưu ' + (loai === 'cl' ? 'CL ' : 'mục tiêu ') + (ma === '*' ? 'chung' : ma), 'ok');
      setTimeout(() => setMsg(null), 2500);
    }

    el.addEventListener('keydown', e => {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.dataset && e.target.dataset.card) { e.preventDefault(); moChiTiet(e.target.dataset.card); }
    });
    el.addEventListener('change', e => {
      const k = e.target.dataset && e.target.dataset.k; if (!k) return;
      if (k === 'start' || k === 'end') {
        if (!e.target.value) return;
        const tu = k === 'start' ? e.target.value : st.start, den = k === 'end' ? e.target.value : st.end;
        // Chọn ngược (Từ sau Đến) thì tự đảo lại cho đúng thứ tự
        datKhoang(tu <= den ? tu : den, tu <= den ? den : tu);
      }
      else if (k === 'kh') { st.kh = e.target.value; render(); }
      else if (k === 'scope') { st.scope = e.target.value; st.sel = null; $('lanbox').hidden = st.scope !== 'POST_PAINTING'; fillKh(); render(); }
      else if (k === 'lan') { st.lan = e.target.value; st.sel = null; render(); }
    });
    el.addEventListener('click', e => {
      const b = e.target.closest('[data-act]');
      if (!b) { const cd = e.target.closest('[data-card]'); if (cd) moChiTiet(cd.dataset.card); return; }
      if (b.disabled) return;
      const a = b.dataset.act;
      if (a === 'cfg') { st.cfgOpen = !st.cfgOpen; b.classList.toggle('on', st.cfgOpen); render(); }
      else if (a === 'close') { st.sel = null; render(); }
      else if (a === 'xls') xuatExcel();
      else if (a === 'preset') {
        const p = PRESETS.find(x => x.k === b.dataset.p);
        if (p) { const [tu, den] = p.f(st.end, ymd(new Date())); datKhoang(tu, den); }
      }
      else if (a === 'p7') { st.pareto = '7'; render(); }
      else if (a === 'pall') { st.pareto = 'all'; render(); }
      else if (a === 'cl' || a === 'mt') luu(a === 'cl' ? 'cl' : 'muc_tieu', b.dataset.ma);
    });

    await taiLai();
    return { taiLai };
  }

  window.OqcNgDash = { mount };
})();
