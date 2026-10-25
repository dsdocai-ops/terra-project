const PW={o:'#3A2014',Y:'#F2B65A',y:'#C7782E',L:'#FFF6D0',H:'#7A4422',S:'#EDB98E',s:'#D0946A',e:'#2A1A14',J:'#D9572B',j:'#A83A1E',B:'#6A3A1E',G:'#8A5A30',N:'#3E4E74',n:'#2C3858',K:'#5A3420'};
const PH=Object.assign({},PW,{o:'#2A1410',Y:'#8A8FA0',y:'#5E6372',L:'#FFE07A',H:'#C8CCD8',S:'#8E5C3C',s:'#6E4228',J:'#C2622E',j:'#8A3A1A',B:'#EFE2C8',G:'#5A3A2A',N:'#6A4258',n:'#4A2A3E',K:'#3A2418'});
const BODY=[".....oooo.....","....oYYYYo....","...oYYLLYYo...","..oyYYYYYYyo..","..oyyyyyyyyo..","..oHHSSSSHHo..","..oHSeSSeSHo..","..oHsSSSSsHo..","..oHoSSSSoHo..","...ooJSSJoHo..","..oJJJBJJJJoH.",".oJjJJBJJJJjo.",".oJjJJBJJJJjo.",".oGoJJJJJJoGo.","..ooBBBBBBoo..","...oNNNNNNo...","...oNNnnNNo...","...oNNooNNo...","...oNo..oNo...","..oKKo..oKKo..","..oooo..oooo.."];
function circ(g,cx,cy,r,c){for(let y=-r;y<=r;y++){const w=Math.round(Math.sqrt(Math.max(0,r*r-y*y)));R(g,cx-w,cy+y,w*2+1,1,c);}}
function line2(g,x0,y0,x1,y1,c){const n=Math.max(1,Math.round(Math.max(Math.abs(x1-x0),Math.abs(y1-y0))));for(let t=0;t<=n;t++)R(g,x0+(x1-x0)*t/n,y0+(y1-y0)*t/n,1,1,c);}
function quad(g,a,b,c,d,col){tri(g,a,b,c,col);tri(g,a,c,d,col);}
function lerp(a,b,t){return[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];}
function up(p,h){return[p[0],p[1]-h];}
function face(g,p0,p1,h,base,line,st,stl,mort,dir){const x0=Math.round(p0[0]),x1=Math.round(p1[0]);for(let cx=x0;cx<x1;cx++){const by=Math.floor(p0[1]+(cx-x0)*dir/2);for(let r=0;r<h;r++){let c=base;if(r<4){c=r===2?mort:(((((cx+(r>2?2:0))>>2)&1)?st:stl));if(((cx+(r>2?2:0))&3)===0)c=mort;}else if((h-r)%3===0)c=line;R(g,cx,by-r,1,1,c);}}}
let WREC=null;
function win(g,p0,dir,fx,len,r0){const cx0=Math.round(p0[0]+fx*len);for(let u=0;u<7;u++){const by=Math.floor(p0[1]+(cx0+u-Math.round(p0[0]))*dir/2);for(let r=r0;r<r0+8;r++){let c='#3E5E84';if(u===0||u===6||r===r0||r===r0+7)c='#F2E6CC';else if(u===3||r===r0+4)c='#E0D2B4';else if(u<3&&r>r0+4)c='#9AC4E6';R(g,cx0+u,by-r,1,1,c);if(WREC&&(c==='#3E5E84'||c==='#9AC4E6'))WREC.push([cx0+u,by-r]);}R(g,cx0+u,by-r0+1,1,1,'#6E4428');}for(let r=r0+1;r<r0+7;r++){const byL=Math.floor(p0[1]+(cx0-1-Math.round(p0[0]))*dir/2);R(g,cx0-1,byL-r,1,1,'#2E6A3A');const byR=Math.floor(p0[1]+(cx0+7-Math.round(p0[0]))*dir/2);R(g,cx0+7,byR-r,1,1,'#2E6A3A');}}
function door(g,p0,dir,fx,len){const cx0=Math.round(p0[0]+fx*len);for(let u=0;u<7;u++){const by=Math.floor(p0[1]+(cx0+u-Math.round(p0[0]))*dir/2);for(let r=0;r<12;r++){let c=(u&1)?'#7A4A28':'#6A3E20';if(u===0||u===6||r===11)c='#3A2214';R(g,cx0+u,by-r,1,1,c);}R(g,cx0+u,by+1,1,1,'#9A9488');}const by=Math.floor(p0[1]+(cx0+5-Math.round(p0[0]))*dir/2);R(g,cx0+5,by-6,1,1,'#F2C14E');}
function house2(g,x,y,w,d,h,rh,pal,opt){
  const T=[x,y],Rt=[x+8*w,y+4*w],B=[x+8*w-8*d,y+4*w+4*d],Lt=[x-8*d,y+4*d];
  g.globalAlpha=0.22;quad(g,[T[0]+10,T[1]+3],[Rt[0]+14,Rt[1]+4],[B[0]+14,B[1]+4],[Lt[0]+10,Lt[1]+3],'#1A2A10');g.globalAlpha=1;
  face(g,Lt,B,h,pal.wl,pal.wlL,'#A8A294','#8A8478','#6A6458',1);
  face(g,B,Rt,h,pal.wr,pal.wrL,'#8E887C','#77716A','#5A5448',-1);
  for(let r=0;r<h;r++){R(g,Lt[0],Lt[1]-r,1,1,'#3A2214');R(g,B[0],B[1]-r,1,1,'#E8C090');R(g,Rt[0]-1,Rt[1]-r,1,1,'#3A2214');}
  (opt.winL||[]).forEach((f)=>win(g,Lt,1,f,B[0]-Lt[0],6));(opt.winR||[]).forEach((f)=>win(g,B,-1,f,Rt[0]-B[0],6));
  if(opt.doorL!=null)door(g,Lt,1,opt.doorL,B[0]-Lt[0]);if(opt.doorR!=null)door(g,B,-1,opt.doorR,Rt[0]-B[0]);
  const Lh=up(Lt,h),Bh=up(B,h),Th=up(T,h),Rh=up(Rt,h),Rl=up(lerp(T,Lt,0.5),h+rh),Rr=up(lerp(Rt,B,0.5),h+rh);
  const ov=(p,dx,dy)=>[p[0]+dx,p[1]+dy];
  quad(g,ov(Th,-1,-1),ov(Rh,2,0),ov(Rr,2,0),ov(Rl,-1,0),pal.rd);
  tri(g,Bh,Rh,Rr,pal.wr);for(let k=3;k<rh;k+=3)line2(g,...lerp(Bh,Rr,k/rh),...lerp(Rh,Rr,k/rh),pal.wrL);
  const cw=lerp(lerp(Bh,Rh,0.5),Rr,0.4);circ(g,Math.round(cw[0]),Math.round(cw[1]),2,'#F2E6CC');R(g,cw[0]-1,cw[1]-1,2,2,'#3E5E84');
  const a=ov(Lh,-2,2),b=ov(Bh,1,3),c2=ov(Rr,2,0),dd=ov(Rl,-2,0);
  quad(g,a,b,c2,dd,pal.r);
  const n=Math.max(3,Math.round(rh/2.2));
  for(let k=1;k<n;k++){const t=k/n,p=lerp(a,dd,t),q=lerp(b,c2,t);line2(g,p[0],p[1],q[0],q[1],pal.rs);const len=q[0]-p[0];for(let u=(k%2)*2;u<len;u+=4)R(g,p[0]+u,p[1]+u/2-1,1,1,pal.rs);}
  line2(g,a[0],a[1],b[0],b[1],pal.ro);line2(g,a[0],a[1]+1,b[0],b[1]+1,'#2A1410');
  line2(g,dd[0],dd[1],c2[0],c2[1],pal.rh);line2(g,dd[0],dd[1]-1,c2[0],c2[1]-1,pal.ro);
  line2(g,b[0],b[1],c2[0],c2[1],pal.ro);line2(g,b[0]+1,b[1],c2[0]+1,c2[1],pal.rs);
  if(opt.chim){const cp=lerp(dd,c2,opt.chim);R(g,cp[0]-2,cp[1]-9,5,9,'#8A8478');R(g,cp[0]+1,cp[1]-9,2,9,'#6A6458');R(g,cp[0]-3,cp[1]-10,7,2,'#5A5448');for(let s=0;s<3;s++){g.globalAlpha=0.5-s*0.12;circ(g,cp[0]+2+s*3,cp[1]-14-s*5,2+s,'#E8E4DC');}g.globalAlpha=1;}
  if(opt.sign){const sp=lerp(Lh,Bh,0.5),sw=tw(opt.sign)+8;R(g,sp[0]-sw/2,sp[1]+1,sw,9,"#2A1410");R(g,sp[0]-sw/2+1,sp[1]+2,sw-2,7,"#C8945A");R(g,sp[0]-sw/2+1,sp[1]+2,sw-2,1,"#E0B070");tx(g,opt.sign,sp[0]-sw/2+4,sp[1]+4,"#3A2214");}
}
function tree(g,x,y,s){
  g.globalAlpha=0.25;ell(g,x+6,y,14*s,'#1A2A10');g.globalAlpha=1;
  R(g,x-2,y-16*s,5,16*s,'#7A4A28');R(g,x+1,y-16*s,2,16*s,'#5A3420');R(g,x-2,y-16*s,1,16*s,'#9A6A3A');R(g,x-4,y-2,3,2,'#5A3420');R(g,x+3,y-1,3,1,'#5A3420');
  const bl=[[0,-28,11],[-9,-21,8],[9,-21,8],[-5,-34,8],[6,-33,8],[0,-18,9],[-12,-27,6],[12,-27,6]].map((b)=>[x+b[0]*s,y+b[1]*s,Math.round(b[2]*s)]);
  for(const b of bl)circ(g,b[0],b[1],b[2]+1,'#20401A');
  for(const b of bl)circ(g,b[0],b[1],b[2],'#3E7A2E');
  for(const b of bl)circ(g,b[0]-1,b[1]-2,b[2]-2,'#5A9A3A');
  for(const b of bl)circ(g,b[0]-3,b[1]-4,Math.max(1,Math.round(b[2]*0.4)),'#86C04E');
  for(let n=0;n<70;n++){const b=bl[n%bl.length],a=hs(n,x)*6.28,rr=hs(n,y)*b[2];const px=b[0]+Math.cos(a)*rr,py=b[1]+Math.sin(a)*rr;R(g,px,py,1,1,py<b[1]-2?'#A8D870':'#2E5A22');}
  if(s>1)for(let n=0;n<5;n++){const b=bl[n];R(g,b[0]+2,b[1]+1,2,2,'#E04A3A');R(g,b[0]+2,b[1]+1,1,1,'#FF9A80');}
}
function bush(g,x,y,c){g.globalAlpha=0.25;ell(g,x+3,y,7,'#1A2A10');g.globalAlpha=1;circ(g,x,y-4,6,'#20401A');circ(g,x,y-4,5,'#3E7A2E');circ(g,x-1,y-6,3,'#5A9A3A');R(g,x-3,y-8,2,1,'#86C04E');for(let n=0;n<4;n++)R(g,x-3+hs(n,x)*6,y-7+hs(n,y)*5,1,1,c);}
function flowers(g,x,y,w,h,cols){for(let n=0;n<w*h/5;n++){const px=x+hs(n,x+3)*w,py=y+hs(n,y+7)*h;R(g,px,py+1,1,2,'#2E6A22');R(g,px,py,1,1,cols[n%cols.length]);if(n%3===0)R(g,px+1,py,1,1,cols[(n+1)%cols.length]);}}
function fence(g,p,q,n){for(let k=0;k<=n;k++){const[x,y]=lerp(p,q,k/n);R(g,x,y-8,2,8,'#5A3420');R(g,x,y-8,1,8,'#B07A44');R(g,x,y-9,2,1,'#D0A064');}line2(g,p[0]+1,p[1]-6,q[0]+1,q[1]-6,'#C08A50');line2(g,p[0]+1,p[1]-5,q[0]+1,q[1]-5,'#7A4A28');line2(g,p[0]+1,p[1]-3,q[0]+1,q[1]-3,'#C08A50');line2(g,p[0]+1,p[1]-2,q[0]+1,q[1]-2,'#7A4A28');}
function barrel(g,x,y){g.globalAlpha=0.25;ell(g,x+2,y,5,'#1A2A10');g.globalAlpha=1;R(g,x-3,y-9,7,9,'#2A1410');R(g,x-2,y-9,5,9,'#A86E3C');R(g,x+1,y-9,2,9,'#7A4A28');R(g,x-2,y-7,5,1,'#5A5F6A');R(g,x-2,y-3,5,1,'#5A5F6A');ell(g,x+0.5,y-9,3,'#C88A50');R(g,x-1,y-10,3,1,'#5A3420');}
function crate(g,x,y){g.globalAlpha=0.25;ell(g,x+3,y,6,'#1A2A10');g.globalAlpha=1;blk(g,x,y-4,7,'#D0A064','#A86E3C','#8A5A30','#E8C080');line2(g,x-7,y-6,x,y-2,'#6A3E20');line2(g,x,y-2,x+7,y-6,'#5A3420');}
function lamp(g,x,y){R(g,x-1,y-1,3,2,'#2A2A30');R(g,x,y-18,1,18,'#3A3A44');R(g,x-2,y-22,5,1,'#2A2A30');R(g,x-2,y-21,5,4,'#2A2A30');R(g,x-1,y-21,3,3,'#FFE6A8');R(g,x-1,y-23,3,1,'#3A3A44');R(g,x,y-24,1,1,'#3A3A44');}
function sign(g,x,y,t){R(g,x,y-14,2,14,'#5A3420');R(g,x,y-14,1,14,'#9A6A3A');const w=tw(t)+6;R(g,x-w/2+1,y-16,w,8,'#2A1410');R(g,x-w/2+2,y-15,w-2,6,'#C8945A');tx(g,t,x-w/2+4,y-14,'#3A2214');R(g,x+w/2+1,y-13,2,2,'#2A1410');}
function well(g,x,y){g.globalAlpha=0.25;ell(g,x+6,y+2,16,'#1A2A10');g.globalAlpha=1;
  ell(g,x,y,12,'#5A5448');for(let yy=-6;yy<=0;yy++)R(g,x-12,y+yy,24,1,yy%3===0?'#7A7468':'#9A9488');for(let u=-12;u<12;u+=4)R(g,x+u+((y&1)?2:0),y-4,1,3,'#6A6458');ell(g,x,y-6,12,'#B8B2A6');ell(g,x,y-6,9,'#3A5A7A');ell(g,x+1,y-5,6,'#2A4060');R(g,x-1,y-6,1,1,'#B08CFF');R(g,x+2,y-6,1,1,'#B08CFF');
  R(g,x-11,y-24,2,19,'#5A3420');R(g,x+10,y-24,2,19,'#5A3420');R(g,x-11,y-24,1,19,'#9A6A3A');R(g,x-10,y-19,21,1,'#7A4A28');R(g,x-1,y-19,1,8,'#C8B080');R(g,x-2,y-11,3,3,'#8A5A30');
  tri(g,[x-15,y-22],[x+15,y-22],[x,y-32],'#2A1410');tri(g,[x-13,y-23],[x+13,y-23],[x,y-31],'#B8442E');for(let k=1;k<4;k++)line2(g,x-13+k*3,y-23-k*2,x+13-k*3,y-23-k*2,'#8E3020');}
