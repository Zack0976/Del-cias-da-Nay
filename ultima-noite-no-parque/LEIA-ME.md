# Última Noite no Parque — o que foi arrumado

Projeto testado no **Godot 4.7**: menu → escolha do personagem → carregando → cutscene → jogo → pausa → continuar. Tudo roda sem erros.

## Os bugs que existiam (e por que aconteciam)

| # | Bug | Por que acontecia | Como ficou |
|---|-----|-------------------|------------|
| 1 | O jogo abria na cena de **teste**, com o menu desenhado por cima do mapa | A cena principal era `teste.tscn` | Agora o jogo abre no **menu** |
| 2 | "ERRO 404: O PARQUE NÃO FOI ENCONTRADO" ao clicar em Novo Jogo | O caminho era `res://Cutsene.tscn` (escrito errado e na pasta errada) | Todos os caminhos ficam juntos no `GameData.gd` |
| 3 | A seleção de personagem e a cutscene também não abriam as próximas cenas | Faltava `Scenes/` nos caminhos | Mesma solução do item 2 |
| 4 | A tela de seleção ficava espremida no canto, com fundo cinza | A cena tinha só 40x40 pixels | Agora ocupa a tela inteira |
| 5 | Apareciam **4 protagonistas grudados** | `protagonista_andar.png` é uma grade 4x4, mas o código cortava em 4 faixas inteiras | Cada quadro de 32x32 é cortado certinho |
| 6 | Bonecos cortados ao meio, "pulando" ou com pedaços de outro boneco | Nas folhas de sprite os quadros não têm o mesmo espaço. Dividir a largura pelo número de quadros não funciona. Também havia contagens erradas (a Jogadora tem 8 quadros e não 9, e o Rafa também tem 8) | `sprite_library.gd` guarda o retângulo exato de cada quadro |
| 7 | Andando para cima, o menino virava o **Lucas** | O código usava `lucas_costas.png` para o protagonista | Cada personagem usa os próprios sprites |
| 8 | Cada direção tinha um tamanho diferente (minúsculo ou gigante) | A mesma escala era usada para folhas de tamanhos muito diferentes | Todos ficam com 32 pixels de altura, em qualquer direção |
| 9 | O **joystick não existia** e dava erro | `JoystickVirtual.gd` era uma cópia do script do Player colocada num Control | Agora é um joystick de verdade: encoste o dedo na metade esquerda da tela e arraste |
| 10 | Dois jogadores na fase de teste (com duas câmeras) | O Player foi colocado duas vezes | Só um Player |
| 11 | A imagem de fundo da fase sumiu (`images.jpeg`) | O arquivo foi apagado, mas a cena ainda usava ele | A fase nova é a cabana desenhada por código |
| 12 | O vento e o chiado tocavam meio segundo e paravam | O som era gerado uma vez só, sem continuar | `sons.gd` cria sons que repetem para sempre |
| 13 | Os sliders de volume não faziam nada | Não estavam ligados ao áudio | Mudam o volume de verdade e ficam salvos |
| 14 | "Continuar" só escrevia no console | Não existia save | Save automático em `user://save.cfg` |
| 15 | Os botões do menu piscavam ao abrir | Ficavam visíveis e só depois eram escondidos para o fade | Já começam invisíveis |
| 16 | As partículas do menu "caíam" | Tinham a gravidade padrão (980) | Agora flutuam devagar, como poeira |
| 17 | O tremor do susto (Sair) não tremia | Era sorteada uma posição só | Sorteia uma posição nova a cada tremida |
| 18 | O texto da caixa de diálogo não dava para pular | Não havia controle de toque | Toque uma vez para mostrar o texto inteiro e outra vez para avançar |
| 19 | O botão "voltar" do Android fechava o jogo | Comportamento padrão | Agora abre "Sair?" no menu e pausa durante o jogo |

## A cutscene nova

Ela segue o roteiro **"Cutscene de Abertura Definitiva"** cena por cena:

