// Read-only source drawing verification; local files/results stay in .review.
import fs from 'node:fs';import assert from 'node:assert/strict';import{createRequire}from'node:module';
import path from 'node:path';import {pathToFileURL}from'node:url';
const canvasRequire=createRequire(import.meta.url);
const {createCanvas,DOMMatrix,ImageData,Path2D}=canvasRequire(path.resolve('.review/tools/node_modules/@napi-rs/canvas'));
Object.assign(globalThis,{DOMMatrix,ImageData,Path2D});
const require=createRequire(import.meta.url),parser=require('../shared/ipqc-drawing-parser.js');
const {getDocument}=await import(pathToFileURL(path.resolve('.review/tools/node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href);
const {createWorker}=require(path.resolve('.review/tools/node_modules/tesseract.js'));
fs.mkdirSync('.review/ocr-models',{recursive:true});let worker;
try{
 for(const [index,file]of process.argv.slice(2).entries()){
  const pdf=await getDocument({data:new Uint8Array(fs.readFileSync(file)),useSystemFonts:true}).promise;
  const page=await pdf.getPage(1),content=await page.getTextContent();
  let rows=parser.pdfSegments(content.items).flatMap(segment=>parser.parseText(segment.text,{page:1,method:'pdf-text',position:{x:segment.x,y:segment.y}}));
  const viewport=page.getViewport({scale:2.5}),canvas=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height));
  await page.render({canvasContext:canvas.getContext('2d'),viewport}).promise;
  const png=canvas.toBuffer('image/png');fs.writeFileSync('.review/drawing-'+index+'.png',png);
  let method='pdf-text';
  if(rows.filter(row=>row.kieu==='so'&&row.danh_nghia!==''&&(row.lsl!==''||row.usl!=='')).length<3){
   if(!worker){worker=await createWorker('eng',1,{cachePath:'.review/ocr-models'});await worker.setParameters({tessedit_pageseg_mode:'11',preserve_interword_spaces:'1'});}
   const {data}=await worker.recognize(png,{}, {text:true,blocks:true});method=rows.length?'pdf-text+ocr':'ocr';
   const lines=(data.blocks||[]).flatMap(b=>(b.paragraphs||[]).flatMap(p=>p.lines||[]));
   rows.push(...(lines.length?lines.flatMap(line=>parser.parseText(line.text,{page:1,method:'ocr',confidence:line.confidence,position:line.bbox})):parser.parseText(data.text,{page:1,method:'ocr',confidence:data.confidence})));fs.writeFileSync('.review/ocr-'+index+'.txt',data.text);
  }
  assert.ok(rows.length>0,'Real drawing must yield candidate dimensions');assert.ok(rows.every(row=>row.da_xac_nhan===false));
  fs.writeFileSync('.review/drawing-'+index+'-candidates.json',JSON.stringify(rows,null,2));
  console.log(JSON.stringify({file:file.split(/[\\/]/).pop(),pages:pdf.numPages,textItems:content.items.length,method,candidates:rows.length,autoConfirmed:0}));
  await pdf.destroy();
 }
}finally{if(worker)await worker.terminate();}
