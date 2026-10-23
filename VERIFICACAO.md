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
