// Use imagegen's extracted alpha with the approved RGB artwork. The model may
// repaint details, so its generated RGB is deliberately never used by the app.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const cars = [
  ['model3', 435, 166, 474], ['modelY', 420, 156, 484],
  ['modelS', 437, 147, 491], ['modelX', 429, 150, 490],
  ['cybertruck', 412, 150, 490]
];
const outlines = {
  model3: {body:[95,545,114], band:[198,237,153,133], mirrors:[[68,120,197,233],[520,573,197,233]], stems:[[120,143,227,238],[497,520,227,238]]},
  modelY: {body:[87,553,70], band:[156,208,158,129], mirrors:[[63,111,155,201],[531,577,155,201]], stems:[[111,142,190,208],[498,531,190,208]]},
  modelS: {body:[78,562,116], band:[198,240,150,120], mirrors:[[56,112,197,233],[533,585,197,233]], stems:[[112,141,227,240],[497,533,227,240]]},
  modelX: {body:[77,563,57], band:[148,200,150,120], mirrors:[[46,98,147,194],[542,594,147,194]], stems:[[98,142,183,201],[498,542,183,201]]},
  cybertruck: {body:[73,567,29], band:[110,162,137,110], mirrors:[[29,82,109,155],[558,611,109,155]], stems:[[82,122,148,163],[520,558,148,163]]}
};
(async () => {
  const report = [];
  for (const [name, floorY, floorLeft, floorRight] of cars) {
    const width = 640, height = 480;
    const original = await sharp(path.join(root, 'outputs/design/clean-cutouts/originals', name + '.png')).ensureAlpha().raw().toBuffer();
    const extracted = await sharp(path.join(root, 'outputs/design/clean-cutouts/masks', name + '.png')).resize(width, height).ensureAlpha().raw().toBuffer();
    const silhouette = Buffer.alloc(width * height);
    for (let i = 0; i < silhouette.length; i++) {
      const p = i * 4, x = i % width, y = Math.floor(i / width);
      const floor = y >= floorY && x >= floorLeft && x <= floorRight;
      silhouette[i] = !floor && original[p+3] > 100 && extracted[p+3] > 150 ? 255 : 0;
    }
    // The AI mask is only a starting segmentation. Recover the exact approved
    // outline from the source's dark enclosing contour, filling white paint
    // and accidental internal alpha seams without adopting an AI redraw.
    const outline = outlines[name];
    const sourceSpan = y => {
      let left=-1,right=-1;
      for(let x=112;x<=528;x++){
        const p=(y*width+x)*4;
        if(Math.min(original[p],original[p+1],original[p+2])<220){if(left<0)left=x;right=x;}
      }
      return [left,right];
    };
    const bandBefore=sourceSpan(outline.band[0]-3), bandAfter=sourceSpan(outline.band[1]+3);
    for (let y = outline.body[2]; y < 460; y++) {
      let lo = outline.body[0], hi = outline.body[1];
      const [y0,y1,x0,x1] = outline.band;
      if (y >= y0 && y <= y1) {
        lo = Math.floor(x0+(x1-x0)*(y-y0)/(y1-y0)-4);
        hi = width-lo;
      }
      let left = -1, right = -1;
      const threshold = y < outline.body[2]+14 ? 230 : 220;
      for (let x=lo; x<=hi; x++) {
        const p=(y*width+x)*4;
        if (Math.min(original[p],original[p+1],original[p+2]) < threshold) {
          if (left < 0) left=x; right=x;
        }
      }
      // The original comparison's mirror clips cut a white gap through the
      // A-pillars. Reconstruct the enclosing contour between intact rows.
      if(y>=y0 && y<=y1){
        const t=(y-(y0-3))/(y1-y0+6);
        left=Math.round(bandBefore[0]+(bandAfter[0]-bandBefore[0])*t);
        right=Math.round(bandBefore[1]+(bandAfter[1]-bandBefore[1])*t);
      }
      if (left < 0) continue;
      for (let x=outline.body[0]; x<=outline.body[1]; x++) silhouette[y*width+x]=0;
      for (let x=left; x<=right; x++) {
        const p=(y*width+x)*4;
        const floor = y >= floorY && x >= floorLeft && x <= floorRight;
        if (!floor) silhouette[y*width+x]=255;
      }
    }
    for (const [lo,hi,y0,y1] of outline.mirrors) for(let y=y0;y<=y1;y++) {
      let left=-1,right=-1;
      for(let x=lo;x<=hi;x++) {
        const p=(y*width+x)*4;
        if(Math.min(original[p],original[p+1],original[p+2])<185){if(left<0)left=x;right=x;}
      }
      if(left>=0)for(let x=left;x<=right;x++)silhouette[y*width+x]=255;
    }
    for(const [lo,hi,y0,y1] of outline.stems)for(let y=y0;y<=y1;y++)for(let x=lo;x<=hi;x++){
      const p=(y*width+x)*4;
      if(Math.max(original[p],original[p+1],original[p+2])<160)silhouette[y*width+x]=255;
    }
    for(let y=floorY-7;y<480;y++)for(let x=floorLeft;x<=floorRight;x++){
      const p=(y*width+x)*4;
      if(y>=floorY || Math.min(original[p],original[p+1],original[p+2])>145)silhouette[y*width+x]=0;
    }
    for(let y=456;y<480;y++)for(let x=0;x<width;x++){
      const p=(y*width+x)*4;
      if(Math.min(original[p],original[p+1],original[p+2])>100)silhouette[y*width+x]=0;
    }
    // Remove one pixel of matte at the outer boundary. Soft coverage restores
    // antialiasing without retaining the white background's coloured fringe.
    const inset = Buffer.alloc(width * height);
    for (let y = 1; y < height-1; y++) for (let x = 1; x < width-1; x++) {
      let inside = true;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (!silhouette[(y+dy)*width+x+dx]) inside = false;
      }
      inset[y*width+x] = inside ? 255 : 0;
    }
    const alpha = await sharp(inset, {raw: {width, height, channels: 1}}).blur(0.4).greyscale().raw().toBuffer();
    const output = Buffer.from(original);
    let decontaminated = 0;
    for (let i = 0; i < alpha.length; i++) {
      const p = i * 4;
      output[p+3] = alpha[i];
      if (!alpha[i] || alpha[i] === 255) continue;
      const x = i % width, y = Math.floor(i / width);
      // Only the partially covered edge may be decontaminated. White paint
      // in the opaque body retains its exact source pixels.
      let closest = null, distance = Infinity;
      for (let dy = -3; dy <= 3; dy++) for (let dx = -3; dx <= 3; dx++) {
        const nx = x+dx, ny = y+dy, d = dx*dx+dy*dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height || d >= distance) continue;
        const ni = ny*width+nx;
        if (alpha[ni] === 255) { closest = ni*4; distance = d; }
      }
      if (closest !== null && original[p]+original[p+1]+original[p+2] > original[closest]+original[closest+1]+original[closest+2]+120) {
        output[p] = original[closest]; output[p+1] = original[closest+1]; output[p+2] = original[closest+2]; decontaminated++;
      }
    }
    const hood = (250*width+320)*4;
    if (output[hood+3] !== 255) throw new Error(name + ': hood must remain opaque');
    for (let c=0;c<3;c++) if (output[hood+c] !== original[hood+c]) throw new Error(name + ': hood colour changed');
    if (output[(450*width+320)*4+3] !== 0) throw new Error(name + ': floor remains under bumper');
    const file = path.join(root, 'outputs/design/clean-cutouts', name + '.png');
    await sharp(output, {raw: {width, height, channels: 4}}).png().toFile(file);
    if(process.argv.includes('--install'))fs.copyFileSync(file,path.join(root,'OpenLatch/Assets.xcassets',`CarFront-${name}.imageset/car.png`));
    report.push({model:name, width,height, floorRemoved:true, opaqueHoodPreserved:true, edgePixelsDecontaminated:decontaminated});
  }
  fs.writeFileSync(path.join(root, 'outputs/design/clean-cutouts/verification.json'), JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
})();
