import sys
from PIL import Image
ref=Image.open(sys.argv[1]).convert('RGBA')
prot=Image.open(sys.argv[2]).convert('RGBA')
out=sys.argv[3]
T=(0,0,0,0); K=(0,0,0,255)
HAIR=[(181,157,0,255),(162,140,0,255),(141,122,0,255),(123,106,0,255)]
JK={'hi':(82,95,155,255),'mid':(72,85,152,255),'base':(49,61,116,255),'dk':(33,41,76,255)}
SHIRT=[(181,121,0,255),(149,99,0,255),(137,92,0,255)]
PANTS={(65,75,120,255):(255,197,135,255),(51,62,117,255):(255,187,114,255),(49,61,116,255):(255,179,98,255),(33,41,76,255):(208,147,82,255)}
SHOE=(144,144,144,255)
def lum(c): return c[0]*0.3+c[1]*0.59+c[2]*0.11
# ---------- recolor do protagonista (para os lados) ----------
def recolor(img):
    im=img.copy(); W,H=im.size
    px=im.load()
    for y in range(H):
        for x in range(W):
            c=px[x,y]
            if c[3]==0 or c[:3]==(0,0,0): continue
            r,g,b,a=c
            if c in PANTS: px[x,y]=PANTS[c]; continue
            if b>r+15 and b>g+15:  # outros tons de azul da calça
                L=lum(c)
                px[x,y]=(255,187,114,255) if L>60 else (208,147,82,255) if L>38 else (160,110,60,255); continue
            if c==(50,25,25,255): px[x,y]=SHOE; continue
            if r in (255,200) and g in (199,155): continue  # pele
            if g==0 and b==0:  # jaqueta vermelha
                px[x,y]={150:JK['hi'],129:JK['mid'],116:JK['base'],103:JK['dk']}.get(r,JK['base']); continue
            if r==g==b: px[x,y]=SHIRT[0] if r>140 else SHIRT[1]; continue
            if y%32>=25:  # sapatos (marrom escuro no protagonista)
                px[x,y]=SHOE if lum(c)>45 else (45,44,42,255); continue
            # cabelo castanho -> loiro
            L=lum(c)
            px[x,y]=HAIR[0] if L>68 else HAIR[1] if L>58 else HAIR[2] if L>42 else HAIR[3]
    return im
# ---------- frames da frente a partir da referência ----------
def shift_up(im,k=1):
    n=Image.new('RGBA',im.size,T); n.paste(im,(0,-k)); return n
def lift_leg(im,x0,x1,top,k=2):
    # sobe a perna (colunas x0..x1) a partir da linha top: o pé "sai do chão"
    n=im.copy(); px=n.load(); src=im.load(); W,H=im.size
    for x in range(x0,x1+1):
        for y in range(top,H): px[x,y]=T
        for y in range(top,H):
            if y-k>=top: px[x,y-k]=src[x,y]
    return n
def lado_back(img):
    # costas: cabelo cobrindo a cabeça; jaqueta sem a camiseta
    im=img.copy(); px=im.load(); W,H=im.size
    # cabeça: linhas 0..10 -> tudo que não é preto/transparente vira cabelo
    for y in range(0,11):
        for x in range(W):
            c=px[x,y]
            if c[3] and c[:3]!=(0,0,0):
                px[x,y]=HAIR[0] if y<=3 else (HAIR[2] if y>=9 or (x+y)%5==0 else HAIR[1])
            elif c[:3]==(0,0,0) and c[3] and 1<y<10 and 11<x<21:
                px[x,y]=HAIR[1]   # some com olhos e contornos internos do rosto
    # pescoço
    for x in range(13,20):
        if px[x,11][3] and px[x,11][:3]!=(0,0,0): px[x,11]=(200,155,146,255)
    # tronco: camiseta e linhas internas viram jaqueta
    for y in range(12,22):
        for x in range(10,23):
            c=px[x,y]
            if c in SHIRT or c in [(149,99,0,255),(181,121,0,255),(137,92,0,255),(132,88,0,255)]:
                px[x,y]=JK['base']
            elif c[:3]==(0,0,0) and c[3] and 11<=x<=21 and 13<=y<=20:
                px[x,y]=JK['base'] if x!=16 else JK['dk']   # costura do meio
    return im
front=[ref, shift_up(lift_leg(ref,10,15,23)), ref, shift_up(lift_leg(ref,16,22,23))]
backbase=lado_back(ref)
back=[backbase, shift_up(lift_leg(backbase,10,15,23)), backbase, shift_up(lift_leg(backbase,16,22,23))]
sheet=Image.new('RGBA',(128,128),T)
for i,f in enumerate(front): sheet.paste(f,(i*32,0))
for i,f in enumerate(back): sheet.paste(f,(i*32,32))
side=recolor(prot.crop((0,64,128,128)))
# cabelo espetado nos lados: alguns fios a mais no topo
px=side.load()
for fr in range(4):
    for row,face_right in ((0,True),(1,False)):
        oy=row*32; ox=fr*32
        # acha topo do cabelo
        for y in range(0,6):
            xs=[x for x in range(32) if px[ox+x,oy+y][:3] in [h[:3] for h in HAIR]]
            if xs:
                xm=xs[len(xs)//2] + (-2 if face_right else 2)
                if y>0 and px[ox+xm,oy+y-1][3]==0:
                    px[ox+xm,oy+y-1]=HAIR[0]
                    if y>1: px[ox+xm,oy+y-2]=K
                break
sheet.paste(side,(0,64))
sheet.save(out)
big=Image.new('RGBA',(128,128),(60,90,60,255)); big.alpha_composite(sheet)
big.resize((768,768),Image.NEAREST).save(out.replace('.png','_preview.png'))
print('ok')
