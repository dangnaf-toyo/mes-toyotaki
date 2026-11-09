/* Measurement inputs only: standard fields stay read-only and missing values never mean OK. */
const IpqcGcEntry = (() => {
  function number(value) {
    const text = String(value ?? "").trim();
    return /^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?$/i.test(text)
      ? Number(text.replace(",", "."))
      : null;
  }
  function mount(target, sourceFeatures, standard, onChange = () => {}) {
    const features = sourceFeatures.map((m) => ({ ...m, muc_no: Number(m.muc_no) }));
    const S = IpqcSpc,
      E = S.esc,
      values = new Map(),
      counts = new Map();
    let disabled = false;
    for (const m of features)
      counts.set(m.muc_no, Number(m.co_mau || (m.kieu === "okng" ? 1 : standard.so_mau) || 1));
    const key = (no, sample) => no + "/" + sample;
    function inputs() {
      return [...target.querySelectorAll("[data-result]")];
    }
    function status() {
      let complete = features.length > 0,
        allOk = true,
        filled = 0,
        total = 0;
      const rows = features.map((m) => {
        const limits = IpqcGcStandard.numericBounds(m);
        let missing = false,
          ng = false;
        for (let sample = 1; sample <= counts.get(m.muc_no); sample++) {
          total++;
          const raw = values.get(key(m.muc_no, sample)) ?? "";
          const value =
            m.kieu === "so" ? number(raw) : ["true", "false"].includes(raw) ? raw === "true" : null;
          const valid =
            value !== null &&
            (m.kieu !== "so" ||
              (Number.isFinite(value) &&
                IpqcGcStandard.normalized(raw) !== null &&
                (limits.lsl !== null || limits.usl !== null)));
          const exact = IpqcGcStandard.bounds(m);
          const passed =
            m.kieu === "so"
              ? (exact.lsl == null || IpqcGcStandard.compare(raw, exact.lsl) >= 0) &&
                (exact.usl == null || IpqcGcStandard.compare(raw, exact.usl) <= 0)
              : value;
          if (!valid) {
            missing = true;
            complete = false;
          } else {
            filled++;
            if (!passed) ng = true;
          }
          const input = target.querySelector('[data-no="' + m.muc_no + '"][data-sample="' + sample + '"]');
          if (input) {
            input.classList.toggle("measure-ng", valid && !passed);
            input.classList.toggle("measure-ok", valid && !!passed);
          }
        }
        if (ng) allOk = false;
        const judgement = missing ? (ng ? "Chưa đủ mẫu · có NG" : "Chưa đủ mẫu") : ng ? "NG" : "OK";
        const cell = target.querySelector('[data-judgement="' + m.muc_no + '"]');
        if (cell) {
          cell.textContent = judgement;
          cell.className = ng ? "bad" : missing ? "muted" : "good";
        }
        return { muc_no: m.muc_no, complete: !missing, dat: missing ? null : !ng };
      });
      return { complete, dat: complete ? allOk : null, filled, total, rows };
    }
    function update() {
      onChange(status());
    }
    function render() {
      const max = Math.max(1, ...counts.values());
      target.innerHTML =
        '<table class="measure-table"><thead><tr>' +
        [
          "STT",
          "Mã đặc tính",
          "Tên đặc tính / vị trí",
          "Danh nghĩa",
          "Dung sai",
          "LSL",
          "USL",
          ...Array.from({ length: max }, (_, i) => "Mẫu " + (i + 1)),
          "Kết quả OK/NG",
        ]
          .map((t) => "<th>" + E(t) + "</th>")
          .join("") +
        "</tr></thead><tbody>" +
        features
          .map((m) => {
            const limits = IpqcGcStandard.numericBounds(m),
              count = counts.get(m.muc_no);
            const tolerance =
              m.kieu === "so"
                ? (() => {
                    const r = IpqcGcStandard.toSigned(m);
                    return (
                      IpqcGcStandard.signed(r.dung_sai_tren) + " / " + IpqcGcStandard.signed(r.dung_sai_duoi)
                    );
                  })()
                : m.tieu_chuan || "OK/NG";
            return (
              "<tr><td>" +
              E(m.muc_no) +
              "</td><td>" +
              E(m.ma_dac_tinh || m.muc_no) +
              "</td><td>" +
              E(m.hang_muc) +
              "<small>" +
              E(m.don_vi || "") +
              "</small></td><td>" +
              E(m.danh_nghia ?? "—") +
              "</td><td>" +
              E(tolerance) +
              "</td><td>" +
              E(limits.lsl ?? "—") +
              "</td><td>" +
              E(limits.usl ?? "—") +
              "</td>" +
              Array.from({ length: max }, (_, i) => {
                const sample = i + 1,
                  raw = values.get(key(m.muc_no, sample)) ?? "";
                if (sample > count) return '<td class="muted">—</td>';
                const attrs =
                  ' data-result data-no="' +
                  m.muc_no +
                  '" data-sample="' +
                  sample +
                  '" required ' +
                  (disabled ? "disabled" : "") +
                  ' aria-label="' +
                  E((m.ma_dac_tinh || m.muc_no) + " · Mẫu " + sample) +
                  '"';
                return (
                  "<td>" +
                  (m.kieu === "so"
                    ? "<input" + attrs + ' inputmode="decimal" autocomplete="off" value="' + E(raw) + '">'
                    : "<select" +
                      attrs +
                      '><option value="">Chọn</option><option value="true"' +
                      (raw === "true" ? " selected" : "") +
                      '>OK</option><option value="false"' +
                      (raw === "false" ? " selected" : "") +
                      ">NG</option></select>") +
                  "</td>"
                );
              }).join("") +
              '<td data-judgement="' +
              m.muc_no +
              '"></td></tr>'
            );
          })
          .join("") +
        "</tbody></table>";
      update();
    }
    target.oninput = target.onchange = (event) => {
      if (event?.target?.matches("[data-result]"))
        values.set(
          key(Number(event.target.dataset.no), Number(event.target.dataset.sample)),
          event.target.value,
        );
      else
        for (const input of inputs())
          values.set(key(Number(input.dataset.no), Number(input.dataset.sample)), input.value);
      update();
    };
    target.onkeydown = (event) => {
      if (event.key !== "Enter" || !event.target.matches("[data-result]")) return;
      event.preventDefault();
      const fields = inputs().filter((e) => !e.disabled),
        index = fields.indexOf(event.target);
      fields[index + (event.shiftKey ? -1 : 1)]?.focus();
    };
    render();
    return {
      status,
      features,
      counts,
      addSample() {
        for (const [no, count] of counts) if (count < 100) counts.set(no, count + 1);
        render();
      },
      ensureSample(no, sample) {
        if (!counts.has(no) || sample < 1 || sample > 100) throw Error("Mẫu phải từ 1 đến 100.");
        if (sample > counts.get(no)) {
          counts.set(no, sample);
          render();
        }
      },
      get(no, sample) {
        return values.get(key(no, sample)) ?? "";
      },
      set(no, sample, value) {
        if (!counts.has(no)) throw Error("Đặc tính không thuộc tiêu chuẩn.");
        this.ensureSample(no, sample);
        values.set(key(no, sample), String(value));
        render();
      },
      setMany(items) {
        if (disabled) throw Error("Không có quyền nhập kết quả.");
        for (const item of items) {
          if (!counts.has(item.muc_no) || !Number.isInteger(item.mau) || item.mau < 1 || item.mau > 100)
            throw Error("Đặc tính/mẫu không hợp lệ.");
        }
        // Validate the entire batch before touching any existing measurement.
        for (const item of items) {
          counts.set(item.muc_no, Math.max(counts.get(item.muc_no), item.mau));
          values.set(key(item.muc_no, item.mau), String(item.value));
        }
        render();
      },
      payload() {
        if (!status().complete) throw Error("Nhập đủ mẫu và kiểm tra giới hạn tiêu chuẩn trước khi lưu.");
        return features.flatMap((m) =>
          Array.from({ length: counts.get(m.muc_no) }, (_, i) => {
            const raw = values.get(key(m.muc_no, i + 1));
            return {
              muc_no: m.muc_no,
              mau: i + 1,
              ...(m.kieu === "so" ? { gia_tri: number(raw) } : { dat: raw === "true" }),
            };
          }),
        );
      },
      sampleCounts() {
        return Object.fromEntries(counts);
      },
      setDisabled(value) {
        disabled = value;
        inputs().forEach((e) => (e.disabled = value));
      },
    };
  }
  return { mount, number };
})();