- Prólogo com a fita cassete
- A chegada de carro
- A cabana e a fotografia
- A fogueira e o rádio
- O desaparecimento do Lucas
- A montagem e as batidas na porta
- "ELES JÁ ESTÃO DENTRO"
- O título "SOBREVIVA."

No fim, o controle passa para o jogador sem corte, como pedem as notas de implementação.

- **PULAR**: toque 2 vezes no botão.
- **Para testar uma cena só**: abra `cutscene.tscn`, clique no nó *Cutscene* e mude **Comecar Na Cena** no Inspector (0 = prólogo, de 1 a 6 = cenas).

## A fase (cabana trancada)

**Objetivo do roteiro:** *"Encontre uma saída da cabana. Investigue o interior e descubra o que aconteceu com Marina e Rafa."*

Examine as coisas da cabana: porta, rádio, foto, telefone, as camas, a lareira, a janela e a cozinha. Uma pista leva à outra até a porta abrir.

## Onde fica cada coisa

| Arquivo | O que faz |
|---------|-----------|
| `GameData.gd` | Script global: save, volume, controles e troca de cena com fade |
| `sprite_library.gd` | Tabela dos quadros de cada sprite |
| `sprite_personagem.gd` | Boneco animado (4 direções, tamanho automático) |
| `sons.gd` | Todos os sons, feitos por código (inclusive o violão do Rafa!) |
| `cabana_interior.gd` / `parque_exterior.gd` | Os cenários, usados na cutscene e no jogo |
| `cutscene.gd` | O roteiro: leia de cima para baixo, como um texto |
| `jogo.gd` | A história da fase (o que acontece ao examinar cada objeto) |
| `Player.gd`, `hud.gd`, `JoystickVirtual.gd`, `dialogue_box.gd`, `interagivel.gd` | Jogador e interface |

## Versão 2 — o jogo fechava sozinho, estilo pixelado e otimização

### Por que o jogo podia fechar depois de 2 a 4 segundos
1. **Imagens gigantes:** as folhas de sprite tinham até 3882 pixels de largura e ocupavam mais de 150 MB de memória de vídeo. Celulares mais simples fecham o app quando a memória acaba. Agora elas são pixel art pequena: a memória de vídeo caiu para **cerca de 16 MB**. As imagens grandes continuam guardadas em `Sprites/originais/`, e o Godot ignora essa pasta.
2. **Renderizador "Mobile":** ele precisa de Vulkan, e muitos celulares Android têm problemas com isso. O projeto agora usa o **Compatibilidade (OpenGL)**, que é o mais estável para jogos 2D.
3. **Cache velho:** se você descompactou a versão nova por cima da antiga, a pasta `.godot` antiga pode confundir o Godot (UIDs repetidos, arquivos apagados).
   **Solução:** descompacte numa pasta **nova** ou apague a pasta `.godot` e abra de novo.

### Se o jogo fechar de novo
- O menu agora avisa: **"O jogo fechou sozinho da última vez (em: ...)"**.
- Em **OPÇÕES > DIAGNÓSTICO** aparecem a placa de vídeo, a memória usada, o FPS e os **erros do log da vez anterior**. Mande uma foto dessa tela que eu descubro o problema.

### Estilo pixelado
O mundo é desenhado numa tela pequena (por exemplo 320x180) e esticado sem suavizar (`mundo_pixel.gd`). Tudo vira pixel art, até as luzes e os desenhos feitos por código. A interface continua nítida.
Em **OPÇÕES > PIXELS** você escolhe entre pixels GRANDES (mais leve), MÉDIOS ou PEQUENOS.

### Otimizações
- O mundo é desenhado até **16x menos pixels** por quadro.
- Os sons são calculados uma vez e **salvos em cache** (`user://cache`). Nas próximas vezes eles só são carregados, e isso acontece numa thread para o jogo não travar.
- Os cenários são redesenhados 12x por segundo, e não 60x. O chão do parque é desenhado uma vez só.
- As árvores são plantadas com uma "grade de vizinhos", muito mais rápido do que comparar todas com todas.
- **FPS 30 (economia)** em OPÇÕES, para o celular esquentar menos.
- **LIMPAR CACHE** em OPÇÕES apaga o cache de sons, mas não apaga o seu save.

