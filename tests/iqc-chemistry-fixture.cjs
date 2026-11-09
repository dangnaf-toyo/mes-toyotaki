/* Isolated UI contract fixture; the real SQL/RLS is tested in the rollback suite. */
function extendChemistry() {
  const db = window.sb,
    originalRpc = db.rpc.bind(db),
    originalFrom = db.from.bind(db),
    uid = "00000000-0000-0000-0000-000000000001";
  window.sbTaiHet = async (make) => make();
  window.IS_PROD = false;
  window.MesNav = { setTitle() {} };
  const saved = JSON.parse(localStorage.getItem("iqc-chem-test") || "null") || {
    lots: db.tables.iqc_lots,
    materials: [
      { code: "AL-01", name: "Kim loại mã A", supplier: "TEST AL supplier", group: "nhom", grade: "ADC12" },
      { code: "ZN-01", name: "Kim loại mã Z", supplier: "TEST ZN supplier", group: "kem", grade: "ZAMAK3" },
      { code: "SP01", name: "Ống nhôm — kiểm ngoại quan", supplier: "VIỆT PHÁP", group: "khac", grade: null },
      { code: "AL-NO-TC", name: "Nhôm chưa có TC", group: "nhom", grade: "OTHER" },
      { code: "UNCLASSIFIED", name: "Chưa cấu hình", group: null, grade: null },
    ],
    headers: [
      {
        id: 10,
        cong_doan: "iqc_hoa_hoc",
        ma_sp: "AL-01",
        ma_nvl: "AL-01",
        mac_vat_lieu: "ADC12",
        nhom_vat_lieu: "nhom",
        phien_ban: "A",
        trang_thai: "da_duyet",
        ngay_hieu_luc: "2020-01-01",
        tao_luc: "2020-01-01",
        dang_dung: true,
      },
      {
        id: 20,
        cong_doan: "iqc_hoa_hoc",
        ma_sp: "ZN-01",
        ma_nvl: "ZN-01",
        mac_vat_lieu: "ZAMAK3",
        nhom_vat_lieu: "kem",
        phien_ban: "A",
        trang_thai: "da_duyet",
        ngay_hieu_luc: "2020-01-01",
        tao_luc: "2020-01-01",
        dang_dung: true,
      },
    ],
    features: [
      { id_btk: 10, muc_no: 1, ma_dac_tinh: "Si", lsl: 9.6, usl: 12, don_vi: "%", bat_buoc: true },
      { id_btk: 10, muc_no: 2, ma_dac_tinh: "Fe", lsl: null, usl: 1.3, don_vi: "%", bat_buoc: true },
      { id_btk: 20, muc_no: 1, ma_dac_tinh: "Al", lsl: 3.5, usl: 4.3, don_vi: "%", bat_buoc: true },
      { id_btk: 20, muc_no: 2, ma_dac_tinh: "Mg", lsl: 0.03, usl: 0.06, don_vi: "%", bat_buoc: true },
    ],
    requests: {},
    files: {},
    history: [],
  };
  Object.assign(db.tables, {
    iqc_lots: saved.lots,
    ipqc_btk: saved.headers,
    ipqc_btk_muc: saved.features,
    iqc_lich_su: saved.history,
    user_roles: [{ user_id: uid, username: "ADMIN", full_name: "Admin", role: "admin" }],
    master_machines: [],
    duc_ncp: [],
    duc_ncp_theo_doi: [],
  });
  db.saved = saved;
  db.calls = [];
  db.failAfterChem = false;
  db.uploads = [];
  const persist = () => localStorage.setItem("iqc-chem-test", JSON.stringify(saved));
  db.from = (table) => {
    const q = originalFrom(table);
    for (const name of ["in", "neq", "is", "contains"]) q[name] ||= () => q;
    return q;
  };
  const standard = (code, date) => {
    const c = saved.materials.find((x) => x.code === code),
      b = saved.headers
        .filter(
          (x) =>
            x.ma_nvl === code && x.mac_vat_lieu === c?.grade && x.trang_thai === "da_duyet" && x.ngay_hieu_luc <= date,
        )
        .sort((a, b) => b.ngay_hieu_luc.localeCompare(a.ngay_hieu_luc) || b.id - a.id)[0];
    return { phan_loai: c, tieu_chuan: b || null, nguyen_to: saved.features.filter((x) => x.id_btk === b?.id) };
  };
  db.rpc = async (name, args = {}) => {
    db.calls.push({ name, args });
    if (name === "qc_danh_sach_tai_khoan")
      return {
        data: [
          { username: "QC01", full_name: "Trần QC", role: "iqc" },
          { username: "ADMIN", full_name: "Admin", role: "admin" },
        ],
      };
    if (name === "iqc_nvl_danh_muc")
      return {
        data: {
          san_pham: db.tables.master_products.map((p) => ({ code: p.ma_sp, name: p.ten_sp })),
          nvl: saved.materials,
        },
      };
    if (name === "iqc_tc_hoa_hoc") return { data: standard(args.p_ma_nvl, args.p_ngay) };
    if (name === "iqc_nvl_luu_phan_loai") {
      const m = saved.materials.find((x) => x.code === args.p_ma_nvl);
      Object.assign(m, { group: args.p_nhom, grade: args.p_mac });
      persist();
      return { data: null };
    }
    if (name === "iqc_luu_hoa_hoc") {
      const d = args.p_data,
        prior = saved.requests[d.request_id];
      if (prior) return { data: { id: prior, result: saved.lots.find((r) => r.id === prior).result } };
      const m = saved.materials.find((x) => x.code === d.ma_nvl),
        tc = standard(m.code, d.ngay_kiem),
        a = IqcChemistry.evaluate(tc.nguyen_to, d.results);
      const old = saved.lots.find((x) => x.id === args.p_id),
        id = old?.id || String(saved.lots.length + 1),
        result = d.xac_nhan ? a.conclusion : "";
      const file = d.file ? { ...d.file, type: saved.files[d.file.path]?.type } : null;
      const row = {
        ...old,
        id,
        doi_tuong: "nvl",
        ma_nvl: m.code,
        nhom_vat_lieu: m.group,
        mac_vat_lieu: m.grade,
        phuong_thuc: "hoa_hoc",
        ngay_kiem: d.ngay_kiem,
        ca_kiem: d.ca_kiem,
        product_code: m.code,
        product_name: m.name,
        supplier: d.supplier,
        lot_no: d.lot_no,
        inspector: d.inspector,
        nguoi_kiem_id: d.inspector,
        nguoi_kiem_ten: "Trần QC",
        note: d.note,
        lot_qty: 0,
        sample_qty: 0,
        ok_qty: 0,
        ng_qty: 0,
        result,
        status: result ? "Đã kiểm tra" : "Đang kiểm tra",
        pham_vi: "Nguyên vật liệu",
        inspection_type: "Kiểm tra thành phần hóa học",
        received_at: d.ngay_kiem + "T00:00:00+07:00",
        created_at: old?.created_at || new Date().toISOString(),
        updated_at: new Date().toISOString(),
        hoa_hoc_json: {
          tieu_chuan: tc.tieu_chuan,
          nguyen_to: a.results.map((r) => ({
            element: r.element,
            min: r.lsl,
            max: r.usl,
            unit: r.don_vi,
            required: r.bat_buoc,
            value: r.value || null,
            result: r.result,
          })),
          file,
          xac_nhan: d.xac_nhan,
        },
      };
      if (old) Object.assign(old, row);
      else saved.lots.push(row);
      saved.requests[d.request_id] = id;
      saved.history.push({ loai: "bao_cao", khoa: id, thoi_diem: new Date().toISOString(), nguoi: "Admin" });
      persist();
      if (db.failAfterChem) {
        db.failAfterChem = false;
        return { error: { message: "Lost save response" } };
      }
      return { data: { id, result } };
    }
    if (name === "iqc_luu_tru_hoa_hoc") {
      saved.lots.find((x) => x.id === args.p_id).da_luu_tru = true;
      persist();
      return { data: null };
    }
    if (name === "iqc_tc_luu_hoa_hoc") {
      const d = args.p_data,
        m = saved.materials.find((x) => x.code === d.ma_nvl),
        id = args.p_id || Math.max(...saved.headers.map((x) => x.id), 0) + 1;
      const header = {
        id,
        cong_doan: "iqc_hoa_hoc",
        ma_nvl: m.code,
        ma_sp: m.code,
        mac_vat_lieu: m.grade,
        nhom_vat_lieu: m.group,
        phien_ban: d.phien_ban,
        ngay_hieu_luc: d.ngay_hieu_luc,
        noi_dung_sua_doi: d.noi_dung_sua_doi,
        trang_thai: args.p_gui ? "cho_kiem_tra" : "ban_nhap",
        nguoi_lap_uid: uid,
        nguoi_lap: "Admin",
        tao_luc: new Date().toISOString(),
      };
      const old = saved.headers.find((x) => x.id === id);
      if (old) Object.assign(old, header);
      else saved.headers.push(header);
      const kept = saved.features.filter((x) => x.id_btk !== id);
      saved.features.splice(
        0,
        saved.features.length,
        ...kept,
        ...d.nguyen_to.map((r, i) => ({
          id_btk: id,
          muc_no: i + 1,
          ma_dac_tinh: r.element,
          lsl: r.min === "" ? null : r.min,
          usl: r.max === "" ? null : r.max,
          don_vi: r.unit,
          bat_buoc: r.required,
          nguon_nhan_dien: { bat_buoc: r.required },
        })),
      );
      persist();
      return { data: id };
    }
    if (name === "ipqc_tc_duyet") {
      const h = saved.headers.find((h) => h.id === args.p_id);
      h.trang_thai =
        args.p_hanh_dong === "kiem_tra" ? "cho_phe_duyet" : args.p_hanh_dong === "phe_duyet" ? "da_duyet" : "tra_lai";
      persist();
      return { data: { ok: true } };
    }
    return originalRpc(name, args);
  };
  db.storage = {
    from(bucket) {
      return {
        async upload(path, file, opts) {
          db.uploads.push({ bucket, path, size: file.size, type: opts.contentType });
          saved.files[path] = { type: opts.contentType };
          persist();
          return { data: { path } };
        },
        async createSignedUrl(path) {
          return { data: { signedUrl: "https://mes.test/__iqc-files__/" + path } };
        },
      };
    },
  };
}
module.exports = { extendChemistry };
