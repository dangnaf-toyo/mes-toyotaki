/* One click records the inspection warning. It never creates a production request. */
const MesIpqcWarning = (() => {
  let busy = false;
  const updates = typeof sb.channel === "function" ? sb.channel("mes-ipqc-warning-inbox").subscribe() : null;
  function publish() {
    if (updates)
      Promise.resolve(updates.send({ type: "broadcast", event: "changed", payload: { refresh: true } })).catch(
        () => {},
      );
  }
  async function open() {
    if (busy || !state.current) return;
    const cp = { ...state.current },
      button = document.getElementById("ipqcWarningButton"),
      controls = [
        ...document.querySelectorAll("#scr-check button,#scr-check input,#scr-check textarea,#scr-check select"),
      ].map((el) => ({ el, disabled: el.disabled }));
    busy = true;
    button.disabled = true;
    for (const { el } of controls) el.disabled = true;
    try {
      const saved = await sb
        .from("duc_ipqc_checkpoint")
        .select("*")
        .eq("id_checkpoint", cp.id_checkpoint)
        .maybeSingle();
      if (saved.error) throw new Error(saved.error.message);
      // T204: chỉ chặn khi KHÁC máy hoặc KHÁC mã SP. Cùng máy + mã mà điểm kiểm đã chuyển sang
      // dòng ca mới (kết ca giữa chừng) thì nhận dòng mới.
      if (!saved.data || saved.data.ma_may !== cp.ma_may || saved.data.ma_sp !== cp.ma_sp)
        throw new Error("Không xác minh được đúng phiên kiểm tra.");
      if ((saved.data.id_dong ?? null) !== (cp.id_dong ?? null)) {
        for (const k of ["id_dong", "ngay", "ca", "phuong_an_ca"]) cp[k] = saved.data[k];
        if (state.current?.id_checkpoint === cp.id_checkpoint)
          for (const k of ["id_dong", "ngay", "ca", "phuong_an_ca"]) state.current[k] = saved.data[k];
      }
      if (saved.data.trang_thai === "da_kiem") {
        if (saved.data.ket_qua !== "CANH_BAO")
          throw new Error("Phiên này đã được lưu với kết quả khác; không ghi đè lịch sử.");
        state.queue = state.queue.filter((r) => r.id_checkpoint !== cp.id_checkpoint);
        state.current = null;
        renderQueue();
        showScreen("scr-queue");
        showToast("Cảnh báo đã được ghi nhận tại Duyệt tiếp tục SX IPQC.");
        publish();
        return;
      }
      // D71: điểm kiểm theo KHSX (id_dong NULL — trưởng ca chưa nhập KH ca) không có dòng ca để đối chiếu.
      // T204: máy vẫn đang chạy đúng mã này (dòng ca nào cũng được) thì cho ghi; máy cũ đã đóng ca thì
      // máy chủ tự gắn điểm kiểm sang dòng đang chạy lúc lưu (duc_submit_ipqc_session).
      if (cp.id_dong) {
        const jobs = await MesIpqcFlow.jobs();
        if (!jobs.some((r) => r.ma_may === cp.ma_may && r.ma_sp === cp.ma_sp))
          throw new Error(
            "Máy " + cp.ma_may + " hiện không còn chạy mã " + cp.ma_sp + "; không ghi cảnh báo cho máy/model khác.",
          );
      }
      if (state.current?.id_checkpoint !== cp.id_checkpoint) throw new Error("Phiên kiểm tra đã thay đổi.");
      const result = await submitCheck("CANH_BAO");
      if (result?.ok) publish();
      else {
        const confirmed = await sb
          .from("duc_ipqc_checkpoint")
          .select("*")
          .eq("id_checkpoint", cp.id_checkpoint)
          .maybeSingle();
        if (
          !confirmed.error &&
          confirmed.data?.trang_thai === "da_kiem" &&
          confirmed.data.ket_qua === "CANH_BAO" &&
          confirmed.data.ma_may === cp.ma_may &&
          confirmed.data.ma_sp === cp.ma_sp
        ) {
          state.queue = state.queue.filter((r) => r.id_checkpoint !== cp.id_checkpoint);
          state.current = null;
          renderQueue();
          showScreen("scr-queue");
          showToast("Cảnh báo đã được ghi nhận tại Duyệt tiếp tục SX IPQC.");
          publish();
        }
      }
    } catch (error) {
      showToast(error.message, true);
    } finally {
      busy = false;
      for (const { el, disabled } of controls) el.disabled = disabled;
      button.disabled = false;
      if (typeof MesIpqcSession !== "undefined") MesIpqcSession.syncControls();
    }
  }
  return { open };
})();
