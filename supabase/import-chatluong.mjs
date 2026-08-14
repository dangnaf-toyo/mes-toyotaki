// Import dữ liệu module Chất lượng từ Google Sheet (CSV publish-to-web) vào Supabase.
// Idempotent: dùng upsert theo khoá chính, chạy lại nhiều lần không tạo trùng dữ liệu — có thể
// dùng làm script đồng bộ định kỳ trong giai đoạn chạy song song Sheet cũ / Supabase mới.
//
// Cách chạy (PowerShell):
//   $env:SUPABASE_URL="https://fgghikpzcxjqzahfiiil.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="<service_role key, lấy ở Settings > API>"
//   node supabase/import-chatluong.mjs
//
// Không commit service_role key vào git — chỉ truyền qua biến môi trường lúc chạy.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Thiếu biến môi trường SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const CSV_URLS = {
  tongHop:       'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=1828890824&single=true&output=csv',
  theoKhachHang: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=342438972&single=true&output=csv',
  theoCongDoan:  'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=902066588&single=true&output=csv',
  qcDaily:       'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=953026792&single=true&output=csv',
  qcRepaint:     'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=560817531&single=true&output=csv',
  targets:       'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=356174980&single=true&output=csv',
  comments:      'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=1687982602&single=true&output=csv',
  config:        'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=925884044&single=true&output=csv',
  batThuongThang:      'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=384977035&single=true&output=csv',
  batThuongKH:         'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=1135801931&single=true&output=csv',
  batThuongNB:         'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=924373293&single=true&output=csv',
  batThuongChuaTraLoi: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=523311830&single=true&output=csv',
  ngLan1:              'https://docs.google.com/spreadsheets/d/e/2PACX-1vSAseiF_WU7d5jEP0pNUPvQYgu0CMmmssR527y5rLpinWigJ9q2nyE2XdI6dscAkf47lJfHm0ii_muR/pub?gid=214850793&single=true&output=csv',
};

// --- Parse CSV giống hệt logic đang dùng trong chatluong.html (giữ nguyên để không lệch hành vi) ---
function parseCSV(text) {
  const rows = []; let row = [], field = '', inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else inQuotes = false; }
      else field += c;
    } else {
      if (c === '"') inQuotes = true;
      else if (c === ',') { row.push(field); field = ''; }
      else if (c === '\n' || c === '\r') {
        if (c === '\r' && text[i + 1] === '\n') i++;
        row.push(field); field = ''; rows.push(row); row = [];
      } else field += c;
    }
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows.filter(r => r.length > 1 || (r[0] !== undefined && r[0] !== ''));
}
function csvToObjects(rows) {
  if (!rows.length) return [];
  const headers = rows[0].map(h => (h || '').trim());
  return rows.slice(1).filter(r => r.some(v => v !== '')).map(r => {
    const obj = {};
    headers.forEach((h, i) => obj[h] = r[i] !== undefined ? String(r[i]).trim() : '');
    return obj;
  });
}
async function fetchCSV(url) {
  const sep = url.includes('?') ? '&' : '?';
  const res = await fetch(url + sep + '_ts=' + Date.now());
  if (!res.ok) throw new Error('HTTP ' + res.status + ' fetching ' + url);
  return csvToObjects(parseCSV(await res.text()));
}

