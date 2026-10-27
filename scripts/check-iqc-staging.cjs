/* Read-only: public staging key only. No login, write, or production requests. */
const fs = require('fs');
(async () => {
  const source = fs.readFileSync('shared/supabase-client.js', 'utf8');
  const url = source.match(/https:\/\/jcjbleugnclzsghfpmvk\.supabase\.co/)[0];
  const key = [...source.matchAll(/'([^']+)'/g)].map(m => m[1]).find(s => s.startsWith('eyJ'));
  for (const select of ['id', 'id,pham_vi,nguoi_kiem_id,nguoi_kiem_ten']) {
    const r = await fetch(url + '/rest/v1/iqc_lots?select=' + select + '&limit=0', {
      headers: { apikey:key, Authorization:'Bearer ' + key }
    });
    const data = await r.json();
    console.log(JSON.stringify({check:select,status:r.status,error:r.ok?null:{code:data.code,message:data.message}}));
  }
  const r = await fetch('https://mes-toyotaki.dangnaf.workers.dev/iqc.html', {headers:{'Cache-Control':'no-cache'}});
  console.log(JSON.stringify({check:'staging frontend',status:r.status,workspace:(await r.text()).includes('mes-iqc-workspace.js')}));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