### Ferramentas do editor (pasta `ferramentas/`)
Abra o script e use **Arquivo > Executar** (Ctrl+Shift+X). O resultado aparece na aba "Saída".
- `verificar_projeto.gd`: procura arquivos faltando, UIDs repetidos, imagens grandes demais e `.import` sobrando.
- `limpar_cache_editor.gd`: apaga os arquivos velhos de `.godot/imported` e reescaneia o projeto.

## Versão 3 — mais proteção contra o jogo fechar

- **O aviso amarelo** `"passo" is shadowing...` era só um aviso. Uma variável tinha o mesmo nome de uma função. Já foi corrigido, mas não era ele que fechava o jogo.
- **Tirei as threads:** os sons eram preparados em paralelo, e isso pode derrubar o jogo em alguns Android. Agora os sons já vêm **prontos dentro do projeto** (`Sons/gerados/`). O celular não precisa calcular nada e o menu abre em menos de 1 segundo.
- **Tirei 3 configurações que podem dar problema no Android:** fonte MSDF, tela girando sozinha (orientação "sensor") e "emular toque com o mouse".
- **Diário de passos:** o jogo escreve na aba **Saída** do editor (e em `user://passos.log`) cada etapa que conclui, com `[PASSO]` no começo. Se ele fechar, a última linha mostra onde parou.
- **Modo seguro:** se o jogo fechou sozinho, na próxima vez ele liga automaticamente sem partículas e avisa no menu.
- O canto do menu mostra a versão (agora **v4**). Se não aparecer, o Godot ainda está rodando a versão antiga (cache velho).

## Versão 4 — Teste do Celular

O aviso "Godot Engine 4 fechou porque este app tem um bug" quer dizer que o **próprio Godot** fechou (um erro dentro do motor, no celular). Não é um erro de script. Por isso o Godot pergunta sobre o "Modo de Recuperação", mas o projeto **não está quebrado**: escolha **Editar normalmente**.

Para descobrir qual parte derruba o Godot **no seu celular**:
1. Abra `Scenes/teste_celular.tscn`.
2. Aperte **Executar Cena Atual** (claquete com ▶).
3. Os testes rodam um por um: desenho, texto, partículas, sons, luz, tela pixelada, sprites, cabana e parque. Cada um fica 3 segundos.
4. Se o Godot fechar, abra o projeto de novo (**Editar normalmente**) e rode o teste outra vez. A tela mostra **"Da última vez o Godot FECHOU durante: teste X"**.

Outras mudanças:
- **Modo seguro:** se o jogo fechar sozinho, na próxima vez ele roda **sem som**. Também dá para desligar o som em OPÇÕES > SOM.
- **Canais de áudio:** agora vêm prontos em `default_bus_layout.tres`, em vez de serem criados com o jogo rodando.

## Versão 7.0 — zoom certo, mundo em pixel art detalhado, luzes seguras

### Bugs corrigidos da 6.4
| Bug | Por que acontecia | Como ficou |
|-----|-------------------|------------|
| Menus, textos e botões **gigantes** | A resolução do projeto inteiro tinha virado 480x270 (modo "viewport"), então a interface feita para 1280x720 ficou 2,7x maior | Voltou para **1280x720 / canvas_items**, igual à 6.0 |
| Zoom da câmera errado | Os zooms da 6.4 foram feitos para a tela de 480x270 | Zoom **igual ao da 6.0**: no jogo a câmera fica em 5x. O zoom não muda mais quando você troca o detalhe |
| Luz real (PointLight2D) religada no celular | A 6.4 voltou a ligar até 2 PointLight2D no Android, e no Mali-G68 isso derruba o Godot | **Nenhuma** PointLight2D no jogo. Todas as luzes agora são `LuzFake` |
| Avisos "invalid UID" | Os arquivos `.uid` dos scripts não vieram no zip | Os `.uid` foram recriados com os códigos que as cenas usam |
| Lareira acesa no jogo | A 6.0 acendia a lareira, mas a história diz "está escuro demais / cinzas frias" | Lareira apagada, só com uma brasinha piscando |
| Código quebrado no carro da cutscene | Havia um "plano B" que trocava o carro por um nó errado | Removido |

