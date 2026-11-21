# Digital Creator Marketplace

Marketplace digital multi-criador, construído sobre Bagisto/Laravel como motor de comércio e módulos próprios para as regras de negócio específicas.

## Decisões de produto (confirmadas)

- Marketplace com múltiplos criadores/vendedores.
- Venda individual de fotografias e vídeos; sem bundles ou subscrições nesta fase.
- Conteúdos gratuitos permitidos.
- Comissão da plataforma: 10% por venda (configurável no futuro, com histórico por transação).
- PayPal é o único meio de pagamento inicial. Não implementar Stripe.
- O comprador paga à conta PayPal da plataforma.
- A plataforma regista os valores devidos a cada criador e mantém-nos retidos durante um período configurável, para cobrir reembolsos e disputas.
- Pagamentos aos criadores são posteriores, quando o saldo elegível atingir um mínimo configurável.
- Registo de criador não concede autorização de venda: validação administrativa obrigatória antes de ativar a capacidade de publicar para venda.
- Nesta fase não existe moderação editorial prévia dos ficheiros. A responsabilidade pelo conteúdo publicado é do criador, sem prejuízo de mecanismos de denúncia, remoção legal e resposta a abuso.
- Não criar nem assumir funcionalidades de produtos físicos, inventário físico, portes ou logística.

## Estratégia de implementação

Usar Bagisto (Laravel) como base para identidade/contas, catálogo, checkout, encomendas, pagamentos PayPal e downloads digitais, após validação da compatibilidade da versão escolhida.

Desenvolver módulos de domínio próprios para:
1. Creator onboarding e verificação administrativa.
2. Media digital (fotografia/vídeo), direitos, metadados e ficheiros protegidos.
3. Compras digitais e entitlement de acesso.
4. Comissão, ledger contabilístico imutável, retenções e saldo elegível.
5. Pedidos e execução administrativa de pagamentos a criadores.
6. Auditoria, segurança e resolução de reembolsos/disputas.

Não assumir que a extensão multi-vendor do Bagisto é open source/incluída no core. Foi identificada como extensão separada nas páginas públicas; a arquitetura deve ser implementável com módulos próprios sem depender dela.

## Repositório base conhecido

O repositório atualmente aberto é `rtmarcomt-tech/spree`, uma cópia de Spree Commerce (Ruby on Rails), não será usado como base tecnológica desta aplicação. Foi criada a branch `marketplace-digital/architecture` para manter a documentação do estudo no repositório de trabalho sem alterar a branch main. A adoção de Bagisto permanece sujeita a revisão de licença, versão e dependências no momento de implementação.

## Arquitetura de domínio (proposta inicial)

### Identidade e autorização
- users: identidade/autenticação base (Bagisto/Laravel).
- creator_profiles: user_id único, slug, nome público, bio, estado, país, timestamps.
- creator_verification_cases: creator_id, estado, submitted_at, reviewed_at, reviewer_id, decisão e motivo interno.
- creator_verification_documents: caso, tipo documental, object_key privado, checksum, estado de acesso, retenção e datas.
- roles/permissions: papéis buyer, creator_pending, creator_active, admin; permissões verificadas no backend por policy/gate.

Estados do criador:
`draft -> submitted -> under_review -> approved | rejected`; posteriormente `suspended` ou `closed`.
Só `approved` pode criar ofertas pagas ou gratuitas públicas. Alterações de perfil não podem elevar permissões.

### Conteúdos digitais
- creator_media: creator_id, tipo (photo/video), título, descrição, slug, preço em unidades menores da moeda, moeda, estado (draft/published/archived/takedown), visibilidade (free/paid), timestamps.
- media_assets: media_id, purpose (original/preview/thumbnail), storage_disk, object_key, mime, size, checksum, width/height/duration, encryption metadata, created_at.
- media_categories e pivot.
- media_rights_declarations: creator_id, media_id, titularidade/autorizações declaradas, versão dos termos, timestamp, IP/hash de evidência conforme política de privacidade.
- media_access_grants: buyer_id, media_id, order_item_id, granted_at, revoked_at, reason. Única fonte de autorização de download.
- media_download_events: grant_id, user_id, issued_at, expires_at, outcome, IP minimizado e user-agent conforme retenção legal.

Os originais nunca ficam em public webroot. Pré-visualizações públicas são derivadas separadas, com resolução/marca de água configurável. Downloads pagos usam URLs curtas assinadas após autorização; não expor storage keys.

### Comércio
- Usar produto digital/downloadable de Bagisto apenas como integração de catálogo e checkout, não como fonte única de autorização. Mapear cada SKU/produto para creator_media através de tabela própria `commerce_media_mappings`.
- orders/order_items e payment records são mantidos no motor comercial.
- Cada order_item deve mapear exatamente um media_id e creator_id no momento da compra (snapshot imutável).
- Impedir que o vendedor compre o próprio conteúdo e impedir duplicação de entitlement por webhook/retry.
- Compra gratuita gera order/entitlement sem captura PayPal e sem crédito financeiro.

### Pagamentos e contabilidade
- platform_payment_transactions: order_id, provider (paypal), provider_order_id, capture_id, gross_minor, currency, status, idempotency_key, timestamps.
- creator_ledger_accounts: creator_id, currency, account_type (pending, available, paid, reserve/debt).
- creator_ledger_entries: account_id, transaction_id, entry_type, amount_minor assinado, currency, reference_type/id, effective_at, created_at. Append-only; correções por lançamentos inversos, nunca editar/apagar movimentos.
- commission_rules: percentagem base (10%), validade temporal e âmbito.
- commission_entries: order_item_id, gross_minor, commission_minor, creator_net_minor, currency, rule_snapshot.
- fund_holds: order_item_id, amount_minor, hold_until, reason, state; libertação apenas por evento de serviço, nunca apenas pelo cliente.
- refund_disputes: payment_transaction_id, provider_case_id, amount_minor, state, outcome, timestamps.
- payout_thresholds: currency, minimum_minor e configuração efetiva.
- payout_batches / payout_items: pedido, aprovação administrativa, valor, destinatário, provider_reference, estado, tentativas e reconciliação.
- ledger_audit_events: ator, evento, entidade, payload minimizado, timestamp.

