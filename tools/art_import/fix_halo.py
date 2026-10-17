import numpy as np, sys, os
from PIL import Image, ImageFilter
D=os.path.join(os.environ.get('HALO_ASSETS_HEROES', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'art', 'heroes')), 'seraphiel', '')
base=np.array(Image.open(D+'seraphiel.png').convert('RGBA')).astype(int)
r,g,b,a=[base[...,i] for i in range(4)]
bg=np.array([172,174,176])
dist=np.abs(base[...,:3]-bg).max(axis=2)
sat=base[...,:3].max(axis=2)-base[...,:3].min(axis=2)
m=(dist<=20)&(sat<=12)&(a>0)
box=np.zeros_like(m); box[600:790,380:670]=True
m&=box
# connected components (4-neighbour flood) and keep clusters >= 40 px
H,W=m.shape; lab=np.zeros((H,W),int); n=0; keep=np.zeros_like(m)
ys,xs=np.nonzero(m)
for y0,x0 in zip(ys,xs):
    if lab[y0,x0]: continue
    n+=1; st=[(y0,x0)]; lab[y0,x0]=n; pts=[]
    while st:
        y,x=st.pop(); pts.append((y,x))
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            yy,xx=y+dy,x+dx
            if 0<=yy<H and 0<=xx<W and m[yy,xx] and not lab[yy,xx]:
                lab[yy,xx]=n; st.append((yy,xx))
    if len(pts)>=40:
        for y,x in pts: keep[y,x]=True
        print('cluster',len(pts),'x',min(p[1] for p in pts),max(p[1] for p in pts),'y',min(p[0] for p in pts),max(p[0] for p in pts))
# grow by 1 px into the anti-aliased grey edge, soften
k=Image.fromarray((keep*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
cut=np.array(k.filter(ImageFilter.GaussianBlur(0.6))).astype(float)/255.
cut=np.where(np.array(k)>0, np.maximum(cut, keep*1.0), 0)
print('px cleared', int(keep.sum()))
if '--apply' in sys.argv:
    for f in [D+'seraphiel.png']+[D+'variants/'+v for v in os.listdir(D+'variants') if v.endswith('.png')]:
        im=np.array(Image.open(f).convert('RGBA')).astype(float)
        im[...,3]=im[...,3]*(1-cut)
        Image.fromarray(im.round().clip(0,255).astype(np.uint8),'RGBA').save(f)
        print('fixed',f)