### Mundo mais bonito (pixel art de verdade)
- `pixel_arte.gd` pinta **pixel por pixel**: grama, grama seca, terra com pedrinhas, água com reflexos, piso de tábuas com pregos, parede de troncos, pedra da lareira e tapete.
- **17 enfeites** desenhados em pixel: arbustos com frutinhas, flores (vermelha, amarela, branca), tufos, pedras, cogumelos, tocos, tronco caído, samambaia, taboas, vitórias-régias, galhos e folhas.
- **Estrada** com beiras irregulares de grama e marcas de pneu. **Lago** com margem de lama, taboas e reflexo da lua. Toras em volta da fogueira e **fogo animado em pixel**.
- **Floresta cheia:** as árvores perto da ação são sprites, e centenas de árvores do fundo são desenhadas junto com o chão, sem pesar.
- **Cabana por dentro:** prateleira com potes, quadro, relógio parado, janela com estrelas, colchas xadrez, mochilas, violão com corda arrebentada, pia, pratos sujos, vela, caneca e lenha empilhada.

### Luzes pixeladas (o "ray tracing" do jogo)
Ray tracing de verdade é coisa de jogos 3D e não roda num celular com Godot 2D. Aqui fizemos o que dá esse efeito em pixel art, sem risco de fechar:
- Cada luz é uma imagem em **6 degraus de brilho** com pontilhado (dithering), do tamanho exato dos pixels do mundo.
- Ela é somada (mistura **aditiva**) numa camada que **a noite não escurece**. Por isso brilha no escuro.
- Luzes: fogueira tremendo, faróis do carro, janelas da cabana acendendo, reflexo da lua, lâmpada do teto, lareira e a lanterna do jogador.

### Nível de detalhe (OPÇÕES > DETALHE)
| | BAIXO (leve) | MÉDIO | ALTO |
|---|---|---|---|
| Árvores perto (celular) | 45 | 70 | 95 |
| Árvores do fundo (celular) | 140 | 230 | 320 |
| Enfeites no chão (celular) | 250 | 450 | 700 |
| Sombras projetadas das árvores | – | – | ✔ |

No PC as quantidades são o dobro.

### Para testar o "modo celular" no PC
Rode o jogo com o argumento `mobile`. Por exemplo: `godot --path . -- mobile`.

## Versão 8.0 — PARTE 2: SOBREVIVÊNCIA

Quando você sai da cabana no fim da Parte 1, o jogo salva (etapa 5) e começa a **Parte 2**.
O botão **CONTINUAR** do menu também leva direto para a Parte 2.

**Objetivo:** aguentar **5 noites**. Quando amanhece o dia 6, o resgate chega e você vence.
Se morrer, a Parte 2 recomeça do início (v9). O jogo salva toda manhã para você poder sair e continuar depois.

### Como os arquivos estão organizados (`Scripts/sobrevivencia/`)

| Arquivo | O que faz |
|---|---|
| `sobrevivencia.gd` | Junta todos os sistemas: entrar/sair da cabana, interação, dormir, save, onde os monstros aparecem |
| `hud_sobrevivencia.gd` | Barras com o botão STATUS, relógio, MOCHILA, CRIAR, ATACAR, LUZ e CORRER, e a visão escurecendo com o estresse |
| `status_jogador.gd` | Vida, Fome, Energia e Mente (estresse) |
| `inventario.gd` / `itens.gd` | Mochila com 12 espaços e itens que empilham. Os ícones são pixel art feita por código |
| `receitas.gd` | Lista de receitas de criação |
| `ciclo_dia.gd` | Relógio: 1 hora do jogo = 20 segundos. Dia das 6h às 18h, entardecer às 18h, noite das 19h às 5h |
| `monstro.gd` | Os 4 monstros, com IA de 6 estados: IDLE, PATROL, INVESTIGATE, ATTACK, SEARCH e RETURN |
| `abertura.gd` | Porta e janelas com barricadas |
| `iluminacao.gd` / `fonte_luz.gd` | Lista de todas as luzes, para os monstros saberem onde tem luz |
| `farol_cone.gd` / `carro.gd` | Faróis do carro e tudo que dá para fazer com o carro |
| `ruido.gd` | Barulho que atrai os monstros |
| `armadilha.gd` / `coletavel.gd` | Armadilhas no chão e recursos para pegar |

