const assert=require('node:assert/strict');
const M=require('../shared/oqc-dashboard-math.js');
const row={ok_qty:1200,ng_qty:0,so_nguoi_kiem:3,gio_kiem_thuc_te:2,inspector_code:'QC01',
 context:{inspection_scope:'FULL_POST_MACHINING'},work:{labor:[{employee_code:'QC01',hours:2}],seconds_per_piece:18,target_efficiency:.8}};
const a=M.summary([row],[]);
assert.equal(a.hours,6);assert.equal(a.productivity,200);assert.equal(a.personTurns,3);assert.equal(a.people,1);
assert.equal(M.summary([row,row],[]).personTurns,6);assert.equal(M.summary([row,row],[]).people,1);
assert.equal(M.summary([{...row,gio_kiem_thuc_te:null}],[]).hours,null);
assert.equal(M.summary([{...row,so_nguoi_kiem:null}],[]).hours,2);
assert.equal(M.summary([{...row,work:{...row.work,labor:[{employee_code:'QC01',hours:2},{employee_code:'QC02',hours:1}]}}],[]).hours,5);
console.log('PASS 3 × 2 = 6 hours, 200 PCS/person/hour, distinct workers vs headcount turns, no invented time, legacy hours retained');
