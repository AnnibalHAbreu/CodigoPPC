# FB_ModbusCommTest — Guia Técnico de Uso

**Projeto:** PPC-GD — Power Plant Controller  
**Plataforma:** WAGO CC100 · Codesys V3.5 SP21 · IEC 61131-3 Structured Text  
**Versão do documento:** 1.0  
**Aplicável a:** Comissionamento, manutenção e diagnóstico de campo

---

## 1. Visão Geral

`FB_ModbusCommTest` é uma ferramenta de diagnóstico de comunicação RS-485/Modbus RTU. Ela permite verificar se os dispositivos do barramento (medidor e inversores) estão fisicamente alcançáveis **antes de iniciar qualquer sequência de controle**.

A FB opera de forma completamente isolada da lógica de controle da usina. Quando ativa, ela assume controle exclusivo dos clients Modbus e bloqueia todo polling de produção via `RETURN` no `PRG_ModbusComm`.

### O que ela faz

- Envia requisições de leitura FC03 (Read Holding Registers) para um ou mais slaves
- Verifica se a resposta retorna dentro do timeout configurado
- Registra no log de eventos os slaves que falharam, com o Slave ID individualizado
- Expõe os dados brutos recebidos para inspeção na IHM ou Watch do Codesys

### O que ela **não** faz

- Não escreve nada em nenhum dispositivo
- Não interfere nos setpoints dos inversores
- Não altera variáveis de controle (`GVL_Main`, `GVL_Comm`)
- Não executa durante operação normal (`bTestModeActive = FALSE`)

---

## 2. Arquitetura e Integração

### 2.1 Onde vive no código

A FB é instanciada dentro de `PRG_ModbusComm`, na mesma task (`Task_ModbusComm`) que os `ClientSerial`. Isso é obrigatório — o ModbusFB exige que requests e clients estejam na mesma task.

```
Task_ModbusComm
└── PRG_ModbusComm
    ├── clientCOM1          (ModbusFB.ClientSerial)
    ├── clientCOM2          (ModbusFB.ClientSerial)
    ├── fbCommTest          (FB_ModbusCommTest)   ← instância de teste
    ├── fbReadMeter         (leitura cíclica do medidor)
    ├── fbWriteCOM1         (escrita nos inversores COM1)
    └── fbWriteCOM2         (escrita nos inversores COM2)
```

### 2.2 Declaração no PRG_ModbusComm

```pascal
VAR
    clientCOM1  : ModbusFB.ClientSerial;
    clientCOM2  : ModbusFB.ClientSerial;
    fbCommTest  : FB_ModbusCommTest;     // ← declarar aqui
    // ...
END_VAR
```

### 2.3 Chamada no corpo do PRG_ModbusComm

O trecho abaixo deve aparecer **logo após** a chamada dos clients e a propagação do estado de conexão, e **antes** do polling do medidor e das escritas nos inversores:

```pascal
// Clients — obrigatório chamar a cada ciclo
clientCOM1();
clientCOM2();

// Propagar estado de conexão — SEMPRE, inclusive durante modo teste
GVL_Comm.bCOM1Connected := clientCOM1.xConnected;
GVL_Comm.bCOM2Connected := clientCOM2.xConnected;
GVL_Comm.bCOM1Error     := clientCOM1.xError;
GVL_Comm.bCOM2Error     := clientCOM2.xError;

IF clientCOM1.xConnected AND clientCOM2.xConnected THEN
    GVL_Comm.bCommInitDone := TRUE;
END_IF

// Modo teste — assume controle exclusivo quando ativo
fbCommTest(rClientCOM1 := clientCOM1, rClientCOM2 := clientCOM2);
IF GVL_Test.bTestModeActive THEN
    RETURN;   // bloqueia polling do medidor e escritas nos inversores
END_IF

// ... polling do medidor, escrita nos inversores ...
```

> **Por que propagar conexão antes do RETURN?**  
> O `FB_Startup` monitora `GVL_Comm.bCommInitDone` no estado `stCheck_COM`. Se a propagação ocorresse após o RETURN, o startup ficaria preso aguardando uma flag que nunca é atualizada durante o modo teste.

### 2.4 Interface de dados — GVL_Test

Toda a comunicação entre a IHM, o `MainProgram` e a `FB_ModbusCommTest` passa pelo `GVL_Test`. Nenhuma variável deste GVL influencia o controle da usina. Todas são não-retain — zeradas em todo power cycle.

---

## 3. Dois Modos de Operação

### Modo A — Teste de Slave Único

Testa a comunicação com **um único dispositivo** cujo Slave ID é informado pelo operador. Útil para confirmar que um dispositivo específico está respondendo antes de integrá-lo ao sistema.

