/* Explicit business fields. Never substitute creation/update time for an inspection event. */
const MesQcFields=(()=>{
  const missing='Chưa ghi nhận';let defects=[],catalogReady=false,catalogPromise=null;
  function date(value){const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value||''));if(!m||+m[2]<1||+m[2]>12||+m[3]<1||+m[3]>new Date(Date.UTC(+m[1],+m[2],0)).getUTCDate())return '';return m[3]+'/'+m[2]+'/'+m[1];}
  function iso(value){if(!value)return null;let text=String(value);if(!date(text.slice(0,10)))return null;if(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?$/.test(text))text+='+07:00';const d=new Date(text);return Number.isNaN(d.getTime())?null:d.toISOString();}
  function input(value){const stamp=iso(value);if(!stamp)return '';return new Date(Date.parse(stamp)+7*3600000).toISOString().slice(0,16);}
  function display(value){const text=input(value);return text?date(text.slice(0,10))+' '+text.slice(11,16):missing;}
  function time(row){const m=/^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$/.exec(String(row?.inspection_time||''));return m&&+m[1]<24&&+m[2]<60?m[1]+':'+m[2]:missing;}
  function machine(row){const list=Array.isArray(row?.checklist_json)?row.checklist_json:Array.isArray(row?.checklist)?row.checklist:[];const item=list.find(x=>x.code==='machine_condition');return item?.dat===true?'PASS':item?.dat===false?'NG':null;}
  function cleanText(value){return String(value??'').replace(/\[QC02_[^\]\r\n]*\]/gi,'').replace(/\bQC02_[A-Z0-9_]+(?::[A-Z0-9_-]+)?\b/gi,'').replace(/[ \t]+\n/g,'\n').trim();}
  function defectName(item,source=defects){const custom=String(item?.code||'').startsWith('ng_khac_')||item?.is_other===true;const known=!custom&&source.find(x=>x.code===item?.code);return String((known?.label||item?.label||item?.name||item?.code||missing));}
  async function loadDefects(){if(catalogPromise)return catalogPromise;catalogPromise=(async()=>{const all=[];for(let offset=0;;offset+=500){const r=await sb.from('quality_defect_catalog').select('*').order('code').range(offset,offset+499);if(r.error)throw Error(r.error.message);all.push(...r.data||[]);if(!r.data||r.data.length<500)break;}defects=all;catalogReady=true;return all;})();try{return await catalogPromise;}catch(e){catalogPromise=null;throw e;}}
  return {missing,date,iso,input,display,time,machine,cleanText,defectName,loadDefects,catalogReady:()=>catalogReady};
})();
