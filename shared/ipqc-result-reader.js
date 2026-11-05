/* Read local measurement reports. Original bytes stay local until the user explicitly saves. */
const IpqcResultReader = (() => {
  let pdfPromise, ocrPromise;
  async function timed(promise, message, ms = 120000) {
    let timer;
    try {
      return await Promise.race([
        promise,
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(Error(message)), ms);
        }),
      ]);
    } finally {
      clearTimeout(timer);
    }
  }
  async function pdfjs() {
    if (!pdfPromise)
      pdfPromise = import("https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.mjs").then((lib) => {
        lib.GlobalWorkerOptions.workerSrc = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.mjs";
        return lib;
      });
    return pdfPromise;
  }
  async function ocr() {
    if (window.Tesseract) return window.Tesseract;
    if (!ocrPromise)
      ocrPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js";
        script.onload = () => resolve(window.Tesseract);
        script.onerror = () => {
          ocrPromise = null;
          reject(Error("Chưa tải được OCR. Kiểm tra kết nối và thử lại."));
        };
        document.head.append(script);
      });
    return ocrPromise;
  }
  function grid(lines) {
    const header = lines.find(
      (l) =>
        /(actual|measured|sample|mẫu|ket qua do|giá trị đo|result)/i.test(l.cells.map((c) => c.text).join(" ")) &&
        l.cells.length >= 3,
    );
    return lines.map((line) => {
      if (!header) return line.cells.map((c) => c.text);
      const values = Array(header.cells.length).fill("");
      for (const cell of line.cells) {
        let nearest = 0,
          distance = Infinity;
        header.cells.forEach((h, i) => {
          const d = Math.abs((h.x0 + h.x1) / 2 - (cell.x0 + cell.x1) / 2);
          if (d < distance) {
            distance = d;
            nearest = i;
          }
        });
        values[nearest] += (values[nearest] ? " " : "") + cell.text;
      }
      return values;
    });
  }
  function pdfLines(items) {
    const lines = [];
    for (const item of items
      .filter((x) => x.str?.trim())
      .sort((a, b) => b.transform[5] - a.transform[5] || a.transform[4] - b.transform[4])) {
      let line = lines.find((l) => Math.abs(l.y - item.transform[5]) < 2);
      if (!line) {
        line = { y: item.transform[5], cells: [] };
        lines.push(line);
      }
      const cell = { text: item.str.trim(), x0: item.transform[4], x1: item.transform[4] + item.width };
      const previous = line.cells.at(-1);
      if (previous && cell.x0 - previous.x1 < Math.max(4, Math.abs(item.height || 10) * 0.7)) {
        previous.text += " " + cell.text;
        previous.x1 = cell.x1;
      } else line.cells.push(cell);
    }
    return lines;
  }
  async function read(file, { progress = () => {}, features = [], signal } = {}) {
    if (file.size > 20 * 1024 * 1024) throw Error("File kết quả đo tối đa 20 MB.");
    const extension = file.name.split(".").at(-1).toLowerCase();
    const sheets = [],
      warnings = [];
    let worker = null,
      doc = null;
    const check = () => {
      if (signal?.aborted) throw new DOMException("Đã hủy đọc file", "AbortError");
    };
    async function recognize(canvas, page) {
      if (!worker) {
        progress("Đang nạp OCR và dữ liệu ngôn ngữ…");
        const lib = await timed(ocr(), "Chưa tải được OCR. Kiểm tra kết nối và đọc lại file.");
        let expired = false;
        const loading = lib.createWorker("eng", 1, {
          logger: (m) => {
            if (m.status === "recognizing text")
              progress("OCR trang " + page + ": " + Math.round(m.progress * 100) + "%");
          },
        });
        loading
          .then((w) => {
            if (expired) w.terminate();
          })
          .catch(() => {});
        try {
          worker = await timed(loading, "Chưa nạp được bộ OCR/dữ liệu ngôn ngữ. Kiểm tra kết nối và thử lại.");
        } catch (error) {
          expired = true;
          throw error;
        }
        check();
        await worker.setParameters({ tessedit_pageseg_mode: "6", preserve_interword_spaces: "1" });
      }
      const { data } = await timed(
        worker.recognize(canvas, {}, { text: true, blocks: true }),
        "OCR trang này quá lâu. Thử ảnh rõ hơn hoặc tách báo cáo đo.",
      );
      check();
      const lines = (data.blocks || [])
        .flatMap((b) => (b.paragraphs || []).flatMap((p) => p.lines || []))
        .map((line) => {
          const cells = [];
          for (const word of line.words || []) {
            const previous = cells.at(-1),
              box = word.bbox;
            if (previous && box.x0 - previous.x1 < Math.max(12, (box.y1 - box.y0) * 0.7)) {
              previous.text += " " + word.text;
              previous.x1 = box.x1;
            } else cells.push({ text: word.text, x0: box.x0, x1: box.x1 });
          }
          if (!cells.length) cells.push({ text: line.text, x0: line.bbox.x0, x1: line.bbox.x1 });
          return { cells, confidence: line.confidence };
        });
      const matrix = (lines.length ? grid(lines) : data.text.split(/\r?\n/).map((s) => [s])).map((row) => {
        // OCR can retain printed table rules as pipe characters inside one cell.
        // Separate only explicit delimiters; do not derive measurements from nominal/tolerances.
        let cells = row.flatMap((v) =>
          String(v)
            .split("|")
            .map((s) => s.trim()),
        );
        while (cells[0] === "") cells.shift();
        while (cells.at(-1) === "") cells.pop();
        cells = cells.flatMap((v) => (/^nominal\s*[\[(]\s*uni[t]?$/i.test(v) ? ["Nominal", "Unit"] : [v]));
        return cells;
      });
      return {
        name: "Trang " + page + " (OCR)",
        rows: matrix,
        confidence: lines.map((l) => l.confidence),
        method: "ocr",
      };
    }
    try {
      if (["xlsx", "xls"].includes(extension)) {
        if (typeof XLSX === "undefined") throw Error("Chưa tải được bộ đọc Excel. Kiểm tra kết nối và thử lại.");
        const workbook = XLSX.read(await file.arrayBuffer(), { type: "array", cellDates: false });
        check();
        for (const name of workbook.SheetNames) {
          const sheet = workbook.Sheets[name],
            range = XLSX.utils.decode_range(sheet["!ref"] || "A1");
          if (range.e.r > 20000 || range.e.c > 500)
            throw Error("Sheet quá lớn. Chọn hoặc tách bảng kết quả cần nhập trước.");
          sheets.push({
            name,
            rows: XLSX.utils.sheet_to_json(sheet, {
              header: 1,
              range: { s: { r: 0, c: 0 }, e: range.e },
              defval: null,
              raw: true,
              blankrows: true,
            }),
            method: "excel",
          });
        }
      } else if (extension === "pdf") {
        const lib = await pdfjs();
        doc = await lib.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
        if (doc.numPages > 40) throw Error("PDF có hơn 40 trang. Tách báo cáo đo cần nhập để kiểm tra.");
        for (let n = 1; n <= doc.numPages; n++) {
          check();
          progress("Đọc PDF trang " + n + "/" + doc.numPages);
          const page = await doc.getPage(n),
            content = await page.getTextContent();
          const sheet = { name: "Trang " + n, rows: grid(pdfLines(content.items)), method: "pdf-text" };
          const candidates = IpqcResultParser.parse([sheet]);
          if (candidates.length) sheets.push(sheet);
          if (!candidates.some((c) => IpqcResultParser.match(c, features).status === "matched")) {
            const base = page.getViewport({ scale: 1 }),
              scale = Math.min(3, 3000 / Math.max(base.width, base.height));
            const viewport = page.getViewport({ scale }),
              canvas = document.createElement("canvas");
            canvas.width = Math.ceil(viewport.width);
            canvas.height = Math.ceil(viewport.height);
            await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise;
            sheets.push(await recognize(canvas, n));
            canvas.width = canvas.height = 0;
          }
          if (!candidates.length && !sheets.some((s) => s.name.startsWith("Trang " + n + " "))) sheets.push(sheet);
          page.cleanup();
        }
      } else if (["jpg", "jpeg", "png"].includes(extension)) {
        const bitmap = await createImageBitmap(file),
          canvas = document.createElement("canvas");
        const scale = Math.min(1, 4500 / Math.max(bitmap.width, bitmap.height));
        canvas.width = Math.ceil(bitmap.width * scale);
        canvas.height = Math.ceil(bitmap.height * scale);
        canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        bitmap.close();
        sheets.push(await recognize(canvas, 1));
        canvas.width = canvas.height = 0;
      } else throw Error("Chọn PDF kết quả đo, XLSX/XLS hoặc ảnh JPG/JPEG/PNG.");
      if (!sheets.some((s) => IpqcResultParser.parse([s]).length))
        warnings.push(
          "Chưa nhận diện được bảng giá trị đo. Chọn mẫu đọc/cột tương ứng hoặc nhập tay; chưa có dữ liệu được đồng bộ.",
        );
      return { sheets, warnings };
    } finally {
      if (worker) await worker.terminate();
      if (doc) await doc.destroy();
    }
  }
  return { read };
})();
