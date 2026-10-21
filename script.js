// ============================================================
// CONFIGURAÇÃO – Altere apenas este número
// ============================================================
const NUMERO_WHATSAPP = "5592992933693"; // 55 + DDD + número (sem espaços)

// ============================================================
// ELEMENTOS
// ============================================================
const form = document.getElementById("form-pedido");
const campoEndereco = document.getElementById("campo-endereco");
const inputData = document.getElementById("data");
const btnEnviar = document.getElementById("btn-enviar");
const toast = document.getElementById("toast");

// ============================================================
// INICIALIZAÇÃO
// ============================================================
document.addEventListener("DOMContentLoaded", () => {
  // Data mínima = hoje
  const hoje = new Date().toISOString().split("T")[0];
  inputData.min = hoje;

  // Mostrar/esconder endereço
  document.querySelectorAll('input[name="tipo_pedido"]').forEach((radio) => {
    radio.addEventListener("change", atualizarCampoEndereco);
  });
  atualizarCampoEndereco(); // estado inicial

  // Controles de quantidade (+ / −)
  document.querySelectorAll(".item-quantidade").forEach((item) => {
    const input = item.querySelector('input[type="number"]');
    const btnMais = item.querySelector(".btn-mais");
    const btnMenos = item.querySelector(".btn-menos");

    btnMais.addEventListener("click", () => {
      let val = parseInt(input.value) || 0;
      input.value = val + 1;
      animarBotao(btnMais);
    });

    btnMenos.addEventListener("click", () => {
      let val = parseInt(input.value) || 0;
      if (val > 0) {
        input.value = val - 1;
        animarBotao(btnMenos);
      }
    });
  });

  // Submit do formulário
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    if (validarFormulario()) {
      enviarPedidoWhatsApp();
    } else {
      mostrarToast("Preencha os campos obrigatórios.", "erro");
    }
  });
});

// ============================================================
// FUNÇÕES AUXILIARES
// ============================================================
function atualizarCampoEndereco() {
  const selecionado = document.querySelector('input[name="tipo_pedido"]:checked');
  if (selecionado && selecionado.value === "Entrega em domicílio") {
    campoEndereco.classList.add("ativo");
  } else {
    campoEndereco.classList.remove("ativo");
  }
}

function animarBotao(btn) {
  btn.style.transform = "scale(0.9)";
  setTimeout(() => {
    btn.style.transform = "";
  }, 120);
}

function mostrarErro(inputId, erroId) {
  const input = document.getElementById(inputId);
  const erro = document.getElementById(erroId);
  if (input) input.classList.add("invalid");
  if (erro) erro.classList.add("visivel");
}

function limparErros() {
  document.querySelectorAll(".erro").forEach((el) => el.classList.remove("visivel"));
  document.querySelectorAll(".invalid").forEach((el) => el.classList.remove("invalid"));
}

function mostrarToast(mensagem, tipo = "sucesso") {
  toast.textContent = mensagem;
  toast.className = `toast visivel ${tipo}`;
  setTimeout(() => {
    toast.classList.remove("visivel");
  }, 3200);
}

function formatarData(dataISO) {
  if (!dataISO) return "";
  const [ano, mes, dia] = dataISO.split("-");
  return `\( {dia}/ \){mes}/${ano}`;
}

// ============================================================
// VALIDAÇÃO
// ============================================================
function validarFormulario() {
  limparErros();
  let valido = true;

  // Nome
  const nome = document.getElementById("nome");
  if (!nome.value.trim()) {
    mostrarErro("nome", "erro-nome");
    valido = false;
  }

  // Telefone (mínimo 10 dígitos)
  const telefone = document.getElementById("telefone");
  const digitos = telefone.value.replace(/\D/g, "");
  if (!telefone.value.trim() || digitos.length < 10) {
    mostrarErro("telefone", "erro-telefone");
    valido = false;
  }

  // Endereço (somente se entrega)
  const tipoPedido = document.querySelector('input[name="tipo_pedido"]:checked').value;
  if (tipoPedido === "Entrega em domicílio") {
    const endereco = document.getElementById("endereco");
    const bairro = document.getElementById("bairro");
    if (!endereco.value.trim()) {
      mostrarErro("endereco", "erro-endereco");
      valido = false;
    }
    if (!bairro.value.trim()) {
      mostrarErro("bairro", "erro-bairro");
      valido = false;
    }
  }

  // Data
  if (!inputData.value) {
    mostrarErro("data", "erro-data");
    valido = false;
  }

  // Horário
  const horario = document.getElementById("horario");
  if (!horario.value) {
    mostrarErro("horario", "erro-horario");
    valido = false;
  }

  // Pelo menos um produto
  const temBolo = document.getElementById("bolo-tamanho").value !== "";
  const quantidades = [
    "qtd-brigadeiro",
    "qtd-beijinho",
    "qtd-coxinha",
    "qtd-empada",
    "qtd-quiche",
    "qtd-bolo-pote",
    "qtd-torta",
  ];
  const temOutros = quantidades.some((id) => {
    const val = parseInt(document.getElementById(id).value) || 0;
    return val > 0;
  });

  if (!temBolo && !temOutros) {
    mostrarToast("Selecione pelo menos um produto (bolo ou outros itens).", "erro");
    valido = false;
  }

  // Foco no primeiro campo com erro
  if (!valido) {
    const primeiroErro = document.querySelector(".invalid");
    if (primeiroErro) {
      primeiroErro.scrollIntoView({ behavior: "smooth", block: "center" });
      primeiroErro.focus({ preventScroll: true });
    }
  }

  return valido;
}

