/* Server-owned report identity. Inspector/labor selections never grant edit rights. */
const OqcReportAccess = (() => {
  let info = null;
  const busy = new Set();
  const ready = (async () => {
    try {
      const session = await MesAuth.getSession();
      if (!session) return;
      const r = await sb.rpc("oqc_quyen_bao_cao");
      if (r.error || r.data?.version !== 177) throw Error("Chưa có quyền báo cáo OQC");
      info = r.data;
    } catch (e) {
      console.warn("Không tải được quyền sửa/xóa OQC", e.message);
    } finally {
      document.dispatchEvent(new Event("oqc-access-ready"));
    }
  })();
  function canManage(row) {
    return !!(
      info?.can_actual &&
      row &&
      !row.da_xoa &&
      (info.is_admin || (row.created_by && row.created_by === info.user_id))
    );
  }
  function actions(row) {
    if (!canManage(row)) return "—";
    const id = Number(row.id);
    return (
      '<button type="button" class="btn secondary" onclick="editRow(' +
      id +
      ')">Sửa</button> <button type="button" class="btn secondary" onclick="OqcReportAccess.remove(' +
      id +
      ')">Xóa</button>'
    );
  }
  async function remove(id) {
    if (busy.has(id)) return;
    const row = dataRows.find((r) => r.id === id);
    if (!canManage(row)) return alert("Chỉ người nhập báo cáo hoặc Admin được sửa/xóa.");
    if (
      !confirm(
        "Xóa báo cáo OQC #" +
          id +
          " — " +
          row.product_code +
          " ngày " +
          MesQcFields.date(row.inspection_date) +
          "? Báo cáo sẽ được loại khỏi thống kê; lịch sử được giữ lại.",
      )
    )
      return;
    busy.add(id);
    try {
      const r = await sb.rpc("oqc_xoa_bao_cao", { p_id: id, p_expected_updated_at: row.updated_at });
      if (r.error) throw r.error;
      if (typeof editing !== "undefined" && editing === id) resetForm();
      await loadStats();
    } catch (e) {
      alert("Không xóa được báo cáo. Tải lại dữ liệu và thử lại.");
      console.error("OQC delete", e);
      await loadStats();
    } finally {
      busy.delete(id);
    }
  }
  document.addEventListener("oqc-access-ready", () => {
    if (typeof renderStats === "function") renderStats();
  });
  return { ready, canManage, actions, remove };
})();
