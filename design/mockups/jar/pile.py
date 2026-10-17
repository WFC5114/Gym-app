import math, sys
from PIL import Image, ImageDraw
FW, FH = 420, 852
side=26; CW=FW-2*side
mech=(side, FH*0.30, CW, FH*0.50)
mx,my,mw,mh=mech
jarW=CW*0.58; wall=7
jarTop=my+70; jarBot=my+mh-8
jx=FW/2-jarW/2
inL=jx+wall; inR=jx+jarW-wall; inW=inR-inL
floor=jarBot-wall
interiorH=floor-jarTop
targetFrac=0.74
targetY=floor-interiorH*targetFrac
PACK=float(sys.argv[2]) if len(sys.argv)>2 else 0.72
target=2450
apk=inW*(floor-targetY)*PACK/target
def fnv(s):
    h=0xcbf29ce484222325
    for b in s.encode():
        h^=b; h=(h*0x100000001b3)&0xFFFFFFFFFFFFFFFF
    h^=h>>30; h=(h*0xbf58476d1ce4e5b9)&0xFFFFFFFFFFFFFFFF
    h^=h>>27; h=(h*0x94d049bb133111eb)&0xFFFFFFFFFFFFFFFF
    h^=h>>31
    return h
def size(kcal, key, scale=1):
    u=(fnv(key)>>8 & 0xffff)/65535
    aspect=1.5+0.9*u
    area=max(kcal,20)*apk*scale*scale
    w=math.sqrt(area*aspect); h=area/w
    w=min(max(w,34),inW*0.92); h=max(area/w,18)
    return w,h
COL=2.0
MAXA=float(sys.argv[3]) if len(sys.argv)>3 else 0.26
def pose(S,xs,c,w,h):
    n=len(S); maxT=math.tan(MAXA)
    lo=c-w/2; hi=c+w/2
    idx=[i for i in range(n) if lo<=xs[i]<=hi]
    ym=min(S[i] for i in idx)
    cands=[i for i in idx if S[i]<=ym+0.5]
    im=min(cands,key=lambda i:abs(xs[i]-c)); xm=xs[im]
    t=0; free=False
    if xm< c-1:
        r=[(S[i]-ym)/(xs[i]-xm) for i in idx if xs[i]>xm+0.5]
        m=min(r) if r else 9
        if m>maxT: free=True
        t=min(m,maxT); dirn=1
    elif xm> c+1:
        r=[(S[i]-ym)/(xs[i]-xm) for i in idx if xs[i]<xm-0.5]
        m=max(r) if r else -9
        if m< -maxT: free=True
        t=max(m,-maxT); dirn=-1
    else: dirn=0
    return xm,ym,t,free,dirn
def layout(entries, scale=1):
    n=int(math.ceil(inW/COL))
    S=[floor]*n
    xs=[inL+(i+0.5)*COL for i in range(n)]
    out=[]
    for (kcal,key) in entries:
        w,h=size(kcal,key,scale)
        u=(fnv(key+"x")>>11)/(2**53)
        c=inL+w/2+u*(inW-w)
        def settle(c):
            for it in range(10):
                xm,ym,t,free,dirn=pose(S,xs,c,w,h)
                if not free: break
                nc=min(max(c+dirn*w*0.2,inL+w/2),inR-w/2)
                if abs(nc-c)<0.5: break
                c=nc
            th=math.atan(t)
            half=(w*math.cos(th)+h*abs(math.sin(th)))/2
            c=min(max(c,inL+half),inR-half)
            xm,ym,t,free,dirn=pose(S,xs,c,w,h)
            by=ym+t*(c-xm)
            return c,xm,ym,t,by
        best=settle(c)
        for k in (-1,1,-2,2,-3,3):
            cc=min(max(c+k*w*0.35,inL+w/2),inR-w/2)
            r=settle(cc)
            if r[4]>best[4]+h*0.45+abs(k)*2: best=r
        c,xm,ym,t,by=best
        th=math.atan(t)
        up=(math.sin(th),-math.cos(th)); d=(math.cos(th),math.sin(th))
        B=(c,by)
        corners=[(B[0]-d[0]*w/2,B[1]-d[1]*w/2),(B[0]+d[0]*w/2,B[1]+d[1]*w/2)]
        corners+= [(corners[1][0]+up[0]*h,corners[1][1]+up[1]*h),(corners[0][0]+up[0]*h,corners[0][1]+up[1]*h)]
        cx=sum(p[0] for p in corners)/4; cy=sum(p[1] for p in corners)/4
        for i in range(n):
            x=xs[i]; best=None
            for k in range(4):
                a=corners[k]; b=corners[(k+1)%4]
                if (a[0]-x)*(b[0]-x)<=0 and a[0]!=b[0]:
                    y=a[1]+(b[1]-a[1])*(x-a[0])/(b[0]-a[0])
                    best=y if best is None else min(best,y)
            if best is not None: S[i]=min(S[i],best)
        out.append(dict(c=(cx,cy),w=w,h=h,th=th,poly=corners,kcal=kcal))
    return out,min(S)
day=[(311,"oats"),(160,"milk"),(105,"banana"),(330,"chicken"),(325,"rice"),(100,"quick1")]
over=day+[(630,"pasta"),(240,"oil"),(240,"cheddar")]
which=sys.argv[1] if len(sys.argv)>1 else "day"
E={"day":day,"over":over,"huge":[(500,"q%d"%i) for i in range(16)],"target":[(250,"t%d"%i) for i in range(10)]}[which]
out,top=layout(E)
scale=1
limit=my+6
while top<limit and scale>0.3:
    scale*=0.92; out,top=layout(E,scale)
print(which,"total",sum(k for k,_ in E),"top",round(top),"targetY",round(targetY),"jarTop",round(jarTop),"scale",round(scale,2),"apk",round(apk,1))
for o in out: print(" %4d w%.0f h%.0f th%.2f"%(o['kcal'],o['w'],o['h'],o['th']))
im=Image.new("RGB",(FW,FH),(232,70,30)); d=ImageDraw.Draw(im)
d.rounded_rectangle([jx,jarTop,jx+jarW,jarBot],radius=30,outline=(255,255,255),width=3)
d.line([inL,targetY,inL+30,targetY],fill="white",width=2)
cols=[(246,231,200),(233,180,76),(201,135,74),(255,215,122)]
for k,o in enumerate(out): d.polygon(o['poly'],fill=cols[k%4],outline=(80,40,20))
d.rectangle([mx,my,mx+mw,my+mh],outline=(0,0,0))
im.save(which+".png")