// ============================================================
// ENVIO PARA O WHATSAPP
// ============================================================
function enviarPedidoWhatsApp() {
  btnEnviar.classList.add("loading");
  btnEnviar.disabled = true;

  const nome = document.getElementById("nome").value.trim();
  const telefoneCliente = document.getElementById("telefone").value.trim();
  const tipoPedido = document.querySelector('input[name="tipo_pedido"]:checked').value;
  const data = formatarData(document.getElementById("data").value);
  const horario = document.getElementById("horario").value;
  const pagamento = document.querySelector('input[name="pagamento"]:checked').value;
  const observacoes = document.getElementById("observacoes").value.trim() || "Nenhuma";

  // Endereço
  let enderecoTexto = "";
  if (tipoPedido === "Entrega em domicílio") {
    const endereco = document.getElementById("endereco").value.trim();
    const bairro = document.getElementById("bairro").value.trim();
    enderecoTexto = `${endereco} – ${bairro}`;
  }

  // Itens
  const itens = [];

  // Bolo
  const tamanho = document.getElementById("bolo-tamanho").value;
  if (tamanho) {
    const massa = document.getElementById("bolo-massa").value || "Não informado";
    const recheio1 = document.getElementById("bolo-recheio1").value || "Não informado";
    const recheio2 = document.getElementById("bolo-recheio2").value;
    let recheios = recheio1;
    if (recheio2) recheios += ` + ${recheio2}`;
    itens.push(`- 1x Bolo Personalizado (${tamanho}) | Massa: ${massa} | Recheio: ${recheios}`);
  }

  // Outros itens
  const listaItens = [
    { id: "qtd-brigadeiro", nome: "Brigadeiro tradicional" },
    { id: "qtd-beijinho", nome: "Beijinho" },
    { id: "qtd-coxinha", nome: "Coxinha de frango" },
    { id: "qtd-empada", nome: "Empada de frango" },
    { id: "qtd-quiche", nome: "Mini quiche" },
    { id: "qtd-bolo-pote", nome: "Bolo de pote" },
    { id: "qtd-torta", nome: "Torta salgada (fatia)" },
  ];

  listaItens.forEach((item) => {
    const qtd = parseInt(document.getElementById(item.id).value) || 0;
    if (qtd > 0) {
      itens.push(`- ${qtd}x ${item.nome}`);
    }
  });

  // Mensagem formatada
  let mensagem = `🍰 *NOVO PEDIDO DE CONFEITARIA*\n\n`;
  mensagem += `👤 *Cliente:* ${nome}\n`;
  mensagem += `📱 *Telefone:* ${telefoneCliente}\n`;
  mensagem += `📅 *Data/Hora:* ${data} às ${horario}\n`;
  mensagem += `🚗 *Entrega/Retirada:* ${tipoPedido}\n`;

  if (enderecoTexto) {
    mensagem += `📍 *Endereço:* ${enderecoTexto}\n`;
  }

  mensagem += `\n📋 *ITENS DO PEDIDO:*\n`;
  mensagem += itens.join("\n");
  mensagem += `\n\n✍️ *Observações:* ${observacoes}\n`;
  mensagem += `💳 *Pagamento:* ${pagamento}`;

  // Abre o WhatsApp
  const url = `https://wa.me/\( {NUMERO_WHATSAPP}?text= \){encodeURIComponent(mensagem)}`;

  // Pequeno delay para feedback visual
  setTimeout(() => {
    window.open(url, "_blank");
    btnEnviar.classList.remove("loading");
    btnEnviar.disabled = false;
    mostrarToast("Pedido aberto no WhatsApp! 🎉", "sucesso");
  }, 600);
}