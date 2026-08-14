// Import dữ liệu module Quản lý tồn kho NVL từ Google Apps Script Web App
// (KHÔNG có CSV publish-to-web — khác với module Sản lượng) vào Supabase.
// Idempotent: dùng upsert theo khoá chính, chạy lại nhiều lần không tạo trùng
// dữ liệu — có thể dùng làm script đồng bộ định kỳ trong giai đoạn pilot.
//
// Cách chạy (PowerShell):
//   $env:SUPABASE_URL="https://fgghikpzcxjqzahfiiil.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="<service_role key, lấy ở Settings > API>"
//   node supabase/import-nvl.mjs
//
// Không commit service_role key vào git — chỉ truyền qua biến môi trường lúc chạy.
//
// LƯU Ý QUAN TRỌNG VỀ ĐƠN VỊ (khảo sát thực tế qua curl ngày 2026-08-12):
//   - getOpening, getSettings, getCurrentStock, getTransactions: dữ liệu gốc
//     lưu bằng TẤN (dù JSON không ghi rõ đơn vị) — xác nhận qua giá trị khớp
//     UI hiển thị "tấn" trong index.html (vd openingStock=21.113 tấn).
//   - getPlanDaily: dữ liệu gốc ĐÃ SẴN LÀ KG (comment trong code.js xác nhận,
//     giá trị hàng nghìn khớp thực tế — vd tieuHao ~1990 kg/ngày).
//   - getTemList: so_luong giữ nguyên đơn vị gốc ghi trên tem (kg hoặc pcs),
//     KHÔNG quy đổi.
// Vì schema mới chuẩn hoá lưu trữ bằng KG (xem schema_nvl.sql), script này
// nhân 1000 cho mọi giá trị đang là tấn (opening, settings, transactions),
// và giữ nguyên cho Kế Hoạch / Tem.
//
// GIỚI HẠN ĐÃ PHÁT HIỆN: action getTemList chỉ trả về 100 tem MỚI NHẤT (giới
// hạn cứng trong code.js, không có action lấy toàn bộ lịch sử) — import định
// kỳ chỉ đồng bộ được 100 tem gần nhất, không phải toàn bộ lịch sử Tem NVL.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Thiếu biến môi trường SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const GAS_URL = 'https://script.google.com/macros/s/AKfycbxXYRfz_wuz3RE0a8TCr4zWyzF23G5rc3SWo4ijKLcv7UkLBfdw2um1HbNwRZgAnCc/exec';

async function fetchAction(action) {
  const res = await fetch(`${GAS_URL}?action=${action}&_ts=${Date.now()}`);
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching action=${action}`);
  const data = await res.json();
  if (data && data.status === 'error') throw new Error(`GAS action=${action} trả lỗi: ${data.message}`);
  return data;
}

async function upsert(table, rows, conflictCols) {
  if (!rows.length) return;
  const url = `${SUPABASE_URL}/rest/v1/${table}?on_conflict=${conflictCols.join(',')}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(rows),
  });
  if (!res.ok) throw new Error(`Upsert ${table} failed: HTTP ${res.status} — ${await res.text()}`);
  console.log(`✓ ${table}: ${rows.length} dòng`);
}

async function main() {
  // --- Master materials (nguồn danh mục dùng chung — KHSX Master cột V:W) ---
  const master = await fetchAction('getMasterMaterials');
  const materials = (master && master.materials) || [];
  await upsert('nvl_materials', materials.map(m => ({
    ma_nvl: m.ma, ten_nvl: m.ten || m.ma,
  })).filter(r => r.ma_nvl), ['ma_nvl']);

  // --- Tồn đầu kỳ (đơn vị gốc = tấn → nhân 1000 ra kg) ---
  const opening = await fetchAction('getOpening');
  await upsert('nvl_ton_dau_ky', Object.entries(opening).map(([ma_nvl, o]) => ({
    ma_nvl,
    ngay_dau_ky: o.openingDate || null,
    ton_dau_ky_kg: (o.openingStock || 0) * 1000,
  })), ['ma_nvl']);

  // --- Kế hoạch daily 30 ngày (đơn vị gốc đã là kg, dạng dài 1 mã × 1 ngày) ---
  const planDaily = await fetchAction('getPlanDaily');
  const planRows = [];
  for (const [ma_nvl, p] of Object.entries(planDaily)) {
    const dates = p.dates || [];
    dates.forEach((ngay, i) => {
      if (!ngay) return;
      planRows.push({
        ma_nvl,
        ngay,
        nhap_kg: p.nhap ? p.nhap[i] : null,
        tieu_hao_kg: p.tieuHao ? p.tieuHao[i] : null,
        ton_du_kien_kg: p.tonDuKien ? p.tonDuKien[i] : null,
      });
    });
  }
  await upsert('nvl_ke_hoach_ngay', planRows, ['ma_nvl', 'ngay']);

  // --- Giao dịch (append-only, đơn vị gốc = tấn → nhân 1000 ra kg).
  // Không có khoá tự nhiên trong sheet gốc → dùng sheet_row (vị trí dòng vật
  // lý, bắt đầu từ dòng 4 theo code.js: getRange('A4:G10000')) làm khoá upsert
  // idempotent. ---
  const transactions = await fetchAction('getTransactions');
  await upsert('nvl_giao_dich', transactions.map((t, i) => ({
    sheet_row: i + 4,
    ngay: t.date || null,
    loai: t.type,
    ma_nvl: t.material,
    so_luong_kg: (t.quantity || 0) * 1000,
    ghi_chu: t.comment || '',
    ton_sau_kg: (t.afterStock || 0) * 1000,
    ts_goc: t.timestamp || null,
  })).filter(r => r.ma_nvl && r.loai), ['sheet_row']);

  // --- Tem NVL (chỉ 100 tem mới nhất — giới hạn của action getTemList).
  // Đơn vị giữ nguyên gốc (kg hoặc pcs), KHÔNG quy đổi. ---
  const tems = await fetchAction('getTemList');
  await upsert('nvl_tem', tems.map(t => ({
    tag_no: t.tagNo,
    ma_nvl: t.material,
    ten_nvl: t.tenNVL || '',
    ngay_nhap: t.ngayNhap || null,
    so_luong: t.soLuong,
    don_vi: t.donVi,
    ghi_chu: t.ghiChu || '',
    ts_goc: t.timestamp || null,
    trang_thai: t.status || '',
  })).filter(r => r.tag_no && r.ma_nvl), ['tag_no']);

  // --- Cài đặt / ngưỡng cảnh báo (đơn vị gốc = tấn → nhân 1000 ra kg) ---
  const settings = await fetchAction('getSettings');
  await upsert('nvl_cai_dat', Object.entries(settings).map(([ma_nvl, v]) => ({
    ma_nvl, be_rong_kg: (v || 0) * 1000,
  })), ['ma_nvl']);

  console.log('Xong.');
}

main().catch(e => { console.error(e); process.exit(1); });
