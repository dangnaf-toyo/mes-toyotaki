/* Explicit, server-timed IPQC sessions. Drafts are account/checkpoint scoped in IndexedDB. */
const MesIpqcSession = (() => {
  let current = null,
    offset = 0,
    busy = false,
    ending = null,
    key = "",
    userId = "",
    storePromise = null,
    persistTimer,
    loadToken = 0,
    ready = false;
  const panel = document.createElement("section");
  panel.className = "session-panel";
  panel.style.cssText = "padding:12px;border:1px solid #94a3b8;border-radius:8px;margin:12px 0";
  const css = document.createElement("style");
  css.textContent =
    ".session-panel{background:#eff6ff;border:2px solid #2563eb!important}.ipqc-start-button{display:block;width:100%;min-height:60px;padding:14px 18px!important;font-size:19px!important;font-weight:800!important;line-height:1.35;background:#1d4ed8!important;color:#fff!important;border:2px solid #1e40af!important;border-radius:10px;box-shadow:0 3px 8px #1d4ed833;touch-action:manipulation}.ipqc-start-button:disabled{opacity:.5;box-shadow:none}.ipqc-start-button:focus-visible{outline:3px solid #f59e0b;outline-offset:3px}.ipqc-start-button[hidden]{display:none}";
  document.head.append(css);
  const start = document.createElement("button");
  start.type = "button";
  start.textContent = "Bắt đầu kiểm tra";
  start.id = "ipqc-session-start";
  start.className = "btn btn-primary ipqc-start-button";
  start.disabled = true;
  const status = document.createElement("div");
  status.id = "ipqc-session-status";
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  status.style.cssText = "white-space:pre-wrap;margin:8px 0";
  const retry = document.createElement("button");
  retry.id = "ipqc-session-retry";
  retry.type = "button";
  retry.textContent = "Kiểm tra lại phiên";
  retry.className = "btn";
  retry.hidden = true;
  const timer = document.createElement("output");
  timer.style.cssText = "display:block;margin-top:8px;font-weight:bold";
  timer.setAttribute("aria-live", "off");
  panel.append(start, status, retry, timer);
  (document.getElementById("ck-btk") || document.getElementById("ck-checklist")).before(panel);
  function message(text, error = false, detail = "") {
    status.textContent = text;
    if (detail) {
      // Chi tiết kỹ thuật để riêng, thu gọn — người kiểm chỉ cần đọc câu trên.
      const more = document.createElement("details");
      more.style.cssText = "margin-top:6px;color:#475569;font-size:12px;white-space:normal";
      const sum = document.createElement("summary");
      sum.textContent = "Chi tiết kỹ thuật";
      sum.style.cursor = "pointer";
      const code = document.createElement("code");
      code.textContent = detail;
      code.style.cssText = "display:block;margin-top:3px;word-break:break-word;font-family:'JetBrains Mono',monospace";
      more.append(sum, code);
      status.append(more);
    }
    status.dataset.state = error ? "error" : "ready";
    status.style.color = error ? "#b91c1c" : "";
    retry.hidden = !error;
  }
  function failure(error) {
    ready = false;
    controls(false);
    start.disabled = true;
    const code = String(error?.code || ""),
      detail = String(error?.message || error || "Không có phản hồi từ máy chủ");
    let reason;
    if (["PGRST202", "PGRST205", "42883", "42P01", "42703"].includes(code))
      reason =
        "Máy chủ chưa cập nhật chức năng phiên kiểm (thiếu bản cập nhật T118). Chưa thể bắt đầu kiểm — báo quản trị hệ thống rồi bấm Kiểm tra lại phiên.";
    else if (
      code === "NOT_AUTHENTICATED" ||
      code === "PGRST301" ||
      code === "PGRST303" ||
      /jwt.*expired|not authenticated/i.test(detail)
    )
      reason = "Chưa xác thực được tài khoản. Hãy đăng nhập lại MES rồi kiểm tra lại phiên.";
    else if (code === "42501" || error?.status === 403 || /permission denied|row-level security/i.test(detail))
      reason =
        "Tài khoản của bạn chưa được cấp quyền kiểm IPQC nên chưa thể bắt đầu kiểm. Nhờ quản trị cấp vai trò IPQC rồi bấm Kiểm tra lại phiên.";
    else if (/failed to fetch|fetch failed|network|timeout|timed out/i.test(detail))
      reason =
        "Không kết nối được máy chủ để xác nhận phiên kiểm. Hãy kiểm tra mạng và thử lại; chưa bắt đầu tính thời gian.";
    else if (/[À-ỹ]/.test(detail) && !/[a-z_]+\.[a-z_]+|relation|column|function/i.test(detail))
      reason = "Chưa thể xác nhận phiên kiểm: " + detail;
    else
      reason =
        "Chưa thể xác nhận phiên kiểm. Bấm Kiểm tra lại phiên; nếu vẫn lỗi, báo quản trị kèm chi tiết bên dưới.";
    message(reason, true, (code ? code + " — " : "") + detail);
  }
  function verified(data, cp, required = false) {
    const s = data?.session;
    if (
      !data ||
      !Object.prototype.hasOwnProperty.call(data, "session") ||
      !Number.isFinite(Date.parse(data.server_now)) ||
      (required && !s)
    )
      throw { code: "INVALID_SESSION", message: "Máy chủ chưa xác nhận đã lưu phiên kiểm; không bật bộ đếm." };
    if (
      s &&
      (s.checkpoint_id !== cp.id_checkpoint ||
        !Number.isFinite(Date.parse(s.started_at)) ||
        (s.completed_at &&
          (!Number.isFinite(Date.parse(s.completed_at)) || Date.parse(s.completed_at) < Date.parse(s.started_at))) ||
        (s.owner_id && s.owner_id !== userId) ||
        (s.machine && s.machine !== cp.ma_may) ||
        (s.product_code && s.product_code !== cp.ma_sp) ||
        (s.job_id != null && s.job_id !== cp.id_dong))
    )
      throw {
        code: "INVALID_SESSION",
        message: "Phiên máy chủ trả về không khớp lần kiểm, người kiểm hoặc thời điểm hợp lệ. Không sử dụng phiên này.",
      };
    return s;
  }
  function db() {
    if (!storePromise)
      storePromise = new Promise((resolve, reject) => {
        if (!window.indexedDB) return reject(Error("Trình duyệt không hỗ trợ lưu bản nháp ảnh; cần bật IndexedDB."));
        const r = indexedDB.open("mes-ipqc-drafts-v1", 1);
        r.onupgradeneeded = () => r.result.createObjectStore("drafts");
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(r.error);
      });
    return storePromise;
  }
  async function storage(mode, task) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const tx = database.transaction("drafts", mode),
        request = task(tx.objectStore("drafts"));
      tx.oncomplete = () => resolve(request?.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }
  function controls(enabled) {
    for (const input of document.querySelectorAll(
      "#ck-checklist button,#ck-btk input,#ck-btk select,#ck-btk textarea,#ck-btk [data-ok],#ck-btk [data-ng],#ck-photo-btn,#ck-photo-input,#ck-ghi-chu,.btn-result,#ipqcWarningButton",
    ))
      input.disabled = !enabled;
    if (enabled && state.btk && typeof khoaMucKichThuoc === "function") khoaMucKichThuoc();
  }
  function tick() {
    if (!current) {
      timer.textContent = "Chưa bắt đầu kiểm tra — chưa tính thời gian thực tế.";
      return;
    }
    const stop = current.completed_at ? Date.parse(current.completed_at) : Date.now() + offset;
    const seconds = Math.max(0, Math.floor((stop - Date.parse(current.started_at)) / 1000));
    timer.textContent =
      "Thời gian kiểm thực tế: " +
      Math.floor(seconds / 3600)
        .toString()
        .padStart(2, "0") +
      ":" +
      Math.floor((seconds % 3600) / 60)
        .toString()
        .padStart(2, "0") +
      ":" +
      (seconds % 60).toString().padStart(2, "0");
    // Phiên mở quá 2 giờ (bấm Bắt đầu rồi để đó) → thời gian kiểm sẽ bị đánh dấu bất thường.
    if (!current.completed_at && seconds > 7200)
      timer.textContent +=
        " — phiên đã mở hơn 2 giờ, thời gian kiểm sẽ bị đánh dấu bất thường. Nộp kết quả ngay khi kiểm xong.";
  }
  async function persist() {
    if (
      !current ||
      !state.current ||
      current.completed_at ||
      !key ||
      current.checkpoint_id !== state.current.id_checkpoint
    )
      return;
    const savedKey = key,
      savedUser = userId,
      cp = state.current;
    const draft = {
      checkpoint: cp,
      answers: state.checklistAnswers,
      note: document.getElementById("ck-ghi-chu").value,
      photos: state.photos,
    };
    try {
      await storage("readwrite", (s) => s.put(draft, savedKey));
      localStorage.setItem("mes-ipqc-active:" + savedUser, cp.id_checkpoint);
    } catch (e) {
      showToast("Không lưu được bản nháp: " + e.message, true);
    }
  }
  function schedule() {
    clearTimeout(persistTimer);
    persistTimer = setTimeout(persist, 100);
  }
  async function load(cp) {
    const token = ++loadToken;
    current = null;
    ending = null;
    ready = false;
    state.checkStartedAt = null;
    controls(false);
    start.hidden = false;
    start.disabled = true;
    retry.disabled = true;
    retry.hidden = true;
    message("Đang xác minh phiên kiểm với máy chủ...");
    tick();
    try {
      const auth = await MesAuth.getSession();
      if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
      if (!auth?.user?.id) throw { code: "NOT_AUTHENTICATED", message: "Không có phiên đăng nhập MES hợp lệ." };
      userId = auth.user.id;
      key = userId + ":" + cp.id_checkpoint;
      const checkpoint = await sb
        .from("duc_ipqc_checkpoint")
        .select("*")
        .eq("id_checkpoint", cp.id_checkpoint)
        .maybeSingle();
      if (checkpoint.error) throw checkpoint.error;
      if (
        !checkpoint.data ||
        checkpoint.data.ma_may !== cp.ma_may ||
        checkpoint.data.ma_sp !== cp.ma_sp ||
        (checkpoint.data.id_dong ?? null) !== (cp.id_dong ?? null)
      )
        throw Error("Điểm kiểm không còn khớp máy/model/Task đã chọn.");
      cp.trang_thai = checkpoint.data.trang_thai;
      const r = await sb.rpc("duc_ipqc_session", { p_checkpoint: cp.id_checkpoint, p_start: false });
      if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
      if (r.error) throw r.error;
      current = verified(r.data, cp) || null;
      offset = Date.parse(r.data.server_now) - Date.now();
      state.checkStartedAt = current ? Date.parse(current.started_at) : null;
      start.hidden = !!current;
      if (current && !current.completed_at) {
        const savedKey = key;
        let draft;
        try {
          draft = await storage("readonly", (s) => s.get(savedKey));
        } catch (e) {
          showToast(
            "Không đọc được bản nháp trên trình duyệt. Phiên và thời điểm bắt đầu vẫn được lưu trên hệ thống.",
            true,
          );
        }
        if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
        if (draft && draft.checkpoint.ma_may === cp.ma_may && draft.checkpoint.ma_sp === cp.ma_sp) {
          state.checklistAnswers = draft.answers;
          state.photos = draft.photos || [];
          document.getElementById("ck-ghi-chu").value = draft.note || "";
          renderChecklist();
          state.checklistAnswers.forEach((answer, i) => {
            document.getElementById("cl-ok-" + i)?.classList.toggle("sel-ok", answer.dat === true);
            document.getElementById("cl-bad-" + i)?.classList.toggle("sel-bad", answer.dat === false);
          });
          renderPhotoGrid();
        }
        ready = true;
        controls(true);
        message("Đã xác nhận phiên đang kiểm trên máy chủ. Tiếp tục từ thời điểm bắt đầu đã lưu.");
        await persist();
      } else {
        controls(false);
        ready = !current && cp.trang_thai === "cho_kiem";
        start.disabled = !ready;
        message(
          current
            ? "Phiên kiểm đã hoàn tất trên máy chủ."
            : ready
              ? "Máy chủ đã sẵn sàng. Bấm Bắt đầu kiểm tra khi thực sự bắt đầu."
              : "Lần kiểm này không còn ở trạng thái chờ kiểm. Hãy tải lại danh sách.",
        );
      }
      tick();
    } catch (e) {
      if (token === loadToken && state.current?.id_checkpoint === cp.id_checkpoint) failure(e);
    } finally {
      if (token === loadToken) retry.disabled = false;
    }
  }
  start.onclick = async () => {
    if (!state.current || busy || !ready || current) return;
    busy = true;
    start.disabled = true;
    retry.disabled = true;
    const cp = state.current,
      token = loadToken;
    message("Đang lưu thời điểm bắt đầu lên máy chủ...");
    try {
      const r = await sb.rpc("duc_ipqc_session", { p_checkpoint: cp.id_checkpoint, p_start: true });
      if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
      if (r.error) throw r.error;
      const saved = verified(r.data, cp, true);
      if (saved.completed_at)
        throw { code: "INVALID_SESSION", message: "Phiên này đã hoàn tất. Hãy tải lại danh sách." };
      current = saved;
      offset = Date.parse(r.data.server_now) - Date.now();
      state.checkStartedAt = Date.parse(current.started_at);
      start.hidden = true;
      controls(true);
      message("Đã lưu thời điểm bắt đầu trên máy chủ. Bộ đếm đang chạy.");
      await persist();
      tick();
    } catch (e) {
      if (token === loadToken && state.current?.id_checkpoint === cp.id_checkpoint) failure(e);
    } finally {
      busy = false;
      if (token === loadToken) {
        retry.disabled = false;
        controls(ready && !!current && !current.completed_at && state.current?.id_checkpoint === current.checkpoint_id);
      }
    }
  };
  retry.onclick = async () => {
    if (busy || !state.current) return;
    await persist();
    await load(state.current);
  };
  const oldOpen = openCheck;
  openCheck = async (...args) => {
    await persist();
    await oldOpen(...args);
    if (state.current) await load(state.current);
  };
  const oldAnswer = setChecklistAnswer;
  setChecklistAnswer = (...args) => {
    if (!ready || !current || current.completed_at) return;
    oldAnswer(...args);
    schedule();
  };
  const oldRender = renderPhotoGrid;
  renderPhotoGrid = (...args) => {
    oldRender(...args);
    schedule();
  };
  document.getElementById("ck-ghi-chu").addEventListener("input", schedule);
  const oldSubmit = submitCheck;
  submitCheck = async (result) => {
    if (busy) return;
    if (!ready || !current || current.completed_at)
      return showToast("Hãy xác minh và bắt đầu phiên kiểm trước khi gửi kết quả.", true);
    const cp = state.current,
      token = loadToken;
    if (!cp) return;
    busy = true;
    let response;
    try {
      await persist();
      response = await oldSubmit(result);
    } finally {
      ending = null;
      try {
        if (token === loadToken && state.current?.id_checkpoint === cp.id_checkpoint) {
          const r = await sb.rpc("duc_ipqc_session", { p_checkpoint: cp.id_checkpoint, p_start: false });
          if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
          if (r.error) throw r.error;
          const saved = verified(r.data, cp, true);
          if (saved.completed_at) {
            const confirmed = await sb
              .from("duc_ipqc_checkpoint")
              .select("*")
              .eq("id_checkpoint", cp.id_checkpoint)
              .maybeSingle();
            if (confirmed.error) throw confirmed.error;
            if (!confirmed.data || confirmed.data.trang_thai !== "da_kiem")
              throw { code: "INVALID_SESSION", message: "Chưa xác minh được kết quả đã lưu." };
            current = saved;
            ready = false;
            controls(false);
            await clearDraft();
            state.queue = state.queue.filter((r) => r.id_checkpoint !== cp.id_checkpoint);
            state.current = null;
            renderQueue();
            showScreen("scr-queue");
            if (confirmed.data.ket_qua === "NG" && typeof MesNg !== "undefined") MesNg.offer(cp.id_checkpoint);
            response = { ok: confirmed.data.ket_qua === result, checkpointId: cp.id_checkpoint, existing: true };
            showToast("Đã xác minh kết quả đã lưu: " + confirmed.data.ket_qua);
          } else {
            const cleared = await sb.rpc("duc_ipqc_session_submit_time", {
              p_checkpoint: cp.id_checkpoint,
              p_clear: true,
            });
            if (token !== loadToken || state.current?.id_checkpoint !== cp.id_checkpoint) return;
            if (cleared.error) throw cleared.error;
            if (cleared.data?.checkpoint_id !== cp.id_checkpoint || cleared.data.submission_at != null)
              throw { code: "INVALID_SESSION", message: "Chưa xác nhận được phiên tiếp tục sau lần gửi lỗi." };
            current = saved;
            ready = true;
            controls(true);
            message("Kết quả chưa hoàn tất. Tiếp tục đúng phiên kiểm đã lưu trên máy chủ.");
          }
        }
      } catch (e) {
        if (token === loadToken && state.current?.id_checkpoint === cp.id_checkpoint) failure(e);
      } finally {
        busy = false;
        controls(ready && !!current && !current.completed_at && state.current?.id_checkpoint === current.checkpoint_id);
        tick();
      }
    }
    return response;
  };
  async function prepare() {
    if (!ready || !current || !state.current) throw Error("Hãy xác minh và bắt đầu phiên kiểm trên máy chủ");
    const r = await sb.rpc("duc_ipqc_session_submit_time", {
      p_checkpoint: state.current.id_checkpoint,
      p_clear: false,
    });
    if (r.error) {
      failure(r.error);
      throw Error(r.error.message);
    }
    if (
      r.data?.checkpoint_id !== state.current.id_checkpoint ||
      !Number.isFinite(Date.parse(r.data.submission_at)) ||
      Date.parse(r.data.submission_at) < Date.parse(current.started_at)
    ) {
      const error = { code: "INVALID_SESSION", message: "Máy chủ chưa xác nhận thời điểm hoàn tất đúng phiên kiểm." };
      failure(error);
      throw Error(error.message);
    }
    ending = Date.parse(r.data.submission_at);
    controls(false);
    message("Đang lưu kết quả; bộ đếm tiếp tục đến khi máy chủ lưu thành công.");
    tick();
  }
  async function clearDraft() {
    try {
      await storage("readwrite", (s) => s.delete(key));
      localStorage.removeItem("mes-ipqc-active:" + userId);
    } catch (e) {
      showToast("Kết quả đã lưu. Không xóa được bản nháp cục bộ; hệ thống vẫn giữ đúng kết quả.", true);
    }
  }
  async function completed(cp, result) {
    const r = await sb.rpc("duc_ipqc_session", { p_checkpoint: cp.id_checkpoint, p_start: false });
    if (r.error) throw r.error;
    const saved = verified(r.data, cp, true);
    if (!saved.completed_at) throw Error("Máy chủ chưa xác nhận hoàn tất phiên kiểm.");
    current = saved;
    ready = false;
    controls(false);
    tick();
    await clearDraft();
    if (result === "NG" && typeof MesNg !== "undefined") MesNg.offer(cp.id_checkpoint);
  }
  window.addEventListener("pagehide", () => {
    persist();
  });
  window.addEventListener("load", async () => {
    try {
      const auth = await MesAuth.getSession();
      if (!auth?.user?.id) return;
      const active = await sb
        .from("duc_ipqc_inspection_session")
        .select("checkpoint_id")
        .eq("owner_id", auth.user.id)
        .is("completed_at", null)
        .order("started_at", { ascending: true });
      if (active.error) throw active.error;
      if (state.current) return;
      let id;
      try {
        id = localStorage.getItem("mes-ipqc-active:" + auth.user.id);
      } catch {}
      const sessions = active.data || [];
      if (!sessions.some((s) => s.checkpoint_id === id)) id = sessions[0]?.checkpoint_id;
      if (!id) return;
      const r = await sb.from("duc_ipqc_checkpoint").select("*").eq("id_checkpoint", id).maybeSingle();
      if (r.error) throw r.error;
      if (r.data?.trang_thai === "cho_kiem") {
        if (!state.queue.some((cp) => cp.id_checkpoint === id)) state.queue.push(r.data);
        await openCheck(id);
      }
    } catch (e) {
      // Không hiện lỗi kỹ thuật thô. Tài khoản không có quyền xem phiên kiểm
      // (vd không phải IPQC) thì đơn giản là không có phiên để khôi phục.
      const r = typeof MesQcUi !== "undefined" ? MesQcUi.loi(e) : { text: String(e?.message || e), detail: "" };
      if (/permission denied|row-level security|42501/i.test(r.detail)) {
        console.warn("IPQC: bỏ qua khôi phục phiên — tài khoản không có quyền xem phiên kiểm.", r.detail);
        return;
      }
      const text = "Không khôi phục được phiên kiểm đang dở. " + r.text + " Mở lại máy cần kiểm và bấm Kiểm tra lại phiên.";
      if (typeof showErrorNotice === "function") showErrorNotice(text, r.detail);
      else showToast(text, true);
    }
  });
  setInterval(tick, 500);
  return {
    prepare,
    completed,
    persist,
    load,
    syncControls: () => controls(ready && !!current && !current.completed_at && !busy),
    start: () => start.onclick(),
  };
})();
