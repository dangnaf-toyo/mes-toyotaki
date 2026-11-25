const assert = require('node:assert/strict');
const { resolve } = require('../shared/iqc-aql-plan.js');
// Synthetic plans exercise resolution and are not a standard table.
const cfg = { approved:true, version:'TEST', source:'TEST ONLY', level:'II', aql:'0.65', method:'single-normal', groups:['fixture'],
  lotRanges:[{min:1,max:99,code:'A'},{min:100,max:199,code:'B'},{min:200,max:null,code:'C'}],
  plans:{A:{sample:10,ac:0,re:1},B:{use:'C'},C:{sample:50,ac:1,re:2}} };
assert.equal(resolve(cfg,'other',100), null);
assert.equal(resolve({...cfg,approved:false},'fixture',100), null);
assert.equal(resolve({...cfg,version:''},'fixture',100), null);
assert.equal(resolve(cfg,'fixture',5), null);
assert.deepEqual(resolve(cfg,'fixture',100), {code:'B',planCode:'C',sample:50,ac:1,re:2,level:'II',aql:'0.65',method:'single-normal',source:'TEST ONLY',version:'TEST'});
assert.equal(resolve({...cfg,lotRanges:[...cfg.lotRanges,{min:100,max:110,code:'A'}]},'fixture',100), null);
assert.equal(resolve({...cfg,plans:{B:{use:'C'},C:{use:'B'}}},'fixture',100), null);
assert.equal(resolve({...cfg,plans:{B:{sample:50,ac:1,re:4}}},'fixture',100), null);
assert.equal(resolve({...cfg,aql:'2.5'},'fixture',100).aql,'2.5');
console.log('PASS configured AQL resolution: group, approval, version, arrows, overlap, boundaries and varying AQL');
