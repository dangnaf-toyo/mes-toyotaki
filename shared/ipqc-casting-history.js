/* Read-only casting history: retain the standard revision and legacy, uncoded results. */
(function () {
  const esc = (s) => window.IpqcSpc.esc(s);
  function html(lan) {
    const values = lan.flatMap((l) => l.kq || []);
    const measured = values.filter((k) => typeof k.dat === "boolean");
    const ng = measured.filter((k) => k.dat === false).length;
    const cvt = values.filter((k) => k.ma_cvt != null).length;
    return (
      '<div class="card" data-casting-history><b>Lịch sử kiểm tra máy — chi tiết CVT</b>' +
      "<p>" +
      lan.length +
      " phiên · CVT đã đo: " +
      cvt +
      " · OK: " +
      (measured.length - ng) +
      " · NG: " +
      ng +
      " · Tỷ lệ NG: " +
      (measured.length ? ((100 * ng) / measured.length).toFixed(1) : "0.0") +
      "% kết quả đo; không quy đổi CVT thành PCS.</p>" +
      [...lan]
        .reverse()
        .map((l) => {
          const rows = l.kq || [],
            items = l.muc_tieu_chuan || [];
          const count = new Set(rows.map((k) => k.muc_no)).size;
          return (
            '<details data-inspection="' +
            esc(l.id_checkpoint) +
            '"><summary>' +
            esc(l.ma_may || "") +
            " · " +
            esc(window.MesQcFields?.display(l.thoi_diem) || l.thoi_diem) +
            " · " +
            esc(l.nguoi || "Chưa ghi nhận") +
            " · Phiên bản " +
            esc(l.tieu_chuan?.phien_ban || l.id_btk || "") +
            " · Đã kiểm: " +
            (l.so_muc_da_kiem ?? count) +
            " / Chưa kiểm: " +
            (l.so_muc_chua_kiem ?? Math.max(0, items.length - count)) +
            "</summary>" +
            "<p>Phiên kiểm: " +
            esc(l.id_checkpoint) +
            "</p>" +
            '<div style="overflow:auto"><table><thead><tr><th>Hạng mục</th><th>CVT</th><th>Giá trị đo</th><th>Kết quả</th></tr></thead><tbody>' +
            rows
              .map((k) => {
                const m = items.find((m) => m.muc_no === k.muc_no);
                return (
                  "<tr><td>" +
                  k.muc_no +
                  ". " +
                  esc(m?.hang_muc || "") +
                  "</td><td>" +
                  esc(k.ma_cvt ?? "Chưa có mã CVT (dữ liệu cũ/OK-NG)") +
                  "</td><td>" +
                  esc(k.gia_tri ?? "—") +
                  "</td><td>" +
                  (k.dat === true ? "OK" : k.dat === false ? "NG" : "Chưa kiểm") +
                  "</td></tr>"
                );
              })
              .join("") +
            items
              .filter((m) => !rows.some((k) => k.muc_no === m.muc_no))
              .map(
                (m) =>
                  "<tr><td>" + m.muc_no + ". " + esc(m.hang_muc) + "</td><td>—</td><td>—</td><td>Chưa kiểm</td></tr>",
              )
              .join("") +
            "</tbody></table></div></details>"
          );
        })
        .join("") +
      (lan.length ? "" : "<p>Chưa có kết quả.</p>") +
      "</div>"
    );
  }
  async function load(el, checkpoint) {
    el.textContent = "Đang tải kết quả đo kích thước…";
    try {
      const inspection = await sb.from("ipqc_do_lan").select("*").eq("id_checkpoint", checkpoint).maybeSingle();
      if (inspection.error) throw inspection.error;
      if (!inspection.data) {
        el.textContent = "Lượt kiểm này chưa có dữ liệu đo kích thước.";
        return;
      }
      const l = inspection.data;
      const [standard, items, values] = await Promise.all([
        sb.from("ipqc_btk").select("*").eq("id", l.id_btk).maybeSingle(),
        sbTaiHet(() => sb.from("ipqc_btk_muc").select("*").eq("id_btk", l.id_btk).order("muc_no")),
        sbTaiHet(() => sb.from("ipqc_do_kq").select("*").eq("id_checkpoint", checkpoint).order("muc_no").order("mau")),
      ]);
      if (standard.error || items.error || values.error) throw standard.error || items.error || values.error;
      el.innerHTML = html([{ ...l, tieu_chuan: standard.data, muc_tieu_chuan: items.data, kq: values.data }]);
    } catch (_) {
      el.textContent = "Chưa tải được kết quả đo. Đóng và mở lại chi tiết để thử lại.";
    }
  }
  window.IpqcCastingHistory = { html, load };
})();