function person(g,pal,x,y,flip){g.globalAlpha=0.3;ell(g,x+1,y,6,'#1A2A10');g.globalAlpha=1;spr(g,BODY,pal,x,y+1,1,flip);}
const HP={wl:'#C8884E',wlL:'#9A6236',wr:'#A86E3C',wrL:'#7E4E28',r:'#B8442E',rs:'#8E3020',rh:'#E07A58',ro:'#5A1A10',rd:'#7A2818'};
const HB={wl:'#E2D2B0',wlL:'#BBA884',wr:'#C4B290',wrL:'#9A8866',r:'#3E7A8A',rs:'#2E5A6A',rh:'#6EAABA',ro:'#1A3440',rd:'#24485A'};
const PK=Object.assign({},PW,{Y:'#4A5A6E',y:'#2E3A4A',L:'#E0FFF8',H:'#2A2A30',S:'#E2B48A',s:'#C0906A',J:'#2E9E96',j:'#1E6A66',B:'#164A46',G:'#3A3040',N:'#3A3040',n:'#2A2230'});
const PI=Object.assign({},PW,{Y:'#7A3A6A',y:'#4E2244',L:'#FFD0F0',H:'#E8C060',S:'#C08860',s:'#9A6844',J:'#C85A94',j:'#8A2E62',B:'#5A1E44',N:'#2A2238',n:'#1E1828'});
const PB=Object.assign({},PW,{Y:'#8A8F9A',y:'#5A5F6A',H:'#B8B8B8',S:'#C08A60',s:'#9A6A44',J:'#6E9A3E',j:'#4A6A28',B:'#3A5420',N:'#3A2A1A',n:'#2A1E12'});
const PHOL=Object.assign({},PW,{o:'#1A1420',Y:'#6E7086',y:'#4A4C5E',L:'#2A2A34',H:'#3A3A44',S:'#9AB08E',s:'#76907A',e:'#D8C8FF',J:'#5A4E70',j:'#3E3452',B:'#2D2640',G:'#76907A',N:'#3A3A48',n:'#2A2A36',K:'#2A2230'});
const GOB={r:['..o......o..','.oGo....oGo.','.oGGooooGGo.','..oGGGGGGo..','.oGGeGGeGGo.','.oGGGGGGGGo.','..oGmmmmGo..','...oooooo...','..oLLLLLLo.f','.oGLLlLLLGor','.oGoLLLLoGor','..ooLLLLoo.r','...oDooDo...','..oKKooKKo..','..oooooooo..'],p:{o:'#1A2410',G:'#6E9A3E',e:'#FFE15A',m:'#3A1A12',L:'#7A4A26',l:'#B07A44',D:'#3A2A1A',K:'#2A1A10',r:'#D23A2E',f:'#FFD15C'}};
const BAT2={r:['o...........o','oo..o...o..oo','oBo.oBoBo.oBo','oBBooBBBooBBo','oBBBBEBEBBBBo','.oBBBBBBBBBo.','..oBo.o.oBo..','...o.....o...'],p:{o:'#120A1A',B:'#4A3A5E',E:'#FF6A5A'}};
function sprLie(g,rows,pal,x,y){const h=rows.length,w=rows[0].length,ox=Math.round(x-h/2),oy=Math.round(y-w);for(let r=0;r<h;r++)for(let c=0;c<w;c++){const ch=rows[r][c];if(ch!=='.'&&pal[ch])R(g,ox+r,oy+(w-1-c),1,1,pal[ch]);}}
function dk(P,t){const o={};for(const k in P)o[k]=mix(P[k],'#000000',t);return o;}
function stonePx(px,r,seed,P){const band=Math.floor(r/4),off=(hs(band,seed)*6)|0,sx=px+off+600,ri=r&3;if(ri===0||sx%6===0)return P.m;const v=hs(Math.floor(sx/6),band+seed*7);if(v>0.97&&P.ore)return P.ore;if(ri===3)return P.hi;if(ri===1)return P.lo;return v<0.4?P.a:v<0.8?P.b:P.c;}
function wallBlk(g,x,y,h,P,Pd,seed){for(let u=0;u<8;u++){const lx=x-8+u,lt=y-h+5+(u>>1);for(let r=0;r<h;r++)R(g,lx,lt+h-1-r,1,1,stonePx(lx,r,seed,P));const rx=x+u,rt=y-h+8-(u>>1);for(let r=0;r<h;r++)R(g,rx,rt+h-1-r,1,1,stonePx(rx,r,seed+3,Pd));}dia(g,x,y-h,P.top,P.tophi);for(let n=0;n<3;n++)R(g,x-4+hs(x,n)*8,y-h+2+hs(y,n)*4,1,1,P.lo);}
function timberL(g,x,y,h){const t=y-h;for(let u=0;u<8;u++){const top=t+5+(u>>1);if(u<2||u>5)for(let r=0;r<h;r++)R(g,x-8+u,top+r,1,1,(u===0||u===6)?'#9A6A3A':((r%5===2)?'#5A3420':'#7A4A26'));R(g,x-8+u,top+2,1,3,u%3===0?'#9A6A3A':'#6A3E1E');R(g,x-8+u,top+5,1,1,'#3A2214');}}
function timberR(g,x,y,h){const t=y-h;for(let u=0;u<8;u++){const top=t+8-(u>>1);if(u<2||u>5)for(let r=0;r<h;r++)R(g,x+u,top+r,1,1,(u===1||u===7)?'#5A3420':((r%5===2)?'#4A2A18':'#6A3E1E'));R(g,x+u,top+2,1,3,u%3===0?'#7A4A26':'#5A3420');R(g,x+u,top+5,1,1,'#2A1810');}}
function inRoom(o,x,y){const a=(x-o.ox)/8,b=(y-o.oy)/4,i=Math.floor((a+b)/2),j=Math.floor((b-a)/2);return i>=0&&j>=0&&i<o.W&&j<o.D;}
function room2(g,o){const Pd=dk(o.wp,0.28);const it=[];for(let i=-1;i<o.W;i++)it.push([i,-1,1]);for(let j=0;j<o.D;j++)it.push([-1,j,1]);for(let i=0;i<o.W;i++)for(let j=0;j<o.D;j++)it.push([i,j,0]);it.sort((a,b)=>a[0]+a[1]-b[0]-b[1]);
  for(const[i,j,w]of it){const[x,y]=P(o,i,j);if(w){if(o.door&&o.door(i,j))continue;wallBlk(g,x,y,o.wh,o.wp,Pd,o.seed);if(o.wdec)o.wdec(g,x,y,i,j);}else{const r=hs(i+o.seed,j*3);const c=o.tile?o.tile(i,j):null;dia(g,x,y,c||o.fl[r<0.5?0:r<0.8?1:2]);}}
  if(o.ftex)for(let n=0;n<o.W*o.D*o.dens;n++){const x=(hs(n,o.seed+11)*320)|0,y=(hs(n,o.seed+13)*180)|0;if(inRoom(o,x,y))o.ftex(g,x,y,hs(n,o.seed+17),n);}}
