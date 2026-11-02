import math, random, struct, wave, sys, os
TAXA=22050
out=sys.argv[1]
def salvar(nome, a):
    m=max(1e-6,max(abs(x) for x in a))
    k=min(1.0,0.9/m)
    with wave.open(os.path.join(out,nome+'.wav'),'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(TAXA)
        w.writeframes(b''.join(struct.pack('<h',int(max(-1,min(1,x*k))*32767)) for x in a))
def n(seg): return int(TAXA*seg)
R=random.Random(10)
# machado: impacto seco de madeira + estalo
a=[]
f=0
for i in range(n(0.32)):
    t=i/TAXA
    f=f+(R.uniform(-1,1)-f)*0.35
    a.append(math.sin(2*math.pi*140*t)*math.exp(-t*22)*0.8+math.sin(2*math.pi*620*t)*math.exp(-t*40)*0.4+f*math.exp(-t*30)*0.9)
salvar('machado',a)
# arvore cai: rachar (estalos) + baque grave
a=[]
for i in range(n(1.1)):
    t=i/TAXA
    rach= R.uniform(-1,1) if R.random()<0.3*math.exp(-((t-0.25)**2)/0.02) else 0
    baque=0
    if t>0.65:
        tt=t-0.65
        baque=(math.sin(2*math.pi*55*tt)*0.9+R.uniform(-1,1)*0.4)*math.exp(-tt*7)
    a.append(rach*0.7+baque)
salvar('arvore_cai',a)
# agua: respingo
a=[];f=0
for i in range(n(0.45)):
    t=i/TAXA
    f=f+(R.uniform(-1,1)-f)*0.5
    bolha=math.sin(2*math.pi*(500+900*t)*t)*math.exp(-t*12)*0.3
    a.append(f*math.exp(-t*10)*0.8+bolha)
salvar('agua',a)
# sapo: croac croac
a=[]
for i in range(n(0.55)):
    t=i/TAXA
    env=0
    for s0 in (0.0,0.28):
        if s0<=t<s0+0.16: env=math.sin(math.pi*(t-s0)/0.16)
    ph=2*math.pi*180*t
    puls=1 if (t*45)%1<0.5 else 0.3
    a.append((math.sin(ph)+0.6*math.sin(ph*2)+0.3*math.sin(ph*3))*env*puls*0.5)
salvar('sapo',a)
# coracao: tum-tum
a=[]
for i in range(n(0.7)):
    t=i/TAXA
    v=0
    for s0,amp in ((0.0,1.0),(0.22,0.7)):
        if t>=s0:
            tt=t-s0
            v+=math.sin(2*math.pi*48*tt)*math.exp(-tt*18)*amp
    a.append(v)
salvar('coracao',a)
# sussurro: ruido filtrado com "silabas"
a=[];f=0;g=0
for i in range(n(1.2)):
    t=i/TAXA
    r=R.uniform(-1,1); f=r-g*0.7; g=r
    sil=max(0,math.sin(2*math.pi*3.4*t+math.sin(2*math.pi*0.9*t)*1.5))
    env=math.sin(math.pi*t/1.2)
    a.append(f*sil*env*0.5)
salvar('sussurro',a)
# papel: farfalhar
a=[]
for i in range(n(0.35)):
    t=i/TAXA
    crep=1 if R.random()<0.2 else 0.25
    a.append(R.uniform(-1,1)*crep*math.sin(math.pi*t/0.35)*0.6)
salvar('papel',a)
# cama: rangido curto de molas/madeira
a=[];ph=0
for i in range(n(0.5)):
    t=i/TAXA
    fr=220+120*math.sin(math.pi*t/0.5)+25*math.sin(2*math.pi*17*t)
    ph+=2*math.pi*fr/TAXA
    serra=((ph/(2*math.pi))%1)*2-1
    a.append(serra*math.sin(math.pi*t/0.5)*0.4)
salvar('cama',a)
# rajada: vento curto (one-shot, nao loop)
a=[];f=0
for i in range(n(1.3)):
    t=i/TAXA
    f=f+(R.uniform(-1,1)-f)*0.03
    a.append(f*3.0*math.sin(math.pi*t/1.3)**2)
salvar('rajada',a)
# peixe: debatendo (tapinhas molhados)
a=[]
for i in range(n(0.4)):
    t=i/TAXA
    v=0
    for s0 in (0,0.1,0.19,0.3):
        if t>=s0:
            tt=t-s0; v+=R.uniform(-1,1)*math.exp(-tt*70)
    a.append(v*0.7)
salvar('peixe',a)
print('ok')
