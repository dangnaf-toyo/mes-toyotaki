/* PDF text first; OCR fallback runs locally in the user's browser. */
const IpqcDrawingReader = (() => {
  let pdfLibrary, ocrLibrary;
  async function pdfjs() {
    if (!pdfLibrary) {
      pdfLibrary = await import("https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.mjs");
      pdfLibrary.GlobalWorkerOptions.workerSrc = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.mjs";
    }
    return pdfLibrary;
  }
  async function ocr() {
    if (!ocrLibrary)
      ocrLibrary = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js";
        script.onload = () => resolve(window.Tesseract);
        script.onerror = () => reject(Error("Chưa tải được bộ OCR. Kiểm tra kết nối và thử lại."));
        document.head.append(script);
      });
    return ocrLibrary;
  }
  async function read(file, onProgress = () => {}) {
    if (file.size > 20 * 1024 * 1024) throw Error("Bản vẽ tối đa 20 MB.");
    const pdf = /\.pdf$/i.test(file.name) || file.type === "application/pdf";
    if (!pdf && !/\.(png|jpe?g)$/i.test(file.name)) throw Error("Chọn PDF, JPG, JPEG hoặc PNG.");
    let worker = null,
      documentPdf = null;
    const rows = [],
      warnings = [];
    async function recognize(canvas, page) {
      if (!worker) {
        const lib = await ocr();
        worker = await lib.createWorker("eng", 1, {
          logger: (message) => {
            if (message.status === "recognizing text")
              onProgress("OCR trang " + page + ": " + Math.round(message.progress * 100) + "%");
          },
        });
        await worker.setParameters({ tessedit_pageseg_mode: "11", preserve_interword_spaces: "1" });
      }
      const { data } = await worker.recognize(canvas, {}, { text: true, blocks: true });
      const lines = (data.blocks || []).flatMap((block) =>
        (block.paragraphs || []).flatMap((paragraph) => paragraph.lines || []),
      );
      if (lines.length)
        for (const line of lines)
          rows.push(
            ...IpqcDrawingParser.parseText(line.text, {
              page,
              method: "ocr",
              confidence: line.confidence,
              position: { ...line.bbox, canvasWidth: canvas.width, canvasHeight: canvas.height },
            }),
          );
      else rows.push(...IpqcDrawingParser.parseText(data.text, { page, method: "ocr", confidence: data.confidence }));
    }
    try {
      if (pdf) {
        const lib = await pdfjs();
        documentPdf = await lib.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
        for (let pageNo = 1; pageNo <= documentPdf.numPages; pageNo++) {
          onProgress("Đang đọc trang " + pageNo + "/" + documentPdf.numPages);
          const page = await documentPdf.getPage(pageNo),
            content = await page.getTextContent();
          const segments = IpqcDrawingParser.pdfSegments(content.items);
          let found = [];
          for (const segment of segments)
            found.push(
              ...IpqcDrawingParser.parseText(segment.text, {
                page: pageNo,
                method: "pdf-text",
                position: { x: segment.x, y: segment.y },
              }),
            );
          if (found.length) rows.push(...found);
          // Mixed PDFs may have text notes over an image/outlined dimensions: don't mistake notes for a full extraction.
          if (
            found.filter((row) => row.kieu === "so" && row.danh_nghia !== "" && (row.lsl !== "" || row.usl !== ""))
              .length < 3
          ) {
            const base = page.getViewport({ scale: 1 }),
              scale = Math.min(3, 3000 / Math.max(base.width, base.height));
            const viewport = page.getViewport({ scale }),
              canvas = document.createElement("canvas");
            canvas.width = Math.ceil(viewport.width);
            canvas.height = Math.ceil(viewport.height);
            await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise;
            await recognize(canvas, pageNo);
            canvas.width = canvas.height = 0;
          }
          page.cleanup();
        }
      } else {
        const image = await createImageBitmap(file);
        const canvas = document.createElement("canvas");
        const scale = Math.min(1, 4500 / Math.max(image.width, image.height));
        canvas.width = Math.ceil(image.width * scale);
        canvas.height = Math.ceil(image.height * scale);
        canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
        await recognize(canvas, 1);
        image.close();
        canvas.width = canvas.height = 0;
      }
      if (!rows.length)
        warnings.push("Không nhận diện được đặc tính đủ rõ. Nhập thủ công; không tự tạo kích thước hoặc dung sai.");
      else
        warnings.push(
          "Mọi kết quả cần đối chiếu bản vẽ. Ren, GD&T, ghi chú và dung sai chung chỉ được gợi ý để xác minh; không tự áp dung sai.",
        );
      return {
        rows: rows.map((row, index) => ({
          ...row,
          muc_no: index + 1,
          ma_dac_tinh: "KT-" + String(index + 1).padStart(3, "0"),
        })),
        warnings,
      };
    } finally {
      if (worker) await worker.terminate();
      if (documentPdf) await documentPdf.destroy();
    }
  }
  return { read };
})();
