# Manual ilustrado — versão 0.2.0+4

- Nove capturas reais do aplicativo incluídas em docs/manual_typica.html.
- HTML único, com logotipo e imagens incorporados, sem recursos externos
  necessários à leitura e sem alteração do código do aplicativo.
- Revisão visual e teste no Chrome em larguras de 1440, 390 e 320 px.
- Navegação pelas etapas, ampliação de imagens, fechamento por Escape,
  retorno de foco e abertura das respostas de ajuda verificados.
- Leitura sem internet, sem solicitações HTTP externas e com JavaScript
  desativado; sem erros no navegador ou rolagem horizontal.
- Cópia do manual no repositório conferida por SHA-256 contra o HTML original.

Capturas e relatório local em build/tutorial_typica/.
Os testes de navegador não substituem testes físicos em Android/iPhone.

---

# Filtros lado a lado — versão 0.2.0+4

- Ciclo de maturação e Instituição em duas colunas dentro da mesma caixa.
- Títulos e seletores alinhados; nomes longos em até duas linhas e menus mais largos.
- Revisão visual em 320 × 568 e 390 × 844, sem transbordamentos.
- Compilação Flutter Web e análise Dart aprovadas.
- Verificação existente aprovada: 24 combinações, oito cenários de limpeza,
  reabertura offline, ausência de exportação e nenhum novo download do banco.
- Lógica dos filtros, catálogo de instituições e manifesto científico idênticos
  à versão anterior; a alteração é visual.
- Publicação anterior preservada em build/web_preservado_0.2.0_3/.

Relatórios e capturas em build/verificacao-lado-0.2.0_4/.
Testes de navegador no Chrome do computador; não incluem aparelhos físicos.

---

# Limpar filtros e exportação — versão 0.2.0+3

- Compilação Flutter Web e análise Dart aprovadas.
- Limpar filtros devolve os quatro campos a Todos e mantém o pixel selecionado.
- Oito cenários de limpeza aprovados, incluindo quatro filtros ativos, lista
  vazia, somente instituição, dois pixels, uso offline e tela de 320 px.
- Botão desabilitado quando todos os campos já estão em Todos.
- 24 combinações anteriores de filtros continuam na ordem do SQLite original.
- Opção de exportar/compartilhar ausente; nenhum arquivo exportado nas interações.
- Serviço PDF e cópia da tela anterior preservados para retomada futura.
- Tela revisada visualmente em 320 e 390 px, sem transbordamento.
- 46 lotes preparados uma vez; limpeza e reabertura offline não repetem download.
- 138 arquivos conferidos: projetos anteriores, serviço PDF e dados científicos
  preservados. A publicação anterior também foi guardada em build/.

Relatórios: `build/verificacao-limpar-0.2.0_3/`.
Os testes são no Chrome do computador; não incluem aparelhos físicos.

---

# Verificação dos filtros — versão 0.2.0+2

- Análise Dart sem problemas e compilação Flutter Web concluída.
- 39 associações de instituição conferidas contra as colunas A/B da aba
  `Informação Cultivares`, sem modificar o Excel.
- 24 combinações de instituição, ciclo e resistência verificadas em dois pixels
  reais de Viçosa, comparando a ordem com o SQLite original.
- Todos inclui os três ciclos; selecionar Todos em um filtro preserva os demais.
- Listas vazias corretas para combinações sem resultados, inclusive instituições
  presentes na planilha mas ausentes nos rankings desta base de 12 cultivares.
- Nome abreviado Bourbon Ama. IAC J10 associado ao nome completo da planilha.
- Filtros funcionam após fechar e reabrir o navegador offline, sem repetir os
  46 downloads. Catálogo de instituições incluído no cache da interface.
- Tela de 320 px e relatório PDF revisados visualmente, sem cortes nos filtros.
- PDF registra Instituição: IAC e Ciclo: Curto junto das duas cultivares esperadas.
- 13 verificações de regressão aprovadas: ranking, GPS, resistência, PDF, maior
  município e reabertura offline.
- Excel, projetos anteriores, catálogo original e bancos científicos preservados.

Relatórios em `build/verificacao-filtros/` e `build/verificacao-regressao-filtros/`.
A publicação anterior permanece em `build/web_preservado_0.2.0_1/`.
Os testes foram feitos no Chrome do computador; não foram testes físicos de celular.

---

# Verificação da versão 0.2.0+1

Projeto independente `typica_pwa_php`. Os resultados detalhados ficam em
`build/verificacao*/resultado.json`, `build/verificacao-api/` e
`build/preservacao_originais.json`.

- Compilação Flutter Web concluída; análise de `lib/` sem problemas.
- Sintaxe PHP validada em PHP 8.2.35; API também executada em PHP 8.5.4.
- Contrato HTTP aprovado nas duas versões; PHP 8.2 validado na raiz e em `/typica/`.
- Integridade dos lotes, manifesto e dados científicos preservada.
- Os 46 lotes são realmente baixados por `api/lote.php`.
- Teste funcional com 13 verificações: download manual, instalação disponível,
  pesquisa de Viçosa, GPS em dois pixels com rankings diferentes, filtros,
  PDF, João Pinheiro e reabertura com o navegador totalmente offline.
- Bancos abertos simultaneamente abaixo de 5 MB, sem abrir o SQLite monolítico.
- Tela de 390 × 844: abertura, indicador de 20 px, ações iniciais, verificação
  de atualização pelo PHP, instalação simulada com preparação dos dados,
  duas janelas sem download duplicado e tutorial completo após instalar.
- Perfil instalado separado prepara os dados e reabre offline.
- Publicação em subpasta testada a 320 × 568: manifesto PHP fixado salvo para
  reabertura offline; versão atualizada não é atendida com cache antigo.
- Atualização interrompida mantém o app anterior; atualização completa preserva
  IndexedDB e preferências e permite reabrir offline.
- 87 arquivos originais conferidos por SHA-256, incluindo todos os arquivos
  versionados do PWA anterior e os cinco arquivos científicos de entrada.
  Nenhum foi modificado. O diff já existente no repositório principal é idêntico
  ao registrado antes da criação da nova pasta.

Os testes de interface usam Chrome no computador. Convite de instalação,
modo standalone e armazenamento separado são simulados. Não substituem testes
físicos em Android e iPhone. A publicação definitiva na UFV-DTI depende da
configuração e aprovação da instituição; não foi realizada nesta tarefa.
