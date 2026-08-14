// Import dữ liệu module Sản lượng & Giao hàng từ Google Sheet (CSV publish-to-web) vào Supabase.
// Idempotent: dùng upsert theo khoá chính, chạy lại nhiều lần không tạo trùng dữ liệu — có thể
// dùng làm script đồng bộ định kỳ trong giai đoạn chạy song song Sheet cũ / Supabase mới.
//
// Cách chạy (PowerShell):
//   $env:SUPABASE_URL="https://fgghikpzcxjqzahfiiil.supabase.co"
//   $env:SUPABASE_SERVICE_ROLE_KEY="<service_role key, lấy ở Settings > API>"
//   node supabase/import-sanluong.mjs
//
// Không commit service_role key vào git — chỉ truyền qua biến môi trường lúc chạy.

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Thiếu biến môi trường SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const CSV_URLS = {
  giaoHang: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=1605056068&single=true&output=csv',
  khsx: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=260979314&single=true&output=csv',
  capacity: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=1583553722&single=true&output=csv',
  forecast: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=740807083&single=true&output=csv',
  comments: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=124432865&single=true&output=csv',
  config: 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRSZR34zYG64CphKRulkYvm_6Ks2kWVHWsJM9NGUZLEjRKwSS6cZcOdMgL-zqEckxyNys_HE1EHEGf3/pub?gid=164897843&single=true&output=csv',
};

// --- Parse CSV giống hệt logic đang dùng trong sanluong.html (giữ nguyên để không lệch hành vi) ---
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
// sanluong.html — bắt buộc tái dùng đúng logic này, vì cast thẳng text sang numeric trong Postgres
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

  await upsert('sl_giao_hang', raw.giaoHang.map(o => ({
    thang: parseInt(o.Thang, 10), ke_hoach: toNum(o.KeHoach), thuc_te: toNum(o.ThucTe),
    ng_tra_ve: toNum(o.NG_TraVe), ng_huy: toNum(o.NG_Huy),
  })).filter(r => r.thang), ['thang']);

  await upsert('sl_khsx', raw.khsx.map(o => ({
    thang: parseInt(o.Thang, 10), duc_kh: toNum(o.Duc_KH), duc_tt: toNum(o.Duc_TT),
    bavia_kh: toNum(o.Bavia_KH), bavia_tt: toNum(o.Bavia_TT),
    gia_cong_kh: toNum(o.GiaCong_KH), gia_cong_tt: toNum(o.GiaCong_TT),
    son_kh: toNum(o.Son_KH), son_tt: toNum(o.Son_TT),
  })).filter(r => r.thang), ['thang']);

  await upsert('sl_capacity', raw.capacity.map(o => ({
    thang: parseInt(o.Thang, 10), capa350: toNum(o.Capa350), capa850: toNum(o.Capa850),
    capa_gc: toNum(o.CapaGC), loai: o.Loai,
  })).filter(r => r.thang && r.loai), ['thang', 'loai']);

  await upsert('sl_forecast', raw.forecast.map(o => ({
    thang: parseInt(o.Thang, 10), loai: o.Loai, fcc: toNum(o.FCC), exedy: toNum(o.Exedy),
    astemo: toNum(o.Astemo), tti: toNum(o.TTI), khac: toNum(o.Khac),
  })).filter(r => r.thang && r.loai), ['thang', 'loai']);

  await upsert('sl_comments', raw.comments.map(o => ({ key: o.Key, noi_dung: o.NoiDung }))
    .filter(r => r.key), ['key']);

  await upsert('sl_config', raw.config.map(o => ({ key: o.Key, value: o.Value }))
    .filter(r => r.key), ['key']);

  console.log('Xong.');
}

main().catch(e => { console.error(e); process.exit(1); });
