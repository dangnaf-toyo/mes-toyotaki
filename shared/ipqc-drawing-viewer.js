/* Reference document viewer only. No OCR, text extraction or standard feature editing. */
const IpqcDrawingViewer = (() => {
  let library;
  async function pdfjs() {
    if (!library)
      library = import("https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.mjs").catch((error) => {
        library = null;
        throw error;
      });
    const pdf = await library;
    pdf.GlobalWorkerOptions.workerSrc =
      "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.mjs";
    return pdf;
  }
  function mount(el, source) {
    let disposed = false,
      generation = 0,
      loading,
      documentPdf,
      rendering;
    let page = 1,
      pages = 1,
      zoom = 1,
      ready = false;
    const button = (label, action) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "btn sm";
      b.textContent = label;
      b.setAttribute("aria-label", label);
      b.onclick = action;
      return b;
    };
    el.className = "gc-drawing-viewer";
    const toolbar = document.createElement("div");
    toolbar.style.cssText = "display:flex;flex-wrap:wrap;gap:5px;align-items:center;margin-bottom:8px";
    const previous = button("Trang trước", () => {
      if (page > 1) {
        --page;
        draw();
      }
    });
    const next = button("Trang sau", () => {
      if (page < pages) {
        ++page;
        draw();
      }
    });
    const pageInput = document.createElement("input");
    pageInput.type = "number";
    pageInput.min = "1";
    pageInput.value = "1";
    pageInput.style.width = "62px";
    pageInput.setAttribute("aria-label", "Trang bản vẽ");
    pageInput.onchange = () => {
      const value = Number(pageInput.value);
      if (Number.isInteger(value) && value >= 1 && value <= pages) {
        page = value;
        draw();
      } else pageInput.value = String(page);
    };
    const total = document.createElement("span");
    const percent = document.createElement("span");
    const smaller = button("Thu nhỏ", () => {
      zoom = Math.max(0.25, zoom - 0.25);
      draw();
    });
    const larger = button("Phóng to", () => {
      zoom = Math.min(4, zoom + 0.25);
      draw();
    });
    const fit = button("Vừa khung", () => {
      zoom = 1;
      draw();
    });
    if (source.pdf) toolbar.append(previous, pageInput, total, next);
    toolbar.append(smaller, percent, larger, fit);
    const frame = document.createElement("div");
    frame.style.cssText = "width:100%;height:440px;overflow:auto;background:#eef1f5;border:1px solid #d9dfe5";
    const canvas = document.createElement("canvas");
    canvas.setAttribute("aria-label", "Bản vẽ PDF");
    canvas.style.display = "block";
    const picture = document.createElement("img");
    picture.alt = source.name || "Bản vẽ gốc";
    picture.style.cssText = "display:block;max-width:none;height:auto";
    frame.append(source.pdf ? canvas : picture);
    const status = document.createElement("p");
    status.className = "hint";
    status.setAttribute("role", "status");
    el.replaceChildren(toolbar, frame, status);
    function controls() {
      previous.disabled = !ready || page <= 1;
      next.disabled = !ready || page >= pages;
      pageInput.disabled = !ready;
      pageInput.value = String(page);
      pageInput.max = String(pages);
      total.textContent = "/ " + pages;
      percent.textContent = Math.round(zoom * 100) + "%";
      smaller.disabled = !ready || zoom <= 0.25;
      larger.disabled = !ready || zoom >= 4;
      fit.disabled = !ready;
    }
    async function draw() {
      const current = ++generation;
      const previousRender = rendering;
      previousRender?.cancel();
      controls();
      if (!ready || disposed) return;
      status.textContent = "Đang hiển thị bản vẽ…";
      try {
        if (!source.pdf) {
          picture.style.width =
            Math.max(1, Math.round(Math.min(picture.naturalWidth, frame.clientWidth - 2) * zoom)) + "px";
        } else {
          if (previousRender) await previousRender.promise.catch(() => {});
          const pdfPage = await documentPdf.getPage(page);
          if (disposed || current !== generation) return;
          const base = pdfPage.getViewport({ scale: 1 });
          const viewport = pdfPage.getViewport({
            scale: (Math.max(1, frame.clientWidth - 2) / base.width) * zoom,
          });
          const ratio = Math.min(
            window.devicePixelRatio || 1,
            2,
            Math.sqrt(16000000 / (viewport.width * viewport.height)),
          );
          canvas.width = Math.ceil(viewport.width * ratio);
          canvas.height = Math.ceil(viewport.height * ratio);
          canvas.style.width = viewport.width + "px";
          canvas.style.height = viewport.height + "px";
          rendering = pdfPage.render({
            canvasContext: canvas.getContext("2d"),
            viewport,
            transform: ratio === 1 ? null : [ratio, 0, 0, ratio, 0, 0],
          });
          await rendering.promise;
          if (disposed || current !== generation) return;
          rendering = null;
        }
        status.textContent = source.pdf
          ? "Trang " + page + "/" + pages + " · Chỉ xem bản vẽ tham khảo."
          : "Chỉ xem bản vẽ tham khảo.";
      } catch (error) {
        if (!disposed && current === generation && error.name !== "RenderingCancelledException") {
          status.textContent = "Chưa hiển thị được bản vẽ. Thử mở lại phiên bản hoặc chọn lại file.";
          console.error(error);
        }
      }
    }
    controls();
    let width = 0;
    const observer = new ResizeObserver(() => {
      if (frame.clientWidth > 0 && frame.clientWidth !== width) {
        width = frame.clientWidth;
        if (ready) draw();
      }
    });
    observer.observe(frame);
    status.textContent = "Đang tải bản vẽ…";
    (async () => {
      try {
        if (source.pdf) {
          const pdf = await pdfjs();
          if (disposed) return;
          loading = pdf.getDocument({ url: source.url });
          documentPdf = await loading.promise;
          if (disposed) {
            await documentPdf.destroy();
            return;
          }
          pages = documentPdf.numPages;
        } else {
          await new Promise((resolve, reject) => {
            picture.onload = resolve;
            picture.onerror = () => reject(Error("Image load failed"));
            picture.src = source.url;
          });
        }
        if (disposed) return;
        ready = true;
        await draw();
      } catch (error) {
        if (!disposed) {
          status.textContent = "Chưa mở được bản vẽ. Kiểm tra file hoặc quyền truy cập và thử lại.";
          console.error(error);
        }
      }
    })();
    return {
      destroy() {
        disposed = true;
        ++generation;
        observer.disconnect();
        rendering?.cancel();
        loading?.destroy()?.catch(() => {});
        picture.onload = picture.onerror = null;
      },
    };
  }
  return { mount };
})();