A cena é `Scenes/sobrevivencia.tscn`. O lado de fora fica na posição (0,0) e o lado de dentro da cabana fica em (4000,0). Entrar e sair da cabana é um "teletransporte" com fade.

### Os monstros

| Monstro | Como age | Como se defender |
|---|---|---|
| **Observador** | Fica longe, só olhando. Quando você está dentro da cabana, ele espia pela janela. Ver ele aumenta o estresse. Só ataca no pânico (Mente muito baixa) e no escuro | **Luz** faz ele sumir. **Feche a cortina** |
| **Rastejante** | Rápido, persegue você e entra pelas janelas sem proteção | **Armadilhas** (o laço prende ele), **tábuas** nas janelas e os **faróis**, que ofuscam ele |
| **Colosso** | Lento, com muita vida. **Quebra barricadas** e arranca você de dentro do carro | Armadilha de **estacas**, **reforço de metal** e o bastão |
| **Sombra** | Quase invisível. Caça quem está sozinho no escuro | **Luz**: ela não entra na luz e não enxerga você iluminado. Armas não funcionam nela |

**O barulho atrai os monstros.** Correr, martelar tábuas, criar coisas na bancada, quebrar galhos, abrir latas e jogar a lata-chocalho fazem barulho. Fazer barulho **dentro** da cabana faz os monstros lá fora atacarem a casa.

### Receitas

| Item | Precisa de | Bancada? | Libera quando |
|---|---|---|---|
| Tocha | 1 madeira, 1 pano | não | desde o começo |
| Bancada | 4 madeira, 2 pedra | não | desde o começo |
| Estaca afiada (arma) | 2 madeira, 1 pedra | não | desde o começo |
| Tábuas pregadas (+50) | 3 madeira, 1 corda | sim | desde o começo |
| Laço de corda | 2 corda, 2 madeira | sim | desde o começo |
| Kit médico | 2 ervas, 1 pano | sim | depois de achar ervas |
| Lata-chocalho (×2) | 1 metal, 2 pedra | sim | depois de achar metal |
| Lampião | 1 metal, 1 pano, 1 fósforo | sim | dia 2 |
| Reforço de metal (+100) | 2 metal, 1 corda, 1 madeira | sim | dia 2 |
| Armadilha de estacas | 3 madeira, 1 metal | sim | dia 3 |
| Bastão reforçado | 2 madeira, 2 metal, 1 corda | sim | dia 3 |

### Como as noites vão ficando mais difíceis

| Noite | Quem aparece |
|---|---|
| 1 | Observador e 1 Rastejante |
| 2 | Mais 1 Sombra (20h) e mais 1 Rastejante (21h) |
| 3 | **Colosso** (22h) e o 3º Rastejante (23h) |
| 4 | Mais uma Sombra (meia-noite) |
| 5 | Todos, com o Colosso de volta |

- **Às 5h** os monstros vão embora.
- **Às 6h** as barricadas perdem 35% da resistência, porque a madeira racha. Os recursos voltam a aparecer e o jogo salva.
- **Dormir na cama** passa a noite rápido, mas os monstros continuam batendo na casa. Se algum deles entrar, você acorda.

### Consertos pedidos

- **Luz do carro:** agora ela é um cone de verdade. São 18 raios que **param nas árvores e na cabana**, e a luz vai ficando mais fraca em 3 faixas. Ela gasta a bateria do carro e enfraquece quando a bateria está baixa. Além disso, a luz é **de verdade para os monstros**: ofusca o Rastejante e espanta o Observador e a Sombra.
- **Cortina:** ela fica exatamente em cima da janela. Ela tem dois estados, aberta e fechada, e muda **dentro e fora ao mesmo tempo**.
  - Com a cortina fechada, a lua não entra, a luz da lareira não aparece lá fora e o Observador não consegue espiar.
  - Com a cortina aberta e a luz acesa dentro, a janela brilha lá fora e **atrai monstros**.
