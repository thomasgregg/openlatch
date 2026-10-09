// Preserve the approved RGB/body alpha. AI extraction is used only to remove
// the floor and tyre matte; it never substitutes a generated vehicle redraw.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'outputs/design/refined-cutouts');
const specs = [['model3',435],['modelY',420],['modelS',437],['modelX',429],['cybertruck',412]];
fs.mkdirSync(out,{recursive:true});
function bounds(data,w,h,threshold=240){
  let left=w,top=h,right=0,bottom=0;
  for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>threshold){
    left=Math.min(left,x);right=Math.max(right,x+1);top=Math.min(top,y);bottom=Math.max(bottom,y+1);
  }
  return {left,top,width:right-left,height:bottom-top};
}
(async()=>{
  const report=[];
  for(const [name,floor] of specs){
    const source=await sharp(path.join(root,'outputs/design/clean-cutouts/originals',name+'.png')).ensureAlpha().raw().toBuffer();
    const previous=await sharp(path.join(root,'outputs/design/clean-cutouts',name+'.png')).ensureAlpha().raw().toBuffer();
    const maskFile=path.join(root,'outputs/design/clean-cutouts/masks',name+(name==='cybertruck'?'-refined':'')+'.png');
    const maskInfo=await sharp(maskFile).metadata();
    const mask=await sharp(maskFile).ensureAlpha().raw().toBuffer();
    const target=bounds(source,640,480,100), crop=bounds(mask,maskInfo.width,maskInfo.height);
    const registered=await sharp(maskFile).extract(crop).resize(target.width,target.height).ensureAlpha().raw().toBuffer();
    const binary=Buffer.alloc(640*480);
    // Flood filling the white comparison backdrop also reached the S's white
    // A-pillars. Restore only paint enclosed by its existing outer contour.
    // These rows stop before the mirror-stalk band; no exterior is filled.
    const pillarSpans=new Map();
    if(name==='modelS')for(let y=128;y<=225;y++){
      let left=-1,right=-1;
      for(let x=125;x<=515;x++){
        const p=(y*640+x)*4;
        if(Math.min(source[p],source[p+1],source[p+2])<220){if(left<0)left=x;right=x;}
      }
      if(left>=0&&left<260&&right>380)pillarSpans.set(y,[left,right]);
    }
    for(let y=0;y<480;y++)for(let x=0;x<640;x++){
      const p=(y*640+x)*4;
      let a=source[p+3];
      const pillarSpan=pillarSpans.get(y);
      if(pillarSpan&&x>=pillarSpan[0]&&x<=pillarSpan[1])a=255;
      // Keep the repaired internal hood seam, away from every external contour.
      const seamLeft=name==='modelS'?115:185, seamRight=name==='modelS'?525:455;
      if(y>220&&y<floor-8&&x>seamLeft&&x<seamRight&&previous[p+3]===255)a=255;
      // The comparison export has a two-row alpha cut through the S hood.
      // Its neighbouring rows enclose this exact span of approved paint.
      if(name==='modelS'&&y>=265&&y<=266&&x>=89&&x<=551)a=255;
      if(name==='cybertruck'&&y>=149&&y<=165&&((x>=84&&x<118)||(x>522&&x<=556))&&Math.min(source[p],source[p+1],source[p+2])>180){
        const mx=x-target.left,my=y-target.top;
        a=Math.min(a,registered[(my*target.width+mx)*4+3]);
      }
      if(y>=floor-8){
        const mx=x-target.left,my=y-target.top;
        const ma=mx>=0&&my>=0&&mx<target.width&&my<target.height?registered[(my*target.width+mx)*4+3]:0;
        a=Math.min(a,ma);
      }
      // A pale floor reflection sits immediately below these dark bumpers.
      // Keep the actual dark underbody, discarding only the reflected matte.
      if(['modelS','modelX','cybertruck'].includes(name)&&y>=floor-3&&x>=150&&x<=490&&Math.min(source[p],source[p+1],source[p+2])>90)a=0;
      if(y>=440&&Math.min(source[p],source[p+1],source[p+2])>150)a=0;
      // The approved board's ground guide extends under the tyre contact line.
      if(y>=457)a=0;
      binary[y*640+x]=a>150?255:0;
    }
    // A one-pixel inset removes the source matte without shifting the canvas.
    const inset=Buffer.alloc(binary.length);
    for(let y=1;y<479;y++)for(let x=1;x<639;x++){
      let inside=true;
      for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(!binary[(y+dy)*640+x+dx])inside=false;
      inset[y*640+x]=inside?255:0;
    }
    const alpha=await sharp(inset,{raw:{width:640,height:480,channels:1}}).blur(0.4).greyscale().raw().toBuffer();
    const pixels=Buffer.from(source);
    for(let i=0;i<alpha.length;i++)pixels[i*4+3]=alpha[i];
    // The Cybertruck extraction also contains opaque white matte on a thin
    // contour band. Repair only its mirror housings/stalks and outer tyres.
    // Use inward source colours, preserving geometry and every interior pixel.
    const repairedEdges=new Set();
    const inCyberEdge=(x,y)=>name==='cybertruck'&&(
      (y>=105&&y<=166&&((x>=25&&x<=111)||(x>=529&&x<=615)))||
      (y>=270&&y<=456&&((x>=70&&x<=94)||(x>=546&&x<=570))));
    const boundaryDistance=(x,y)=>{
      for(let r=1;r<=4;r++)for(let dy=-r;dy<=r;dy++)for(let dx=-r;dx<=r;dx++){
        if(Math.max(Math.abs(dx),Math.abs(dy))!==r)continue;
        const nx=x+dx,ny=y+dy;
        if(nx<0||ny<0||nx>=640||ny>=480||alpha[ny*640+nx]<128)return r;
      }
      return 5;
    };
    for(let y=105;y<=456;y++)for(let x=25;x<=615;x++){
      if(!inCyberEdge(x,y))continue;
      const i=y*640+x,p=i*4;
      if(!alpha[i]||boundaryDistance(x,y)>3||Math.min(source[p],source[p+1],source[p+2])<65)continue;
      const inner=[];
      for(let dy=-6;dy<=6;dy++)for(let dx=-6;dx<=6;dx++){
        const nx=x+dx,ny=y+dy,d=dx*dx+dy*dy;
        if(d>36||!inCyberEdge(nx,ny)||alpha[ny*640+nx]!==255||boundaryDistance(nx,ny)<4)continue;
        const n=(ny*640+nx)*4;
        inner.push({n,d});
      }
      inner.sort((a,b)=>a.d-b.d);
      if(!inner.length)continue;
      const samples=inner.slice(0,5);
      const rgb=[0,1,2].map(c=>Math.round(samples.reduce((sum,{n})=>sum+source[n+c],0)/samples.length));
      if((source[p]+source[p+1]+source[p+2]-rgb.reduce((a,b)=>a+b,0))/3<15)continue;
      for(let c=0;c<3;c++)pixels[p+c]=rgb[c];
      repairedEdges.add(i);
    }
    // Decontaminate partial coverage using the nearest opaque source pixel.
    for(let y=0;y<480;y++)for(let x=0;x<640;x++){
      const i=y*640+x,p=i*4;
      if(alpha[i]===0||alpha[i]===255||repairedEdges.has(i))continue;
      let nearest=-1,distance=Infinity;
      for(let dy=-3;dy<=3;dy++)for(let dx=-3;dx<=3;dx++){
        const nx=x+dx,ny=y+dy,d=dx*dx+dy*dy;
        if(nx<0||nx>=640||ny<0||ny>=480||d>=distance)continue;
        const n=ny*640+nx;
        if(alpha[n]===255){nearest=n*4;distance=d;}
      }
      if(nearest>=0&&pixels[p]+pixels[p+1]+pixels[p+2]>source[nearest]+source[nearest+1]+source[nearest+2]+100){
        for(let c=0;c<3;c++)pixels[p+c]=source[nearest+c];
      }
    }
    const file=path.join(out,name+'.png');
    await sharp(pixels,{raw:{width:640,height:480,channels:4}}).png().toFile(file);
    if(process.argv.includes('--install'))fs.copyFileSync(file,path.join(root,'OpenLatch/Assets.xcassets',`CarFront-${name}.imageset/car.png`));
    let changedOpaqueRGB=0;
    for(let i=0;i<alpha.length;i++)if(alpha[i]===255&&!repairedEdges.has(i))for(let c=0;c<3;c++)if(pixels[i*4+c]!==source[i*4+c])changedOpaqueRGB++;
    if(changedOpaqueRGB)throw new Error(name+': approved body changed');
    if(pixels[(450*640+320)*4+3]!==0)throw new Error(name+': floor remains');
    report.push({name,canvas:[640,480],target,crop,changedOpaqueRGB,repairedEdgePixels:repairedEdges.size,maskFile});
  }
  fs.writeFileSync(path.join(out,'verification.json'),JSON.stringify(report,null,2)+'\n');
  // QA sheet only: identical assets shown on white and black backgrounds.
  const tiles=[];
  for(let row=0;row<2;row++)for(let col=0;col<specs.length;col++){
    const tile=await sharp(path.join(out,specs[col][0]+'.png')).flatten({background:row?'#000':'#fff'}).png().toBuffer();
    tiles.push({input:tile,left:col*640,top:row*480});
  }
  await sharp({create:{width:3200,height:960,channels:3,background:'#fff'}}).composite(tiles).png().toFile(path.join(out,'light-dark-check.png'));
  console.log(JSON.stringify(report));
})();
