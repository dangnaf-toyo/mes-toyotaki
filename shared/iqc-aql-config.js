/* Manager-only configuration of company-approved AQL tables; no values are prefilled. */
(() => {
  const root=document.getElementById('iqcDashboard');
  const button=document.createElement('button');button.type='button';button.className='button btn-secondary';button.textContent='Cấu hình AQL';
  const dialog=document.createElement('dialog');
  dialog.innerHTML=`<form id="iqcAqlConfigForm"><h3>Cấu hình AQL theo nhóm</h3>
    <label>Nhóm sản phẩm <input name="group" required></label><label>Mã sản phẩm/NVL trong nhóm, cách nhau bởi dấu phẩy <textarea name="products" required></textarea></label>
    <label>Tiêu chuẩn và phiên bản <input name="source" required></label><label>Phiên bản cấu hình <input name="version" required></label>
    <label>Mức kiểm <input name="level" required></label><label>AQL <input name="aql" required></label><label>Chế độ <select name="method" required><option value="">Chọn chế độ</option><option>Normal</option><option>Tightened</option><option>Reduced</option></select></label>
    <label>Khoảng LOT: mỗi dòng Từ, Đến, Mã chữ (để trống Đến nếu không giới hạn)<textarea name="ranges" required placeholder="1, 100, A"></textarea></label>
    <label>Bảng mẫu: mỗi dòng Mã chữ, Cỡ mẫu, Ac, Re; chuyển mã: Mã chữ, →, Mã đích<textarea name="plans" required placeholder="A, 10, 0, 1"></textarea></label>
    <p id="iqcAqlConfigError" role="status"></p><button type="submit" class="button btn-primary">Duyệt cấu hình</button> <button type="button" id="iqcAqlConfigClose" class="button btn-secondary">Hủy</button></form>`;
  root.prepend(button);root.append(dialog);button.onclick=()=>{dialog.querySelector('form').reset();document.getElementById('iqcAqlConfigError').textContent='';dialog.showModal();};document.getElementById('iqcAqlConfigClose').onclick=()=>dialog.close();
  dialog.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget, error=document.getElementById('iqcAqlConfigError'), submit=e.submitter;error.textContent='';submit.disabled=true;try{
    const val=n=>f.elements[n].value.trim(), int=s=>{if(!/^\d+$/.test(s))throw Error('Giá trị số không hợp lệ');return Number(s);};
    const lines=s=>s.split(/\r?\n/).filter(x=>x.trim()).map(x=>x.split(',').map(y=>y.trim()));
    const ranges=lines(val('ranges')).map(x=>{if(x.length!==3||!x[2])throw Error('Khoảng LOT không hợp lệ');return {min:int(x[0]),max:x[1]?int(x[1]):null,code:x[2]};});
    const plans={};for(const x of lines(val('plans'))){if(!x[0]||plans[x[0]])throw Error('Mã chữ trùng hoặc thiếu');if(x.length===3&&x[1]==='→'&&x[2])plans[x[0]]={use:x[2]};else if(x.length===4)plans[x[0]]={sample:int(x[1]),ac:int(x[2]),re:int(x[3])};else throw Error('Bảng mẫu không hợp lệ');}
    const products=val('products').split(',').map(x=>x.trim()).filter(Boolean);if(!ranges.length||!Object.keys(plans).length||!products.length)throw Error('Cần đủ nhóm, khoảng LOT và bảng mẫu');
    if(!confirm('Xác nhận bảng này đã được đối chiếu với tiêu chuẩn và phê duyệt cho nhóm sản phẩm?'))return;
    const r=await sb.rpc('iqc_luu_cau_hinh_aql',{p_nhom:val('group'),p_phien_ban:val('version'),p_nguon:val('source'),p_cap_do:val('level'),p_aql:val('aql'),p_phuong_an:val('method'),p_bang:{lotRanges:ranges,plans},p_san_pham:products,p_duyet:true});if(r.error)throw r.error;dialog.close();await loadDashboard();
  }catch(err){error.textContent=err.message||String(err);}finally{submit.disabled=false;}};
})();
