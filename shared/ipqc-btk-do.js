/* Casting measurements: explicit item selection; CVT identifies a position, never a PCS. */
(function () {
  const S = () => window.IpqcSpc;
  const esc = (s) => S().esc(s);
  const number = (v) =>
    /^[-+]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(String(v).trim()) &&
    Number.isFinite(Number(String(v).trim().replace(",", ".")))
      ? Number(String(v).trim().replace(",", "."))
      : null;

  async function mount(el, cp, opt) {
    const root = document.createElement("div");
    el.replaceChildren(root);
    el.classList.add("hidden");
    const { data, error } = await sb.rpc("ipqc_do_du_lieu", {
      p_ma_sp: cp.ma_sp,
      p_tu: null,
      p_den: null,
      p_so_lan: 30,
      p_cong_doan: "duc",
    });
    if (error) {
      el.classList.remove("hidden");
      root.textContent = "Không tải được tiêu chuẩn Đúc. Thử lại trước khi kiểm tra.";
      throw new Error(error.message);
    }
    if (!data?.btk) return null;
    const btk = data.btk,
      mucs = data.muc || [];
    const nhap = Object.fromEntries(
      mucs.map((m) => [m.muc_no, { chon: false, rows: [{ cvt: "", value: "" }], dat: null }]),
    );
    let enabled = false;
    const previous = (data.lan || []).filter((l) => l.id_btk === btk.id);
    function hints(r) {
      const values = r.results.filter((x) => x.value !== null);
      const near = values.some((x) => S().satGioiHan(x.value, r.sp));
      const warnings = [];
      values.forEach((row) => {
        const points = previous.flatMap((l) =>
          (l.kq || [])
            .filter((k) => k.muc_no === r.m.muc_no && k.ma_cvt === row.code && k.gia_tri != null)
            .map((k) => ({ x: Number(k.gia_tri), r: 0 })),
        );
        const limits = S().gioiHan({ gioi_han: [] }, r.m.muc_no, 1, points);
        const xs = points.map((p) => p.x).concat(row.value);
        S()
          .quyTac(xs, limits)
          .filter((w) => w.i === xs.length - 1)
          .forEach((w) => warnings.push("CVT " + row.code + ": " + w.msg));
      });
      return (
        (near ? '<div class="sub">Sát giới hạn tiêu chuẩn.</div>' : "") +
        warnings.map((w) => '<div class="sub">' + esc(w) + " — báo QC Manager.</div>").join("")
      );
    }
    function danhGia() {
      let measured = 0,
        cvt = 0,
        ng = 0;
      const errors = [],
        kq = [];
      const items = mucs.map((m) => {
        const a = nhap[m.muc_no],
          sp = S().specMuc(m);
        const r = { m, sp, status: "Chưa kiểm", results: [] };
        if (!a.chon) return r;
        const errs = [];
        if (m.kieu === "so") {
          const seen = new Set();
          a.rows.forEach((row, i) => {
            const code = row.cvt.trim(),
              value = number(row.value);
            if (!code || value === null) errs.push("CVT " + (i + 1) + ": nhập mã và giá trị đo hợp lệ");
            if (code && seen.has(code.toLocaleLowerCase("vi"))) errs.push("trùng mã CVT " + code);
            seen.add(code.toLocaleLowerCase("vi"));
            const dat = value === null ? null : S().datGiaTri(value, sp);
            r.results.push({ code, value, dat });
            if (code && value !== null) {
              cvt++;
              if (dat === false) ng++;
              kq.push({ muc_no: m.muc_no, mau: i + 1, ma_cvt: code, gia_tri: value });
            }
          });
          if (!a.rows.length) errs.push("thêm ít nhất một CVT");
        } else if (typeof a.dat !== "boolean") errs.push("chọn OK hoặc NG");
        else {
          kq.push({ muc_no: m.muc_no, mau: 1, dat: a.dat });
          if (!a.dat) ng++;
        }
        if (errs.length) {
          r.status = "Thiếu kết quả";
          errors.push("Hạng mục " + m.muc_no + ": " + errs.join("; "));
        } else {
          measured++;
          r.status = (m.kieu === "so" ? r.results.some((x) => x.dat === false) : a.dat === false) ? "NG" : "OK";
        }
        return r;
      });
      if (!kq.length && !errors.length) errors.push("Chọn ít nhất một hạng mục và nhập kết quả kiểm tra.");
      return {
        du: !errors.length && kq.length > 0,
        dat: kq.length ? ng === 0 : null,
        measured,
        unchecked: mucs.length - measured,
        cvt,
        ng,
        errors,
        items,
        kq,
      };
    }
    function summary(d) {
      return (
        "<b>Đã kiểm: " +
        d.measured +
        " hạng mục · Chưa kiểm: " +
        d.unchecked +
        " hạng mục</b>" +
        "<div>CVT đã đo: " +
        d.cvt +
        " · NG: " +
        d.ng +
        " kết quả đo (không quy đổi thành PCS)</div>" +
        (d.errors.length
          ? '<div role="status">' + esc(d.errors[0]) + ". Có thể bỏ chọn hạng mục chưa thực hiện.</div>"
          : "<div>Kết quả các hạng mục đã kiểm: <b>" +
            (d.dat ? "OK" : "NG") +
            "</b>" +
            (d.ng ? " — giữ quy trình xử lý NG hiện tại." : "") +
            "</div>")
      );
    }
    function notify(d) {
      opt?.onChange?.(d);
      root.dispatchEvent(new CustomEvent("ipqc-measurements-change", { bubbles: true }));
    }
    function paint() {
      const d = danhGia();
      root.innerHTML =
        '<div class="btkdo"><div class="hd"><b>Kích thước — bảng tuần kiểm ' +
        esc(btk.phien_ban) +
        "</b>" +
        (btk.ban_ve_url ? '<button type="button" data-bv>Xem bản vẽ</button>' : "") +
        "<div>Chọn hạng mục cần kiểm; mã CVT do người kiểm tự nhập.</div></div>" +
        d.items
          .map((r) => {
            const m = r.m,
              a = nhap[m.muc_no];
            return (
              '<section class="it" data-status="' +
              esc(r.status) +
              '" data-it="' +
              m.muc_no +
              '"><div class="r1"><label><input type="checkbox" data-select="' +
              m.muc_no +
              '"' +
              (a.chon ? " checked" : "") +
              "> <b>" +
              m.muc_no +
              ". " +
              esc(m.hang_muc) +
              " " +
              esc(S().chuanText(m)) +
              "</b></label>" +
              "<span data-status>" +
              r.status +
              '</span></div><div class="sub">' +
              esc(m.dung_cu || "") +
              "</div><div data-hints>" +
              hints(r) +
              "</div>" +
              (a.chon
                ? '<div class="measurements">' +
                  (m.kieu === "so"
                    ? a.rows
                        .map(
                          (row, i) =>
                            '<div class="vals"><input type="text" data-code="' +
                            m.muc_no +
                            ":" +
                            i +
                            '" value="' +
                            esc(row.cvt) +
                            '" maxlength="80" placeholder="Mã CVT" aria-label="Mã CVT hạng mục ' +
                            m.muc_no +
                            " dòng " +
                            (i + 1) +
                            '">' +
                            '<input type="text" inputmode="decimal" data-v="' +
                            m.muc_no +
                            ":" +
                            i +
                            '" value="' +
                            esc(row.value) +
                            '" placeholder="Giá trị đo" aria-label="Giá trị đo hạng mục ' +
                            m.muc_no +
                            " dòng " +
                            (i + 1) +
                            '">' +
                            "<span data-row-result>" +
                            (r.results[i].dat === null ? "Chưa kiểm" : r.results[i].dat ? "OK" : "NG") +
                            "</span>" +
                            '<button type="button" data-delete="' +
                            m.muc_no +
                            ":" +
                            i +
                            '" aria-label="Xóa CVT dòng ' +
                            (i + 1) +
                            '">Xóa</button></div>',
                        )
                        .join("") +
                      '<button type="button" data-add="' +
                      m.muc_no +
                      '">+ Thêm CVT</button>'
                    : '<div class="okng"><button type="button" data-ok="' +
                      m.muc_no +
                      '" aria-pressed="' +
                      (a.dat === true) +
                      '">OK</button>' +
                      '<button type="button" data-ng="' +
                      m.muc_no +
                      '" aria-pressed="' +
                      (a.dat === false) +
                      '">NG</button></div>') +
                  "</div>"
                : "") +
              "</section>"
            );
          })
          .join("") +
        '<div class="tong" data-tong aria-live="polite">' +
        summary(d) +
        "</div>" +
        "<details><summary>Lịch sử kiểm tra máy</summary>" +
        IpqcCastingHistory.html((data.lan || []).filter((l) => l.ma_may === cp.ma_may)) +
        "</details></div>";
      lock(enabled);
      notify(d);
    }
    function lock(value) {
      enabled = !!value;
      root.querySelectorAll("input,button:not([data-bv])").forEach((input) => {
        input.disabled = !enabled;
      });
    }
    function update() {
      const d = danhGia();
      d.items.forEach((r) => {
        const item = root.querySelector('[data-it="' + r.m.muc_no + '"]');
        item.querySelector("[data-status]").textContent = r.status;
        item.dataset.status = r.status;
        item.querySelector("[data-hints]").innerHTML = hints(r);
        item.querySelectorAll("[data-row-result]").forEach((node, i) => {
          const v = r.results[i];
          node.textContent = v.dat === null ? "Chưa kiểm" : v.dat ? "OK" : "NG";
          node.className = v.dat === false ? "ng" : v.dat === true ? "ok" : "";
        });
      });
      root.querySelector("[data-tong]").innerHTML = summary(d);
      notify(d);
    }
    root.addEventListener("input", (e) => {
      if (!enabled) return;
      const key = e.target.dataset.v || e.target.dataset.code;
      if (!key) return;
      const [no, i] = key.split(":").map(Number);
      nhap[no].rows[i][e.target.dataset.v ? "value" : "cvt"] = e.target.value;
      update();
    });
    root.addEventListener("change", (e) => {
      if (!enabled || !e.target.matches("[data-select]")) return;
      nhap[e.target.dataset.select].chon = e.target.checked;
      paint();
    });
    root.addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (!b) return;
      if (b.hasAttribute("data-bv")) {
        const dialog = document.createElement("dialog");
        dialog.className = "btkdo-bv";
        dialog.innerHTML =
          '<div class="drawing"><img alt="Bản vẽ vị trí đo" src="' +
          esc(btk.ban_ve_url) +
          '">' +
          (btk.ban_ve_vi_tri || [])
            .map(
              (v) =>
                '<span class="balloon" style="left:' +
                Math.max(0, Math.min(100, +v.x || 0)) +
                "%;top:" +
                Math.max(0, Math.min(100, +v.y || 0)) +
                '%">' +
                esc(v.no) +
                "</span>",
            )
            .join("") +
          '</div><button type="button">Đóng</button>';
        document.body.append(dialog);
        dialog.querySelector("button").onclick = () => dialog.close();
        dialog.addEventListener("close", () => dialog.remove());
        dialog.showModal();
        return;
      }
      if (!enabled) return;
      if (b.dataset.add) nhap[b.dataset.add].rows.push({ cvt: "", value: "" });
      else if (b.dataset.delete) {
        const [no, i] = b.dataset.delete.split(":").map(Number);
        nhap[no].rows.splice(i, 1);
      } else if (b.dataset.ok || b.dataset.ng) {
        const a = nhap[b.dataset.ok || b.dataset.ng],
          value = !!b.dataset.ok;
        a.dat = a.dat === value ? null : value;
      } else return;
      paint();
    });
    el.classList.remove("hidden");
    paint();
    return {
      btk,
      trangThai: danhGia,
      setEnabled: lock,
      duLieu() {
        const d = danhGia();
        if (!d.du) throw new Error(d.errors.join("\n"));
        return { id_btk: btk.id, muc_da_chon: mucs.filter((m) => nhap[m.muc_no].chon).map((m) => m.muc_no), kq: d.kq };
      },
      draft() {
        return { id_btk: btk.id, items: JSON.parse(JSON.stringify(nhap)) };
      },
      restore(draft) {
        if (!draft || draft.id_btk !== btk.id || !draft.items) return;
        mucs.forEach((m) => {
          const a = draft.items[m.muc_no];
          if (a && Array.isArray(a.rows))
            nhap[m.muc_no] = {
              chon: a.chon === true,
              rows: a.rows.map((r) => ({ cvt: String(r.cvt ?? ""), value: String(r.value ?? "") })),
              dat: typeof a.dat === "boolean" ? a.dat : null,
            };
        });
        paint();
      },
    };
  }
  window.IpqcBtkDo = { mount };
})();