**Quando usar:**
- Verificar o medidor antes do primeiro startup
- Confirmar que um inversor recém-instalado ou substituído está no barramento
- Diagnosticar um slave específico após uma falha de comunicação

**Variáveis de controle (escritas pela IHM):**

| Variável | Tipo | Descrição |
|---|---|---|
| `GVL_Test.bTestModeActive` | BOOL | Deve estar TRUE para a FB operar |
| `GVL_Test.uiSingleSlaveId` | UINT | Slave ID do dispositivo alvo |
| `GVL_Test.uiSingleStartReg` | UINT | Endereço do primeiro registrador a ler |
| `GVL_Test.uiSingleRegCount` | UINT | Quantidade de registradores (1 a 4) |
| `GVL_Test.bSingleTestTrigger` | BOOL | Pulso TRUE dispara uma leitura |

**Variáveis de resultado (lidas pela IHM):**

| Variável | Tipo | Descrição |
|---|---|---|
| `GVL_Test.bSingleTestDone` | BOOL | TRUE por 1 ciclo ao concluir |
| `GVL_Test.bSingleTestOk` | BOOL | TRUE = dispositivo respondeu |
| `GVL_Test.eSingleResult` | E_ModbusResult | DONE / TIMEOUT / ERRO |
| `GVL_Test.awSingleRawData[0..3]` | WORD | Dados brutos recebidos |
| `GVL_Test.uiSingleErrorCode` | UINT | Código de erro Modbus raw |

**Comportamento interno:**

```
bSingleTestTrigger (pulso TRUE)
         │
         ▼
   Valida parâmetros
   (clamp: 1 ≤ RegCount ≤ 4)
         │
         ├── rClientCOM1.xConnected = FALSE?
         │       └── eSingleResult := ERRO, bSingleTestDone := TRUE (imediato)
         │
         └── Client conectado → dispara FC03
                   │
                   ├── xDone → bSingleTestOk := TRUE, eSingleResult := DONE
                   ├── xError (timeout) → eSingleResult := TIMEOUT
                   └── xError (outro) → eSingleResult := ERRO
```

---

### Modo B — Varredura Completa

Testa **todos os slaves configurados** em sequência: medidor (COM1) → inversores COM1 → inversores COM2. Ao final, registra no log de eventos o resumo e cada slave que falhou individualmente.

**Quando usar:**
- Antes do primeiro startup de uma usina nova
- Após substituição de múltiplos inversores
- Diagnóstico de falha de comunicação em campo
- Recomissionamento após manutenção no cabeamento

**Variáveis de controle (escritas pela IHM):**

| Variável | Tipo | Descrição |
|---|---|---|
| `GVL_Test.bTestModeActive` | BOOL | Deve estar TRUE |
| `GVL_Test.bScanTrigger` | BOOL | Pulso TRUE inicia a varredura |
| `GVL_Test.bScanAbort` | BOOL | TRUE cancela varredura em andamento |

**Variáveis de progresso (lidas pela IHM em tempo real):**

| Variável | Tipo | Descrição |
|---|---|---|
| `GVL_Test.bScanBusy` | BOOL | TRUE enquanto varredura em andamento |
| `GVL_Test.uiScanCurrentSlave` | UINT | Slave ID sendo testado no momento |
| `GVL_Test.uiScanProgress` | UINT | Índice do slave atual (1..total) |
| `GVL_Test.uiScanTotal` | UINT | Total de slaves a testar |

**Variáveis de resultado (lidas pela IHM ao concluir):**

| Variável | Tipo | Descrição |
|---|---|---|
| `GVL_Test.bScanDone` | BOOL | TRUE ao concluir (sucesso ou parcial) |
| `GVL_Test.uiScanResponded` | UINT | Quantidade de slaves que responderam |
| `GVL_Test.uiScanFailed` | UINT | Quantidade de slaves que falharam |
| `GVL_Test.abScanOk[1..30]` | BOOL[] | TRUE = slave respondeu |
| `GVL_Test.auiScanSlaveId[1..30]` | UINT[] | Slave ID de cada posição |
| `GVL_Test.aeScanResult[1..30]` | E_ModbusResult[] | Resultado individual por slave |

**Ordem de varredura e mapeamento dos índices:**

```
Índice 1          → Medidor (GVL_Comm.uiMeterSlaveId, COM1)
Índices 2..N+1    → Inversores COM1 (GVL_Comm.auiInvSlaveIdsCOM1[1..N])
Índices N+2..N+M+1→ Inversores COM2 (GVL_Comm.auiInvSlaveIdsCOM2[1..M])

Onde N = GVL_Main.NInversoresCOM01
     M = GVL_Main.NInversoresCOM02
```

**Exemplo com 3 inversores por COM:**