Invariantes:
1. Valores monetários são inteiros em unidades menores da moeda; nunca float.
2. Cada captura PayPal é processada idempotentemente.
3. Commission + creator_net = gross, sujeito a uma política explícita para taxas PayPal (não inventar deduções).
4. Crédito do criador é pending durante a retenção; só depois pode passar a available.
5. Reembolso/disputa pode congelar saldo e lançar movimentos compensatórios.
6. Não pagar mais do que o available balance, nem abaixo do mínimo configurado.
7. Payout só se considera concluído após confirmação/reconciliação do fornecedor ou comprovativo administrativo validado.
8. PayPal payout/batch API availability, account eligibility and regional limits must be verified. Até essa validação, permitir execução administrativa registada, sem alegar transferência automática.

### Segurança e privacidade
- Policies por recurso e ownership em todas as queries.
- MFA para administração e ações financeiras sensíveis.
- Rate limit para autenticação, checkout, downloads e webhooks.
- Verificação de assinatura PayPal e persistência do evento antes do processamento.
- Webhooks com deduplicação, retries e dead-letter handling.
- Segredos exclusivamente em variáveis de ambiente/secret manager.
- Storage privado com TLS, checksums, limites de tamanho, validação real de MIME e antivírus quando disponível.
- Não armazenar dados de cartão.
- GDPR: minimização, prazos de retenção, exportação e eliminação sujeita a obrigações contabilísticas/legais.
- Ações administrativas e financeiras auditadas.

## Fluxos críticos

### Onboarding de criador
1. Utilizador cria conta.
2. Solicita ativação de criador e fornece dados/documentos necessários.
3. Conta fica pending; não pode publicar ofertas.
4. Admin analisa e aprova/rejeita, com justificação e trilho de auditoria.
5. Apenas aprovado recebe permissões creator_active.

### Publicação
1. Criador aprovado carrega original para storage privado.
2. Backend valida tipo, tamanho, checksum e gera preview/thumbnail.
3. Criador declara direitos e aceita termos.
4. Conteúdo é publicado como free ou paid.
5. Não há aprovação editorial prévia nesta fase; denúncia/takedown são processos separados.

### Compra paga
1. Checkout cria order e inicia PayPal.
2. Só captura confirmada por webhook/verificação server-to-server confirma pagamento.
3. Evento é persistido e deduplicado.
4. Criar entitlement de forma idempotente.
5. Lançar gross, comissão de 10% e net do criador no ledger.
6. Creator net fica pending até ao fim do hold period.
7. Disponibilizar download via grant e URL assinada.

### Compra gratuita
1. Validar conta/acesso conforme política.
2. Criar entitlement gratuito sem PayPal.
3. Nenhum ledger financeiro é criado.

### Reembolso/disputa
1. Registar evento e congelar o valor ainda não pago.
2. Decisão baseada no estado real PayPal e política aplicável.
3. Criar lançamentos compensatórios auditáveis; nunca apagar a venda original.
4. Revogar entitlement apenas quando a regra de negócio/decisão o determinar.

### Pagamento ao criador
1. Job calcula available balance reconciliado.
2. Verifica mínimo configurável, dados do beneficiário e bloqueios.
3. Cria payout request/batch idempotente.
4. Admin revê/autoriza quando exigido.
5. Executa API PayPal Payouts se a conta for elegível; caso contrário, fluxo manual registado.
6. Reconcilia resultado e lança transferência para paid.

## Estados essenciais
- Media: draft, processing, published, archived, takedown, failed.
- Order/payment: pending, authorized, captured, failed, partially_refunded, refunded, disputed.
- Entitlement: active, revoked, expired.
- Ledger hold: pending, released, frozen, reversed.
- Payout: requested, under_review, approved, processing, paid, failed, cancelled.

## Critérios de aceitação obrigatórios
- Criador pendente não consegue publicar nem por API direta.
- Criador A não consegue consultar ficheiros privados nem dados financeiros do criador B.
- Comprador sem entitlement não obtém URL válida do original.
- Repetir o mesmo webhook não duplica order, entitlement, comissão ou ledger.
- Duas compras concorrentes não permitem double credit.
- O cálculo 10% é determinístico por item e moeda.
- Hold não pode ser libertado antes do prazo.
- Disputa aberta impede payout do montante afetado.
- Payout não excede saldo disponível nem duplica em retries.
- Downloads gratuitos e pagos têm autorização e auditoria.
- Testes de integração cobrem falhas de PayPal, timeouts, webhooks fora de ordem e reembolsos.
- CI executa formatter, static analysis, unit tests e feature tests sem falhas.

## Próximas tarefas técnicas
1. Confirmar versão estável Bagisto/Laravel e requisitos da VPS.
2. Fazer fork/cópia licenciada do Bagisto para repositório próprio (MIT, preservar notices).
3. Inspecionar código real do módulo PayPal e dos produtos downloadable.
4. Criar package(s) Laravel próprios para Creator, DigitalMedia e MarketplaceLedger.
5. Definir contrato de integração commerce/order/payment com testes de contrato.
6. Implementar vertical slice: registo -> aprovação -> publicação -> compra PayPal sandbox -> entitlement -> ledger -> hold.
