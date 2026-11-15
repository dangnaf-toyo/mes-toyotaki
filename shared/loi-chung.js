/* T265: Danh mục lỗi chung toàn nhà máy (mã 1 chữ nhóm + 2 số, vd "D01 Rỗ khí").
   Nguồn: bảng quality_defect_catalog (cột ma_loi, processes = công đoạn dùng).
   Công đoạn: DUC, DUC_KEM, BAVIA, GIA_CONG, SON, OQC, OQC_SON, IQC, IPQC.
   Dùng:  LoiChung.ds('BAVIA')  → [{ma, nhan}] (đồng bộ: bản DB nếu đã nạp, không thì bản dự phòng)
          LoiChung.nap()        → nạp lại từ DB (gọi 1 lần lúc mở màn)
          LoiChung.KHAC         → "Z99 Khác" (bắt buộc ghi rõ)
          LoiChung.laKhac(v)    → true với "Z99 Khác" hoặc "Khác" (bản cũ) */
(function (root) {
  'use strict';
  const NHOM = { D: 'Lỗi đúc', B: 'Lỗi bavia', G: 'Lỗi gia công', S: 'Lỗi sơn', T: 'Thao tác, vận chuyển', Z: 'Khác' };
  const T_ALL = 'DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC';
  // Bản dự phòng khi chưa nạp được DB — giữ khớp migration T265.
  const DU_PHONG = [
    ['D01', 'Rỗ khí', 'DUC,DUC_KEM,BAVIA,GIA_CONG,OQC,IQC,OQC_SON'], ['D02', 'Thiếu nhôm', 'DUC,DUC_KEM,BAVIA,GIA_CONG,OQC'],
    ['D03', 'Thiếu nhôm cạnh răng', 'BAVIA,GIA_CONG,OQC'], ['D04', 'Nhăn', 'DUC,BAVIA,GIA_CONG,OQC'],
    ['D05', 'Bong nhôm', 'BAVIA,GIA_CONG,OQC'], ['D06', 'Dính nhôm', 'BAVIA,GIA_CONG,OQC'],
    ['D07', 'Nứt', 'DUC,DUC_KEM,BAVIA,GIA_CONG,OQC,IQC'], ['D08', 'Phồng', 'DUC,DUC_KEM,BAVIA,OQC'],
    ['D09', 'Lõm pin', 'BAVIA,GIA_CONG,OQC'], ['D10', 'Lồi, lõm bề mặt', 'BAVIA,GIA_CONG,OQC,IQC'],
    ['D11', 'Bã trầu', 'BAVIA,OQC'], ['D12', 'Mỏng cuống', 'BAVIA'], ['D13', 'Tạp chất, dị vật', 'BAVIA,GIA_CONG,OQC,IQC'],
    ['D14', 'Biến dạng (cong, vênh, méo)', 'DUC,BAVIA,GIA_CONG,OQC,IQC'], ['D15', 'Mờ lot mark', 'BAVIA,GIA_CONG,OQC'],
    ['D16', 'Bắn nhôm', 'BAVIA,OQC'], ['D17', 'Nhẹ cân', 'DUC_KEM'], ['D18', 'Sai kích thước đúc', 'DUC,BAVIA'],
    ['B01', 'Sót bavia', 'BAVIA,GIA_CONG,OQC'], ['B02', 'Bẻ lõm sâu', 'BAVIA,OQC'],
    ['B03', 'Sứt, mẻ', 'DUC_KEM,BAVIA,GIA_CONG,OQC,OQC_SON,IQC'], ['B04', 'Dập lệch', 'BAVIA,OQC'],
    ['G01', 'Sai kích thước gia công', 'GIA_CONG,OQC,IQC'], ['G02', 'Lỗi ren', 'GIA_CONG,OQC,IQC'],
    ['G03', 'Gá lệch, lệch tâm', 'GIA_CONG,OQC'], ['G04', 'Cắt vát, vát C', 'GIA_CONG,OQC,IQC'],
    ['G05', 'Thiếu nguyên công', 'GIA_CONG,OQC'], ['G06', 'Chật JIG, không lọt JIG', 'GIA_CONG,OQC,IQC'],
    ['G07', 'Sót phoi', 'GIA_CONG,OQC'], ['G08', 'Độ nhám không đạt', 'GIA_CONG,OQC'], ['G09', 'Tụt chốt', 'GIA_CONG,OQC'],
    ['S01', 'Rỗ sơn', 'SON,OQC_SON'], ['S02', 'Mụn sơn', 'SON,OQC_SON'], ['S03', 'Thiếu sơn', 'SON,OQC_SON'],
    ['S04', 'Sần sơn', 'SON,OQC_SON'], ['S05', 'Nhăn sơn', 'SON,OQC_SON'], ['S06', 'Bavia sơn', 'SON,OQC_SON'],
    ['S07', 'Dày, mỏng sơn', 'SON,OQC_SON'], ['S08', 'Khác màu', 'SON,OQC_SON,IQC'], ['S09', 'Tạp chất trong sơn', 'SON,OQC_SON'],
    ['S10', 'Móp méo chân', 'SON,OQC_SON'], ['S11', 'Vênh chân', 'SON,OQC_SON'], ['S12', 'Lõm sơn', 'SON,OQC_SON'],
    ['T01', 'Va đập', T_ALL], ['T02', 'Xước bề mặt', T_ALL], ['T03', 'Sản phẩm rơi', 'DUC,DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON'],
    ['T04', 'Dính dầu, bẩn', T_ALL], ['T05', 'Mốc, ố, rỉ, oxi hóa', 'DUC_KEM,BAVIA,GIA_CONG,SON,OQC,OQC_SON,IQC'],
    ['Z01', 'Hủy để kiểm tra', 'BAVIA,GIA_CONG,OQC'], ['Z02', 'Hàng chỉnh máy', 'GIA_CONG'], ['Z99', 'Khác', T_ALL],
  ].map(([ma, ten, cd]) => ({ ma, nhan: ma + ' ' + ten, cd: cd.split(',') }));

  let ds = DU_PHONG, dangNap = null;
  const sx = (a, b) => a.ma.localeCompare(b.ma);

  function nap() {
    if (dangNap) return dangNap;
    const client = typeof sb !== 'undefined' ? sb : root.sb;
    if (!client) return Promise.resolve(ds);
    dangNap = client.from('quality_defect_catalog').select('ma_loi,label,processes').not('ma_loi', 'is', null).eq('is_active', true)
      .then(({ data, error }) => {
        if (error || !data || !data.length) return ds;
        const m = new Map();
        for (const r of data) {
          if (!(r.processes || []).length) continue; // hàng gộp trùng nghĩa
          const o = m.get(r.ma_loi) || { ma: r.ma_loi, nhan: r.label, cd: [] };
          o.cd = [...new Set([...o.cd, ...r.processes])];
          m.set(r.ma_loi, o);
        }
        if (m.size) ds = [...m.values()].sort(sx);
        return ds;
      })
      .catch(() => ds);
    return dangNap;
  }

  const KHAC = 'Z99 Khác';
  root.LoiChung = {
    NHOM, KHAC,
    nap,
    ds: (cd) => (cd ? ds.filter((x) => x.cd.includes(cd)) : ds.slice()),
    laKhac: (v) => { const s = String(v || '').trim(); return s === KHAC || s === 'Khác'; },
    nhomCua: (ma) => NHOM[String(ma || '').charAt(0)] || '',
  };
  nap();
})(typeof window !== 'undefined' ? window : this);
