(() => {
  const source = document.querySelector('.deck-image');
  function build() {
    const width=source.naturalWidth, height=source.naturalHeight;
    if (!width || !height) return;
    let base=document.querySelector('.art-base');
    if(!base){base=document.createElement('canvas');base.className='art-base';base.setAttribute('aria-hidden','true');document.querySelector('.turntable').prepend(base);}
    base.width=width; base.height=height;
    const ctx=base.getContext('2d',{willReadFrequently:true}); ctx.drawImage(source,0,0);
    const data=ctx.getImageData(0,0,width,height), pixels=data.data;
    const plinth=new Path2D('M157 66 H1362 Q1469 66 1469 175 V850 Q1469 958 1364 958 H158 Q61 958 61 852 V172 Q61 66 157 66 Z');
    const inner=new Path2D('M165 111 H1358 Q1429 111 1429 184 V845 Q1429 920 1358 920 H166 Q104 920 104 843 V187 Q104 111 165 111 Z');
    const hardware=new Path2D('M1245 83 H1358 V190 H1245 Z M1280 179 A117 117 0 1 0 1280 413 A117 117 0 1 0 1280 179 M1098 665 L1182 701 L1118 821 L1010 772 Z');
    const tube=new Path2D('M1293 172 L1287 466 C1295 602 1260 674 1117 738 M1340 332 L1427 421 M1109 771 L1157 818');
    ctx.lineWidth=35;
    for(let y=0;y<height;y++) for(let x=0;x<width;x++){
      const i=(y*width+x)*4;
      const instrument=ctx.isPointInPath(hardware,x,y)||ctx.isPointInStroke(tube,x,y);
      const record=((x-664)/463)**2+((y-487)/444)**2<1;
      if(record&&!instrument){pixels[i+3]=0;continue;}
      if(!ctx.isPointInPath(plinth,x,y)&&!instrument){pixels[i+3]=0;continue;}
      const r=pixels[i],g=pixels[i+1],b=pixels[i+2];
      const value=Math.max(r,g,b);
      // The Forge asset uses a clean black matte, never a painted checkerboard.
      // Unpremultiply glass highlights so black becomes genuine alpha transparency.
      let alpha;
      if(instrument) alpha=Math.max(0,Math.min(1,(value-5)/24));
      else {
        alpha=Math.max(0,(value-3)/252);
        if(alpha>0){pixels[i]=Math.min(255,r/alpha);pixels[i+1]=Math.min(255,g/alpha);pixels[i+2]=Math.min(255,b/alpha);}
        if(ctx.isPointInPath(inner,x,y)) alpha*=.32;
      }
      pixels[i+3]=Math.round(alpha*255);
    }
    ctx.putImageData(data,0,0);
    const rotor=document.querySelector('.record-texture'); rotor.width=540; rotor.height=540;
    const rc=rotor.getContext('2d'); rc.drawImage(source,201,43,926,888,0,0,540,540);
    const clean=document.createElement('canvas');clean.width=540;clean.height=540;clean.getContext('2d').drawImage(rotor,0,0);
    // Reuse unobstructed opposite grooves beneath the stationary pickup.
    rc.save();rc.beginPath();rc.moveTo(270,270);rc.arc(270,270,400,20*Math.PI/180,57*Math.PI/180);rc.closePath();rc.clip();
    rc.translate(270,270);rc.rotate(Math.PI);rc.drawImage(clean,-270,-270);rc.restore();
    document.body.classList.add('art-ready');
  }
  if(source.complete) build(); else source.addEventListener('load',build,{once:true});
  const fader=new Image();fader.src='assets/volume-fader.png';
  fader.onload=()=>{
    const track=document.querySelector('.fader-track');track.width=1460;track.height=46;
    const tc=track.getContext('2d');tc.beginPath();tc.roundRect(0,0,1460,46,23);tc.clip();tc.drawImage(fader,38,460,1460,46,0,0,1460,46);tc.drawImage(fader,550,460,110,46,680,0,110,46);
    const knob=document.querySelector('.fader-knob');knob.width=104;knob.height=154;
    const kc=knob.getContext('2d');kc.beginPath();kc.roundRect(0,0,104,154,19);kc.clip();kc.drawImage(fader,719,404,104,154,0,0,104,154);
    document.body.classList.add('fader-ready');
  };
})();
