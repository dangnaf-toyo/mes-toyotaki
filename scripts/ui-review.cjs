#!/usr/bin/env node
/**
 * scripts/ui-review.cjs — chụp màn hình + đo nhanh giao diện các trang MES
 * với phiên đăng nhập GIẢ (không cần tài khoản thật), dùng cho bước
 * "review trước khi đưa lên prod" (.claude/skills/review-truoc-prod).
 *
 *   node scripts/ui-review.cjs [--out <thư mục>] trang1.html "trang2.html?id=..." ...
 *
 * Mở file cục bộ (file://) → shared/supabase-client.js tự dùng DB STAGING.
 * Phiên giả: ghi token vào localStorage + chặn /auth/v1/user, mọi lời gọi
 * /rest/v1 đổi Authorization sang khoá anon staging → dữ liệu đọc công khai
 * hiện được, RPC/bảng cần quyền sẽ báo lỗi quyền (bình thường, không phải lỗi trang).
 *
 * In mỗi trang × 2 cỡ (d = 1366×768, m = 390×844):
 *   h = chiều cao trang, w = bề rộng (w > khung = tràn ngang), font<11 = số phần
 *   tử chữ < 11px, tinyBtn = nút cao < 28px, err = lỗi JavaScript.
 * Ảnh lưu ở <out>/<tên_trang>_d.png / _m.png.
 *
 * Cần Playwright + Chromium. Đường dẫn lấy theo biến môi trường:
 *   MES_PLAYWRIGHT = thư mục module playwright (mặc định: require('playwright'))
 *   MES_CHROME     = file chrome.exe (mặc định: Chromium của Playwright)
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
let out = path.join(require('os').tmpdir(), 'mes-ui-review');
const pages = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') out = path.resolve(args[++i]);
  else pages.push(args[i]);
}
if (!pages.length) {
  console.error('Cách dùng: node scripts/ui-review.cjs [--out <thư mục>] trang.html ...');
  process.exit(1);
}
fs.mkdirSync(out, { recursive: true });

const { chromium } = require(process.env.MES_PLAYWRIGHT || 'playwright');
const src = fs.readFileSync(path.join(ROOT, 'shared/supabase-client.js'), 'utf8');
const ref = (src.match(/https:\/\/([a-z0-9]+)\.supabase\.co'\s*;/) || [])[1];
const anon = (src.match(/:\s*'(eyJ[^']+)'/) || [])[1];
if (!ref || !anon) throw new Error('Không đọc được URL / khoá anon staging trong shared/supabase-client.js');

const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const exp = Math.floor(Date.now() / 1000) + 86400;
const uid = '00000000-0000-0000-0000-000000000001';
const jwt = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64({ sub: uid, role: 'authenticated', exp }) + '.x';
const user = { id: uid, email: 'review@mes.local', aud: 'authenticated', role: 'authenticated' };
const sess = { access_token: jwt, refresh_token: 'r', expires_at: exp, expires_in: 86400, token_type: 'bearer', user };

(async () => {
  const browser = await chromium.launch(process.env.MES_CHROME ? { executablePath: process.env.MES_CHROME } : {});
  let bad = 0;
  for (const [W, H, tag] of [[1366, 768, 'd'], [390, 844, 'm']]) {
    const ctx = await browser.newContext({ viewport: { width: W, height: H } });
    await ctx.addInitScript(([k, s]) => { localStorage.setItem(k, s); }, ['sb-' + ref + '-auth-token', JSON.stringify(sess)]);
    await ctx.route('**/auth/v1/user**', r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(user) }));
    await ctx.route('**/rest/v1/**', r => r.continue({ headers: { ...r.request().headers(), authorization: 'Bearer ' + anon } }));
    for (const pg of pages) {
      const p = await ctx.newPage();
      const errs = [];
      p.on('pageerror', e => errs.push(e.message.slice(0, 140)));
      await p.goto('file:///' + ROOT.replace(/\\/g, '/') + '/' + pg).catch(e => errs.push('nav ' + e.message));
      await p.waitForTimeout(3500);
      const m = await p.evaluate(() => ({
        h: document.documentElement.scrollHeight,
        w: document.documentElement.scrollWidth,
        small: [...document.querySelectorAll('body *')].filter(e => e.offsetParent &&
          [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim()) &&
          parseFloat(getComputedStyle(e).fontSize) < 11).length,
        tinyBtn: [...document.querySelectorAll('button,a.btn,a.btn-ghost,a.tab-btn')]
          .filter(e => e.offsetParent && e.getBoundingClientRect().height < 28).length,
      }));
      const overflow = m.w > W;
      if (errs.length || overflow) bad++;
      await p.screenshot({ path: path.join(out, pg.replace(/[^a-z0-9]+/gi, '_') + '_' + tag + '.png') });
      console.log(tag, pg.padEnd(38), 'h', m.h, 'w', m.w + (overflow ? ' TRÀN' : ''), 'font<11:', m.small,
        'tinyBtn:', m.tinyBtn, 'err:', errs.length ? errs.join(' | ') : '-');
      await p.close();
    }
    await ctx.close();
  }
  await browser.close();
  console.log('Ảnh:', out);
  process.exit(bad ? 2 : 0);
})();
