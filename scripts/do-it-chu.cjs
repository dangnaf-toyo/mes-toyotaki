#!/usr/bin/env node
/**
 * scripts/do-it-chu.cjs — đo "ít chữ" tĩnh trên mã nguồn (không cần trình duyệt), để so trước/sau mỗi đợt tinh gọn.
 *
 *   node scripts/do-it-chu.cjs                 → đo bản đang sửa (thư mục làm việc)
 *   node scripts/do-it-chu.cjs --ref <commit>  → đo thêm bản ở commit đó và in cột chênh lệch
 *   node scripts/do-it-chu.cjs --tat           → chỉ in dòng TỔNG
 *
 * Mỗi trang *.html (gộp cả shared/*.js, shared/*.css vào dòng "shared/"):
 *   chu    = số ký tự chữ hiển thị trong HTML tĩnh (bỏ <script>/<style>/thẻ) — chữ do JS vẽ không đếm
 *   nut    = số <button> trong HTML tĩnh
 *   bt     = số biểu tượng emoji (trong cả HTML lẫn JS)
 *   f<11   = số khai báo font-size < 11px
 *   alert  = số lời gọi alert(  (từ T255 navbar.js đổi alert → thông báo góc màn hình)
 *   conf   = số lời gọi confirm(
 * Số đo trên giao diện thật (chữ < 11px đang hiện, nút thấp < 28px, tràn ngang): scripts/ui-review.cjs.
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const ref = args.includes('--ref') ? args[args.indexOf('--ref') + 1] : null;
const tat = args.includes('--tat');

const EMOJI = /\p{Extended_Pictographic}/gu;
const FONT = /font-size:\s*(?:[0-9]|10)(?:\.[0-9]+)?px/g;

function danhSach(r) {
  if (!r) {
    const html = fs.readdirSync(ROOT).filter(f => f.endsWith('.html'));
    const sh = fs.readdirSync(path.join(ROOT, 'shared')).filter(f => /\.(js|css|html)$/.test(f)).map(f => 'shared/' + f);
    return html.concat(sh);
  }
  return execSync('git ls-tree -r --name-only ' + r, { cwd: ROOT, encoding: 'utf8' })
    .split('\n').filter(f => /^[^/]+\.html$/.test(f) || /^shared\/[^/]+\.(js|css|html)$/.test(f));
}
function doc(f, r) {
  try {
    return r ? execSync('git show ' + r + ':"' + f + '"', { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 << 20 })
             : fs.readFileSync(path.join(ROOT, f), 'utf8');
  } catch (e) { return ''; }
}
function dem(src, laHtml) {
  const o = { chu: 0, nut: 0, bt: 0, f11: 0, alert: 0, conf: 0 };
  o.bt = (src.match(EMOJI) || []).length;
  o.f11 = (src.match(FONT) || []).length;
  o.alert = (src.match(/(?<![\w.$])(?:window\.)?alert\(/g) || []).length;
  o.conf = (src.match(/(?<![\w.$])(?:window\.)?confirm\(/g) || []).length;
  if (laHtml) {
    const than = src.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ');
    o.nut = (than.match(/<button\b/gi) || []).length;
    o.chu = than.replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, 'x').replace(/\s+/g, '').length;
  }
  return o;
}
function doHet(r) {
  const kq = {};
  for (const f of danhSach(r)) {
    const k = f.startsWith('shared/') ? 'shared/' : f;
    const d = dem(doc(f, r), f.endsWith('.html') && !f.startsWith('shared/'));
    const c = kq[k] || (kq[k] = { chu: 0, nut: 0, bt: 0, f11: 0, alert: 0, conf: 0 });
    for (const x in d) c[x] += d[x];
  }
  return kq;
}

const COT = ['chu', 'nut', 'bt', 'f11', 'alert', 'conf'];
const TEN = { chu: 'chu', nut: 'nut', bt: 'bt', f11: 'f<11', alert: 'alert', conf: 'conf' };
const nay = doHet(null);
const truoc = ref ? doHet(ref) : null;
const tong = o => COT.reduce((a, c) => (a[c] = Object.values(o).reduce((s, x) => s + x[c], 0), a), {});
const o = (v, t) => (t == null || v === t ? String(v) : v + '(' + (v - t > 0 ? '+' : '') + (v - t) + ')').padStart(13);

console.log('trang'.padEnd(34) + COT.map(c => TEN[c].padStart(13)).join(''));
const dong = (ten, a, b) => console.log(ten.padEnd(34) + COT.map(c => o(a[c], b && b[c])).join(''));
if (!tat) for (const k of Object.keys(nay).sort()) dong(k, nay[k], truoc && (truoc[k] || {}));
dong('TỔNG', tong(nay), truoc && tong(truoc));
if (ref) console.log('(trong ngoặc = chênh lệch so với ' + ref + ')');
