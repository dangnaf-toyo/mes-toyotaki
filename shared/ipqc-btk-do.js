/**
 * ============================================================================
 * ipqc-btk-do.js — T133: khung "Kích thước — bảng tuần kiểm" trên ipqc.html.
 * Mã có bảng tuần kiểm (ipqc_btk đang dùng) → IPQC nhập giá trị đo từng hạng
 * mục (so_mau ô / hạng mục số), OK/NG cho hạng mục lắp ghép...; tự phán định
 * theo dung sai, báo "sát giới hạn" và vi phạm quy tắc biểu đồ kiểm soát
 * (chỉ báo, không bắt buộc chọn Cảnh báo). Mục checklist "Kích thước (theo bảng
 * tuần kiểm)" lấy kết quả từ đây (onChange). Lưu bằng RPC ipqc_do_luu TRƯỚC
 * duc_submit_ipqc_session.
 *   const ctl = await IpqcBtkDo.mount(el, cp, { onChange: s => ... });  // null = mã chưa có bảng
 *   ctl.trangThai() → { du: bool, dat: bool|null }
 *   await ctl.luu(idCheckpoint, nguoi)
 * Cần shared/ipqc-spc.js.
 * ============================================================================
 */
(function () {
  const S = () => window.IpqcSpc;
  const esc = s => S().esc(s);

  function css() {
    if (document.getElementById('btkdo-css')) return;
    const st = document.createElement('style'); st.id = 'btkdo-css';
    st.textContent =
      '.btkdo{display:flex;flex-direction:column;gap:.55rem;margin:.6rem 0}' +
      '.btkdo .hd{display:flex;align-items:center;gap:.6rem;background:#fff;border:1px solid #D9DFE5;border-radius:.75rem;padding:.55rem .7rem}' +
      '.btkdo .hd .th{width:4.6rem;height:3.2rem;border-radius:.45rem;border:1px solid #CBD5E1;background:#F8FAFC center/contain no-repeat;flex:none;cursor:zoom-in}' +
      '.btkdo .hd .t{font-weight:800;font-size:.92rem}.btkdo .hd .s{font-size:.75rem;color:#64748B}' +
      '.btkdo .it{background:#fff;border:1.5px solid #D9DFE5;border-radius:.75rem;padding:.55rem .7rem;display:flex;flex-direction:column;gap:.4rem}' +
      '.btkdo .it.ng{border-color:#DC2626;background:#FEF2F2}.btkdo .it.sat{border-color:#F59E0B}' +
      '.btkdo .r1{display:flex;align-items:flex-start;gap:.5rem}' +
      '.btkdo .no{width:1.55rem;height:1.55rem;border-radius:50%;background:#DC2626;color:#fff;font-weight:800;font-size:.78rem;display:flex;align-items:center;justify-content:center;flex:none}' +
      '.btkdo .nm{font-weight:700;font-size:.88rem;line-height:1.25}.btkdo .nm b{font-family:"JetBrains Mono",monospace}' +
      '.btkdo .sub{font-size:.72rem;color:#64748B}' +
      '.btkdo .vals{display:flex;flex-wrap:wrap;gap:.4rem;align-items:center}' +
      '.btkdo .vals input{width:6.6rem;font-family:"JetBrains Mono",monospace;font-size:1.15rem;font-weight:700;padding:.45rem .55rem;border:2px solid #CBD5E1;border-radius:.55rem;height:2.8rem;box-sizing:border-box}' +
      '.btkdo .vals input.ng{border-color:#DC2626;color:#991B1B}.btkdo .vals input.sat{border-color:#F59E0B}.btkdo .vals input.ok{border-color:#16A34A}' +
      '.btkdo .pill{font-size:.75rem;font-weight:800;padding:.2rem .55rem;border-radius:1rem}' +
      '.btkdo .pill.ok{background:#DCFCE7;color:#166534}.btkdo .pill.ng{background:#FEE2E2;color:#991B1B}.btkdo .pill.sat{background:#FEF3C7;color:#92400E}' +
      '.btkdo .ls{font-size:.72rem;color:#475569;display:flex;gap:.4rem;flex-wrap:wrap}.btkdo .ls span.m{font-family:"JetBrains Mono",monospace}' +
      '.btkdo .ls .xh{margin-left:auto;font-weight:700}' +
      '.btkdo .okng{display:flex;gap:.5rem}.btkdo .okng button{flex:1;height:2.6rem;border-radius:.55rem;border:1.5px solid #CBD5E1;background:#fff;font-weight:800;font-size:.9rem;font-family:inherit}' +
      '.btkdo .okng button.on.ok{background:#047857;border-color:#047857;color:#fff}.btkdo .okng button.on.ng{background:#DC2626;border-color:#DC2626;color:#fff}' +
      '.btkdo .tong{border-radius:.75rem;padding:.55rem .7rem;font-size:.8rem;display:flex;flex-direction:column;gap:.25rem}' +
      '.btkdo .tong.ng{background:#FEF2F2;border:1.5px solid #FCA5A5;color:#7F1D1D}.btkdo .tong.ok{background:#ECFDF5;border:1.5px solid #A7E3C6;color:#065F46}' +
      '.btkdo .tong.cho{background:#F8FAFC;border:1.5px dashed #CBD5E1;color:#475569}.btkdo .tong .w{color:#92400E}.btkdo .tong b{font-size:.88rem}' +
      '.btkdo-bv{position:fixed;inset:0;background:rgba(15,23,42,.85);z-index:9999;overflow:auto;display:flex;flex-direction:column;align-items:center;padding:1rem}' +
      '.btkdo-bv .wrap{position:relative;max-width:100%;background:#fff}.btkdo-bv img{display:block;max-width:100%}' +
      '.btkdo-bv .b{position:absolute;transform:translate(-50%,-50%);width:1.7rem;height:1.7rem;border-radius:50%;background:#DC2626;color:#fff;font-weight:800;display:flex;align-items:center;justify-content:center;font-size:.85rem;border:2px solid #fff}' +
      '.btkdo-bv button{margin-top:.8rem;padding:.6rem 1.4rem;border:0;border-radius:.6rem;font-weight:800;font-size:.95rem}';
    document.head.appendChild(st);
  }

  function xemBanVe(url, viTri) {
    const d = document.createElement('div'); d.className = 'btkdo-bv';
    d.innerHTML = '<div class="wrap"><img src="' + esc(url) + '" alt="Bản vẽ vị trí đo">' +
      (viTri || []).map(v => '<span class="b" style="left:' + (+v.x) + '%;top:' + (+v.y) + '%">' + esc(v.no) + '</span>').join('') +
      '</div><button type="button">Đóng</button>';
    d.querySelector('button').onclick = () => d.remove();
    document.body.appendChild(d);
  }

  async function mount(el, cp, opt) {
    css();
    // Khung con mới mỗi lần mở điểm kiểm (không cộng dồn bộ xử lý sự kiện).
    const root = document.createElement('div');
    el.replaceChildren(root); el.classList.add('hidden');
    // T183: điểm kiểm IPQC Đúc → bảng tuần kiểm công đoạn Đúc.
    const { data, error } = await sb.rpc('ipqc_do_du_lieu', { p_ma_sp: cp.ma_sp, p_tu: null, p_den: null, p_so_lan: 30, p_cong_doan: 'duc' });
    if (error || !data || !data.btk) return null;
    const btk = data.btk, mucs = data.muc || [], soMau = btk.so_mau || 1;
    const nhap = {};   // muc_no -> [giá trị chuỗi] | true/false
    mucs.forEach(m => { nhap[m.muc_no] = m.kieu === 'so' ? new Array(soMau).fill('') : null; });
    const lichSu = {};
    mucs.filter(m => m.kieu === 'so').forEach(m => {
      const pts = S().chuoi(data, m.muc_no);
      lichSu[m.muc_no] = { pts, lim: S().gioiHan(data, m.muc_no, soMau, pts) };
    });

    function danhGia() {
      const kq = [];
      let du = true, dat = true;
      mucs.forEach(m => {
        const sp = S().specMuc(m);
        const r = { m, sp, trangThai: 'cho', canhBao: [], vals: [] };
        if (m.kieu === 'so') {
          const vs = nhap[m.muc_no].map(v => v === '' ? null : Number(String(v).replace(',', '.')));
          r.vals = vs;
          if (vs.some(v => v === null || !isFinite(v))) du = false;
          const co = vs.filter(v => v !== null && isFinite(v));
          if (co.length) {
            const ng = co.filter(v => S().datGiaTri(v, sp) === false);
            if (ng.length) { r.trangThai = 'ng'; dat = false; }
            else if (co.some(v => S().satGioiHan(v, sp))) r.trangThai = 'sat';
            else r.trangThai = co.length === soMau ? 'ok' : 'cho';
            if (co.length === soMau) {
              const ls = lichSu[m.muc_no];
              const x = co.reduce((s, v) => s + v, 0) / co.length;
              const xs = ls.pts.map(p => p.x).concat([x]);
              S().quyTac(xs, ls.lim).filter(v => v.i === xs.length - 1).forEach(v => r.canhBao.push(v.msg + (ls.lim && ls.lim.tam ? ' (giới hạn tạm)' : '')));
            }
          }
        } else {
          if (nhap[m.muc_no] === null) du = false;
          else { r.trangThai = nhap[m.muc_no] ? 'ok' : 'ng'; if (!nhap[m.muc_no]) dat = false; }
        }
        kq.push(r);
      });
      return { du, dat: du ? dat : (dat ? null : false), kq };
    }

    function render() {
      const dg = danhGia();
      const tren = '<div class="hd">' +
        (btk.ban_ve_url ? '<div class="th" data-bv style="background-image:url(\'' + esc(btk.ban_ve_url) + '\')" role="button" aria-label="Xem bản vẽ vị trí đo"></div>' : '') +
        '<div><div class="t">📐 Kích thước — bảng tuần kiểm ' + esc(btk.phien_ban) + '</div><div class="s">' +
        (btk.ban_ve_url ? 'Chạm bản vẽ để xem vị trí đo · ' : '') + soMau + ' mẫu / lần · ' + esc(btk.tan_suat || '') + '</div></div></div>';
      const items = dg.kq.map(r => {
        const m = r.m, d = S().soLe(m);
        if (m.kieu !== 'so') {
          return '<div class="it' + (r.trangThai === 'ng' ? ' ng' : '') + '"><div class="r1"><span class="no">' + m.muc_no + '</span><div><div class="nm">' + esc(m.hang_muc) + '</div>' +
            '<div class="sub">' + esc(m.tieu_chuan || '') + (m.dung_cu ? ' · ' + esc(m.dung_cu) : '') + '</div></div></div>' +
            '<div class="okng"><button type="button" class="ok' + (nhap[m.muc_no] === true ? ' on' : '') + '" data-ok="' + m.muc_no + '">OK</button>' +
            '<button type="button" class="ng' + (nhap[m.muc_no] === false ? ' on' : '') + '" data-ng="' + m.muc_no + '">NG</button></div></div>';
        }
        const ls = lichSu[m.muc_no];
        const truoc = ls.pts.slice(-4).map(p => S().fmt(p.x, d)).join(' ');
        const xs = ls.pts.slice(-5).map(p => p.x);
        const xh = xs.length >= 4 ? (xs.every((v, i) => !i || v > xs[i - 1]) ? 'Tăng dần' : xs.every((v, i) => !i || v < xs[i - 1]) ? 'Giảm dần' : '') : '';
        const gh = (r.sp.lsl !== null ? S().fmt(r.sp.lsl, d) : '—') + ' – ' + (r.sp.usl !== null ? S().fmt(r.sp.usl, d) : '—');
        return '<div class="it' + (r.trangThai === 'ng' ? ' ng' : r.trangThai === 'sat' ? ' sat' : '') + '" data-it="' + m.muc_no + '">' +
          '<div class="r1"><span class="no">' + m.muc_no + '</span><div><div class="nm">' + esc(m.hang_muc) + ' <b>' + esc(S().chuanText(m)) + '</b></div>' +
          '<div class="sub">' + (m.dung_cu ? esc(m.dung_cu) + ' · ' : '') + 'giới hạn ' + gh + '</div></div></div>' +
          '<div class="vals">' + nhap[m.muc_no].map((v, i) => {
            const n = v === '' ? null : Number(String(v).replace(',', '.'));
            const c = n === null || !isFinite(n) ? '' : S().datGiaTri(n, r.sp) === false ? 'ng' : S().satGioiHan(n, r.sp) ? 'sat' : 'ok';
            return '<input type="text" inputmode="decimal" autocomplete="off" class="' + c + '" data-v="' + m.muc_no + ':' + i + '" value="' + esc(v) + '" placeholder="' + (soMau > 1 ? 'Mẫu ' + (i + 1) : S().fmt(+m.danh_nghia, d)) + '" aria-label="Giá trị đo hạng mục ' + m.muc_no + (soMau > 1 ? ' mẫu ' + (i + 1) : '') + '">';
          }).join('') + '<span data-pill>' + pill(r) + '</span></div>' +
          (truoc ? '<div class="ls"><span>' + Math.min(4, ls.pts.length) + ' lần trước:</span><span class="m">' + truoc + '</span>' + (xh ? '<span class="xh" style="color:#92400E">' + xh + '</span>' : '') + '</div>' : '') +
          '</div>';
      }).join('');
      root.innerHTML = '<div class="btkdo">' + tren + items + '<div data-tong>' + tongHtml(dg) + '</div></div>';
      if (opt && opt.onChange) opt.onChange({ du: dg.du, dat: dg.dat });
    }
    function pill(r) {
      return r.trangThai === 'ng' ? '<span class="pill ng">NG' + nguoc(r) + '</span>'
        : r.trangThai === 'sat' ? '<span class="pill sat">Sát giới hạn</span>' : r.trangThai === 'ok' ? '<span class="pill ok">OK</span>' : '';
    }
    function nguoc(r) {
      const v = r.vals.find(x => x !== null && S().datGiaTri(x, r.sp) === false);
      if (v === undefined) return '';
      const d = S().soLe(r.m);
      return r.sp.usl !== null && v > r.sp.usl ? ' +' + (v - r.sp.usl).toFixed(d) : r.sp.lsl !== null ? ' −' + (r.sp.lsl - v).toFixed(d) : '';
    }
    function tongHtml(dg) {
      const ngs = dg.kq.filter(r => r.trangThai === 'ng'), sats = dg.kq.filter(r => r.trangThai === 'sat'), cbs = dg.kq.filter(r => r.canhBao.length);
      const tong = !dg.du && !ngs.length ? '<div class="tong cho">Nhập đủ kết quả đo các hạng mục để tự đánh giá mục "Kích thước".</div>'
        : '<div class="tong ' + (ngs.length ? 'ng' : 'ok') + '"><b>Kết quả bảng tuần kiểm: ' + (ngs.length ? 'NG' : dg.du ? 'OK' : '…') + '</b>' +
          ngs.map(r => '<div>Hạng mục ' + r.m.muc_no + ' (' + esc(r.m.hang_muc) + ') ngoài tiêu chuẩn ' + esc(S().chuanText(r.m)) + '.</div>').join('') +
          sats.map(r => '<div class="w">Hạng mục ' + r.m.muc_no + ' sát giới hạn tiêu chuẩn.</div>').join('') +
          cbs.map(r => '<div class="w">Hạng mục ' + r.m.muc_no + ': ' + esc(r.canhBao.join('; ')) + ' — báo QC Manager.</div>').join('') +
          '</div>';
      return tong;
    }
    // Gõ số: chỉ cập nhật màu ô, nhãn, khung tổng (không vẽ lại để giữ bàn phím).
    function capNhat(input) {
      const dg = danhGia();
      const no = +input.dataset.v.split(':')[0];
      const r = dg.kq.find(x => x.m.muc_no === no);
      const v = input.value.trim() === '' ? null : Number(input.value.trim().replace(',', '.'));
      input.className = v === null || !isFinite(v) ? '' : S().datGiaTri(v, r.sp) === false ? 'ng' : S().satGioiHan(v, r.sp) ? 'sat' : 'ok';
      const it = root.querySelector('[data-it="' + no + '"]');
      if (it) {
        it.classList.toggle('ng', r.trangThai === 'ng'); it.classList.toggle('sat', r.trangThai === 'sat');
        it.querySelector('[data-pill]').innerHTML = pill(r);
      }
      root.querySelector('[data-tong]').innerHTML = tongHtml(dg);
      if (opt && opt.onChange) opt.onChange({ du: dg.du, dat: dg.dat });
    }

    root.addEventListener('input', e => {
      const i = e.target.closest('input[data-v]'); if (!i) return;
      const [no, k] = i.dataset.v.split(':').map(Number);
      nhap[no][k] = i.value.trim();
      capNhat(i);
    });
    root.addEventListener('click', e => {
      const ok = e.target.closest('[data-ok]'), ng = e.target.closest('[data-ng]'), bv = e.target.closest('[data-bv]');
      if (ok) { const n = +ok.dataset.ok; nhap[n] = nhap[n] === true ? null : true; render(); }
      if (ng) { const n = +ng.dataset.ng; nhap[n] = nhap[n] === false ? null : false; render(); }
      if (bv) xemBanVe(btk.ban_ve_url, btk.ban_ve_vi_tri);
    });

    el.classList.remove('hidden');
    render();
    return {
      btk,
      trangThai() { const d = danhGia(); return { du: d.du, dat: d.dat }; },
      async luu(idCheckpoint, nguoi) {
        const kq = [];
        mucs.forEach(m => {
          if (m.kieu === 'so') nhap[m.muc_no].forEach((v, i) => kq.push({ muc_no: m.muc_no, mau: i + 1, gia_tri: String(v).replace(',', '.') }));
          else kq.push({ muc_no: m.muc_no, mau: 1, dat: nhap[m.muc_no] });
        });
        const { data: r, error: e } = await sb.rpc('ipqc_do_luu', { p_id_checkpoint: idCheckpoint, p_kq: kq, p_nguoi: nguoi });
        if (e) throw new Error(e.message);
        if (!r || !r.ok) throw new Error((r && r.error) || 'Không lưu được kết quả đo kích thước');
        return r;
      },
    };
  }

  window.IpqcBtkDo = { mount };
})();
