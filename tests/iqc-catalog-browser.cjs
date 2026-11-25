const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const { chromium } = require(process.env.MES_PLAYWRIGHT_PATH || 'playwright');
const { extendChemistry } = require('./iqc-chemistry-fixture.cjs');
const legacy = fs.readFileSync('tests/iqc-workspace-browser.cjs', 'utf8');
const base = legacy.slice(legacy.indexOf('function backend()'), legacy.indexOf('\n(async () => {'));
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.addInitScript({ content: base + `window.sb=backend();window.MesAuth={getSession:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),requireAuth:async()=>({user:{id:'00000000-0000-0000-0000-000000000001'}}),getCurrentUserIdentity:async()=>'ADMIN_Admin'};(${extendChemistry.toString()})();sb.saved.materials[0].supplierCode='SUP-AL';sb.tables.master_products.push({ma_sp:'PRODUCT-UNIQUE',ten_sp:'Sản phẩm mới'});` });
    await page.route('**/*', route => {
      const u = new URL(route.request().url());
      if (u.hostname !== 'mes.test' || ['/shared/supabase-client.js','/shared/navbar.js'].includes(u.pathname)) return route.fulfill({ body: '', contentType: 'application/javascript' });
      const f = path.resolve('.' + decodeURIComponent(u.pathname));
      if (!fs.existsSync(f) || !f.startsWith(process.cwd() + path.sep)) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ body: fs.readFileSync(f), contentType: f.endsWith('.js') ? 'application/javascript' : f.endsWith('.css') ? 'text/css' : 'text/html' });
    });
    await page.goto('https://mes.test/iqc.html');
    await page.locator('#iqcNewTab').click();
    await page.waitForSelector('#iqcMaterialStatus');
    await page.waitForFunction(() => [...document.querySelectorAll('#qc02-products option')].some(o => o.textContent.includes('SUP-AL') && o.textContent.includes('Kim loại mã A')));
    const code = page.locator('#productCode');
    await code.fill('product-unique');
    await page.waitForFunction(() => document.querySelector('#productName').value === 'Sản phẩm mới');
    await code.fill('sup-al');
    await page.waitForFunction(() => document.querySelector('#iqcChemRows tr')?.dataset.element === 'Si');
    assert.equal(await page.locator('#productName').inputValue(), 'Kim loại mã A');
    await page.locator('#iqcChemRows [data-measure]').first().fill('10.5');
    page.once('dialog', d => d.dismiss());
    await code.fill('[NVL] ZN-01');
    await page.waitForFunction(() => document.querySelector('#productCode').value === '[NVL] AL-01');
    assert.equal(await page.locator('#iqcChemRows [data-measure]').first().inputValue(), '10.5');
    page.once('dialog', d => d.accept());
    await code.fill('[NVL] ZN-01');
    await page.waitForFunction(() => document.querySelector('#iqcChemRows tr')?.dataset.element === 'Al');
    await page.evaluate(() => { sb.saved.materials.push({code:'NEW-01', name:'Mã mới', supplierCode:'VENDOR-NEW', group:'khac'}); });
    await code.fill('vendor-new');
    await page.waitForFunction(() => document.querySelector('#productName').value === 'Mã mới');
    assert.equal(await page.locator('#iqc-chemical-entry').isHidden(), true);
    await page.evaluate(async () => { const m=sb.saved.materials.find(x=>x.code==='NEW-01'); m.name='Tên đã đổi'; await IqcMaterialCatalog.load(true); window.dispatchEvent(new Event('iqc-catalog-refreshed')); });
    assert.equal(await page.locator('#productName').inputValue(), 'Tên đã đổi');
    await page.evaluate(async () => { const m=sb.saved.materials.find(x=>x.code==='NEW-01'); m.group='nhom'; m.grade='ADC12'; await IqcMaterialCatalog.load(true); window.dispatchEvent(new Event('iqc-catalog-refreshed')); });
    await page.waitForFunction(() => !document.querySelector('#iqc-chemical-entry').hidden);
    assert.deepEqual(errors, []);
    console.log('PASS direct typing, supplier codes, chemical mode, cancel/confirm change, fresh non-metal catalog');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
