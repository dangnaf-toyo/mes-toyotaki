// T397: Xuất PDF A4 nhiều trang — thay html2pdf.js 0.10.1 (hay mất trang 2+ vì
// nó chụp trong khung position:fixed cao bằng màn hình).
// Cách làm: chép phần tử ra 1 khung rộng cố định trong body, html2canvas chụp
// TOÀN BỘ chiều cao, rồi tự cắt thành từng trang A4 tại ranh giới dòng bảng /
// khối (không cắt ngang chữ), mỗi trang 1 ảnh trong jsPDF.
// Cần nạp trước: html2canvas 1.4.1 + jspdf 2.5.1 (UMD).
(function(){
  const LE_MM = 10, A4_W = 210, A4_H = 297;

  function diemCat(root, top0){
    const s = new Set();
    // đáy từng dòng bảng (trừ dòng tiêu đề bảng)
    root.querySelectorAll('tbody tr').forEach(tr => s.add(Math.round(tr.getBoundingClientRect().bottom - top0)));
    // khối con trực tiếp: cắt TRƯỚC tiêu đề / bảng, SAU khối thường
    const goc = root.children.length === 1 && root.firstElementChild.children.length ? root.firstElementChild : root;
    Array.from(goc.children).forEach(n => {
      const r = n.getBoundingClientRect();
      s.add(Math.round(r.top - top0));
      if (!/^H[1-6]$/.test(n.tagName)) s.add(Math.round(r.bottom - top0));
    });
    return Array.from(s).filter(x => x > 0).sort((a, b) => a - b);
  }

  window.xuatPdfNhieuTrang = async function(el, filename, rong){
    if (!window.html2canvas || !window.jspdf) throw new Error('Chưa tải được thư viện xuất PDF — tải lại trang');
    const W = rong || 780;
    const box = document.createElement('div');
    box.style.cssText = 'position:absolute;left:0;top:0;width:' + W + 'px;background:#fff;z-index:-1;padding:0;margin:0';
    const clone = el.cloneNode(true);
    clone.removeAttribute('id');
    clone.style.cssText += ';display:block;max-height:none;overflow:visible;height:auto;margin:0';
    box.appendChild(clone);
    document.body.appendChild(box);
    const sx = window.scrollX, sy = window.scrollY;
    window.scrollTo(0, 0);   // trang đã cuộn → html2canvas chụp lệch
    try {
      if (document.fonts && document.fonts.ready) await document.fonts.ready;
      const top0 = box.getBoundingClientRect().top;
      const H = Math.ceil(box.getBoundingClientRect().height);
      const trangPx = Math.floor(W * (A4_H - 2 * LE_MM) / (A4_W - 2 * LE_MM));
      const cuts = diemCat(clone, top0);
      cuts.push(H);

      const scale = 2;
      const canvas = await window.html2canvas(box, {
        scale: scale, useCORS: true, backgroundColor: '#ffffff', logging: false,
        scrollX: 0, scrollY: 0, windowWidth: Math.max(W + 40, document.documentElement.clientWidth),
        windowHeight: H + 40, width: W, height: H,
      });

      // chia trang
      const trang = [];
      let y = 0;
      while (y < H - 2) {
        let cat = 0;
        for (const c of cuts) if (c > y && c <= y + trangPx) cat = c;
        if (!cat || cat - y < trangPx * 0.3) cat = Math.min(y + trangPx, H);   // khối quá cao → cắt cứng
        trang.push([y, cat]);
        y = cat;
      }

      const pdf = new window.jspdf.jsPDF({ unit: 'mm', format: 'a4', orientation: 'portrait' });
      const mmPerPx = (A4_W - 2 * LE_MM) / W;
      trang.forEach(([a, b], i) => {
        const hPx = b - a;
        const c = document.createElement('canvas');
        c.width = canvas.width;
        c.height = Math.ceil(hPx * scale);
        const g = c.getContext('2d');
        g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height);
        g.drawImage(canvas, 0, Math.floor(a * scale), canvas.width, c.height, 0, 0, canvas.width, c.height);
        if (i > 0) pdf.addPage();
        pdf.addImage(c.toDataURL('image/jpeg', 0.95), 'JPEG', LE_MM, LE_MM, A4_W - 2 * LE_MM, hPx * mmPerPx);
        if (trang.length > 1) {
          pdf.setFontSize(8); pdf.setTextColor(120);
          pdf.text((i + 1) + '/' + trang.length, A4_W - LE_MM, A4_H - 4, { align: 'right' });
        }
      });
      pdf.save(filename || 'BaoCao.pdf');
      return pdf;
    } finally {
      box.remove();
      window.scrollTo(sx, sy);
    }
  };
})();
