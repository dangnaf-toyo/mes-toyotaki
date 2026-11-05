/* Isolated API contract fixture. SQL behavior is verified separately on staging. */
function backend(options = {}) {
  const standard = {id:1,ma_sp:'PART',phien_ban:'A',cong_doan:'gia_cong',dang_dung:true,
    trang_thai:'da_duyet',ngay_hieu_luc:'2026-01-01',so_mau:2,ma_ban_ve:'DWG',buoc_gia_cong:'Phay mặt A'};
  const feature = (id,code,name,nominal,tolerance,count) => ({id,id_btk:1,muc_no:id,ma_dac_tinh:code,
    hang_muc:name,kieu:'so',danh_nghia:nominal,dung_sai_tren:tolerance,dung_sai_duoi:tolerance,
    lsl:nominal-tolerance,usl:nominal+tolerance,co_mau:count,don_vi:'mm',dung_cu:'CMM'});
  const tables = {
    master_products:[{ma_sp:'PART',ten_sp:'Part',ten_khach_hang:'Customer'}],
    master_machines:[{ma_may:'MC01',bo_phan:'Gia công - Sơn'}],
    user_roles:[{user_id:'u1',username:'QC01',full_name:'Inspector',role:options.role||'admin'}],
    ipqc_btk:options.empty?[]:[standard],
    ipqc_btk_muc:options.empty?[]:[feature(1,'D01','Đường kính',20,.05,2),feature(2,'L02','Chiều dài',38,.2,2),
      feature(3,'W03','Chiều rộng',15,.1,2)],
    ipqc_gc_lan:[],ipqc_gc_kq:[],ipqc_lan_tong_hop:[],ipqc_gc_tieu_chuan_lich_su:[],
    ...options.tables
  };
  const calls=[],orders=[],uploads=[];
  const db={tables,calls,orders,uploads,from(name){
    let data=[...(tables[name]||[])],single=false,error=null;
    const query={select(){return query;},eq(k,v){data=data.filter(r=>String(r[k])===String(v));return query;},
      neq(k,v){data=data.filter(r=>String(r[k])!==String(v));return query;},
      in(k,values){data=data.filter(r=>values.some(v=>String(r[k])===String(v)));return query;},
      or(){return query;},limit(n){data=data.slice(0,n);return query;},
      gte(k,v){data=data.filter(r=>r[k]>=v);return query;},lte(k,v){data=data.filter(r=>r[k]<=v);return query;},
      ilike(k,v){data=data.filter(r=>String(r[k]||'').toLowerCase().includes(v.replaceAll('%','').toLowerCase()));return query;},
      order(k){orders.push({table:name,column:k});
        if(name==='master_machines'&&!['ma_may','bo_phan'].includes(k))error={code:'42703',message:'column '+k+' does not exist'};
        data.sort((a,b)=>String(a[k]||'').localeCompare(String(b[k]||'')));return query;},
      range(a,b){data=data.slice(a,b+1);return query;},single(){single=true;return query;},maybeSingle(){single=true;return query;},
      then(resolve,reject){return Promise.resolve({data:single?data[0]||null:data,error}).then(resolve,reject);}};
    return query;
  },async rpc(name,args){
    calls.push({name,args});
    if(name==='ipqc_gc_luu_do'){
      const p=args.p_data,prior=tables.ipqc_gc_lan.find(r=>r.request_id===p.request_id);
      if(prior)return {data:prior.id};
      const b=tables.ipqc_btk.find(r=>r.id===p.id_btk),features=tables.ipqc_btk_muc.filter(r=>r.id_btk===b?.id);
      if(!b||b.trang_thai!=='da_duyet')return {error:{code:'P0001',message:'Tiêu chuẩn chưa phát hành'}};
      const id='saved-'+(tables.ipqc_gc_lan.length+1),kq=p.kq.map(k=>{
        const m=features.find(m=>m.muc_no===k.muc_no);
        return {...k,dat:m.kieu==='so'?Number.isFinite(k.gia_tri)&&(m.lsl==null||k.gia_tri>=m.lsl)&&
          (m.usl==null||k.gia_tri<=m.usl):k.dat};
      });
      const row={id,request_id:p.request_id,id_btk:b.id,ma_sp:b.ma_sp,revision:b.phien_ban,
        buoc_gia_cong:b.buoc_gia_cong,ma_may:p.ma_may,ca:p.ca,ma_lo:p.ma_lo,
        nguoi_kiem:'Inspector',thoi_diem:new Date().toISOString(),so_mau:Math.max(...kq.map(k=>k.mau)),
        dat:kq.every(k=>k.dat),tieu_chuan:{btk:{...b},muc:features.map(m=>({...m}))},
        nguon_nhap:p.nguon_nhap||'nhap_tay',tep_ket_qua:p.tep_ket_qua||null,nhan_dien:p.nhan_dien||null,kq};
      tables.ipqc_gc_lan.push(row);tables.ipqc_lan_tong_hop.push({...row,cong_doan:'gia_cong'});
      tables.ipqc_gc_kq.push(...kq.map(k=>({...k,id_lan:id})));return {data:id};
    }
    return {data:null,error:null};
  },storage:{from(bucket){return{
    async upload(path,file){uploads.push({bucket,path,size:file.size});return {data:{path},error:null};},
    async createSignedUrl(path){return {data:{signedUrl:'https://example.invalid/'+path},error:null};}
  };}}};
  return db;
}
module.exports={backend};