function mineTex(g,x,y,t,n){if(t<0.35){R(g,x,y,2,1,'#4A2E1C');R(g,x,y-1,1,1,'#B08058');}else if(t<0.45){let px=x,py=y;for(let k=0;k<5;k++){R(g,px,py,1,1,'#3A2214');px+=1;py+=(hs(n,k)<0.5?1:0);}}else if(t<0.6){circ(g,x,y,1,'#4A2E1C');R(g,x-1,y-1,1,1,'#B08868');}else if(t<0.62){R(g,x,y,1,1,'#E0956A');R(g,x+1,y,1,1,'#FFC28A');}else R(g,x,y,1,1,t<0.8?'#6A4430':'#A0704A');}
function rubble(g,x,y){for(const[dx,dy,r]of[[0,0,3],[-4,1,2],[4,1,2],[-1,-2,2]]){circ(g,x+dx,y+dy,r+1,'#2A1A10');circ(g,x+dx,y+dy,r,'#6E5A48');R(g,x+dx-1,y+dy-r+1,2,1,'#A08A70');}}
function cart(g,x,y){g.globalAlpha=0.3;ell(g,x+2,y+2,10,'#000');g.globalAlpha=1;blk(g,x,y-2,8,'#7A808E','#4E5462','#3A3E4A','#9AA0AE');line2(g,x-8,y-4,x,y,'#2A2E38');line2(g,x,y,x+8,y-4,'#2A2E38');for(const[dx,dy]of[[-6,2],[4,3]]){circ(g,x+dx,y+dy,2,'#1A1A20');R(g,x+dx,y+dy,1,1,'#8A8F9A');}for(let n=0;n<14;n++){const a=hs(n,x)*6.28,rr=hs(n,y)*5;R(g,x+Math.cos(a)*rr,y-11+Math.sin(a)*rr/2,2,1,n%3?'#C9733A':'#FFC28A');}}
function hangLamp(g,x,y){R(g,x,y-4,1,3,'#8A93AE');R(g,x-1,y-1,3,1,'#2A2A30');R(g,x-2,y,5,5,'#2A2A30');R(g,x-1,y,3,4,'#FFD27A');R(g,x-1,y+5,3,1,'#2A2A30');}
function hangLampGlow(g,x,y){glo(g,x,y+2,8,'#FFC86A',0.35);R(g,x-1,y+1,3,3,'#FFE6A8');R(g,x,y+2,1,1,'#FFFFFF');}
function mush2(g,x,y,s,cap,spot){R(g,x-1,y-s*2,3,s*2,'#2A2418');R(g,x,y-s*2,1,s*2,'#E8E0C8');R(g,x+1,y-s*2,1,s*2,'#B8B098');R(g,x-s-1,y-s*2-1,s*2+3,2,'#2A2418');circ(g,x,y-s*2-1,s+1,'#2A1424');for(let k=0;k<=s+1;k++)R(g,x-s-1,y-s*2+k-1,s*2+3,1,'#00000000');R(g,x-s,y-s*2-1,s*2+1,1,mix(cap,'#000',0.4));circ(g,x,y-s*2-2,s,cap);R(g,x-s+1,y-s*2-1,s*2-1,1,mix(cap,'#000',0.3));R(g,x-s+1,y-s*2-s,2,1,mix(cap,'#FFF',0.4));if(spot){R(g,x-1,y-s*2-s+1,1,1,spot);R(g,x+2,y-s*2-2,1,1,spot);}}
function crystal2(g,x,y,h,c1,c2,c3){circ(g,x,y,3,'#2A2A4A');tri(g,[x-4,y],[x+4,y],[x,y-h],'#141838');tri(g,[x-3,y],[x,y],[x,y-h+1],c1);tri(g,[x,y],[x+3,y],[x,y-h+1],c2);line2(g,x,y-1,x,y-h+3,c3);tri(g,[x+3,y],[x+7,y],[x+5,y-h/2],'#141838');tri(g,[x+4,y],[x+6,y],[x+5,y-h/2+1],c2);}
function candle(g,x,y){R(g,x-1,y-5,2,5,'#E8E0C8');R(g,x,y-5,1,5,'#C8C0A8');R(g,x,y-6,1,1,'#2A2A2A');}
function candleGlow(g,x,y){glo(g,x,y-8,6,'#FFC86A',0.4);R(g,x,y-8,1,2,'#FFD27A');R(g,x,y-9,1,1,'#FFF3C4');}
function pillar(g,x,y,h,P){g.globalAlpha=0.3;ell(g,x+3,y,8,'#000');g.globalAlpha=1;R(g,x-6,y-3,13,3,P.m);R(g,x-5,y-3,11,2,P.hi);for(let r=3;r<h-3;r++){R(g,x-4,y-r,9,1,P.b);R(g,x-4,y-r,2,1,P.hi);R(g,x+3,y-r,2,1,P.lo);if(r%6===0)R(g,x-4,y-r,9,1,P.m);}R(g,x-6,y-h,13,3,P.m);R(g,x-5,y-h,11,1,P.hi);}