```
Índice 1 → Slave 100 (medidor,    COM1)
Índice 2 → Slave 101 (inversor 1, COM1)
Índice 3 → Slave 102 (inversor 2, COM1)
Índice 4 → Slave 103 (inversor 3, COM1)
Índice 5 → Slave 201 (inversor 1, COM2)
Índice 6 → Slave 202 (inversor 2, COM2)
Índice 7 → Slave 203 (inversor 3, COM2)
```

**Timeouts aplicados:**

| Dispositivo | Timeout |
|---|---|
| Medidor | 3 000 ms |
| Inversores COM1 | 2 000 ms |
| Inversores COM2 | 2 000 ms |

**Registro no log de eventos:**

Ao concluir a varredura, a FB gera as seguintes entradas no log:

- **Por cada slave que falhou:** `WARN_INV_CHECK_PARTIAL` com `rParam1 = Slave ID`
- **Resumo final (com falhas):** `WARN_INV_CHECK_PARTIAL` com `rParam1 = responderam`, `rParam2 = total`
- **Resumo final (sem falhas):** `INFO_INV_CHECK_OK` com `rParam1 = responderam`, `rParam2 = total`

---

## 4. Interpretação dos Resultados

### E_ModbusResult — significado em contexto de teste

| Resultado | Significado | O que verificar |
|---|---|---|
| `DONE` | Dispositivo respondeu corretamente | — Comunicação OK |
| `TIMEOUT` | Sem resposta dentro do tempo limite | Cabeamento RS-485, terminação de barramento, alimentação do dispositivo, Slave ID correto, baud rate e paridade |
| `ERRO` | Resposta recebida mas com exceção Modbus | Endereço de registrador inválido, função não suportada pelo dispositivo, permissão de leitura |

### Falha imediata com ERRO (sem timeout)

Ocorre quando `rClientCOM1.xConnected = FALSE` no momento do trigger. Indica que o driver Modbus RTU não inicializou a porta serial. Verificar:
- Configuração de baud rate e paridade no `PRG_ModbusComm`
- Driver SysCom carregado no CLP
- Porta COM fisicamente disponível

### awSingleRawData — leitura dos dados brutos

Os valores em `awSingleRawData[0..3]` são WORDs brutos (16 bits cada) no formato big-endian Modbus. Para interpretar:

- **Medidor Chint DTSU666 / URP1439:** consultar o mapa de registradores do fabricante. O registrador `0x2006` retorna tensão de fase em décimos de volt.
- **Inversores Goodwe:** registrador `0x0000` retorna o primeiro holding register disponível — geralmente status operacional.

---

## 5. Procedimento Passo a Passo

### 5.1 Teste de slave único via Watch do Codesys

1. Colocar o `MainProgram` em estado que permita o modo teste (COMMISSION, STOP ou ERRO — ver seção 6)
2. No Watch, setar `GVL_Test.bTestModeActive := TRUE`
3. Configurar os parâmetros do alvo:
   ```
   GVL_Test.uiSingleSlaveId  := 100    (ex: endereço do medidor)
   GVL_Test.uiSingleStartReg := 16#2006
   GVL_Test.uiSingleRegCount := 2
   ```
4. Setar `GVL_Test.bSingleTestTrigger := TRUE` por 1 scan, depois `FALSE`
5. Aguardar `GVL_Test.bSingleTestDone = TRUE`
6. Verificar:
   - `GVL_Test.bSingleTestOk` → TRUE = comunicação OK
   - `GVL_Test.eSingleResult` → DONE / TIMEOUT / ERRO
   - `GVL_Test.awSingleRawData[0]` → primeiro valor bruto recebido
7. Ao terminar, setar `GVL_Test.bTestModeActive := FALSE`

### 5.2 Varredura completa via Watch do Codesys

1. Verificar que `GVL_Main.NInversoresCOM01` e `NInversoresCOM02` estão configurados corretamente (feito pelo `FB_Startup.stInit`)
2. Setar `GVL_Test.bTestModeActive := TRUE`
3. Pulso em `GVL_Test.bScanTrigger := TRUE`, depois `FALSE`
4. Monitorar em tempo real:
   - `GVL_Test.bScanBusy` → TRUE enquanto varrendo
   - `GVL_Test.uiScanCurrentSlave` → Slave ID sendo testado agora
   - `GVL_Test.uiScanProgress` / `GVL_Test.uiScanTotal` → progresso
5. Aguardar `GVL_Test.bScanDone = TRUE`
6. Analisar resultado:
   - `GVL_Test.uiScanResponded` e `GVL_Test.uiScanFailed`
   - Para cada `GVL_Test.abScanOk[i] = FALSE`: verificar `GVL_Test.auiScanSlaveId[i]` e `GVL_Test.aeScanResult[i]`
