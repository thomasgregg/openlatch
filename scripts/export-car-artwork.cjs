// Mechanical export of the approved comparison, without any AI redraw.
// A common canvas preserves relative sizes and the ground baseline in the app.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'output/playwright/car-comparison-windshield-refined.png');
const cars = [['model3',350],['modelY',970],['modelS',1600],['modelX',2240],['cybertruck',2900]];
(async () => {
  const exports = [];
  for (const [name, cx] of cars) {
    const width = 640, height = 480;
    const {data} = await sharp(source).extract({left:cx-320,top:260,width,height}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    // Remove only connected exterior backdrop. The dark enclosing silhouette
    // protects white body panels, glass and lamps. Preserve their RGB pixels.
    const exterior = new Uint8Array(width*height), queue = new Int32Array(width*height);
    let head=0, tail=0;
    const visit = index => {
      if (exterior[index]) return;
      const p=index*4;
      if (Math.min(data[p],data[p+1],data[p+2])<235) return;
      exterior[index]=1; queue[tail++]=index;
    };
    for(let x=0;x<width;x++){visit(x);visit((height-1)*width+x);}
    for(let y=0;y<height;y++){visit(y*width);visit(y*width+width-1);}
    while(head<tail){
      const i=queue[head++],x=i%width,y=Math.floor(i/width);
      if(x>0)visit(i-1); if(x<width-1)visit(i+1);
      if(y>0)visit(i-width); if(y<height-1)visit(i+width);
    }
    // The S's antialiased hood outline has small bright gaps. Protect its
    // interior envelope before applying the exterior mask, so white paint
    // cannot be mistaken for backdrop. Interpolate across the mirror band.
    if(name==='modelS'){
      const span=y=>{
        const xs=[];
        for(let x=82;x<559;x++){
          const p=(y*width+x)*4;
          if(data[p]+data[p+1]+data[p+2]<480)xs.push(x);
        }
        if(!xs.length)throw new Error('Missing S body outline at '+y);
        return [xs[0],xs[xs.length-1]];
      };
      const before=span(190),after=span(245);
      for(let y=210;y<=430;y++){
        const edges=y<245 ? before.map((v,i)=>Math.round(v+(after[i]-v)*(y-190)/55)) : span(y);
        for(let x=edges[0];x<=edges[1];x++)exterior[y*width+x]=0;
      }
    }
    for(let i=0;i<exterior.length;i++)if(exterior[i])data[i*4+3]=0;
    // The comparison's horizontal ground guide is presentation-only.
    for(let y=458;y<height;y++)for(let x=0;x<width;x++){
      const p=(y*width+x)*4;
      if(y>=460 || data[p]+data[p+1]+data[p+2]>480)data[p+3]=0;
    }
    // Body white at the centre of the hood must survive the exterior mask.
    if(data[(250*width+320)*4+3]!==255)throw new Error(name+' lost its hood');
    const directory=path.join(root,'OpenLatch/Assets.xcassets',`CarFront-${name}.imageset`);
    fs.mkdirSync(directory,{recursive:true});
    await sharp(data,{raw:{width,height,channels:4}}).png().toFile(path.join(directory,'car.png'));
    fs.writeFileSync(path.join(directory,'Contents.json'),JSON.stringify({images:[{filename:'car.png',idiom:'universal'}],info:{author:'xcode',version:1}},null,2)+'\n');
    exports.push({model:name,source,left:cx-320,top:260,width,height,baseline:460,exteriorPixels:tail});
  }
  fs.writeFileSync(path.join(root,'outputs/design/app-artwork-export.json'),JSON.stringify(exports,null,2)+'\n');
  if(fs.existsSync(path.join(root,'outputs/design/clean-cutouts/masks/cybertruck-refined.png'))){
    require('node:child_process').execFileSync(process.execPath,[path.join(root,'scripts/refine-car-cutouts.cjs'),'--install'],{stdio:'inherit'});
  }else if(fs.existsSync(path.join(root,'outputs/design/clean-cutouts/masks/model3.png'))){
    require('node:child_process').execFileSync(process.execPath,[path.join(root,'scripts/clean-car-cutouts.cjs'),'--install'],{stdio:'inherit'});
  }
  console.log('Exported the five approved cars at one scale and baseline.');
})();