- **Luz que sumia (bug achado nos testes):** a luz do jogador sumia depois de entrar ou sair da cabana. O motivo é que o `reparent` tira o nó da árvore por um instante, e o script achava que a luz tinha sido apagada. Agora o script só esconde o brilho nesse momento e só apaga quando o nó é destruído de verdade.
- **Tela mais limpa:** a sede saiu do jogo. O botão **STATUS** esconde e mostra as barras; com elas escondidas, só aparece o alerta do que está baixo.

### Controles

| Ação | Celular | Teclado |
|---|---|---|
| Andar | joystick (metade esquerda da tela) | WASD ou setas |
| Interagir | botão de ação (EXAMINAR, PEGAR, ENTRAR...) | E |
| Correr | segurar CORRER | Shift |
| Atacar | ATACAR | F |
| Luz | LUZ | Q |
| Mochila | MOCHILA | I ou Tab |
| Criar | CRIAR | C |

### Testes feitos

Os testes automáticos rodaram no **modo celular** e deram **85 de 85 OK**. Foram testados:

- a mochila: empilhar, encher e organizar
- a criação: tempo, bancada e receitas que liberam depois
- as barricadas e o desgaste da manhã
- a cortina por dentro e por fora
- os status
- o dia e a noite, e onde os monstros aparecem
- os estados da IA e o barulho
- a luz contra o Observador e a Sombra
- o cone do farol parando na árvore
- o Rastejante ofuscado pelo farol
- as armadilhas
- o Rastejante entrando pela janela
- o Colosso quebrando barricadas
- o combate
- dormir
- salvar e carregar
- o CONTINUAR
- a morte e a vitória
- o botão STATUS

Também testei o menu, a cutscene e a Parte 1 para ver se continuavam abrindo sem erros.

## Versão 9.0 — monstros novos, árvores sólidas, pesca e monstro do lago

### O que mudou
- **Monstros redesenhados.** Os monstros foram feitos em pixel art com **iluminação calculada por pixel** (`Scripts/relevo.gd`), uma espécie de mini "ray tracing".
  - O desenho é "esculpido" com bolas e tubos, como se fosse massinha.
  - Para cada pixel, o computador calcula a luz da lua, o brilho molhado e a **sombra**. A sombra é feita lançando um **raio** em direção à luz: se o raio bate numa parte mais alta do desenho, aquele pixel fica escuro.
  - Cada monstro tem 4 quadros de animação, todos gerados quando o jogo abre (não pesa durante o jogo).
  - Como são os monstros agora:
    - **Observador:** alto e pálido, com um olho vertical e braços enormes.
    - **Rastejante:** carapaça em gomos, muitas patas e mandíbulas.
    - **Colosso:** gigante de madeira podre com musgo e rachaduras de brasa.
    - **Sombra:** fumaça viva com olhos roxos.
- **Monstro do Lago (novo).**
  - É uma serpente que **nunca sai da água**. Ela nada escondida (só aparece uma sombra e ondinhas), sobe e morde quem chega na beira à noite.
  - Luz forte ou um golpe fazem ela mergulhar.
  - Pescar à noite atrai ela.
- **Árvores novas, 100% em pixel art.**
  - A origem de cada árvore é a **base do tronco**, então a colisão fica exatamente no tronco que você vê.
  - As árvores de "fundo" que ficavam dentro da área do jogo viraram sólidas. Antes elas eram só desenho no chão com colisão invisível, e por isso pareciam bugadas.
- **Colisão do carro e da cabana consertadas.**
  - O carro bloqueia a lataria inteira de baixo.
  - Na cabana, agora dá para **subir a escada e chegar na porta**. A varanda tem grade dos lados e o jogador aparece na frente da cabana quando está nela.
