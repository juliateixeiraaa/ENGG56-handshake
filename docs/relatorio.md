# Relatório Técnico — Sistema de Comunicação com Handshake Assíncrono

**ENGG56 — Projeto de Circuitos Integrados Digitais — 2026.2 — UFBA**
**Prof.:** Wagner L. A. de Oliveira
**Grupo:** Amanda Bastos de Melo Correia, Júlia Teixeira Gonçalves, Maria Clara Andrade Magalhães Paternostro D'Oliveira

> Esqueleto do relatório. Trechos em _itálico_ ou marcados com **TODO** devem
> ser preenchidos com os resultados obtidos na VM.

---

## 1. Introdução

_Objetivo do trabalho em 1 parágrafo: capturar 16 palavras de 16 bits no
domínio CLK_A, transferi-las para o domínio CLK_B por handshake REQ/ACK de
4 fases e disponibilizá-las por uma interface valid/ready de saída, passando
por RTL, simulação, síntese lógica (Yosys) e física (OpenROAD)._

## 2. Arquitetura

### 2.1 Diagrama de blocos
_Inserir o diagrama (pode ser o do README exportado como imagem)._

### 2.2 Sinais e parâmetros
_Copiar/ajustar a tabela de interface do README. Parâmetros: WIDTH = 16, DEPTH = 16, SYNC_STAGES = 2._

### 2.3 Máquinas de estados
- **Sender:** CAPTURE → LOAD → REQ → WAIT_ACK_LOW → (LOAD | DONE)
- **Receiver:** WAIT_REQ → WAIT_REQ_LOW → (WAIT_REQ | OUTPUT) → FIM
  (o estado final se chama FIM para não confundir com a saída OUT_DONE)

_Inserir os diagramas e explicar cada transição._

### 2.4 Decisões de projeto
- **Polaridade do reset:** RESET_N ativo baixo; assertion assíncrona e deassertion síncrona por domínio (`reset_sync`).
- **Sincronizadores:** 2 flip-flops para `req` (no Receiver) e `ack` (no Sender).
- **Bundled-data:** `tx_data` registrado em LOAD; `req` sobe 1 ciclo de CLK_A depois; captura no Receiver só após `req` sincronizado. `tx_data` só muda com `req = ack = 0`.
- **Sinais de CDC saem de flip-flops** (sem lógica combinacional) para evitar glitches.
- **Armazenamento:** registradores (16 × 16 bits em cada bloco), sem reset nos dados.
- **RX_DONE × OUT_VALID na mesma borda de CLK_B:** o enunciado pede que as palavras
  sejam entregues após o recebimento completo. No Receiver, a transição para OUTPUT
  e a subida de RX_DONE acontecem na mesma borda, e OUT_VALID é uma saída de Moore
  do estado OUTPUT; logo nenhuma palavra é oferecida antes de RX_DONE = 1. O monitor
  do testbench confirma isso em todos os cenários. Acrescentar um estado de espera de
  1 ciclo antes de OUTPUT foi considerado e descartado: atrasaria a saída sem mudar
  a funcionalidade. Decisão tomada pelo grupo em 22/11.
- _Outras decisões/alternativas consideradas._

## 3. Verificação funcional

### 3.1 Ambiente
_Icarus Verilog (`-g2012`) + GTKWave. Clocks com períodos distintos e fases iniciais diferentes._

Os períodos de cada cenário foram escolhidos com mdc(T_A, T_B) = 0,1 ns, para
que a fase relativa entre as bordas de CLK_A e CLK_B passe por muitos valores
distintos antes de se repetir. Em simulação RTL não há atrasos, então só a
razão e a fase entre os clocks importam. Os pares de T2 e T4 coincidem com os do
SDC (Nangate45 e Sky130HD) por rastreabilidade, não por exigência de temporização.

| Cenário | CLK_A (ns) | CLK_B (ns) | Razão | Fases distintas | Repete a cada |
|---|---|---|---|---|---|
| T1, T2, T3 | 4,0 | 5,7 | 40:57 | 40 | 228 ns |
| T4 | 10,0 | 14,3 | 100:143 | 100 | 1430 ns |
| T5 | 23,3 | 7,0 | 233:70 | 70 | 1631 ns |
| T6 | 10,0 | 10,1 | 100:101 | 100 | 1010 ns |

Fases iniciais: os clocks começam com atrasos diferentes (`#1.3` para CLK_A e
`#3.7` para CLK_B no testbench). Com os períodos de T1, a primeira borda de
subida de CLK_A ocorre em 3,3 ns e a de CLK_B em 6,55 ns. Nas trocas de período
entre cenários, os clocks continuam rodando, então a fase não é reiniciada.

