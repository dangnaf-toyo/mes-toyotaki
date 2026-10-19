/* Read-only QC views. Submission and database contracts remain in each page. */
const Qc02View = (() => {
  function overdue(minutes) {
    return minutes != null && Number.isFinite(Number(minutes)) && Number(minutes) > 120;
  }
  function summarize(rows) {
    const machines = new Map(), defects = new Map();
    for (const r of rows) {
      const name = r.ma_may || '(không rõ)';
      const m = machines.get(name) || { machine: name, total: 0, ok: 0, ng: 0, warning: 0 };
      m.total++;
      if (r.ket_qua === 'OK') m.ok++;
      if (r.ket_qua === 'NG') m.ng++;
      if (r.ket_qua === 'CANH_BAO') m.warning++;
      machines.set(name, m);
      const checklist = r.checklist || r.checklist_json;
      for (const item of Array.isArray(checklist) ? checklist : []) {
        if (!item || item.dat !== false) continue;
        const label = item.muc || item.muc_kiem || item.ten || item.label || 'Mục không đạt';
        defects.set(label, (defects.get(label) || 0) + 1);
      }
    }
    return { machines: [...machines.values()].sort((a, b) => a.machine.localeCompare(b.machine)),
      defects: [...defects].sort((a, b) => b[1] - a[1]) };
  }
  function table(target, headers, rows) {
    target.replaceChildren();
    const t = document.createElement('table');
    for (const values of [headers, ...rows]) {
      const tr = document.createElement('tr');
      for (const value of values) {
        const cell = document.createElement(values === headers ? 'th' : 'td');
        cell.textContent = value == null || value === '' ? '—' : String(value); tr.append(cell);
      }
      t.append(tr);
    }
    target.append(t);
    if (!rows.length) target.append(document.createTextNode('Chưa có dữ liệu.'));
  }
  function safeUrl(url, image = false) {
    try {
      const parsed = new URL(url, location.href);
      if (['https:', 'http:', 'blob:'].includes(parsed.protocol)) return parsed.href;
      if (image && /^data:image\/(png|jpeg|jpg|gif|webp);base64,/i.test(url)) return url;
    } catch { /* invalid URL */ }
    return '';
  }
  function openDialog(dialog) {
    if(typeof dialog.showModal === 'function') { document.body.append(dialog);dialog.showModal();return; }
    const backdrop=document.createElement('div');
    backdrop.style.cssText='position:fixed;inset:0;background:rgba(15,23,42,.85);z-index:10000;display:flex;align-items:center;justify-content:center';
    dialog.style.display='block';dialog.style.position='relative';
    dialog.close=()=>{if(dialog.onclose)dialog.onclose();backdrop.remove();};
    backdrop.onclick=e=>{if(e.target===backdrop)dialog.close();};
    backdrop.append(dialog);document.body.append(backdrop);dialog.setAttribute('open','');
  }
  function photo(url,urls=[url]){
    const gallery=[...new Set(urls.map(u=>safeUrl(u,true)).filter(Boolean))];if(!gallery.length)return;hidePreview();let index=Math.max(0,gallery.indexOf(safeUrl(url,true))),scale=1,x=0,y=0,fitScale=1,pinch=null;const points=new Map();
    const dialog=document.createElement('dialog');dialog.className='qc02-viewer qc-zoom-viewer';dialog.style.cssText='position:fixed;inset:0;margin:auto;width:98vw;height:94vh;height:94dvh;max-width:98vw;max-height:96vh;border:0;border-radius:10px;padding:8px;box-sizing:border-box;background:#111827;color:white';
    const shell=document.createElement('div');shell.style.cssText='height:100%;display:flex;flex-direction:column;gap:8px';const toolbar=document.createElement('div');toolbar.style.cssText='display:flex;flex-wrap:wrap;align-items:center;gap:4px;flex-shrink:0';const viewport=document.createElement('div');viewport.className='qc-zoom-viewport';viewport.style.cssText='position:relative;flex:1;min-height:0;overflow:hidden;touch-action:none;user-select:none;background:#0b1020';
    const img=document.createElement('img');img.alt='Ảnh QC';img.draggable=false;img.style.cssText='position:absolute;left:50%;top:50%;max-width:none;max-height:none;object-fit:contain;transform-origin:center;pointer-events:none';const count=document.createElement('span'),ratio=document.createElement('output');ratio.setAttribute('aria-live','polite');
    function bounds(){return {w:viewport.clientWidth||innerWidth*.95,h:viewport.clientHeight||innerHeight*.75,nw:img.naturalWidth||800,nh:img.naturalHeight||600};}
    function paint(){const b=bounds();const mx=Math.max(0,(b.nw*scale-b.w)/2),my=Math.max(0,(b.nh*scale-b.h)/2);x=Math.max(-mx,Math.min(mx,x));y=Math.max(-my,Math.min(my,y));img.style.width=b.nw+'px';img.style.height=b.nh+'px';img.style.transform='translate(-50%,-50%) translate('+x+'px,'+y+'px) scale('+scale+')';ratio.textContent=Math.round(scale*100)+'%';viewport.style.cursor=scale>fitScale?'grab':'default';viewport.dataset.scale=String(scale);viewport.dataset.panX=String(x);viewport.dataset.panY=String(y);}
    function fit(){const b=bounds();fitScale=Math.min(32,b.w/b.nw,b.h/b.nh);scale=fitScale;x=y=0;paint();}
    function zoom(value,px=0,py=0){const next=Math.max(.05,Math.min(32,value)),factor=next/scale;x=px-(px-x)*factor;y=py-(py-y)*factor;scale=next;paint();}
    function button(label,run){const b=document.createElement('button');b.type='button';b.textContent=label;b.onclick=run;toolbar.append(b);return b;}
    const prev=button('← Trước',()=>{index=(index+gallery.length-1)%gallery.length;update();}),next=button('Sau →',()=>{index=(index+1)%gallery.length;update();});prev.hidden=next.hidden=gallery.length<2;toolbar.append(count);button('Phóng to +',()=>zoom(scale*1.25));button('Thu nhỏ −',()=>zoom(scale/1.25));button('Kích thước gốc',()=>{scale=1;x=y=0;paint();});button('Vừa màn hình',fit);toolbar.append(ratio);const close=button('Đóng ×',()=>dialog.close());
    function update(){points.clear();pinch=null;img.src=gallery[index];count.textContent=(index+1)+'/'+gallery.length;img.onload=fit;fit();}viewport.append(img);shell.append(toolbar,viewport);dialog.append(shell);
    viewport.addEventListener('wheel',e=>{e.preventDefault();const r=viewport.getBoundingClientRect();zoom(scale*Math.exp(-Math.sign(e.deltaY)*.15),e.clientX-r.left-r.width/2,e.clientY-r.top-r.height/2);},{passive:false});
    const pair=()=>{const [a,b]=[...points.values()];return {distance:Math.hypot(a.x-b.x,a.y-b.y),x:(a.x+b.x)/2,y:(a.y+b.y)/2};};
    viewport.addEventListener('pointerdown',e=>{if(e.pointerType==='mouse'&&e.button!==0)return;e.preventDefault();points.set(e.pointerId,{x:e.clientX,y:e.clientY});viewport.setPointerCapture?.(e.pointerId);if(points.size===2)pinch=pair();});
    viewport.addEventListener('pointermove',e=>{const old=points.get(e.pointerId);if(!old)return;points.set(e.pointerId,{x:e.clientX,y:e.clientY});if(points.size===2){const current=pair(),r=viewport.getBoundingClientRect();if(pinch?.distance>0){zoom(scale*current.distance/pinch.distance,pinch.x-r.left-r.width/2,pinch.y-r.top-r.height/2);x+=current.x-pinch.x;y+=current.y-pinch.y;paint();}pinch=current;}else if(points.size===1&&scale>fitScale){x+=e.clientX-old.x;y+=e.clientY-old.y;paint();}});
    for(const name of ['pointerup','pointercancel','lostpointercapture'])viewport.addEventListener(name,e=>{points.delete(e.pointerId);pinch=points.size===2?pair():null;});
    dialog.onkeydown=e=>{if(e.key==='ArrowLeft')prev.click();else if(e.key==='ArrowRight')next.click();else if(['+','='].includes(e.key))zoom(scale*1.25);else if(e.key==='-')zoom(scale/1.25);else if(e.key==='Escape')dialog.close();else return;e.preventDefault();};const resize=()=>fit();window.addEventListener('resize',resize);dialog.onclose=()=>{window.removeEventListener('resize',resize);points.clear();dialog.remove();};openDialog(dialog);update();close.focus();
  }
  function pdf(url) {
    const src = safeUrl(url);
    if (!src) return;
    const dialog = document.createElement('dialog'); dialog.className = 'qc02-viewer';
    dialog.style.cssText = 'width:94vw;height:90vh;border:0;padding:12px;border-radius:8px';
    const close = document.createElement('button'); close.textContent = 'Đóng'; close.onclick = () => dialog.close();
    const frame = document.createElement('iframe'); frame.title = 'Tiêu chuẩn kiểm tra PDF'; frame.src = src;
    frame.style.cssText = 'width:100%;height:calc(100% - 40px);border:0;display:block';
    dialog.onclick = e => { if (e.target === dialog) dialog.close(); };
    dialog.onclose = () => dialog.remove(); dialog.append(close, frame); openDialog(dialog);close.focus();
  }
  const style = document.createElement('style');
  style.textContent = '[hidden]{display:none!important}.qc02-viewer::backdrop{background:rgba(15,23,42,.85)}.qc02-viewer button{margin:4px;padding:8px 12px;cursor:pointer}img[data-qc-photo],.img-thumb img,.photo-thumb img{cursor:zoom-in}';
  document.head.append(style);
  function photoSource(element) {
    return element.getAttribute('data-qc-image-url') || element.getAttribute('data-qc-photo') || element.href || element.src || '';
  }
  let hoverTarget = null, preview = null, previewImage = null;
  function hidePreview() { hoverTarget=null; if(preview)preview.hidden=true; }
  function movePreview(event) {
    if(!preview || preview.hidden)return;
    const rect=preview.getBoundingClientRect(), gap=16, margin=8;
    let left=event.clientX+gap,top=event.clientY+gap;
    if(left+rect.width>innerWidth-margin)left=event.clientX-gap-rect.width;
    if(top+rect.height>innerHeight-margin)top=event.clientY-gap-rect.height;
    preview.style.left=Math.max(margin,Math.min(left,innerWidth-rect.width-margin))+'px';
    preview.style.top=Math.max(margin,Math.min(top,innerHeight-rect.height-margin))+'px';
  }
  // pointerover/out bubble, including buttons inserted after API loads.
  document.addEventListener('pointerover',event=>{
    if(event.pointerType==='touch')return;
    const target=event.target.closest('[data-qc-image-url]');
    if(!target || target===hoverTarget)return;
    const url=safeUrl(photoSource(target),true);if(!url)return;
    if(!preview){
      preview=document.createElement('div');preview.id='qc02-image-preview';preview.setAttribute('aria-hidden','true');
      preview.style.cssText='position:fixed;z-index:99999;pointer-events:none;opacity:1;visibility:visible;background:#fff;padding:6px;border:1px solid #cbd5e1;border-radius:8px;box-shadow:0 8px 24px rgba(0,0,0,.3);width:min(312px,calc(100vw - 16px))';
      previewImage=document.createElement('img');previewImage.alt='Xem nhanh ảnh QC';
      previewImage.style.cssText='display:block;width:300px;max-width:100%;height:300px;max-height:min(300px,calc(100vh - 28px));object-fit:contain;pointer-events:none';
      preview.append(previewImage);document.body.append(preview);
    }
    hoverTarget=target;previewImage.src=url;preview.hidden=false;movePreview(event);
  });
  document.addEventListener('pointermove',movePreview);
  document.addEventListener('pointerout',event=>{
    if(hoverTarget && hoverTarget.contains(event.target) && !hoverTarget.contains(event.relatedTarget))hidePreview();
  });
  document.addEventListener('scroll',hidePreview,true);
  window.addEventListener('blur',hidePreview);
  // Chỉ ảnh QC (gắn data-qc-photo hoặc thumbnail chụp/đính kèm) — không bắt click mọi <img> trên trang.
  const PHOTO_SELECTOR = '[data-qc-photo],.photo-thumb img,.img-thumb img';
  document.addEventListener('click', event => {
    const link = event.target.closest(PHOTO_SELECTOR);
    if (link) {
      if (link.closest('.qc02-viewer,#qc02-print')) return;
      hidePreview();
      event.preventDefault(); event.stopImmediatePropagation();
      const group = link.closest('[data-qc-gallery],.img-gallery,.ds-row-img,.photo-grid,td') || link.parentElement;
      const urls = [...group.querySelectorAll(PHOTO_SELECTOR)].map(photoSource);
      photo(photoSource(link), urls);
    }
  }, true);
  function machineNote(note, checked) {
    const clean = String(note || '').replace(/\n?\[QC02_MACHINE_CHECK:(?:0|1)\]/g, '');
    return clean + '\n[QC02_MACHINE_CHECK:' + (checked ? '1' : '0') + ']';
  }
  function machineChecked(note) {
    const match = String(note || '').match(/\[QC02_MACHINE_CHECK:(0|1)\]/);
    return match ? match[1] === '1' : null;
  }
  return { overdue, summarize, table, photo, pdf, safeUrl, machineNote, machineChecked };
})();