7. Consultar o log de eventos — cada slave que falhou gerou uma entrada com seu Slave ID
8. Setar `GVL_Test.bTestModeActive := FALSE`

> **Se precisar abortar:** setar `GVL_Test.bScanAbort := TRUE`. A FB cancela imediatamente e retorna para SC_IDLE.

---

## 6. Estado do MainProgram durante o Teste

O modo teste só deve ser ativado em estados onde a usina não está gerando e nenhuma ação de controle está em andamento.

| Estado | Pode ativar bTestModeActive? | Observação |
|---|---|---|
| `COMMISSION` | ✅ Recomendado | Estado dedicado para comissionamento pré-START |
| `STOP` (STOP_LATCHED) | ✅ Seguro | K2 aberto, sem controle ativo |
| `ERRO` | ✅ Seguro | Sistema parado, aguardando reset |
| `START` | ❌ Proibido | FB_Startup em execução, usa os clients |
| `IDLE` | ⚠️ Risco | MainProgram transita para READ automaticamente |
| `READ` | ❌ Proibido | Conflito direto com leitura do medidor |
| `CONTROL` | ❌ Proibido | Cálculo de setpoints em andamento |
| `WRITE` | ❌ Proibido | Escrita nos inversores em andamento |
| `FAIL` | ❌ Proibido | Estado de segurança ativo |
| `TURNOFF` | ❌ Proibido | Sequência de desligamento em andamento |

**Garantia de segurança ao sair do modo teste:**  
Nos estados `STOP_LATCHED` e `ERRO`, o `MainProgram` reseta `GVL_Test.bTestModeActive := FALSE` automaticamente ao processar o botão Start/Reset, impedindo que o modo teste persista inadvertidamente após a transição para `START`.

---

## 7. Limitações Conhecidas

**O Modo B não testa slaves fora do range configurado.**  
A varredura usa `NInversoresCOM01` e `NInversoresCOM02`. Se um inversor estiver fisicamente presente mas não configurado (potência = 0 no `GVL_Pers`), ele não será testado. Para testar um slave fora do range, usar o Modo A com o Slave ID específico.

**O Modo A usa sempre COM1.**  
A implementação atual do Modo A fixa `rClientCOM1`. Para testar um slave na COM2 individualmente com o Modo A, usar um Slave ID que pertença à COM2 e verificar a resposta — a comunicação física passará pela COM2 somente se o Slave ID responder naquele barramento.

**Sem retry.**  
A FB não repete a leitura em caso de falha. Um único TIMEOUT ou ERRO é suficiente para marcar o slave como falho. Isso é intencional — em comissionamento, qualquer falha deve ser investigada, não silenciada por retry automático.

**Requer NInversoresCOM01/02 inicializados.**  
O Modo B usa os contadores de inversores calculados pelo `FB_Startup.stInit`. Se o modo teste for ativado antes do startup completo (ex: estado COMMISSION), esses contadores podem estar em zero, resultando em uma varredura que testa apenas o medidor. Solução: garantir que o stInit seja executado antes de acionar o Modo B, ou aceitar que a varredura parcial (apenas medidor) é suficiente para o diagnóstico inicial.

---

## 8. Checklist de Comissionamento

Usar este checklist na ordem indicada antes do primeiro startup da usina:

- [ ] Verificar alimentação 24 VCC no CLP e em todos os dispositivos
- [ ] Verificar cabeamento RS-485: polaridade A/B, terminação de 120 Ω nas extremidades
- [ ] Configurar Slave IDs no `GVL_Pers` (inversores) e `GVL_Comm` (medidor)
- [ ] Entrar no estado COMMISSION (ou STOP/ERRO em recomissionamento)
- [ ] Ativar `GVL_Test.bTestModeActive := TRUE`
- [ ] **Modo A — Medidor:** testar Slave ID 100, reg `0x2006`, qty 2. Confirmar `bSingleTestOk = TRUE`
- [ ] **Modo A — Inversor 1 (COM1):** testar Slave ID 101, reg `0x0000`, qty 1. Confirmar OK
- [ ] **Modo A — Inversor 1 (COM2):** testar Slave ID 201, reg `0x0000`, qty 1. Confirmar OK
- [ ] **Modo B — Varredura completa:** confirmar `uiScanFailed = 0`
- [ ] Verificar log de eventos — não deve conter entradas `WARN_INV_CHECK_PARTIAL`
- [ ] Desativar `GVL_Test.bTestModeActive := FALSE`
- [ ] Prosseguir para START

---

*Documento gerado para uso interno de engenharia. Revisar após qualquer alteração nas FBs `FB_ModbusCommTest` ou `GVL_Test`.*
