/* Conservative candidates from actual drawing text. Nothing is confirmed automatically. */
(function(root){
  const number='(?:\\d+(?:[.,]\\d+)?|[.,]\\d+)';
  function parseText(text,meta={}){
    const result=[];
    for(const original of String(text||'').split(/\r?\n/)){
      const raw=original.trim();if(!raw||raw.length>240)continue;
      const value=raw.replace(/[−–]/g,'-').replace(/⌀|Φ/g,'Ø').replace(/(\d),(\d)/g,'$1.$2');
      const special=/\bM\s*\d+(?:\s*[x×]\s*[\d.]+)?|[⌖⊥∥⏥◎]|GD\s*&\s*T|GENERAL\s*TOL|ISO\s*2768|JIS\s*B\s*0|\b(?:DRAFT|EMBOSS|LETTER|YEAR|MONTH|DAY|NOTE|SIZE|TOLERANCE)\b|\d\s*°\s*\d+\s*['′]/i.test(value);
      const explicit=new RegExp('([ØR]?[ ]*'+number+')[ ]*(?:±|\\+/-|\\+ / -)[ ]*('+number+')','i').exec(value);
      const signed=new RegExp('([ØR]?[ ]*'+number+')[ ]+([+-]'+number+')[ ]*(?:/|[ ])+[ ]*([+-]?'+number+')','i').exec(value);
      const bound=new RegExp('('+number+')[ ]*(MIN|MAX)\\b|\\b(MIN|MAX)[ ]*('+number+')','i').exec(value);
      const bare=new RegExp('^[ØR]?[ ]*'+number+'[ ]*(?:mm|°|deg)?$','i').test(value);
      const singleOffset=new RegExp('^[ØR]?[ ]*'+number+'[ ]*[+-][ ]*'+number+'[ ]*(?:mm|°|deg)?$','i').test(value);
      if(!special&&!explicit&&!signed&&!bound&&!bare&&!singleOffset&&!/[ØR]\s*\d|\d\s*°/.test(value))continue;
      if(/^\d{7,}$/.test(value))continue;
      const row={hang_muc:raw,kieu:special?'okng':'so',danh_nghia:'',dung_sai_tren:'',dung_sai_duoi:'',lsl:'',usl:'',
        don_vi:/°|\bdeg\b/i.test(value)?'°':/\bmm\b/i.test(value)?'mm':'',phuong_phap:'',dung_cu:'',tan_suat:'',co_mau:1,
        tieu_chuan:special?raw:'',da_xac_nhan:false,
        nguon_nhan_dien:{text:raw,trang:meta.page||1,vi_tri:meta.position||null,phuong_phap:meta.method||'text',
          do_tin_cay:meta.confidence??null,can_xac_minh:true,ghi_chu:'Kiểm tra lại bản vẽ trước khi xác nhận; không suy diễn dung sai chung.'}};
      const numeric=s=>Number(String(s).replace(/[ØR ]/g,''));
      if(!special&&explicit){row.danh_nghia=numeric(explicit[1]);row.dung_sai_tren=Number(explicit[2]);row.dung_sai_duoi=-Number(explicit[2]);}
      else if(!special&&signed){row.danh_nghia=numeric(signed[1]);row.dung_sai_tren=Number(signed[2]);row.dung_sai_duoi=Number(signed[3]);}
      else if(!special&&bound){row[/min/i.test(bound[2]||bound[3])?'lsl':'usl']=Number(bound[1]||bound[4]);}
      else if(!special){const angle=new RegExp('('+number+')[ ]*°').exec(value);const m=angle||new RegExp(number).exec(value);if(m)row.danh_nghia=Number(angle?angle[1]:m[0]);}
      if(row.danh_nghia!==''&&row.dung_sai_tren!=='')row.usl=Number((row.danh_nghia+row.dung_sai_tren).toPrecision(12));
      if(row.danh_nghia!==''&&row.dung_sai_duoi!=='')row.lsl=Number((row.danh_nghia+row.dung_sai_duoi).toPrecision(12));
      result.push(row);
    }
    return result;
  }
  function pdfSegments(items){
    const ordered=items.filter(i=>i.str?.trim()).map(i=>({...i,x:i.transform[4],y:i.transform[5],h:Math.max(1,Math.abs(i.height||i.transform[3]||8))}))
      .sort((a,b)=>b.y-a.y||a.x-b.x);
    const groups=[];
    for(const item of ordered){
      let group=groups.find(g=>Math.abs(g.y-item.y)<=Math.min(g.h,item.h)*.35&&item.x>=g.end-1&&item.x-g.end<Math.max(g.h,item.h)*3);
      if(!group){group={text:'',x:item.x,y:item.y,h:item.h,end:item.x};groups.push(group);}
      group.text+=(group.text?' ':'')+item.str;group.end=item.x+(item.width||0);
    }
    return groups;
  }
  const api={parseText,pdfSegments};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.IpqcDrawingParser=api;
})(typeof globalThis!=='undefined'?globalThis:this);