### 3.2 Cenários

| Cenário | Descrição | Resultado |
|---|---|---|
| T1 | Reset inicial e liberação síncrona | **TODO** |
| T2 | Fluxo sem esperas; IN_VALID extra ignorado | **TODO** |
| T3 | Reset assíncrono durante o handshake | **TODO** |
| T4 | Esperas aleatórias em IN_VALID e OUT_READY | **TODO** |
| T5 | Clocks invertidos (A lento, B rápido) | **TODO** |
| T6 | Clocks quase iguais (10,0 / 10,1 ns) | **TODO** |

### 3.3 Formas de onda
_Prints com legenda: (a) captura na entrada, (b) um ciclo completo REQ/ACK
mostrando os sincronizadores, (c) leitura com OUT_READY inativo, (d) RX_DONE e
OUT_DONE, (e) reset no meio da transferência._

## 4. Síntese lógica (Yosys)

### 4.1 Relatório de células
_Colar o resumo de `SinteseLogica/yosys_stat_nangate45.txt` (número de células, área, tipos)._

| Recurso | Quantidade | Comentário |
|---|---|---|
| Flip-flops (total) | **TODO** | esperado ≈ 2×256 (memórias) + contadores + estados + sincronizadores |
| Flip-flops com reset | **TODO** | |
| Multiplexadores / lógica | **TODO** | |
| Área total (µm²) | **TODO** | |

### 4.2 Análise da netlist
_Identificar na netlist (view_rtl / view_mapped / view_orfs):_
- _registradores das memórias e o mux de leitura 16:1;_
- _contadores (somadores de 4 bits);_
- _registradores de estado das FSMs e codificação adotada pelo Yosys;_
- _sincronizadores (2 DFFs em série sem lógica entre eles);_
- _diferenças entre síntese independente e a do ORFS._

## 5. Síntese física (OpenROAD)

### 5.1 Restrições (SDC)
| Item | Nangate45 | Sky130HD |
|---|---|---|
| Período CLK_A (ns) | 4,0 | 10,0 |
| Período CLK_B (ns) | 5,7 | 14,3 |
| Atraso de E/S | 20% do período | 20% do período |
| Orçamento CDC (`set_max_delay`) | 4,0 ns | 10,0 ns |

**Exceções de temporização adotadas:**
1. `set_false_path -from RESET_N`: entrada assíncrona; deassertion re-sincronizada. Os caminhos reset_sync → flip-flops continuam analisados (recovery/removal).
2. `set_max_delay` entre CLK_A e CLK_B (setup): os caminhos `req`, `ack` e `tx_data` **continuam na análise**, com orçamento igual ao menor período.
3. `set_false_path -hold` entre os domínios: não há relação de fase, a checagem de hold não tem significado.
4. **Não** foi usado `set_clock_groups -asynchronous`, pois removeria todos os caminhos entre domínios (inclusive o barramento de dados).

### 5.2 Etapas do fluxo
_Prints do floorplan, placement, CTS e roteamento (Nangate45 e Sky130HD)._

### 5.3 Resultados

_Gerar com `make -f Makefile.physical compare` e conferir nos relatórios._

| Métrica | Nangate45 | Sky130HD |
|---|---|---|
| Área do design (µm²) | **TODO** | **TODO** |
| Área do die (µm²) | **TODO** | **TODO** |
| Utilização do core (%) | **TODO** | **TODO** |
| Nº de células | **TODO** | **TODO** |
| WNS setup (ns) | **TODO** | **TODO** |
| TNS setup (ns) | **TODO** | **TODO** |
| Pior slack hold (ns) | **TODO** | **TODO** |
| Potência total | **TODO** | **TODO** |
| Buffers de clock (CTS) | **TODO** | **TODO** |

_Discussão: por que as áreas/atrasos diferem (nó tecnológico 45 nm × 130 nm,
bibliotecas, altura das células, número de camadas metálicas)._

## 6. Limitações da STA em CDC
- _O STA analisa caminhos entre flip-flops com relação de clock conhecida; entre clocks assíncronos o resultado de setup/hold "padrão" não tem significado físico, por isso as exceções da seção 5.1._
- _O STA não modela metaestabilidade nem prova MTBF; não verifica se o sinal que cruza vem de flip-flop, se há reconvergência ou se o protocolo bundled-data é respeitado._
- _`set_max_delay` garante só um limite de atraso de fio/lógica; a correção do protocolo depende da arquitetura e foi demonstrada por simulação._
- _Ferramentas de CDC dedicadas não estavam disponíveis na VM._

## 7. Dificuldades encontradas
_Listar._

## 8. Conclusão
_Resumo dos resultados e do que foi aprendido._