- **Tocos, troncos caídos, galhos e pedras do chão** agora dão madeira e pedra. Quando você chega perto, aparece uma **setinha** com o ícone do item e o botão vira **PEGAR**.
- **Água com movimento:** ondinhas, brilho deslizando, espuma na margem, peixes pulando e a boia da vara de pescar.
- **Pesca:**
  - Crie a **vara de pescar** e escolha **LAGO → PESCAR** na beira do lago.
  - Espere a boia afundar e toque em **PUXAR!** na hora certa. Se puxar cedo, o peixe foge.
  - Às vezes vem uma lata (metal) ou linha (corda).
  - A vara aguenta 12 pescarias.
- **Receitas novas:**
  - Na mão: vara de pescar e corda (feita de pano).
  - No fogo: peixe assado, chá de ervas e ensopado.
  - Na bancada, a partir do dia 2: lança e sinalizador.
- **Ícones novos (16x16, iluminados)** em todos os itens e nos botões MOCHILA, CRIAR, ATACAR (mostra a arma na mão), LUZ, CORRER e STATUS.
- **Morreu = recomeça a Parte 2 do zero.** Saiu a opção "voltar ao último amanhecer", que deixava pular as noites difíceis.
- O objetivo fica clarinho depois de alguns segundos, para a tela ficar mais limpa.

### Testes
Os testes automáticos rodaram no modo celular e deram **113 OK**. Os testes novos verificam:
- que o jogador não atravessa troncos nem o carro
- que dá para subir a escada e que a grade da varanda bloqueia
- que dá para pegar os tocos
- a pesca, puxando na hora certa e puxando cedo
- que assar precisa de fogo
- que o monstro do lago morde e mergulha com um golpe
- que os 31 itens têm ícone
- o sinalizador
- que a morte apaga o save da Parte 2

## Ideias para a próxima etapa

1. **Sair da cabana**: reaproveite `parque_exterior.gd` como fase, com colisões nas árvores.
2. **A criatura**: um inimigo que procura o grupo `"jogador"` e foge da luz da lanterna.
3. **Bateria da lanterna**: a luz vai diminuindo e você precisa achar pilhas.
4. **Encontrar Marina e Rafa**: cada um é um objetivo novo.

## Versão 10.0 — bugs consertados, sombras, machado, cama, cartazes, lago e o Lucas novo

> Abra o projeto no editor da Godot **uma vez** antes de exportar: ele importa sozinho
> os arquivos novos (`Sprites/lucas_andar.png` e os sons `.wav` em `Sons/gerados/`).

### Bugs consertados
| Bug | Por que acontecia | Como ficou |
|---|---|---|
| **O joystick sumia** depois de abrir o CRIAR | O HUD "lembrava" se o joystick estava visível na hora de esconder. Abrindo a MOCHILA e depois o CRIAR, ele lembrava "invisível". E fechar o CRIAR **enquanto algo era criado** saía da função antes de devolver o joystick | Cada pedido para esconder tem um **motivo** (conversa, painel, leitura). O joystick volta quando não sobra nenhum. Minimizar o app com o dedo na tela também solta o joystick |
| **Menu CRIAR bugado** | A lista inteira era apagada e recriada a cada item que entrava na mochila. A rolagem pulava, os botões piscavam e dava para tocar num botão que já tinha sido apagado | Cada receita tem a sua linha fixa. Tem **abas** (TUDO / NA MÃO / BANCADA / NO FOGO), o que dá para criar aparece primeiro, o botão diz o que falta (FALTA ITEM, VÁ À BANCADA, PERTO DO FOGO), os ingredientes ficam verdes/vermelhos e aparece uma **barra de progresso** |
| Perdia os ingredientes com a mochila cheia | Os ingredientes eram tirados antes de ver se o item novo cabia | Se não couber, nada é gasto |
| O tempo de criar continuava com o jogo pausado | O timer ignorava a pausa | Agora para junto com a pausa |
| **Save automático** | Só salvava no amanhecer. Se o Android fechasse o jogo à tarde, você voltava para as 6h. O "Menu principal" gravava dados velhos. Se o app fechasse no meio da gravação, o save podia estragar | Salva ao entrar/sair da cabana, ao pausar, ao minimizar, a cada hora do jogo e a cada 45 s (sem monstro perto). A gravação é **segura** (arquivo temporário + `save.bak` de reserva). O menu de pausa mostra quando foi o último save. Carregar no meio da noite traz os monstros de volta |
| A intro da Parte 2 repetia | O "já vi a intro" não era salvo | Salva no fim da intro |
| A fogueira/lareira apagavam ao continuar | Não eram salvas | Voltam acesas com o tempo que faltava |

