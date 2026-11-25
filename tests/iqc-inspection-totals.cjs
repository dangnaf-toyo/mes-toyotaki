const assert = require('node:assert/strict');
const { inspection, summarize } = require('../shared/iqc-inspection-totals.js');
const rounds = [
  {id:1,checked:2000,ok:1980,ng:20},
  {id:2,checked:3000,ok:2960,ng:40},
];
assert.deepEqual(summarize(10000, rounds), {total:10000,checked:5000,ok:4940,ng:60,remaining:5000,progress:'Đang kiểm',ngPercent:1.2});
assert.equal(summarize(10000, [...rounds,{id:3,checked:5000,ok:5000,ng:0}]).progress, 'Đã kiểm hết');
assert.equal(summarize(10000, []).progress, 'Chưa kiểm');
assert.equal(summarize(10000, rounds, {paused:true}).progress, 'Tạm dừng / Chờ xử lý');
assert.equal(summarize(10000, rounds, {legacyUnknown:true}).checked, null);
assert.throws(() => summarize(10000, [...rounds,rounds[0]]), /trùng/);
assert.throws(() => summarize(4999, rounds), /vượt/);
assert.throws(() => inspection({checked:5,ok:4,ng:0}), /OK \+ NG/);
assert.throws(() => inspection({checked:2.5,ok:1,ng:1}), /nguyên/);
// Defect occurrences do not determine the number of rejected pieces.
assert.equal(summarize(10, [{id:1,checked:10,ok:8,ng:2,defects:[{qty:2},{qty:2}]}]).ng, 2);
console.log('PASS IQC inspection totals, validation, legacy unknown and independent defect occurrences');
