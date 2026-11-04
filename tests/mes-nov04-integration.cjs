const fs = require('fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { parseHTML } = require('../.review/tools/node_modules/linkedom');

for (const file of ['oqc-daily.html', 'qc-manager.html', 'ncp-detail.html', 'ipqc-gia-cong.html', 'ipqc.html']) {
  const { document } = parseHTML(fs.readFileSync(file, 'utf8'));
  for (const script of document.querySelectorAll('script:not([src])')) {
    new vm.Script(script.textContent, { filename: file });
  }
}
const oqc = fs.readFileSync('shared/oqc-dashboard.js', 'utf8');
const sync = oqc.match(/const syncOutside\s*=\s*\(\)\s*=>\s*\{[\s\S]*?\};/)[0];
const outsourced = { style: {} }, scope = { value: 'POST_PAINTING' };
const context = vm.createContext({ outsourced, $: () => scope, editing:null, dataRows:[],
  OqcScope:require('../shared/oqc-scope.js') });
vm.runInContext(sync + ';syncOutside();', context);
assert.equal(outsourced.hidden, true);
assert.equal(outsourced.style.display, 'none');
scope.value = 'POST_OUTSOURCED_MACHINING';
vm.runInContext('syncOutside()', context);
assert.equal(outsourced.hidden, false);
assert.equal(outsourced.style.display, '');

const detailSource=fs.readFileSync('ncp-detail.html','utf8');
const handler=detailSource.match(/window\.addEventListener\('ncp-doi-sach-saved',[\s\S]*?\n\}\);/)[0];
const draft={id_doi_sach:'saved-id',noi_dung:'Before',nguoi_thuc_hien:'Before',danh_gia:'Unsaved evaluation'};
let savedHandler,rendered;
vm.runInNewContext(handler,{
  window:{addEventListener:(name,fn)=>{savedHandler=fn;}},
  state:{id:'N1',doiSach:{ps_tam_thoi:[draft]}},
  renderDoiSachList:key=>{rendered=key;}
});
savedHandler({detail:{id:'saved-id',nhom_cu:'ps_tam_thoi',data:{
  id_ncp:'N1',noi_dung_tra_loi:'From board',nguoi_phu_trach:'Inspector'
}}});
assert.equal(draft.noi_dung,'From board');
assert.equal(draft.danh_gia,'Unsaved evaluation');
assert.equal(rendered,'ps_tam_thoi');

const { window } = parseHTML('<html><body><div id="tab-ncp"></div></body></html>');
const document = window.document;
Object.defineProperty(window.HTMLSelectElement.prototype, 'value', {
  configurable: true,
  get() { return this._value || ''; },
  set(value) { this._value = value; }
});
const fixture = [
  { id: '1', id_ncp: 'N1', loai: 'noi_bo', trang_thai: 'chua_tra_loi', van_de: 'Internal pending' },
  { id: '2', id_ncp: 'N2', loai: 'khach_hang', trang_thai: 'qua_han', van_de: 'Customer overdue' },
  { id: '3', id_ncp: 'N3', loai: 'khach_hang', trang_thai: 'da_tra_loi', van_de: 'Customer answered',
    noi_dung_tra_loi: 'Response', tra_loi_muon: true }
];
const ui = vm.createContext({
  document, window, location: { search: '' }, URLSearchParams, console, setInterval() {},
  Qc02Data: { attachEmployees() {} },
  sb: { from: () => ({ select() { return this; }, order() { return this; } }) },
  sbTaiHet: async make => { make(); return { data: fixture }; }
});
vm.runInContext(fs.readFileSync('shared/ncp-doi-sach-board.js', 'utf8'), ui);
(async () => {
  await new Promise(setImmediate);
  const panel = document.querySelector('section');
  assert.equal(panel.querySelectorAll('tbody tr').length, 3);
  assert.ok(panel.textContent.includes('Chưa đặt hạn'));
  assert.ok(panel.textContent.includes('Trả lời quá hạn'));
  const styles = [...panel.querySelectorAll('tbody tr')].map(row => row.children[6].getAttribute('style'));
  assert.ok(styles[0].includes('#fef3c7'));
  assert.ok(styles[1].includes('#fee2e2'));
  assert.ok(styles[2].includes('#dcfce7'));
  panel.querySelector('[data-type]').value = 'khach_hang';
  panel.onchange();
  assert.equal(panel.querySelectorAll('tbody tr').length, 2);
  panel.querySelector('[data-status]').value = 'qua_han';
  panel.onchange();
  assert.equal(panel.querySelectorAll('tbody tr').length, 1);
  assert.ok(panel.querySelector('tbody').textContent.includes('Customer overdue'));
  console.log('PASS page script syntax, conditional outsourcing field, NCP colors/deadline/late flag and combined filters');
})().catch(error => { console.error(error); process.exitCode = 1; });
