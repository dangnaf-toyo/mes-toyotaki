(function(root){
  function capability(groups,spec){
    if(groups.length<30)return null;
    const n=groups[0]?.vals.length;
    if(!n||n>5||groups.some(g=>g.vals.length!==n))return null;
    const values=groups.flatMap(g=>g.vals);if(values.length<100||values.some(v=>!Number.isFinite(v)))return null;
    const ranges=n===1?groups.slice(1).map((g,i)=>Math.abs(g.x-groups[i].x)):groups.map(g=>g.r);
    const meanRange=ranges.reduce((sum,v)=>sum+v,0)/ranges.length;
    const sigma=meanRange/({1:1.128,2:1.128,3:1.693,4:2.059,5:2.326})[n];
    if(!(sigma>0))return null;
    const mean=values.reduce((sum,v)=>sum+v,0)/values.length;
    const cp=spec.usl!=null&&spec.lsl!=null?(spec.usl-spec.lsl)/(6*sigma):null;
    const limits=[spec.usl!=null?(spec.usl-mean)/(3*sigma):null,spec.lsl!=null?(mean-spec.lsl)/(3*sigma):null].filter(v=>v!=null);
    return limits.length?{cp,cpk:Math.min(...limits),sigma,mean}:null;
  }
  const api={capability};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.IpqcGcMath=api;
})(typeof globalThis!=='undefined'?globalThis:this);