// --- Chuẩn hoá số kiểu VN (dấu phẩy thập phân / dấu chấm ngăn cách nghìn) giống hệt toNum() trong
// chatluong.html — bắt buộc tái dùng đúng logic này, vì cast thẳng text sang numeric trong Postgres
// sẽ hiểu sai các giá trị dạng "0,60" (thập phân) hoặc lẫn lộn dấu phẩy/chấm. ---
function toNum(v) {
  if (v === undefined || v === null || v === '') return null;
  let s = String(v).trim();
  let isPct = false;
  if (s.endsWith('%')) { isPct = true; s = s.slice(0, -1).trim(); }

  const hasComma = s.includes(',');
  const hasDot = s.includes('.');
  if (hasComma && hasDot) {
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) s = s.replace(/\./g, '').replace(',', '.');
    else s = s.replace(/,/g, '');
  } else if (hasComma && !hasDot) {
    const parts = s.split(',');
    const lastLen = parts[parts.length - 1].length;
    s = (parts.length === 2 && lastLen !== 3) ? s.replace(',', '.') : s.replace(/,/g, '');
  }
  const n = parseFloat(s);
  if (isNaN(n)) return null;
  return isPct ? n / 100 : n;
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
  const raw = {};
  for (const [key, url] of Object.entries(CSV_URLS)) raw[key] = await fetchCSV(url);

  await upsert('cl_tong_hop', raw.tongHop.map(o => ({
    thang: parseInt(o.Thang, 10),
    san_luong_noi_bo_tong: toNum(o.SanLuongNoiBoTong),
    bao_phe_noi_bo_tong: toNum(o.BaoPheNoiBoTong),
    giao_hang_tong: toNum(o.GiaoHangTong),
    tra_ve_tong: toNum(o.TraVeTong),
    diem_thuong_phat: toNum(o.DiemThuongPhat),
  })).filter(r => r.thang), ['thang']);

  await upsert('cl_theo_khach_hang', raw.theoKhachHang.map(o => ({
    thang: parseInt(o.Thang, 10), khach_hang: o.KhachHang,
    san_luong: toNum(o.SanLuong), bao_phe: toNum(o.BaoPhe),
    giao_hang: toNum(o.GiaoHang), tra_ve: toNum(o.TraVe),
  })).filter(r => r.thang && r.khach_hang), ['thang', 'khach_hang']);

  // theoCongDoan: CSV có thêm 1-2 cột rác phía sau (ghi chú hướng dẫn nhập liệu) —
  // chỉ lấy 4 cột đầu (Thang, CongDoan, SanLuong, BaoPhe), bỏ qua phần còn lại.
  await upsert('cl_theo_cong_doan', raw.theoCongDoan.map(o => ({
    thang: parseInt(o.Thang, 10), cong_doan: o.CongDoan,
    san_luong: toNum(o.SanLuong), bao_phe: toNum(o.BaoPhe),
  })).filter(r => r.thang && r.cong_doan), ['thang', 'cong_doan']);

  // qcDaily: Ngay là text "dd/MM" không có năm — giữ nguyên là text, dùng làm khoá chính
  // y hệt hạn chế của Sheet gốc. CSV cũng có thể có cột rác phía sau, bỏ qua.
  await upsert('cl_qc_daily', raw.qcDaily.map(o => ({
    ngay: o.Ngay, so_luong_ng: toNum(o.SoLuongNG), ty_le_ng: toNum(o.TyLeNG),
  })).filter(r => r.ngay), ['ngay']);

  // qcRepaint: chỉ 2 dòng "Son lan 1"/"Son lai", cột rác phía sau bỏ qua.
  await upsert('cl_qc_repaint', raw.qcRepaint.map(o => ({
    loai: o.Loai, ty_le_ng: toNum(o.TyLeNG),
  })).filter(r => r.loai), ['loai']);

  await upsert('cl_targets', raw.targets.map(o => ({
    loai: o.Loai, ten: o.Ten,
    muc_tieu_noi_bo: toNum(o.MucTieuNoiBo), muc_tieu_tra_ve: toNum(o.MucTieuTraVe),
    theo_doi_tra_ve: o.TheoDoiTraVe,
  })).filter(r => r.loai && r.ten), ['loai', 'ten']);

  // comments: NoiDung chứa HTML rich-text thật (bold/color/div lồng nhau) — lưu nguyên
  // văn, KHÔNG xử lý/strip HTML.
  await upsert('cl_comments', raw.comments.map(o => ({ key: o.Key, noi_dung: o.NoiDung }))
    .filter(r => r.key), ['key']);

  await upsert('cl_config', raw.config.map(o => ({ key: o.Key, value: o.Value }))
    .filter(r => r.key), ['key']);

  await upsert('cl_bat_thuong_thang', raw.batThuongThang.map(o => ({
    thang: parseInt(o.Thang, 10),
    kh_tong_so: toNum(o.KH_TongSo), kh_da_doi_sach: toNum(o.KH_DaDoiSach),
    nb_tong_so: toNum(o.NB_TongSo), nb_da_doi_sach: toNum(o.NB_DaDoiSach),
  })).filter(r => r.thang), ['thang']);

  await upsert('cl_bat_thuong_kh', raw.batThuongKH.map(o => ({
    thang: parseInt(o.Thang, 10), duc: toNum(o.Duc), bavia: toNum(o.Bavia),
    gia_cong: toNum(o.GiaCong), son: toNum(o.Son),
  })).filter(r => r.thang), ['thang']);

  await upsert('cl_bat_thuong_nb', raw.batThuongNB.map(o => ({
    thang: parseInt(o.Thang, 10), duc: toNum(o.Duc), bavia: toNum(o.Bavia),
    gia_cong: toNum(o.GiaCong), son: toNum(o.Son),
  })).filter(r => r.thang), ['thang']);

  await upsert('cl_bat_thuong_chua_tra_loi', raw.batThuongChuaTraLoi.map(o => ({
    cong_doan: o.CongDoan, so_vu: toNum(o.SoVu),
  })).filter(r => r.cong_doan), ['cong_doan']);

  // ngLan1: nhiều dòng giá trị rỗng, chấp nhận null (toNum('') đã trả về null).
  await upsert('cl_ng_lan1', raw.ngLan1.map(o => ({
    thang: parseInt(o.Thang, 10), duc: toNum(o.Duc), bavia: toNum(o.Bavia),
    gia_cong: toNum(o.GiaCong), son: toNum(o.Son),
  })).filter(r => r.thang), ['thang']);

  console.log('Xong.');
}

main().catch(e => { console.error(e); process.exit(1); });
