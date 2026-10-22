#!/usr/bin/env node
/**
 * scripts/code-review-check.cjs — kiểm tra tĩnh code sắp đưa lên prod
 * (bước 2 của .claude/skills/review-truoc-prod). Chỉ đọc file, không sửa gì.
 *
 *   node scripts/code-review-check.cjs [<from>..<to>]     (mặc định origin/master..origin/staging)
 *   node scripts/code-review-check.cjs --files a.html shared/b.js supabase/x.sql
 *
 * Kiểm tra:
 *  - HTML/JS: cú pháp (node --check), dòng > 400 ký tự (code nén), chữ < 11px
 *    trong CSS, thông báo lỗi thô (error.message / mã 42501 / tên migration)
 *    hiện cho người dùng, URL script/css không có ?v= khi file shared đổi.
 *  - SQL migration: hàm security definer thiếu revoke/grant, thiếu kiểm tra
 *    auth.uid()/has_role, tin tên người do client gửi (p_nguoi/p_user/p_actor),
 *    delete/drop/truncate, ghi "STAGING ONLY", số T/D trùng file khác.
 * Mỗi phát hiện in mức: [CAO] / [TB] / [THẤP]. Thoát mã 2 nếu có mức CAO.
 */
const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const sh = c => execSync(c, { cwd: ROOT, encoding: 'utf8' });
const args = process.argv.slice(2);
let files;
let range = 'origin/master..origin/staging';
if (args[0] === '--files') files = args.slice(1);
else {
  if (args[0]) range = args[0];
  files = sh(`git diff --name-only --diff-filter=AM ${range.replace('..', ' ')}`).split('\n').filter(Boolean);
}
files = files.filter(f => /\.(html|js|cjs|css|sql)$/.test(f) && fs.existsSync(path.join(ROOT, f)));

const out = [];
const add = (lv, f, msg) => out.push({ lv, f, msg });
const tmp = path.join(require('os').tmpdir(), 'mes-review-check.js');

