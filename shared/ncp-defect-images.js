/* Defect attachments only. Cause/action images and NCP workflow remain independent. */
const NcpDefectImages = (() => {
  const BUCKET = 'ncp-hinh-anh', LIMIT = 10, MAX_BYTES = 5 * 1024 * 1024;
  const TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };
  const message = e => e?.message || String(e);
  function safe(url) {
    try { const u = new URL(url); return ['https:', 'blob:'].includes(u.protocol) ? u.href : ''; } catch { return ''; }
  }
  function button(text, action) {
    const b = document.createElement('button'); b.type = 'button'; b.textContent = text; b.onclick = action; return b;
  }
  async function check(result) {
    const r = await result;
    if (r.error || r.data?.ok === false) throw Error(r.error?.message || r.data.error);
    return r.data;
  }
  async function raster(file) {
    const ext = file.name.split('.').pop().toLowerCase(), mime = TYPES[ext];
    if (!mime || (file.type && file.type !== mime)) throw Error('Chỉ chọn ảnh JPG, JPEG, PNG hoặc WEBP');
    if (!file.size || file.size > MAX_BYTES) throw Error('Mỗi ảnh phải có dung lượng từ 1 byte đến 5 MB');
    const bytes = new Uint8Array(await file.slice(0, 16).arrayBuffer());
    const valid = mime === 'image/jpeg' ? bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 :
      mime === 'image/png' ? [137,80,78,71,13,10,26,10].every((v,i) => bytes[i] === v) :
      String.fromCharCode(...bytes.slice(0,4)) === 'RIFF' && String.fromCharCode(...bytes.slice(8,12)) === 'WEBP';
    if (!valid) throw Error('Nội dung file không đúng định dạng ảnh');
    const bitmap = await createImageBitmap(file).catch(() => { throw Error('Ảnh bị lỗi hoặc không đọc được'); });
    try {
      if (!bitmap.width || !bitmap.height || bitmap.width * bitmap.height > 24000000) throw Error('Ảnh vượt quá 24 triệu điểm ảnh');
      const ratio = Math.min(1, 4096 / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(bitmap.width * ratio)); canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
      const ctx = canvas.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0,0,canvas.width,canvas.height);
      ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);
      // Store decoded pixels only; strip metadata and any non-image payload from the original.
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', .94));
      if (!blob || blob.size > MAX_BYTES) throw Error('Ảnh sau xử lý vượt quá 5 MB; hãy chọn ảnh nhỏ hơn');
      return blob;
    } finally { bitmap.close(); }
  }
  function mount(root, { persisted = false, onUrls = () => {} } = {}) {
    let pending = [], saved = [], editable = false, busy = false, caseId = null;
    let requestId = crypto.randomUUID(), generation = 0, processing = false, history = [];
    root.classList.add('ncp-defect-images');
    const title = document.createElement('label'); title.textContent = 'Hình ảnh lỗi';
    const help = document.createElement('small'); help.textContent = 'JPG, JPEG, PNG, WEBP · tối đa 5 MB/ảnh, 10 ảnh/phiếu. Bấm ảnh để phóng to.';
    const input = document.createElement('input'); input.type = 'file'; input.accept = '.jpg,.jpeg,.png,.webp'; input.multiple = true; input.hidden = true;
    const status = document.createElement('p'); status.setAttribute('role','status');
    const gallery = document.createElement('div'); gallery.className = 'ncp-defect-gallery';
    const add = button('+ Thêm ảnh', () => input.click()); add.dataset.ncpAdd = '';
    const save = button('Lưu ảnh bổ sung', () => savePending()); save.dataset.ncpSave = '';
    const log = document.createElement('details'), summary = document.createElement('summary'), logBody = document.createElement('div');
    summary.textContent = 'Lịch sử hình ảnh'; log.append(summary,logBody); log.hidden = !persisted;
    root.append(title,help,add,input,gallery,save,status,log);
    function setStatus(text, error = false) { status.textContent = text; status.classList.toggle('ncp-image-error',error); }
    function lock(value) { busy = value; render(); }
    async function getUrl(row) {
      return row.storage_path ? safe((await check(sb.storage.from(BUCKET).createSignedUrl(row.storage_path,3600))).signedUrl) : safe(row.legacy_url);
    }
    async function enlarge(item) {
      try {
        const url = item.storage_path ? await getUrl(item) : item.url;
        if (url) Qc02View.photo(url);
      } catch(e) { setStatus('Không mở được ảnh: '+message(e),true); }
    }
    function thumb(item, isSaved) {
      const card = document.createElement('div'); card.className = 'ncp-defect-thumb';
      const open = button('', () => enlarge(item)); open.className = 'ncp-defect-open'; open.setAttribute('aria-label','Phóng to '+item.ten_file);
      const img = document.createElement('img'); img.alt = item.ten_file; img.src = item.url || ''; open.append(img);
      const name = document.createElement('span'); name.textContent = item.ten_file;
      card.append(open,name);
      if (editable) {
        if (!isSaved) {
          const replace = button('Thay ảnh', () => {
            const pick = document.createElement('input'); pick.type='file'; pick.accept=input.accept;
            pick.onchange = () => choose([...pick.files], item); pick.click();
          }); replace.disabled = busy || processing; card.append(replace);
        }
        const remove = button('Xóa ảnh', async () => {
          if (isSaved) {
            if (!confirm('Xóa ảnh khỏi phiếu? Thao tác sẽ được lưu vào lịch sử.')) return;
            lock(true);
            try { await check(sb.rpc('ncp_anh_xoa',{p_id:item.id})); await refresh(); setStatus('Đã xóa ảnh và ghi lịch sử.'); }
            catch(e) { setStatus(message(e),true); } finally { lock(false); }
          } else { pending = pending.filter(x => x !== item); URL.revokeObjectURL(item.url); render(); }
        }); remove.disabled = busy || processing; card.append(remove);
      }
      return card;
    }
    function render() {
      gallery.replaceChildren(...saved.map(x => thumb(x,true)),...pending.map(x => thumb(x,false)));
      if (!saved.length && !pending.length) gallery.textContent = 'Chưa có ảnh';
      add.hidden = !editable; add.disabled = busy || processing || pending.length + saved.length >= LIMIT;
      save.hidden = !persisted || !editable || !pending.length; save.disabled = busy || processing;
    }
    async function choose(files, replacing = null) {
      if (busy || processing || !editable || !files.length) return;
      if (pending.length + saved.length + files.length - (replacing ? 1 : 0) > LIMIT) return setStatus('Tối đa 10 ảnh mỗi phiếu',true);
      const ticket = generation; processing = true; render(); setStatus('Đang kiểm tra ảnh...');
      const items = [];
      try {
        for (const file of files) {
          if (file.name.length>255) throw Error('Tên ảnh không được quá 255 ký tự');
          const blob = await raster(file);
          items.push({ten_file:file.name,blob,url:URL.createObjectURL(blob),path:null});
        }
        if (ticket !== generation) { items.forEach(x => URL.revokeObjectURL(x.url)); return; }
        if (replacing) { pending = pending.filter(x => x !== replacing); URL.revokeObjectURL(replacing.url); }
        pending.push(...items); setStatus(persisted ? 'Ảnh chưa lưu. Bấm “Lưu ảnh bổ sung”.' : 'Ảnh sẽ được lưu cùng phiếu.');
      } catch(e) { items.forEach(x => URL.revokeObjectURL(x.url)); if(ticket===generation)setStatus(message(e),true); }
      finally { if(ticket===generation){processing=false;input.value='';render();} }
    }
    input.onchange = () => choose([...input.files]);
    async function uploads() {
      if (processing) throw Error('Đợi kiểm tra ảnh hoàn tất');
      const session = await MesAuth.getSession();
      if (!session) throw Error('Vui lòng đăng nhập lại');
      const images=[];
      for (const item of pending) {
        item.path ||= session.user.id+'/'+requestId+'/'+crypto.randomUUID()+'.jpg';
        if (!item.uploaded) {
          const r=await sb.storage.from(BUCKET).upload(item.path,item.blob,{contentType:'image/jpeg',upsert:false});
          // A response can be lost after a successful upload. Only reuse our immutable object.
          if (r.error) {
            if (!['409','Duplicate'].includes(String(r.error.statusCode || r.error.error))) throw Error(message(r.error));
            await check(sb.storage.from(BUCKET).createSignedUrl(item.path,60));
          }
          item.uploaded=true;
        }
        images.push({path:item.path,name:item.ten_file});
      }
      return images;
    }
    async function refresh() {
      const [rows,allowed,events]=await Promise.all([
        check(sb.from('ncp_hinh_anh').select('*').eq('id_ncp',caseId).is('xoa_luc',null).order('them_luc',{nullsFirst:true})),
        check(sb.rpc('ncp_anh_duoc_sua',{p_id_ncp:caseId})),
        check(sb.from('ncp_hinh_anh_lich_su').select('*').eq('id_ncp',caseId).order('thoi_diem',{ascending:false}))
      ]);
      saved=await Promise.all(rows.map(async row => ({...row,url:await getUrl(row)})));
      editable=!!allowed; history=events;
      logBody.replaceChildren(...history.map(e => {
        const p=document.createElement('p'); p.textContent=new Date(e.thoi_diem).toLocaleString('vi-VN')+' · '+(e.ten_nguoi||'Tài khoản')+' · '+(e.thao_tac==='xoa'?'Xóa':'Thêm')+' · '+e.ten_file; return p;
      }));
      if(!history.length)logBody.textContent='Chưa có thao tác mới.';
      onUrls(saved.map(x=>x.url).filter(Boolean)); render();
    }
    async function savePending() {
      if(busy || processing)return; lock(true);
      try {
        const images=await uploads(); await check(sb.rpc('ncp_anh_them',{p_id_ncp:caseId,p_images:images}));
        // Clear only after the server commits. Failed requests retain upload paths for safe retry.
        pending.forEach(x=>URL.revokeObjectURL(x.url));pending=[];
        await refresh();setStatus('Đã lưu hình ảnh.');
      } catch(e) {setStatus('Chưa hoàn tất: '+message(e)+'. Có thể bấm lưu lại.',true);}
      finally {lock(false);}
    }
    async function reset() {
      generation++; pending.forEach(x=>URL.revokeObjectURL(x.url));pending=[];saved=[];
      requestId=crypto.randomUUID();busy=false;processing=false;editable=false;input.value='';setStatus('');render();
      try {editable=!!(await check(sb.rpc('ncp_anh_duoc_sua',{p_id_ncp:null})));render();}
      catch(e){setStatus('Không tải được quyền hình ảnh: '+message(e),true);}
    }
    render();
    return {
      reset,
      async load(id) { caseId=id;lock(true);try{await refresh();setStatus('');}catch(e){setStatus('Không tải được hình ảnh: '+message(e),true);}finally{lock(false);} },
      async create(mode,data) {
        if(busy || processing)throw Error('Đợi kiểm tra/lưu ảnh hoàn tất');
        lock(true);
        const controls=[...(root.closest('.modal-box')?.querySelectorAll('input,select,textarea,button')||[])].map(el=>[el,el.disabled]);
        controls.forEach(([el])=>{el.disabled=true;});
        try {return await check(sb.rpc('ncp_mo_phieu_co_anh',{p_request_id:requestId,p_mode:mode,p_data:data,p_images:await uploads()}));}
        finally {controls.forEach(([el,disabled])=>{el.disabled=disabled;});lock(false);}
      }
    };
  }
  return {mount};
})();
