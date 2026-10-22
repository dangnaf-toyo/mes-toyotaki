/* T141: tiện ích hiển thị dùng chung cho ipqc.html / qc-manager.html —
   định dạng thời lượng, thông báo lỗi dễ hiểu, đóng điểm kiểm tồn đọng. */
const MesQcUi = (() => {
  const TON_PHUT = 24 * 60; // chờ quá 24 giờ = tồn đọng
  const BAT_THUONG_GIAY = 2 * 3600; // 1 lần kiểm > 2 giờ = bất thường
  const RPC_DONG_TON = "duc_ipqc_dong_diem_kiem_ton";
  const esc = (s) =>
    String(s == null ? "" : s).replace(
      /[&<>"']/g,
      (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
    );

  /* <60 phút → "x phút"; <24 giờ → "x giờ y phút"; ≥24 giờ → "x ngày y giờ". */
  function thoiLuong(phut) {
    if (phut == null || phut === "" || !Number.isFinite(Number(phut))) return "—";
    const n = Math.max(0, Math.round(Number(phut)));
    if (n < 60) return n + " phút";
    if (n < 1440) {
      const h = Math.floor(n / 60),
        m = n % 60;
      return h + " giờ" + (m ? " " + m + " phút" : "");
    }
    const d = Math.floor(n / 1440),
      h = Math.floor((n % 1440) / 60);
    return d + " ngày" + (h ? " " + h + " giờ" : "");
  }
  /* Thời lượng tính bằng giây (thời gian kiểm): dưới 1 giờ giữ cả giây. */
  function thoiLuongGiay(giay) {
    const s = Number(giay);
    if (!Number.isFinite(s) || s <= 0) return "—";
    if (s < 60) return Math.round(s) + " giây";
    if (s < 3600) {
      const m = Math.floor(s / 60),
        r = Math.round(s % 60);
      return m + " phút" + (r ? " " + r + " giây" : "");
    }
    return thoiLuong(s / 60);
  }
  const batThuong = (giay) => Number(giay) > BAT_THUONG_GIAY;
  const TIP_BAT_THUONG =
    "Một lần kiểm thường chỉ vài phút. Thời gian trên 2 giờ thường là do bấm “Bắt đầu kiểm tra” rồi để đó " +
    "(chuyển máy khác, hết ca, đóng trình duyệt) và quay lại nộp sau — phiên kiểm vẫn tính giờ liên tục. " +
    "Không nên dùng con số này để đánh giá tốc độ kiểm.";
  function thoiGianKiemHtml(giay) {
    const txt = esc(thoiLuongGiay(giay));
    if (!batThuong(giay)) return txt;
    return (
      '<span class="qcui-batthuong" title="' +
      esc(TIP_BAT_THUONG) +
      '">' +
      txt +
      ' <span class="qcui-tag">bất thường</span></span>'
    );
  }

  /* Thông báo lỗi: câu dễ hiểu + chi tiết kỹ thuật để riêng. */
  function loi(e, truoc) {
    const code = String(e?.code || ""),
      msg = String(e?.message || e || "Không có phản hồi từ máy chủ"),
      detail = [code, msg, e?.details, e?.hint].filter(Boolean).join(" — ");
    let text;
    if (
      ["PGRST202", "PGRST205", "42883", "42P01", "42703"].includes(code) ||
      /could not find the function|does not exist|schema cache/i.test(msg)
    )
      text = "Máy chủ chưa cập nhật chức năng này (thiếu bản cập nhật cơ sở dữ liệu). Báo quản trị hệ thống.";
    else if (code === "42501" || e?.status === 403 || /permission denied|row-level security|42501/i.test(msg))
      text =
        "Tài khoản của bạn chưa được cấp quyền cho thao tác/dữ liệu này. Nếu bạn là IPQC hoặc QC, nhờ quản trị cấp quyền rồi thử lại.";
    else if (
      ["NOT_AUTHENTICATED", "PGRST301", "PGRST303"].includes(code) ||
      /jwt|not authenticated|cần đăng nhập/i.test(msg)
    )
      text = "Phiên đăng nhập đã hết hạn hoặc chưa đăng nhập. Hãy đăng nhập lại MES rồi thử lại.";
    else if (/failed to fetch|fetch failed|network|timeout|timed out/i.test(msg))
      text = "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.";
    else if (/[À-ỹ]/.test(msg) && !/[a-z_]+\.[a-z_]+|relation|column|function|syntax/i.test(msg))
      text = msg; // thông báo nghiệp vụ tiếng Việt từ máy chủ — đã dễ hiểu
    else text = "Có lỗi khi xử lý yêu cầu. Thử lại; nếu vẫn lỗi, báo quản trị kèm chi tiết bên dưới.";
    if (truoc) text = truoc.replace(/[.\s]*$/, ". ") + text;
    return { text, detail };
  }
  function loiHtml(e, truoc) {
    const r = loi(e, truoc);
    return (
      '<div class="qcui-loi"><div>' +
      esc(r.text) +
      "</div>" +
      (r.detail && r.detail !== r.text
        ? "<details><summary>Chi tiết kỹ thuật</summary><code>" + esc(r.detail) + "</code></details>"
        : "") +
      "</div>"
    );
  }

  const css = document.createElement("style");
  css.textContent = `
.qcui-tag{display:inline-block;padding:1px 6px;border-radius:9px;background:#FEF3C7;color:#92400E;font:600 11px Inter,sans-serif;margin-left:4px;white-space:nowrap}
.qcui-batthuong{cursor:help;color:#B45309}
.qcui-loi{font-size:13px;line-height:1.45;color:#991B1B}
.qcui-loi details{margin-top:4px;color:#475569;font-size:12px}
.qcui-loi summary{cursor:pointer;font-weight:600}
.qcui-loi code{display:block;margin-top:3px;white-space:pre-wrap;word-break:break-word;font:12px 'JetBrains Mono',monospace}
.qcui-dlg{border:0;border-radius:10px;padding:0;margin:auto;width:min(640px,94vw);max-height:90vh;box-shadow:0 12px 32px rgba(15,23,42,.25);font-family:Inter,sans-serif;color:#0F172A}
.qcui-dlg::backdrop{background:rgba(15,23,42,.5)}
.qcui-dlg form{display:flex;flex-direction:column;max-height:90vh}
.qcui-dlg .hd{padding:14px 18px;border-bottom:1px solid #D9DFE5;font-weight:700;font-size:15px}
.qcui-dlg .bd{padding:12px 18px;overflow:auto;display:flex;flex-direction:column;gap:10px;font-size:13px}
.qcui-dlg .ft{padding:12px 18px;border-top:1px solid #D9DFE5;display:flex;justify-content:flex-end;gap:8px;flex-wrap:wrap}
.qcui-dlg .ds{border:1px solid #D9DFE5;border-radius:8px;max-height:40vh;overflow:auto}
.qcui-dlg .ds label{display:flex;gap:8px;align-items:center;padding:7px 10px;border-bottom:1px solid #EEF1F5;cursor:pointer;font-size:13px}
.qcui-dlg .ds label:last-child{border-bottom:0}
.qcui-dlg .ds .t{margin-left:auto;font-family:'JetBrains Mono',monospace;color:#B91C1C;font-size:12px;white-space:nowrap}
.qcui-dlg textarea{width:100%;min-height:64px;padding:8px 10px;border:1px solid #B8C1CC;border-radius:6px;font:13px Inter,sans-serif;resize:vertical}
.qcui-dlg .b{min-height:34px;padding:6px 14px;border-radius:6px;font:600 13px Inter,sans-serif;cursor:pointer;border:1px solid #B8C1CC;background:#fff;color:#0F172A}
.qcui-dlg .b.do{background:#B91C1C;border-color:#B91C1C;color:#fff}
.qcui-dlg .b:disabled{opacity:.5;cursor:not-allowed}
.qcui-dlg .note{color:#64748B;font-size:12px}
.qcui-dlg .err{color:#B91C1C}
`;
  document.head.append(css);

  /* Vai trò tài khoản hiện tại (RLS user_roles cho đọc dòng của chính mình). */
  let rolePromise = null;
  function vaiTro() {
    if (!rolePromise)
      rolePromise = (async () => {
        try {
          const auth = await MesAuth.getSession();
          if (!auth?.user?.id) return null;
          const r = await sb.from("user_roles").select("role").eq("user_id", auth.user.id).maybeSingle();
          return r.data?.role || null;
        } catch {
          return null;
        }
      })();
    return rolePromise;
  }
  /* Đóng được tồn đọng: admin/qc_manager + RPC T141 đã có trên máy chủ.
     Trả { duoc, ly_do } — ly_do để hiện ghi chú khi khoá nút. */
  let quyenDongPromise = null;
  function quyenDongTon() {
    if (!quyenDongPromise)
      quyenDongPromise = (async () => {
        const role = await vaiTro();
        if (!["admin", "qc_manager"].includes(role))
          return { duoc: false, an: true, ly_do: "Chỉ QC Manager hoặc admin được đóng điểm kiểm tồn đọng." };
        // Thăm dò: mảng rỗng → hàm có sẵn sẽ báo lỗi nghiệp vụ, không thay đổi dữ liệu.
        const r = await sb.rpc(RPC_DONG_TON, { p_ids: [], p_ly_do: "", p_nguoi: null });
        const code = String(r.error?.code || ""),
          msg = String(r.error?.message || "");
        if (["PGRST202", "42883"].includes(code) || /could not find the function|does not exist/i.test(msg))
          return {
            duoc: false,
            ly_do: "Chức năng đóng tồn đọng chưa bật trên máy chủ (cần chạy migration T141).",
          };
        return { duoc: true };
      })();
    return quyenDongPromise;
  }

  /* Nút + ghi chú "Đóng điểm kiểm tồn đọng" gắn vào container.
     items: [{ id_checkpoint, ma_may, ma_sp, loai, phut }] — chỉ điểm kiểm thật. */
  async function ganNutDongTon(container, items, onDone) {
    if (!container) return;
    const q = await quyenDongTon();
    container.replaceChildren();
    if (q.an) return;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "qcui-btn-dong";
    btn.textContent = "Đóng điểm kiểm tồn đọng…";
    btn.disabled = !q.duoc || !items.length;
    container.append(btn);
    const note = document.createElement("span");
    note.className = "qcui-note";
    note.textContent = !q.duoc
      ? q.ly_do
      : items.length
        ? ""
        : "Không có điểm kiểm thật nào để đóng (điểm định kỳ tự tính sẽ tự hết khi máy được kiểm hoặc kết ca).";
    if (note.textContent) container.append(note);
    btn.onclick = () => moHopDongTon(items, onDone);
  }

  function moHopDongTon(items, onDone) {
    const dlg = document.createElement("dialog");
    dlg.className = "qcui-dlg";
    dlg.innerHTML =
      '<form method="dialog"><div class="hd">Đóng điểm kiểm tồn đọng</div><div class="bd">' +
      '<div class="note">Điểm kiểm chờ quá 24 giờ thường không còn ý nghĩa (ca đã xong, máy đã đổi mã). ' +
      "Đóng = chuyển sang <b>Hết hiệu lực</b>, không xoá dữ liệu; lý do được lưu vào nhật ký.</div>" +
      '<label style="display:flex;gap:8px;align-items:center;font-weight:600"><input type="checkbox" data-all checked> Chọn tất cả (' +
      items.length +
      ")</label>" +
      '<div class="ds">' +
      items
        .map(
          (it) =>
            '<label><input type="checkbox" name="cp" value="' +
            esc(it.id_checkpoint) +
            '" checked><b>' +
            esc(it.ma_may) +
            "</b> " +
            esc(it.ma_sp) +
            ' <span class="note">' +
            esc(it.loai || "") +
            '</span><span class="t">' +
            esc(thoiLuong(it.phut)) +
            "</span></label>",
        )
        .join("") +
      "</div>" +
      '<label style="font-weight:600">Lý do đóng (bắt buộc, ít nhất 3 ký tự)<textarea name="ly_do" required minlength="3" placeholder="VD: Ca đã kết thúc, máy đã đổi mã — không còn kiểm được"></textarea></label>' +
      '<div class="kq" aria-live="polite"></div></div>' +
      '<div class="ft"><button type="button" class="b" data-huy>Huỷ</button><button type="submit" class="b do" data-ok>Đóng điểm kiểm đã chọn</button></div></form>';
    const form = dlg.querySelector("form"),
      ok = dlg.querySelector("[data-ok]"),
      kq = dlg.querySelector(".kq"),
      boxes = () => [...dlg.querySelectorAll('input[name="cp"]')];
    const capNhat = () => {
      const n = boxes().filter((b) => b.checked).length;
      ok.textContent = "Đóng " + n + " điểm kiểm";
      ok.disabled = !n;
    };
    dlg.querySelector("[data-all]").onchange = (e) => {
      boxes().forEach((b) => (b.checked = e.target.checked));
      capNhat();
    };
    dlg.querySelector(".ds").onchange = capNhat;
    dlg.querySelector("[data-huy]").onclick = () => dlg.close();
    capNhat();
    let daDong = false;
    form.onsubmit = async (ev) => {
      ev.preventDefault();
      const ids = boxes()
          .filter((b) => b.checked)
          .map((b) => b.value),
        lyDo = form.elements.ly_do.value.trim();
      if (lyDo.length < 3) {
        kq.innerHTML = '<div class="err">Nhập lý do ít nhất 3 ký tự.</div>';
        form.elements.ly_do.focus();
        return;
      }
      if (!ids.length) return;
      ok.disabled = true;
      kq.textContent = "Đang đóng…";
      let nguoi = null;
      try {
        nguoi = (await MesAuth.getCurrentUserIdentity()) || null;
      } catch {}
      const r = await sb.rpc(RPC_DONG_TON, { p_ids: ids, p_ly_do: lyDo, p_nguoi: nguoi });
      if (r.error) {
        kq.innerHTML = loiHtml(r.error, "Chưa đóng được điểm kiểm.");
        ok.disabled = false;
        return;
      }
      daDong = true;
      const boQua = r.data?.bo_qua || [];
      kq.innerHTML =
        "<div><b>Đã đóng " +
        esc(r.data?.so_dong ?? 0) +
        " điểm kiểm.</b></div>" +
        (boQua.length
          ? '<div class="err">Bỏ qua ' +
            boQua.length +
            ":<br>" +
            boQua.map((b) => esc(b.id) + " — " + esc(b.ly_do)).join("<br>") +
            "</div>"
          : "");
      ok.hidden = true;
      dlg.querySelector("[data-huy]").textContent = "Xong";
    };
    dlg.onclose = () => {
      dlg.remove();
      if (daDong && typeof onDone === "function") onDone();
    };
    document.body.append(dlg);
    dlg.showModal();
  }

  return {
    TON_PHUT,
    BAT_THUONG_GIAY,
    TIP_BAT_THUONG,
    thoiLuong,
    thoiLuongGiay,
    batThuong,
    thoiGianKiemHtml,
    loi,
    loiHtml,
    vaiTro,
    quyenDongTon,
    ganNutDongTon,
    moHopDongTon,
    esc,
  };
})();

/* Keep inspection NG immutable; render continuation decisions independently. */
const MesNg = (() => {
  let decisions = new Map(),
    refreshing = false,
    canForward = false;
  const pending = new Set();
  const status = (r) =>
    !r
      ? "Chưa chuyển duyệt"
      : r.status === "Đang có hiệu lực"
        ? r.expired_at && Date.parse(r.expired_at) <= Date.now()
          ? "Hết hiệu lực"
          : r.allowed_qty != null && Number(r.produced_current) - Number(r.produced_at_request) >= Number(r.allowed_qty)
            ? "Hết phạm vi cho phép"
            : "Đã duyệt tiếp tục SX"
        : r.status === "Từ chối"
          ? "Không cho phép tiếp tục SX"
          : ["Hết hiệu lực", "Đã hủy"].includes(r.status)
            ? r.status
            : "Chờ duyệt";
  const text = (tag, value) => {
    const node = document.createElement(tag);
    node.textContent = value ?? "";
    return node;
  };
  async function forward(id) {
    if (pending.has(id)) return;
    pending.add(id);
    try {
      const r = await sb.rpc("duc_ipqc_forward_ng", { p_checkpoint: id });
      if (r.error) throw Error(r.error.message);
      alert("Đã chuyển đúng kết quả NG sang Duyệt tiếp tục SX IPQC. Kết quả gốc vẫn là NG.");
      await refresh();
      return r.data;
    } catch (e) {
      alert(e.message);
    } finally {
      pending.delete(id);
    }
  }
  function offer(id) {
    let panel = document.getElementById("ng-forward-offer");
    if (!panel) {
      panel = document.createElement("section");
      panel.id = "ng-forward-offer";
      panel.style.cssText = "padding:12px;border:1px solid #ef4444;margin:12px";
      document.body.append(panel);
    }
    panel.replaceChildren(text("p", "Kết quả kiểm: NG. Có thể chuyển lần kiểm này sang Duyệt tiếp tục SX IPQC."));
    const button = text("button", "Chuyển NG sang Duyệt tiếp tục SX");
    button.type = "button";
    button.onclick = async () => {
      button.disabled = true;
      try {
        const request = await forward(id);
        if (request) {
          const link = text("a", "Xem yêu cầu duyệt");
          link.href = "ipqc-approval.html?requestId=" + request;
          panel.append(link);
        }
      } finally {
        button.disabled = false;
      }
    };
    panel.append(button);
  }
  async function details(r) {
    const dialog = document.createElement("dialog");
    dialog.className = "qc02-viewer";
    dialog.style.cssText = "width:min(850px,94vw);max-height:90vh;overflow:auto;padding:20px";
    dialog.append(text("h2", "Lượt kiểm gốc — " + status(r)));
    const source = await sb.from("duc_ipqc_checkpoint").select("*").eq("id_checkpoint", r.checkpoint_id).maybeSingle();
    if (source.error) return alert(source.error.message);
    const cp = source.data;
    if (cp) {
      const info = document.createElement("div");
      Qc02View.table(
        info,
        ["Lần kiểm gốc", "Nội dung"],
        [
          ["Kết quả kiểm", cp.ket_qua],
          ["Máy", cp.ma_may],
          ["Model", cp.ma_sp],
          ["Người kiểm", cp.nguoi_kiem],
          ["Bắt đầu phiên", MesQcFields.display(cp.session_started_at)],
          ["Hoàn tất kiểm", MesQcFields.display(cp.session_completed_at || cp.thoi_diem_kiem_thuc_te)],
          [
            "Thời gian kiểm thực tế",
            MesQcUi.thoiLuongGiay(cp.thoi_gian_kiem_giay) +
              (MesQcUi.batThuong(cp.thoi_gian_kiem_giay) ? " (bất thường — " + MesQcUi.TIP_BAT_THUONG + ")" : ""),
          ],
          ["Mô tả", MesQcFields.cleanText(cp.ghi_chu)],
          [
            "Các mục NG",
            (cp.checklist_json || [])
              .filter((x) => x.dat === false)
              .map((x) => x.muc || x.label)
              .join(" / "),
          ],
        ],
      );
      dialog.append(info);
      const gallery = document.createElement("div");
      gallery.dataset.qcGallery = "";
      for (const raw of cp.anh_bang_chung_url || []) {
        const safe = Qc02View.safeUrl(raw, true);
        if (!safe) continue;
        const img = document.createElement("img");
        img.src = safe;
        img.alt = "Ảnh lượt kiểm gốc";
        img.dataset.qcPhoto = "";
        img.style.cssText = "width:120px;height:90px;object-fit:contain;margin:6px";
        gallery.append(img);
      }
      dialog.append(gallery);
    }
    const h = r?.ng_handling || {},
      list = document.createElement("div");
    Qc02View.table(
      list,
      ["Thông tin", "Nội dung"],
      [
        ["Phiếu duyệt", r?.request_code],
        ["Trạng thái duyệt", status(r)],
        ["Lý do cho chạy", h.reason],
        ["Điều kiện/phạm vi", h.scope],
        ["Giới hạn được duyệt", r?.approved_scope],
        ["Công đoạn xử lý tiếp", h.next_process],
        ["Bộ phận/người chịu trách nhiệm", h.responsible],
        ["Người xử lý duyệt", h.decided_by],
        ["Thời gian xử lý", h.decided_at ? MesQcFields.display(h.decided_at) : "Chưa ghi nhận"],
      ],
    );
    dialog.append(list);
    for (const step of r?.duc_ipqc_continue_approval || [])
      if (step.decision)
        dialog.append(
          text(
            "p",
            [
              step.approval_level,
              step.decision,
              step.decided_by_name,
              step.decided_at ? MesQcFields.display(step.decided_at) : "",
              step.note,
            ]
              .filter(Boolean)
              .join(" · "),
          ),
        );
    const link = text("a", "Mở Duyệt tiếp tục SX IPQC");
    link.href = "ipqc-approval.html?requestId=" + r.id;
    dialog.append(link);
    const close = text("button", "Đóng");
    close.onclick = () => dialog.close();
    dialog.append(close);
    dialog.onclose = () => dialog.remove();
    document.body.append(dialog);
    dialog.showModal();
  }
  function paint(node) {
    const id = node.dataset.ngCheckpoint,
      r = decisions.get(id);
    node.replaceChildren(text("p", "Kết quả kiểm: NG"), text("p", "Trạng thái duyệt: " + status(r)));
    if (r) {
      const h = r.ng_handling;
      if (h)
        node.append(
          text(
            "p",
            [h.decided_by, h.decided_at ? MesQcFields.display(h.decided_at) : "", h.next_process, h.responsible]
              .filter(Boolean)
              .join(" · "),
          ),
        );
      const button = text("button", "Xem quyết định / xử lý");
      button.type = "button";
      button.onclick = () => details(r);
      node.append(button);
    } else if (canForward) {
      const button = text("button", "Chuyển NG sang duyệt");
      button.type = "button";
      button.onclick = () => forward(id);
      node.append(button);
    }
  }
  async function refresh() {
    if (refreshing) return;
    refreshing = true;
    try {
      const ids = [
        ...new Set([...document.querySelectorAll("[data-ng-checkpoint]")].map((n) => n.dataset.ngCheckpoint)),
      ];
      if (!ids.length) return;
      const all = [];
      for (let part = 0; part < ids.length; part += 100)
        for (let offset = 0; ; offset += 500) {
          const r = await sb
            .from("duc_ipqc_continue_request")
            .select("*,duc_ipqc_continue_approval(*)")
            .in("checkpoint_id", ids.slice(part, part + 100))
            .order("id", { ascending: false })
            .range(offset, offset + 499);
          if (r.error) throw Error(r.error.message);
          all.push(...(r.data || []));
          if (!r.data || r.data.length < 500) break;
        }
      decisions = new Map();
      for (const r of all) if (!decisions.has(r.checkpoint_id)) decisions.set(r.checkpoint_id, r);
      document.querySelectorAll("[data-ng-checkpoint]").forEach(paint);
    } catch (e) {
      document.querySelectorAll("[data-ng-checkpoint]").forEach((node) => {
        node.innerHTML = MesQcUi.loiHtml(e, "Kết quả kiểm: NG. Không tải được trạng thái duyệt.");
      });
    } finally {
      refreshing = false;
    }
  }
  async function isNg(id, requests) {
    const r = requests.find((r) => r.id === id);
    if (!r?.checkpoint_id) return false;
    const cp = await sb
      .from("duc_ipqc_checkpoint")
      .select("ket_qua")
      .eq("id_checkpoint", r.checkpoint_id)
      .maybeSingle();
    if (cp.error) throw Error(cp.error.message);
    return cp.data?.ket_qua === "NG";
  }
  async function decide(id, decision) {
    const actor = (await MesAuth.getCurrentUserIdentity()) || "MES";
    if (decision === "Từ chối") {
      const note = prompt("Lý do không cho tiếp tục SX:");
      if (note === null) return;
      const r = await sb.rpc("duc_ipqc_decide_ng", {
        p_request_id: id,
        p_decision: decision,
        p_actor: actor,
        p_note: note,
        p_conditions: {},
      });
      if (r.error) return alert(r.error.message);
      return loadRequests();
    }
    const dialog = document.createElement("dialog");
    dialog.className = "qc02-viewer";
    dialog.style.cssText = "width:min(700px,94vw);max-height:90vh;overflow:auto;padding:20px";
    const form = document.createElement("form");
    form.innerHTML =
      '<h2>Cho chạy tiếp khi kết quả vẫn NG</h2><label>Lý do cho phép chạy<textarea name="reason" required></textarea></label><label>Điều kiện / phạm vi<textarea name="scope" required></textarea></label><label>Công đoạn xử lý tiếp<input name="next_process" required></label><label>Bộ phận / người chịu trách nhiệm<input name="responsible" required></label><label>Giới hạn<select name="mode"><option value="TIME">Giờ chạy thêm</option><option value="PLAN_QTY">Số lượng chạy thêm</option></select></label><label>Giá trị giới hạn<input name="amount" type="number" min="0.01" step="any" required></label><label>Ghi chú<textarea name="note"></textarea></label><button type="submit">Xác nhận quyết định</button>';
    form.querySelectorAll("label").forEach((n) => (n.style.cssText = "display:block;margin:10px 0"));
    form.querySelectorAll("input,textarea,select").forEach((n) => (n.style.cssText = "display:block;width:95%"));
    const cancel = text("button", "Hủy");
    cancel.type = "button";
    cancel.onclick = () => dialog.close();
    form.append(cancel);
    form.onsubmit = async (event) => {
      event.preventDefault();
      if (pending.has("decide:" + id)) return;
      const field = (name) => form.elements.namedItem(name).value.trim(),
        amount = Number(field("amount"));
      if (
        !["reason", "scope", "next_process", "responsible"].every((n) => field(n)) ||
        !Number.isFinite(amount) ||
        amount <= 0
      )
        return alert("Nhập đủ lý do, điều kiện, trách nhiệm và giới hạn hợp lệ");
      const conditions = {
        reason: field("reason"),
        scope: field("scope"),
        next_process: field("next_process"),
        responsible: field("responsible"),
        mode: field("mode"),
        hours: field("mode") === "TIME" ? amount : null,
        quantity: field("mode") === "PLAN_QTY" ? amount : null,
      };
      pending.add("decide:" + id);
      try {
        const r = await sb.rpc("duc_ipqc_decide_ng", {
          p_request_id: id,
          p_decision: decision,
          p_actor: actor,
          p_note: field("note") || conditions.reason,
          p_conditions: conditions,
        });
        if (r.error) throw Error(r.error.message);
        dialog.close();
        await loadRequests();
      } catch (e) {
        alert(e.message);
      } finally {
        pending.delete("decide:" + id);
      }
    };
    dialog.append(form);
    dialog.onclose = () => dialog.remove();
    document.body.append(dialog);
    dialog.showModal();
  }
  function mountDetail(checkpoint, parent) {
    if (checkpoint.ket_qua !== "NG") return;
    const node = text("section", "Đang tải trạng thái duyệt…");
    node.dataset.ngCheckpoint = checkpoint.id_checkpoint;
    parent.append(node);
    refresh();
  }
  MesAuth.getSession().then(async (auth) => {
    if (!auth) return;
    canForward = ["admin", "ipqc", "qc_manager"].includes(await MesQcUi.vaiTro());
    await refresh();
  });
  if (typeof sb.channel === "function")
    sb.channel("mes-ng-decisions")
      .on("postgres_changes", { event: "*", schema: "public", table: "duc_ipqc_continue_request" }, refresh)
      .on("broadcast", { event: "changed" }, refresh)
      .subscribe();
  setInterval(refresh, 15000);
  let openedRequest = 0;
  function requestDetails(id, requests) {
    const r = requests.find((r) => r.id === id);
    if (r) return details(r);
  }
  function openRequested(requests) {
    const id = Number(new URLSearchParams(location.search).get("requestId"));
    if (id && openedRequest !== id && requests.some((r) => r.id === id)) {
      openedRequest = id;
      requestDetails(id, requests);
    }
  }
  return { forward, offer, refresh, isNg, decide, status, details, requestDetails, openRequested, mountDetail };
})();
