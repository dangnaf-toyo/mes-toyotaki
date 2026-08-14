// Import nhật ký QR Chuyển công đoạn từ Google Sheet (CSV publish-to-web) vào Supabase.
// Idempotent: upsert theo id_phieu, chạy lại nhiều lần an toàn — dùng để đồng bộ định kỳ
// trong giai đoạn chạy song song (bảng này tăng nhanh nhất trong toàn hệ thống).
//
// Cách chạy (PowerShell):
//   $env:SUPABASE_URL="https://fgghikpzcxjqzahfiiil.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="<service_role/secret key, lấy ở Settings > API>"
//   node supabase/import-chuyencongdoan.mjs
//
// Không commit service_role key vào git — chỉ truyền qua biến môi trường lúc chạy.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Thiếu biến môi trường SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const CSV_URL = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vR0ND13RyA9AQesTrJRE5qoLCLEiUUqz9Rt-2yfmYEov84fPeVMI9N352I9JUuM3UAtnuqDokf4ahXA/pub?gid=0&single=true&output=csv';

// --- Parse CSV (giống hệt logic dùng ở các module trước) ---
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

function toNum(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = parseFloat(String(v).replace(',', '.'));
  return isNaN(n) ? null : n;
}

// "dd/MM/yyyy HH:mm:ss" (giờ Việt Nam, UTC+7) -> ISO string có offset, để Postgres
// lưu đúng thời điểm tuyệt đối thay vì hiểu nhầm theo UTC.
function toVNTimestamp(s) {
  const m = String(s || '').trim().match(/^(\d{2})\/(\d{2})\/(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return null;
  const [, dd, MM, yyyy, HH, mm, ss] = m;
  return `${yyyy}-${MM}-${dd}T${HH}:${mm}:${ss}+07:00`;
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
  const raw = await fetchCSV(CSV_URL);

  const rows = raw.map(o => ({
    id_phieu: o['ID Phiếu'],
    thoi_gian_chuyen: toVNTimestamp(o['Thời gian chuyển']),
    tag_no: o['Tag No'],
    ma_sp: o['Mã SP'] || null,
    ten_sp: o['Tên SP'] || null,
    sl_tren_tem: toNum(o['SL trên tem']),
    sl_thuc_chuyen: toNum(o['SL thực chuyển']),
    chenh_lech: toNum(o['Chênh lệch (hao hụt)']),
    lot_no: o['Lot No'] || null,
    so_khuon: o['Số khuôn'] || null,
    nguyen_lieu: o['Nguyên liệu'] || null,
    may_duc: o['Máy đúc'] || null,
    ngay_duc: o['Ngày đúc'] || null,
    cong_doan_giao: o['Công đoạn giao'],
    cong_doan_nhan: o['Công đoạn nhận'],
    nguoi_giao: o['Người giao'] || null,
    nguoi_nhan: o['Người nhận'],
    trang_thai_xac_nhan: o['Công đoạn trước xác nhận'] || null,
    ngay_gio_xac_nhan: o['Ngày giờ xác nhận'] || null,
  })).filter(r => r.id_phieu && r.thoi_gian_chuyen && r.tag_no && r.cong_doan_giao && r.cong_doan_nhan && r.nguoi_nhan);

  const skipped = raw.length - rows.length;
  if (skipped > 0) console.warn(`⚠ Bỏ qua ${skipped} dòng thiếu trường bắt buộc hoặc sai định dạng thời gian.`);

  await upsert('cd_chuyen_cong_doan_log', rows, ['id_phieu']);
  console.log('Xong.');
}

main().catch(e => { console.error(e); process.exit(1); });