### Otimização
- Os ~150 recursos do chão não rodam mais código a cada quadro: só os que estão **perto** do jogador.
- O lago não calcula nem redesenha nada quando está fora da tela.
- As barras de status e a vinheta do estresse só redesenham quando o valor muda.
- No máximo **8 efeitos de som ao mesmo tempo** no celular (16 no PC).

### Sombras dinâmicas (seguras no Mali)
Não usa PointLight2D, LightOccluder2D nem shader. Cada sombra é um Sprite2D com uma
elipse pixelada, e todas usam a mesma textura (a placa de vídeo desenha tudo junto).
Elas são atualizadas só 5 a 10 vezes por segundo, e só perto da câmera.
- **De dia:** a sombra do sol gira com as horas. Fica comprida de manhã e à tarde e curtinha ao meio-dia.
- **De noite:** sombra fraquinha da lua. Perto de uma luz (fogueira, lampião, tocha, lareira, sinalizador), a sombra aponta para longe dela. Nos faróis do carro ela fica bem comprida.
- O jogador, os monstros (menos a Sombra, que é fumaça), o Lucas e as árvores fazem sombra.
- Em DETALHE BAIXO só os personagens fazem sombra.

### Coisas novas
- **Machado** (2 madeira, 2 pedra, 1 corda, na mão) e **Machado de ferro** (bancada, dia 2):
  - chegue perto de uma árvore e toque em **CORTAR**
  - 3 golpes (ou 2 com o de ferro) derrubam a árvore e dão 3 ou 4 madeiras
  - fica um toco no lugar
  - cortar faz barulho
  - também servem de arma
- **Cama → DEITAR:**
  - a barra da **Mente** sobe aos poucos
  - o tempo **não** acelera
  - relaxa mais rápido com portas e janelas protegidas e com a lareira acesa
  - mexa o joystick para levantar
  - se um monstro te acertar, você levanta
  - **DORMIR** continua existindo
- **4 cartazes de DESAPARECIDO** pelo mapa (botão LER). São pessoas que sumiram no parque em outras épocas. Têm dicas escondidas, e um deles leva a um esconderijo.
- **Lago:**
  - **barco virado** para vasculhar
  - **covo** (armadilha de peixe): coloque na beira e ele pega peixes sozinho com as horas
  - **isca:** o peixe morde mais rápido e às vezes vem um **peixe grande**
  - **vagalumes** à noite
  - sapos coaxando
- **Receitas novas:**
  - machado e machado de ferro
  - bandagem (+15 vida)
  - isca
  - covo
  - fruta assada (no fogo)
- **O Lucas:**
  - folha de sprite nova (`Sprites/lucas_andar.png`, 4x4 quadros de 32 px: frente, costas, direita e esquerda), feita a partir do desenho enviado
  - ele usa essa folha na cutscene
  - na Parte 2, a partir do dia 2, às vezes você vê o **vulto do Lucas** no fim da tarde, ou de noite quando a mente está ruim
  - quando você chega perto, ele some e deixa uma **página do diário** dele (5 no total)
- **Sons novos** (WAV curtos, tocam uma vez só, sem loop):
  - machado e árvore caindo
  - água e peixe
  - sapo
  - coração (monstro perto ou mente no limite)
  - sussurros (mente ruim)
  - papel
  - cama
  - rajadas de vento
  - galhos estalando longe à noite
  - Os arquivos são gerados por `ferramentas/gerar_sons_v10.py`. A folha do Lucas é gerada por `ferramentas/gerar_lucas_v10.py`.