for (const f of files) {
  const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
  const lines = src.split(/\r?\n/);

  if (/\.(html|js|cjs)$/.test(f)) {
    const code = f.endsWith('.html')
      ? [...src.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n;\n')
      : src;
    fs.writeFileSync(tmp, code);
    const r = spawnSync(process.execPath, ['--check', tmp], { encoding: 'utf8' });
    if (r.status !== 0) add('CAO', f, 'Lỗi cú pháp JavaScript: ' + (r.stderr.split('\n').find(l => /Error/.test(l)) || '').trim());

    const longs = lines.map((l, i) => [i + 1, l.length]).filter(x => x[1] > 400);
    if (longs.length) add(longs.length > 5 ? 'TB' : 'THẤP', f, `${longs.length} dòng > 400 ký tự (code nén, khó review/diff) — dài nhất dòng ${longs.sort((a, b) => b[1] - a[1])[0][0]} (${longs[0][1]}+ ký tự). Định dạng: npx prettier@3.3.3 --print-width 120`);

    const small = [...src.matchAll(/font-size\s*:\s*([0-9.]+)px/g)].filter(m => parseFloat(m[1]) < 11);
    if (small.length) add('THẤP', f, `${small.length} chỗ font-size < 11px trong CSS`);

    const raw = [];
    lines.forEach((l, i) => {
      if (/(alert|showToast|showMsg|textContent\s*=|innerHTML\s*=)[^;]*(\.message\b|42501|permission denied|migration|staging)/i.test(l)) raw.push(i + 1);
    });
    if (raw.length) add('THẤP', f, `(kiểm tay) Có thể hiện lỗi kỹ thuật thô cho người dùng ở dòng ${raw.slice(0, 8).join(', ')}${raw.length > 8 ? '…' : ''} — nên đổi câu dễ hiểu + <details> "Chi tiết kỹ thuật"`);

    if (f.endsWith('.html')) {
      const noVer = [...src.matchAll(/(?:src|href)="(shared\/[^"?]+\.(?:js|css))"/g)].map(m => m[1]).filter(s => files.includes(s) && !/navbar\.js|supabase-client\.js/.test(s));
      if (noVer.length) add('TB', f, `Nạp file shared vừa đổi nhưng không có ?v= (trình duyệt dùng bản cũ trong cache): ${noVer.join(', ')}`);
      if (/<title>/.test(src) && !/navbar\.js/.test(src) && !/location\.replace/.test(src)) add('TB', f, 'Trang không nạp shared/navbar.js (thiếu menu chung)');
    }
  }

  if (f.endsWith('.sql')) {
    const fnRe = /create\s+or\s+replace\s+function\s+(?:public\.)?(\w+)\s*\(([^)]*)\)([\s\S]*?)(?=create\s+or\s+replace\s+function|$)/gi;
    for (const m of src.matchAll(fnRe)) {
      const [, name, params, body] = m;
      if (!/security\s+definer/i.test(body)) continue;
      // Quyền có thể cấp trực tiếp, hoặc qua vòng lặp do $$ ... execute format('revoke ...') $$ (đồng đội hay dùng).
      const doBlocks = [...src.matchAll(/\bdo\s+(\$\w*\$)([\s\S]*?)\1/gi)].map(d => d[2]);
      const inDo = kw => doBlocks.some(d => new RegExp(kw, 'i').test(d) && new RegExp(`\\b${name}\\b`, 'i').test(d));
      const isTrigger = /returns\s+trigger/i.test(body);
      if (!new RegExp(`revoke[^;]*${name}[^;]*from[^;]*(public|anon)`, 'i').test(src) && !inDo('revoke')) add('CAO', f, `Hàm security definer ${name} thiếu "revoke ... from public, anon" (gọi được khi chưa đăng nhập)`);
      if (!isTrigger && !new RegExp(`grant\\s+execute[^;]*${name}`, 'i').test(src) && !inDo('grant\\s+execute')) add('TB', f, `Hàm ${name} thiếu "grant execute ... to authenticated"`);
      if (!isTrigger && !/auth\.uid\(\)/i.test(body)) add('CAO', f, `Hàm ${name} không kiểm tra auth.uid()`);
      if (!isTrigger && /\b(insert|update|delete)\b/i.test(body) && !/has_role/i.test(body)) add('TB', f, `Hàm ghi dữ liệu ${name} không kiểm tra vai trò has_role(...) — xác nhận có cố ý cho mọi tài khoản không`);
      const trusted = (params.match(/\bp_(nguoi|user|actor)\w*/gi) || []);
      if (trusted.some(p => new RegExp(`${p}\\b`, 'i').test(body.replace(params, '')) && !/user_roles/i.test(body))) add('TB', f, `Hàm ${name} lấy tên người thao tác từ tham số client (${trusted.join(', ')}) — nên lấy từ user_roles theo auth.uid()`);
    }
    if (/\b(drop\s+table|truncate)\b/i.test(src)) add('CAO', f, 'Có drop table / truncate — kiểm tra kỹ có làm mất dữ liệu thật không');
    else if (/\bdelete\s+from\b/i.test(src)) add('THẤP', f, 'Có delete from — xác nhận chỉ xoá dữ liệu phụ / có lịch sử, không xoá dữ liệu nghiệp vụ');
    if (/staging\s+only/i.test(src)) add('THẤP', f, 'Đầu file ghi "STAGING ONLY" — sửa lại trạng thái thật khi lên prod');
    const num = (path.basename(f).match(/migration_phase_([TDS]\d+)/i) || [])[1];
    if (num) {
      const same = fs.readdirSync(path.join(ROOT, 'supabase')).filter(x => new RegExp(`migration_phase_${num}[_a-z]`, 'i').test(x) && x !== path.basename(f));
      if (same.length) add('TB', f, `Số ${num} trùng với: ${same.join(', ')}`);
    } else if (/supabase\//.test(f)) add('THẤP', f, 'Tên file migration không theo quy ước migration_phase_<T|D|S><số>_...');
  }
}

const order = { CAO: 0, TB: 1, 'THẤP': 2 };
out.sort((a, b) => order[a.lv] - order[b.lv] || a.f.localeCompare(b.f));
console.log(`Đã kiểm ${files.length} file${args[0] === '--files' ? '' : ' (' + range + ')'}; ${out.length} phát hiện.`);
for (const o of out) console.log(`[${o.lv}] ${o.f}: ${o.msg}`);
process.exit(out.some(o => o.lv === 'CAO') ? 2 : 0);
