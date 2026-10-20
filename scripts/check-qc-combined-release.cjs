const fs=require('fs'),assert=require('assert/strict');
const migrations=['supabase/migration_phase_T118_qc_sessions_sources_ng.sql','supabase/migration_phase_T120_oqc_capacity_staging.sql'];
const names=migrations.map(file=>[...fs.readFileSync(file,'utf8').matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?(\w+)\s*\(/gi)].map(m=>m[1]));
assert.deepEqual(names[0].filter(name=>names[1].includes(name)),[],'T118/T120 must not redefine the same function');
const pages=['ipqc.html','ipqc-approval.html','qc-manager.html','ncp-detail.html','oqc-daily.html','oqc-capacity.html'];
for(const page of pages){const sources=[...fs.readFileSync(page,'utf8').matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/gi)].map(m=>m[1].split('?')[0]).filter(src=>src.startsWith('shared/'));assert.equal(sources.length,new Set(sources).size,'Duplicate module in '+page);}
const math=require('../shared/oqc-capacity-math.js');assert.equal(math.EFFICIENCY,.8);assert.equal(math.capacity(30,7).value,672);assert.equal(math.capacity(30,8).value,768);
const html=fs.readFileSync('oqc-capacity.html','utf8');for(const id of ['previewHours','planHours'])assert.ok(!new RegExp('<input[^>]*id="'+id+'"[^>]*value="7"').test(html),'No fixed 7-hour default');
console.log(JSON.stringify({result:'PASS',pagesWithoutDuplicateModules:pages.length,t118Functions:names[0].length,t120Functions:names[1].length,overlappingFunctions:0,planningEfficiency:.8,hours:'user input'}));
