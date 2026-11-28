const assert=require('node:assert/strict');const {describe}=require('../shared/iqc-lot-status.js');
assert.deepEqual(describe({result:''},{checked:0,remaining:100}),{text:'CHƯA KIỂM',color:'gray'});
assert.deepEqual(describe({result:''},{checked:20,remaining:80,ng:5}),{text:'ĐANG KIỂM',color:'yellow'});
assert.deepEqual(describe({result:''},{checked:100,remaining:0,ng:5}),{text:'ĐÃ KIỂM HẾT · CHƯA KẾT LUẬN',color:'yellow'});
assert.equal(describe({result:'OK'},{checked:20,remaining:80}).text,'PASS');
assert.deepEqual(describe({result:'NG'},{checked:20,remaining:80}),{text:'NG',color:'red'});
assert.deepEqual(describe({result:'',multiPaused:true},{checked:20,remaining:80}),{text:'CHỜ XỬ LÝ',color:'orange'});
assert.equal(describe({result:''},{checked:null,remaining:null}).text,'CHƯA XÁC ĐỊNH');
console.log('PASS LOT colors and explicit quality decision independent of NG count and progress');
