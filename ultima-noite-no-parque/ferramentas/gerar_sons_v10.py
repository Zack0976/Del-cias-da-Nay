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
# ===================== v11 =====================
R=random.Random(11)
# uivo (uivador): glissando grave->agudo->grave com vibrato
a=[];ph=0
for i in range(n(1.6)):
    t=i/TAXA
    fr=260+260*math.sin(math.pi*min(t/1.3,1))+8*math.sin(2*math.pi*6*t)
    ph+=2*math.pi*fr/TAXA
    env=min(1,t/0.2)*max(0,1-max(0,t-1.2)/0.4)
    a.append((math.sin(ph)+0.35*math.sin(2*ph)+0.1*R.uniform(-1,1))*env*0.5)
salvar('uivo',a)
# rosnado: ronco grave modulado
a=[];f=0
for i in range(n(0.8)):
    t=i/TAXA
    f=f+(R.uniform(-1,1)-f)*0.12
    mod=0.6+0.4*math.sin(2*math.pi*28*t)
    a.append((math.sin(2*math.pi*70*t)*0.5+f*1.2)*mod*math.sin(math.pi*t/0.8))
salvar('rosnado',a)
# voz (imitador): "so-co-rro" sussurrado tonal, distorcido
a=[];ph=0
for i in range(n(1.3)):
    t=i/TAXA
    sil=0
    for s0 in (0.05,0.4,0.75):
        if s0<=t<s0+0.28: sil=math.sin(math.pi*(t-s0)/0.28)
    fr=210-40*t+15*math.sin(2*math.pi*5*t)
    ph+=2*math.pi*fr/TAXA
    v=(math.sin(ph)+0.5*math.sin(2*ph)+0.3*math.sin(3*ph))*0.4+R.uniform(-1,1)*0.25
    a.append(v*sil*0.6)
salvar('voz',a)
# fosforo: risco + chama
a=[];f=0
for i in range(n(0.6)):
    t=i/TAXA
    risco=R.uniform(-1,1)*math.exp(-t*25)*0.9
    f=f+(R.uniform(-1,1)-f)*0.08
    chama=f*min(1,t/0.1)*math.exp(-t*3)*1.2 if t>0.05 else 0
    a.append(risco+chama)
salvar('fosforo',a)
# comer: mordidas crocantes
a=[]
for i in range(n(0.5)):
    t=i/TAXA
    v=0
    for s0 in (0,0.18,0.34):
        if t>=s0:
            tt=t-s0; v+=R.uniform(-1,1)*math.exp(-tt*35)*(1 if R.random()<0.6 else 0.3)
    a.append(v*0.6)
salvar('comer',a)
# beber: goles (bolhas graves)
a=[]
for i in range(n(0.6)):
    t=i/TAXA
    v=0
    for s0 in (0,0.22,0.42):
        if t>=s0:
            tt=t-s0; v+=math.sin(2*math.pi*(180+500*tt)*tt)*math.exp(-tt*20)
    a.append(v*0.5)
salvar('beber',a)
# ziper: mochila
a=[]
for i in range(n(0.35)):
    t=i/TAXA
    dente=1 if (t*180)%1<0.3 else 0
    a.append(R.uniform(-1,1)*dente*math.sin(math.pi*t/0.35)*0.6)
salvar('ziper',a)
# pedra: batida seca de pedra
a=[]
for i in range(n(0.25)):
    t=i/TAXA
    a.append((math.sin(2*math.pi*900*t)*0.4+math.sin(2*math.pi*1450*t)*0.3+R.uniform(-1,1)*0.5)*math.exp(-t*30))
salvar('pedra',a)
# porta: rangido curto + trinco
a=[];ph=0
for i in range(n(0.7)):
    t=i/TAXA
    fr=380+120*math.sin(math.pi*t/0.5)
    ph+=2*math.pi*fr/TAXA
    serra=((ph/(2*math.pi))%1)*2-1
    v=serra*0.3*math.sin(math.pi*min(t,0.5)/0.5) if t<0.5 else 0
    if t>0.55: v+=math.sin(2*math.pi*220*(t-0.55))*math.exp(-(t-0.55)*40)
    a.append(v)
salvar('porta',a)
# pista: sininho misterioso
a=[]
for i in range(n(1.0)):
    t=i/TAXA
    a.append((math.sin(2*math.pi*988*t)*0.4+math.sin(2*math.pi*1319*t)*0.25*(1 if t>0.12 else 0)+math.sin(2*math.pi*1976*t)*0.1)*math.exp(-t*3.5))
salvar('pista',a)
# resgate: acorde maior quente subindo
a=[]
for i in range(n(1.4)):
    t=i/TAXA
    v=0
    for k,fr in enumerate((262,330,392,523)):
        if t>=k*0.12: v+=math.sin(2*math.pi*fr*(t-k*0.12))*math.exp(-(t-k*0.12)*2.2)
    a.append(v*0.3)
salvar('resgate',a)
# passo na madeira (cabana): toc oco
a=[]
for i in range(n(0.12)):
    t=i/TAXA
    a.append((math.sin(2*math.pi*180*t)*0.7+R.uniform(-1,1)*0.3)*math.exp(-t*45))
salvar('passo_madeira',a)
print('v11 ok')
