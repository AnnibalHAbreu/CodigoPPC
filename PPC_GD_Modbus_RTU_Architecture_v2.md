# Arquitetura de Comunicação Modbus RTU Programática — PPC-GD

## Documento Técnico de Referência

**Projeto:** PPC-GD (Power Plant Controller — Geração Distribuída)
**Plataforma:** WAGO CC100 (751-9402)
**IDE:** CODESYS V3.5 SP21 Patch 4
**Protocolo:** Modbus RTU sobre RS-485
**Revisão:** 2.0
**Data:** 2026-03-07

---

## 1. OBJETIVO

Este documento especifica a atualização do subsistema de comunicação Modbus RTU do PPC-GD. A alteração substitui o mecanismo de comunicação baseado no mapa e driver Modbus do CODESYS (Device Tree) por uma implementação totalmente programática usando a biblioteca `ModbusFB`. O código de controle, proteção e máquina de estados do MainProgram permanece inalterado. Apenas a camada de transporte Modbus é substituída.

A motivação é eliminar a necessidade de recompilação e download do projeto CODESYS sempre que um dispositivo Modbus (inversor, medidor, BESS) for alterado, adicionado ou substituído. Os mapas de registros passam a ser carregados de arquivos CSV externos no boot do controlador.

### 1.1 Abordagem Anterior (sendo substituída)

Comunicação configurada via Device Tree do CODESYS (Modbus COM → Master → Slaves → Channels), usando `IoDrvModbus.ModbusChannel` com referência a `ModbusSlaveComPort`. Polling de 5ms. FBs envolvidos: `FB_ModBus`, `FB_WriteCom`, `FB_CheckInversores`, estados `stCheck_COM`/`stCheck_Medidor`/`stCheck_Inversores` do `FB_Startup`, e `fbChannel`/`fbReadMeas` no `MainProgram`. Qualquer alteração de dispositivo exigia editar o projeto, recompilar e fazer download.

```iecst
// Abordagem anterior — código acoplado ao Device Tree
fbChannel(
    Slave := escravo^,          // ModbusSlaveComPort gerado pelo Device Tree
    xExecute := FALSE,
    xAbort := FALSE,
    iChannelIndex := canal      // Canal pré-definido no IDE
);
```

### 1.2 Abordagem Nova (programática)

Comunicação via `ModbusFB.ClientSerial` (biblioteca CODESYS padrão) com `ClientRequestRead*`/`ClientRequestWrite*`. Nenhum dispositivo Modbus no Device Tree. As portas COM1 e COM2 existem apenas sob "Serial" no Device Tree. Toda a configuração de dispositivos e registros vem de arquivos CSV no sistema de arquivos do CC100.

### 1.3 Convenção de Indexação

O código existente do PPC-GD usa arrays de inversores indexados a partir de 1 (não 0). Exemplos: `pInversores100[1..15]`, `trigInvCOM100[1..15, 0..4]`, `P_inv_kW[1..N]`. **Esta convenção é mantida na nova implementação** para compatibilidade e para evitar erros de off-by-one durante a migração. Arrays de inversores usam `[1..16]`, não `[0..15]`.

---

## 2. PLATAFORMA E HARDWARE

### 2.1 WAGO CC100 751-9402 — Recursos Relevantes

| Recurso | Especificação |
|---|---|
| Modelo | 751-9402 Compact Controller 100 |
| I/O onboard | 8DI, 8DIO, 2AI, 2AIO, 2NI/PT |
| Portas seriais | **2 × RS-485** nativas |
| Ethernet | 2 × Ethernet |
| Armazenamento | SD card |
| Runtime | CODESYS V3 (64-bit, Linux embarcado) |
| Firmware mínimo | FW28 (04.06.03) — primeiro firmware com suporte ao 751-9402 |

### 2.2 Mapeamento das Portas Seriais — Confirmado no Equipamento

Resultado do comando `ls /dev/ttySTM*` no CC100:
```
/dev/ttySTM0  /dev/ttySTM1  /dev/ttySTM2
```

| Device Linux | Função | COM Port CODESYS | Constante SysCom |
|---|---|---|---|
| `/dev/ttySTM0` | Interface USB de serviço/debug. **Não usar para Modbus.** | — | — |
| `/dev/ttySTM1` | RS-485 porta #1 | COM1 | `SysCom.SYS_COM_PORTS.SYS_COMPORT1` |
| `/dev/ttySTM2` | RS-485 porta #2 | COM2 | `SysCom.SYS_COM_PORTS.SYS_COMPORT2` |

### 2.3 Configuração do Runtime

O firmware do CC100 751-9402 registra as portas seriais no subsistema `SysCom` automaticamente durante o boot. Confirmado: o arquivo `/home/codesys/CODESYSControl.cfg` não contém seção `[SysCom]` e a comunicação Modbus RTU funciona. Os exemplos oficiais do CODESYS para o 751-9402 usam `SysCom.SYS_COM_PORTS.SYS_COMPORT1` e `SYS_COMPORT2` diretamente, sem configuração adicional.

Caso futuro requeira configuração explícita (migração de firmware, outro hardware), adicionar ao `CODESYSControl_User.cfg`:

```ini
[SysCom]
Linux.Devicefile.1=/dev/ttySTM1
Linux.Devicefile.2=/dev/ttySTM2
```

### 2.4 Device Tree — Configuração Mínima

Com a abordagem programática, o Device Tree **não contém** nenhum dispositivo Modbus:

```
751-9402 WAGO Compact Controller 100
├── Compact Controller 100 Onboard IO
│   ├── X5_DIO, X6_AIO, X12_DI, X13_RTD, X14_AIN
│   ├── Ethernet (Ethernet)
│   └── Serial
│       ├── COM1 (COM1)          ← RS-485 porta #1
│       └── COM2 (COM2)          ← RS-485 porta #2
└── Application
    ├── Gestor de biblioteca
    ├── PRG_Main, PRG_ModbusComm
    └── Configuração de tarefas
        ├── Task_Main (10ms)
        └── Task_ModbusComm (2ms)
```

Não deve existir "Modbus COM", "Modbus Client" ou "Modbus Server" no Device Tree. O `ModbusFB.ClientSerial` abre a porta COM diretamente via `SysCom`. Se houver um item Modbus no Device Tree apontando para a mesma porta, haverá conflito de acesso.

---

## 3. BIBLIOTECA ModbusFB — INTERFACE DE REFERÊNCIA

Baseado nos exemplos oficiais do CODESYS para o 751-9402 (projetos `MODBUS_master_example_ST`, `MODBUS_slave_example_ST` e `Example_Serial`).

### 3.1 FBs Utilizados

**Client (gerencia a porta COM):**

| FB | Função |
|---|---|
| `ModbusFB.ClientSerial` | Gerencia porta COM, fila FIFO de requests, conexão/desconexão |

**Requests (transações individuais):**

| FB | FC Modbus | Uso típico |
|---|---|---|
| `ClientRequestReadHoldingRegisters` | FC03 | Ler dados de inversores, medidores |
| `ClientRequestReadInputRegisters` | FC04 | Ler dados somente-leitura |
| `ClientRequestWriteSingleRegister` | FC06 | Escrever 1 registro (control word, modo) |
| `ClientRequestWriteMultipleRegisters` | FC16 | Escrever N registros (setpoints) |
| `ClientRequestWriteSingleCoil` | FC05 | Escrever coil (enable/disable) |
| `ClientRequestReadCoils` | FC01 | Ler coils (status discreto) |

**Classe base polimórfica:**

| FB | Uso |
|---|---|
| `ModbusFB.ClientRequest` | Classe base abstrata de todos os requests. Permite armazenar ponteiros genéricos `POINTER TO ModbusFB.ClientRequest` e iterar sobre requests heterogêneos |

### 3.2 Ciclo de Vida

**Fase 1 — Inicialização (uma vez, no primeiro scan):**

```iecst
IF NOT bInitDone THEN
    bInitDone := TRUE;
    
    // 1. Configurar client serial
    client(
        iPort      := SysCom.SYS_COM_PORTS.SYS_COMPORT1,
        dwBaudRate := SysCom.SYS_BR_9600,
        byDataBits := 8,
        eParity    := SysCom.SYS_EVENPARITY,
        eStopBits  := SysCom.SYS_ONESTOPBIT,
        eRtuAscii  := ModbusFB.RtuAscii.RTU
    );
    
    // 2. Conectar
    client(xConnect := TRUE);
    
    // 3. Configurar requests e vincular ao client via rClient (referência)
    fbReadHolding(
        rClient      := client,
        uiUnitId     := 1,
        uiStartItem  := 5016,
        uiQuantity   := 2,
        pData        := ADR(awReadBuffer),
        uiMaxRetries := 2              // Retry automático do ModbusFB
    );
    
    // 4. Disparo inicial
    fbReadHolding.xExecute := TRUE;
END_IF
```

**Fase 2 — Execução cíclica (a cada scan da task de comunicação):**

```iecst
// OBRIGATÓRIO: chamar client e TODOS os requests a cada ciclo
client();
fbReadHolding(rClient := client);

// Sequenciamento: verificar resultado, avançar para próximo
IF fbReadHolding.xDone THEN
    // Dados em awReadBuffer
    fbReadHolding.xExecute := FALSE;    // Preparar próximo trigger
    // ... avançar para próximo request
ELSIF fbReadHolding.xError THEN
    // Diagnóstico via fbReadHolding.eErrorID, .eException
    fbReadHolding.xExecute := FALSE;
    // ... avançar para próximo request
END_IF
```

### 3.3 Padrão de Iteração sobre Requests (do exemplo oficial)

Os exemplos oficiais usam um array de ponteiros para a classe base `ClientRequest`, permitindo iterar sobre requests heterogêneos de forma uniforme:

```iecst
VAR
    clientRequests : ARRAY[0..N] OF POINTER TO ModbusFB.ClientRequest;
    pCurrentReq    : POINTER TO ModbusFB.ClientRequest;
    uiReqIndex     : UINT;
END_VAR

// Iteração: processar todos os requests a cada ciclo
FOR i := 0 TO N DO
    clientRequests[i]^(rClient := client);
END_FOR

// Sequenciamento: disparar um por vez, aguardar conclusão
IF NOT pCurrentReq^.xExecute AND NOT pCurrentReq^.xDone THEN
    pCurrentReq^.xExecute := TRUE;
END_IF

IF pCurrentReq^.xDone OR pCurrentReq^.xError THEN
    pCurrentReq^.xExecute := FALSE;
    // Avançar para próximo request
    uiReqIndex := uiReqIndex + 1;
    IF uiReqIndex > N THEN
        uiReqIndex := 0;   // Reiniciar ciclo
    END_IF
    pCurrentReq := clientRequests[uiReqIndex];
END_IF
```

### 3.4 Características Confirmadas

| Característica | Detalhe |
|---|---|
| **Fila FIFO interna** | `ClientSerial` serializa requests automaticamente (first-come, first-served) |
| **Vinculação por referência** | `rClient` é `VAR_IN_OUT`, não ponteiro |
| **Timeout por request** | `udiTimeout` em µs (default 2s). `udiReplyTimeout` para timeout de resposta |
| **Retry automático** | `uiMaxRetries` no request — o ModbusFB retenta automaticamente |
| **Diagnóstico integrado** | `eErrorID`, `eException`, `ToStringWithId()`, `ToStringWithIdAndState()` |
| **Estatísticas no client** | `udiNumMsgSent`, `udiNumMsgReply`, `udiNumReplyTimeouts`, `udiNumMsgExcReply` |
| **Logging opcional** | `udiLogOptions` com flags `LoggingOptions.ClientConnectDisconnect`, etc. |
| **Endereçamento base-0** | Convenção CODESYS: "registro 40001" = `uiStartItem := 0` |
| **Cycle time curto** | Exemplo oficial usa task de 1ms. Necessário para acompanhar processamento de frames seriais |
| **Chamada obrigatória de todos os FBs** | Client E todos os requests devem ser chamados a cada ciclo, mesmo que não estejam sendo controlados no momento |

---

## 4. ARQUITETURA DE TASKS E SINCRONIZAÇÃO

### 4.1 Problema

A comunicação Modbus RTU requer cycle time muito curto (1-5ms) para processar frames seriais sem perda. A task principal do PPC-GD (controle PI, lógica de proteção) não deve ser sobrecarregada com esse overhead, e seu jitter não deve ser afetado pela comunicação.

### 4.2 Solução: Duas Tasks com Sincronização via GVL

```
┌─────────────────────────────────────┐
│      Task_ModbusComm (2ms)          │
│  Prioridade: ALTA (ex: 1)          │
│                                     │
│  - Chama ClientSerial (COM1, COM2)  │
│  - Chama todos os ClientRequest*    │
│  - Sequencia requests               │
│  - Atualiza buffers raw em GVL      │
│  - Atualiza diagnóstico em GVL      │
│  - Processa escritas pendentes      │
└──────────────┬──────────────────────┘
               │ GVL_CommData (buffers raw + flags de sincronização)
┌──────────────▼──────────────────────┐
│        Task_Main (10ms)             │
│  Prioridade: NORMAL (ex: 10)       │
│                                     │
│  - Lê dados convertidos de GVL     │
│  - Controle PI, proteção, rampas   │
│  - Escreve setpoints em GVL        │
│  - Flag bWritePending := TRUE      │
└─────────────────────────────────────┘
```

### 4.3 GVL de Sincronização

```iecst
// =============================================================================
// GVL_CommData
// Área compartilhada entre Task_ModbusComm e Task_Main.
//
// REGRA DE CONCORRÊNCIA:
//   - Task_ModbusComm ESCREVE nos buffers de leitura (awReadData, rValues, astDiag)
//   - Task_Main LÊ os buffers de leitura
//   - Task_Main ESCREVE nos buffers de escrita (awWriteData, bWritePending)
//   - Task_ModbusComm LÊ os buffers de escrita e reseta bWritePending
//
// Não há lock/mutex — a sincronização é por convenção:
//   - Cada variável tem um único writer
//   - Tipos atômicos (BOOL, REAL, WORD) são naturalmente consistentes no ARM
//   - Arrays maiores usam flag de "snapshot ready" para indicar consistência
// =============================================================================
{attribute 'qualified_only'}
VAR_GLOBAL
    // ─── Dados de leitura (escritos por Task_ModbusComm) ─────────
    // Indexação base-1 (compatível com código existente do PPC-GD)
    // COM1: inversores [1..15], COM2: inversores [1..16]
    arInvActivePower_COM1   : ARRAY[1..15] OF REAL;     // kW por inversor COM1
    arInvReactivePower_COM1 : ARRAY[1..15] OF REAL;     // kvar por inversor COM1
    arInvVoltage_COM1       : ARRAY[1..15] OF REAL;     // V por inversor COM1
    arInvStatus_COM1        : ARRAY[1..15] OF UINT;     // Status word por inversor COM1

    arInvActivePower_COM2   : ARRAY[1..16] OF REAL;     // kW por inversor COM2
    arInvReactivePower_COM2 : ARRAY[1..16] OF REAL;     // kvar por inversor COM2
    arInvVoltage_COM2       : ARRAY[1..16] OF REAL;     // V por inversor COM2
    arInvStatus_COM2        : ARRAY[1..16] OF UINT;     // Status word por inversor COM2
    
    // Medidor (COM1, device especial)
    rMeterActivePower   : REAL;                     // kW no ponto de conexão
    rMeterReactivePower : REAL;                     // kvar no ponto de conexão
    rMeterVoltage       : REAL;                     // V no ponto de conexão
    rMeterFrequency     : REAL;                     // Hz
    
    bReadDataValid      : BOOL;                     // TRUE quando ciclo completo ok
    uiOnlineInvCountCOM1 : UINT;                    // Inversores respondendo em COM1
    uiOnlineInvCountCOM2 : UINT;                    // Inversores respondendo em COM2
    bMeterOnline        : BOOL;                     // Medidor respondendo
    bCOM1Connected      : BOOL;                     // ClientSerial COM1 conectado
    bCOM2Connected      : BOOL;                     // ClientSerial COM2 conectado
    
    // ─── Diagnóstico (escritos por Task_ModbusComm) ──────────────
    astDiagMeter        : ST_CommDiagnostics;                   // Medidor
    astDiagCOM1         : ARRAY[1..15] OF ST_CommDiagnostics;   // Inversores COM1
    astDiagCOM2         : ARRAY[1..16] OF ST_CommDiagnostics;   // Inversores COM2
    
    // ─── Dados de escrita (escritos por Task_Main) ───────────────
    // Indexação base-1 (compatível com GVL_Main.P_inv_kW[1..N])
    arInvSetpointP_COM1     : ARRAY[1..15] OF REAL;     // kW setpoint COM1
    arInvSetpointQ_COM1     : ARRAY[1..15] OF REAL;     // kvar setpoint COM1
    auiInvControlWord_COM1  : ARRAY[1..15] OF UINT;     // Control word COM1

    arInvSetpointP_COM2     : ARRAY[1..16] OF REAL;     // kW setpoint COM2
    arInvSetpointQ_COM2     : ARRAY[1..16] OF REAL;     // kvar setpoint COM2
    auiInvControlWord_COM2  : ARRAY[1..16] OF UINT;     // Control word COM2
    
    bWritePendingCOM1   : BOOL;                     // TRUE = novos setpoints para COM1
    bWritePendingCOM2   : BOOL;                     // TRUE = novos setpoints para COM2
    
    // ─── Configuração (escrita pelo ConfigLoader no boot) ────────
    uiDeviceCountCOM1   : UINT;                     // Máx 16 (1 medidor + 15 inversores)
    uiDeviceCountCOM2   : UINT;                     // Máx 16 inversores
    astProfilesCOM1     : ARRAY[0..15] OF ST_DeviceProfile;  // [0]=medidor, [1..15]=inversores
    astProfilesCOM2     : ARRAY[1..16] OF ST_DeviceProfile;  // [1..16]=inversores
    bConfigLoaded       : BOOL;
END_VAR
```

### 4.4 Proteção contra Inconsistência

Para tipos simples (BOOL, REAL, WORD, UINT) no processador ARM do CC100, leituras e escritas são atômicas — não há risco de ler um valor "meio escrito". Para o cenário do PPC-GD, onde os dados são amostrados a cada 10ms pela task principal e atualizados a cada ciclo de polling pela task de comunicação, essa granularidade é aceitável.

Se no futuro for necessário garantir que um conjunto de variáveis (ex: todos os valores de um inversor) seja lido como snapshot atômico, usar um padrão double-buffer:

```iecst
// Na Task_ModbusComm, após completar leitura de um device:
GVL_CommData.arInvActivePower[i] := rNewValue;
GVL_CommData.arInvReactivePower[i] := rNewValue2;
// ... etc
GVL_CommData.bSnapshot[i] := TRUE;   // Sinaliza que dados estão consistentes
```

### 4.5 Configuração das Tasks

| Task | Cycle Time | Prioridade | Programa | Justificativa |
|---|---|---|---|---|
| `Task_ModbusComm` | **2ms** | 1 (alta) | `PRG_ModbusComm` | Processamento de frames seriais. O exemplo oficial CODESYS usa 1ms. Com 2ms mantemos margem e compatibilidade com o polling de 5ms que vocês já usavam |
| `Task_Main` | **10ms** | 10 (normal) | `PRG_Main` | Controle PI, proteção, lógica do PPC-GD. 10ms é adequado para malhas de controle de potência |

**Justificativa do cycle time de 2ms para comunicação:**

A 9600 baud, um frame Modbus RTU de leitura de 2 registros (request + response) leva aproximadamente 20-25ms no barramento. O processamento do frame pela `ClientSerial` precisa ocorrer dentro do tempo de um caractere (~1ms a 9600 baud) para não perder bytes. Com cycle time de 2ms, garantimos que o `ClientSerial` é chamado frequentemente o suficiente para processar os bytes recebidos sem overflow do buffer serial.

---

## 5. ARQUITETURA DA SOLUÇÃO

### 5.1 Princípios de Design

1. **Separação entre transporte, perfil e aplicação** — três camadas distintas.
2. **Configuração externa via arquivo CSV** — lido no boot, sem recompilação.
3. **Um `ClientSerial` por porta COM** — fila FIFO interna serializa transações.
4. **Sequenciamento explícito de requests** — um request ativo por vez por client, conforme padrão dos exemplos oficiais.
5. **Todos os requests chamados a cada ciclo** — obrigatório para processamento interno do ModbusFB.
6. **Task dedicada para comunicação** — cycle time 2ms, prioridade alta.
7. **Sincronização via GVL** — escritor único por variável, sem locks.
8. **Fail-safe explícito** — timeout, retry automático (ModbusFB), contagem de erros, modo degradado.
9. **Independência de hardware** — código ST não referencia nada específico do WAGO.

### 5.2 Diagrama de Camadas

```
┌──────────────────────────────────────────────────────────────────┐
│                 APLICAÇÃO (PPC-GD) — Task_Main 10ms              │
│  Lê: GVL_CommData.arInvActivePower[], rMeterActivePower, etc.    │
│  Escreve: GVL_CommData.arInvSetpointP[], bWritePending           │
│  Controle PI, proteção, rampas, lógica de exportação             │
└──────────────────────┬───────────────────────────────────────────┘
                       │ GVL_CommData (REAL, em unidades de engenharia)
┌──────────────────────▼───────────────────────────────────────────┐
│          CAMADA DE PERFIL + TRANSPORTE — Task_ModbusComm 2ms     │
│                                                                   │
│  FB_ConfigLoader     → Lê CSV no boot, preenche profiles          │
│  FB_RegisterConverter → Converte raw ↔ engenharia                 │
│  FB_ModbusChannel    → Gerencia ClientSerial + requests           │
│  FB_DeviceHandler    → Um por device, controla requests           │
│                                                                   │
│  Usa internamente: ModbusFB.ClientSerial                          │
│                    ModbusFB.ClientRequestRead*                    │
│                    ModbusFB.ClientRequestWrite*                   │
└──────────────────────┬───────────────────────────────────────────┘
                       │ RS-485 (half-duplex)
┌──────────────────────▼───────────────────────────────────────────┐
│               HARDWARE — COM1 / COM2                             │
│  WAGO CC100 751-9402 — 2 × RS-485 onboard                       │
│  /dev/ttySTM1 (COM1) — /dev/ttySTM2 (COM2)                      │
└──────────────────────────────────────────────────────────────────┘
```

### 5.3 Estrutura do Projeto CODESYS

```
Application
├── Types/
│   ├── E_MbFunctionCode          (ENUM: FC03, FC04, FC06, FC16)
│   ├── E_MbDataType              (ENUM: UINT16, INT16, UINT32, INT32, FLOAT32, ...)
│   ├── E_MbByteOrder             (ENUM: BigEndian, LittleEndian, MidBig, MidLittle)
│   ├── E_ChannelState            (ENUM: Init, Connecting, Polling, Error, Disconnected)
│   ├── E_DeviceStatus            (ENUM: Unknown, Online, CommLoss, Degraded, Error)
│   ├── ST_RegisterDef            (definição de um registro — do CSV)
│   ├── ST_ReadGroup              (grupo de registros lidos numa transação)
│   ├── ST_WriteOperation         (operação de escrita pendente)
│   ├── ST_DeviceProfile          (perfil completo de um dispositivo)
│   └── ST_CommDiagnostics        (estatísticas de comunicação)
├── Communication/
│   ├── FB_ModbusChannel          (engine — um por porta COM)
│   ├── FB_DeviceHandler          (um por device slave)
│   ├── FB_RegisterConverter      (converte raw ↔ engenharia)
│   └── FB_ConfigLoader           (lê CSV no boot)
├── DeviceAbstraction/
│   ├── FB_GenericInverter        (interface padronizada)
│   ├── FB_GenericMeter           (interface padronizada)
│   └── FB_GenericBESS            (interface padronizada)
├── GVL/
│   ├── GVL_CommData              (buffers compartilhados entre tasks)
│   └── GVL_CommConfig            (configurações gerais)
└── Programs/
    ├── PRG_ModbusComm            (Task_ModbusComm — 2ms)
    └── PRG_Main                  (Task_Main — 10ms)
```

### 5.4 Capacidade por Porta COM

| Porta COM | Dispositivos | Máximo |
|---|---|---|
| COM1 | 1 Medidor + Inversores | 1 medidor + até 15 inversores = 16 devices |
| COM2 | Inversores | Até 16 inversores |
| **Total** | | **Até 32 devices** |

Convenção de indexação (base-1, compatível com código existente):

```
COM1: device[0]      = Medidor (índice especial, base-0 para o medidor único)
      device[1..15]  = Inversores (Slave 101..115)

COM2: device[1..16]  = Inversores (Slave 201..216)
```

**Implicação no tempo de polling:**

A 9600 baud, cada transação FC03 de leitura de ~20 registros consome ~25ms no barramento.

| Porta | Devices | Transações/ciclo (est.) | Tempo a 9600 baud |
|---|---|---|---|
| COM1 | 1 medidor + 15 inversores = 16 | ~35 | ~900ms |
| COM2 | 16 inversores | ~35 | ~900ms |
| **Sistema** | **32 devices** | | **~900ms** (COM1 e COM2 em paralelo) |

COM1 e COM2 operam em paralelo (barramentos RS-485 independentes, cada um com seu `ClientSerial`). O tempo total do sistema é o máximo dos dois, não a soma.

```iecst
// =============================================================================
// E_MbFunctionCode
// =============================================================================
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_MbFunctionCode :
(
    FC_ReadHoldingRegisters    := 3,
    FC_ReadInputRegisters      := 4,
    FC_WriteSingleRegister     := 6,
    FC_WriteMultipleRegisters  := 16
);
END_TYPE

// =============================================================================
// E_MbDataType
// =============================================================================
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_MbDataType :
(
    DT_UINT16       := 0,
    DT_INT16        := 1,
    DT_UINT32       := 2,
    DT_INT32        := 3,
    DT_FLOAT32      := 4,
    DT_UINT16_BOOL  := 5
);
END_TYPE

// =============================================================================
// E_MbByteOrder — Ordem de palavras para tipos de 32 bits
// =============================================================================
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_MbByteOrder :
(
    BO_BigEndian          := 0,   // AB CD — high word first (padrão Modbus)
    BO_LittleEndian       := 1,   // CD AB — low word first
    BO_MidBigEndian       := 2,   // BA DC
    BO_MidLittleEndian    := 3    // DC BA
);
END_TYPE

// =============================================================================
// E_ChannelState
// =============================================================================
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_ChannelState :
(
    CS_INIT           := 0,
    CS_CONNECTING     := 10,
    CS_POLLING        := 20,
    CS_ERROR          := 80,
    CS_DISCONNECTED   := 90
);
END_TYPE

// =============================================================================
// E_DeviceStatus
// =============================================================================
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_DeviceStatus :
(
    DS_Unknown     := 0,
    DS_Online      := 1,
    DS_CommLoss    := 2,
    DS_Degraded    := 3,
    DS_Error       := 4
);
END_TYPE

// =============================================================================
// ST_RegisterDef — Definição de um ponto Modbus (carregada do CSV)
// =============================================================================
TYPE ST_RegisterDef :
STRUCT
    sTag            : STRING(31);
    uiPointIndex    : UINT;
    uiRegAddress    : UINT;           // Base 0 (convenção CODESYS/ModbusFB)
    uiRegCount      : UINT;           // 1 ou 2
    eFunctionCode   : E_MbFunctionCode;
    eDataType       : E_MbDataType;
    eByteOrder      : E_MbByteOrder;
    rScale          : REAL := 1.0;
    rOffset         : REAL := 0.0;
    uiGroupId       : UINT;
    bIsWritable     : BOOL;
    bEnabled        : BOOL := TRUE;
END_STRUCT
END_TYPE

// =============================================================================
// ST_ReadGroup — Grupo de registros lidos numa única transação
// =============================================================================
TYPE ST_ReadGroup :
STRUCT
    uiGroupId       : UINT;
    uiStartAddress  : UINT;
    uiTotalRegs     : UINT;
    eFunctionCode   : E_MbFunctionCode;
    awRawData       : ARRAY[0..63] OF WORD;
    bValid          : BOOL;
    bPending        : BOOL;
END_STRUCT
END_TYPE

// =============================================================================
// ST_WriteOperation — Operação de escrita pendente
// =============================================================================
TYPE ST_WriteOperation :
STRUCT
    uiRegAddress    : UINT;
    uiRegCount      : UINT;
    eFunctionCode   : E_MbFunctionCode;
    awData          : ARRAY[0..15] OF WORD;
    bPending        : BOOL;
    bDone           : BOOL;
    bError          : BOOL;
END_STRUCT
END_TYPE

// =============================================================================
// ST_DeviceProfile — Perfil completo de um dispositivo (carregado do CSV)
// =============================================================================
TYPE ST_DeviceProfile :
STRUCT
    sDeviceName         : STRING(31);
    sDeviceType         : STRING(15);       // 'INVERTER', 'METER', 'BESS'
    usiSlaveId          : USINT;            // 1..247
    usiComPort          : USINT;            // 1 ou 2

    udiBaudrate         : UDINT := 9600;
    usiParity           : USINT := 2;       // 0=None, 1=Odd, 2=Even
    usiStopBits         : USINT := 1;

    uiMaxRegsPerWrite   : UINT := 1;
    bSupportsFC06       : BOOL := TRUE;
    bSupportsFC16       : BOOL := TRUE;

    astRegisters        : ARRAY[0..63] OF ST_RegisterDef;
    uiRegCount          : UINT;

    astReadGroups       : ARRAY[0..15] OF ST_ReadGroup;
    uiGroupCount        : UINT;

    astWriteOps         : ARRAY[0..7] OF ST_WriteOperation;
    uiWriteCount        : UINT;

    uiPollInterval_ms   : UINT := 1000;
    uiResponseTimeout_ms : UINT := 1000;
    usiMaxRetries       : USINT := 2;

    bEnabled            : BOOL := TRUE;
    bProfileLoaded      : BOOL;
END_STRUCT
END_TYPE

// =============================================================================
// ST_CommDiagnostics — Diagnóstico por dispositivo
// =============================================================================
TYPE ST_CommDiagnostics :
STRUCT
    udiTxCount           : UDINT;
    udiRxOkCount         : UDINT;
    udiRxErrorCount      : UDINT;
    udiTimeoutCount      : UDINT;
    udiRetryCount        : UDINT;
    uiConsecutiveErrors  : UINT;        // Reseta a 0 quando resposta OK
    rSuccessRate         : REAL;
    eDeviceStatus        : E_DeviceStatus;
END_STRUCT
END_TYPE
```

---

## 7. FB_RegisterConverter — Conversão Raw ↔ Engenharia

Único local onde conversão de escala acontece. Acima desta camada: unidades de engenharia (kW, kvar, V, A, Hz). Abaixo: WORD/registros brutos.

```iecst
FUNCTION_BLOCK FB_RegisterConverter

METHOD PUBLIC RawToEngineering : REAL
VAR_INPUT
    pRawData    : POINTER TO WORD;
    eDataType   : E_MbDataType;
    eByteOrder  : E_MbByteOrder;
    rScale      : REAL;
    rOffset     : REAL;
END_VAR
VAR
    wHigh, wLow : WORD;
    dwCombined  : DWORD;
    rRaw32      : REAL;
END_VAR

IF pRawData = 0 THEN
    RawToEngineering := 0.0;
    RETURN;
END_IF

CASE eDataType OF
    E_MbDataType.DT_UINT16:
        RawToEngineering := UINT_TO_REAL(WORD_TO_UINT(pRawData^)) * rScale + rOffset;

    E_MbDataType.DT_INT16:
        RawToEngineering := INT_TO_REAL(WORD_TO_INT(pRawData^)) * rScale + rOffset;

    E_MbDataType.DT_UINT32, E_MbDataType.DT_INT32, E_MbDataType.DT_FLOAT32:
        // Montar DWORD conforme byte order
        CASE eByteOrder OF
            E_MbByteOrder.BO_BigEndian:
                wHigh := pRawData^;           wLow := (pRawData + 1)^;
            E_MbByteOrder.BO_LittleEndian:
                wLow := pRawData^;            wHigh := (pRawData + 1)^;
            E_MbByteOrder.BO_MidBigEndian:
                wHigh := ROL(pRawData^, 8);   wLow := ROL((pRawData + 1)^, 8);
            E_MbByteOrder.BO_MidLittleEndian:
                wLow := ROL(pRawData^, 8);    wHigh := ROL((pRawData + 1)^, 8);
        END_CASE
        dwCombined := SHL(WORD_TO_DWORD(wHigh), 16) OR WORD_TO_DWORD(wLow);

        CASE eDataType OF
            E_MbDataType.DT_UINT32:
                RawToEngineering := UDINT_TO_REAL(DWORD_TO_UDINT(dwCombined)) * rScale + rOffset;
            E_MbDataType.DT_INT32:
                RawToEngineering := DINT_TO_REAL(DWORD_TO_DINT(dwCombined)) * rScale + rOffset;
            E_MbDataType.DT_FLOAT32:
                rRaw32 := DWORD_TO_REAL(dwCombined);
                IF rRaw32 <> rRaw32 THEN                        // NaN
                    RawToEngineering := 0.0;
                ELSIF rRaw32 > 3.4E+38 OR rRaw32 < -3.4E+38 THEN  // Inf
                    RawToEngineering := 0.0;
                ELSE
                    RawToEngineering := rRaw32 * rScale + rOffset;
                END_IF
        END_CASE
END_CASE


METHOD PUBLIC EngineeringToRaw
VAR_INPUT
    rValue : REAL;  eDataType : E_MbDataType;  eByteOrder : E_MbByteOrder;
    rScale : REAL;  rOffset : REAL;
END_VAR
VAR_OUTPUT
    awResult : ARRAY[0..1] OF WORD;  uiRegCount : UINT;
END_VAR
VAR
    rRaw : REAL;  dwRaw : DWORD;  wHigh, wLow : WORD;
END_VAR

IF ABS(rScale) < 1.0E-12 THEN
    awResult[0] := 0; awResult[1] := 0; uiRegCount := 1; RETURN;
END_IF
rRaw := (rValue - rOffset) / rScale;

CASE eDataType OF
    E_MbDataType.DT_UINT16:
        rRaw := LIMIT(0.0, rRaw, 65535.0);
        awResult[0] := UINT_TO_WORD(REAL_TO_UINT(rRaw));
        uiRegCount := 1;
    E_MbDataType.DT_INT16:
        rRaw := LIMIT(-32768.0, rRaw, 32767.0);
        awResult[0] := INT_TO_WORD(REAL_TO_INT(rRaw));
        uiRegCount := 1;
    E_MbDataType.DT_FLOAT32:
        dwRaw := REAL_TO_DWORD(rValue);
        wHigh := DWORD_TO_WORD(SHR(dwRaw, 16));
        wLow := DWORD_TO_WORD(dwRaw AND 16#0000FFFF);
        CASE eByteOrder OF
            E_MbByteOrder.BO_BigEndian:        awResult[0] := wHigh; awResult[1] := wLow;
            E_MbByteOrder.BO_LittleEndian:     awResult[0] := wLow;  awResult[1] := wHigh;
            E_MbByteOrder.BO_MidBigEndian:     awResult[0] := ROL(wHigh, 8); awResult[1] := ROL(wLow, 8);
            E_MbByteOrder.BO_MidLittleEndian:  awResult[0] := ROL(wLow, 8);  awResult[1] := ROL(wHigh, 8);
        END_CASE
        uiRegCount := 2;
    E_MbDataType.DT_UINT32, E_MbDataType.DT_INT32:
        IF eDataType = E_MbDataType.DT_UINT32 THEN
            rRaw := MAX(0.0, rRaw);
            dwRaw := UDINT_TO_DWORD(REAL_TO_UDINT(rRaw));
        ELSE
            dwRaw := DINT_TO_DWORD(REAL_TO_DINT(rRaw));
        END_IF
        wHigh := DWORD_TO_WORD(SHR(dwRaw, 16));
        wLow := DWORD_TO_WORD(dwRaw AND 16#0000FFFF);
        CASE eByteOrder OF
            E_MbByteOrder.BO_BigEndian:    awResult[0] := wHigh; awResult[1] := wLow;
            E_MbByteOrder.BO_LittleEndian: awResult[0] := wLow;  awResult[1] := wHigh;
        END_CASE
        uiRegCount := 2;
END_CASE
```

---

## 8. CONFIGURAÇÃO EXTERNA VIA CSV

### 8.1 devices.csv

```csv
DeviceName;DeviceType;SlaveId;ComPort;Baudrate;Parity;MaxRegsPerWrite;SupportsFC06;SupportsFC16;PollInterval_ms;ResponseTimeout_ms;MaxRetries
Sungrow_SG110CX;INVERTER;1;1;9600;2;10;1;1;1000;1000;2
Sungrow_SG110CX_2;INVERTER;2;1;9600;2;10;1;1;1000;1000;2
Schneider_PM5340;METER;100;1;9600;2;1;1;1;500;800;3
```

### 8.2 registers.csv

```csv
DeviceName;Tag;RegAddress;RegCount;FunctionCode;DataType;ByteOrder;Scale;Offset;GroupId;IsWritable
Sungrow_SG110CX;ActivePower;5016;2;3;4;0;1.0;0.0;1;0
Sungrow_SG110CX;ReactivePower;5018;2;3;4;0;1.0;0.0;1;0
Sungrow_SG110CX;Voltage_L1;5020;2;3;4;0;0.1;0.0;1;0
Sungrow_SG110CX;Frequency;5036;2;3;4;0;0.1;0.0;2;0
Sungrow_SG110CX;InverterStatus;5038;1;3;0;0;1.0;0.0;2;0
Sungrow_SG110CX;SetpointP;5000;2;16;4;0;1.0;0.0;10;1
Sungrow_SG110CX;SetpointQ;5002;2;16;4;0;1.0;0.0;10;1
Sungrow_SG110CX;ControlWord;5004;1;6;0;0;1.0;0.0;11;1
Schneider_PM5340;ActivePower_Total;3060;2;3;4;0;0.001;0.0;1;0
Schneider_PM5340;ReactivePower_Total;3068;2;3;4;0;0.001;0.0;1;0
Schneider_PM5340;Voltage_L1N;3028;2;3;4;0;1.0;0.0;2;0
Schneider_PM5340;Frequency;3110;2;3;4;0;1.0;0.0;2;0
```

**Convenção:**
`FunctionCode`: 3=FC03, 4=FC04, 6=FC06, 16=FC16 |
`DataType`: 0=UINT16, 1=INT16, 2=UINT32, 3=INT32, 4=FLOAT32, 5=BOOL16 |
`ByteOrder`: 0=Big, 1=Little, 2=MidBig, 3=MidLittle |
`Parity`: 0=None, 1=Odd, 2=Even |
`GroupId`: mesmo ID + endereços contíguos = lidos numa transação |
`IsWritable`: 0=leitura, 1=leitura+escrita

### 8.3 Localização e Atualização

| Localização | Uso |
|---|---|
| `/home/admin/ppc_config/` | Recomendada — persistente |
| `/media/sd/ppc_config/` | Alternativa — cartão SD |

**Procedimento (sem recompilação):**
1. Editar via SSH: `nano /home/admin/ppc_config/registers.csv`
2. Reiniciar runtime: `sudo systemctl restart codesyscontrol`
3. `FB_ConfigLoader` relê CSVs e reconstrói profiles automaticamente.

---

## 9. SEQUÊNCIA DE POLLING

```
Ciclo de Polling (ambas as portas COM em paralelo):

COM1 (ClientSerial #1):                    COM2 (ClientSerial #2):
┌─ Device [0]: Medidor (Slave 100)         ┌─ Device [1]: Inversor (Slave 201)
│   ├─ FC03 read regs 3028..3079           │   ├─ FC03 read regs 5016..5035
│   └─ FC03 read regs 3110..3111           │   └─ FC03 read regs 5036..5039
├─ Device [1]: Inversor (Slave 101)        ├─ Device [2]: Inversor (Slave 202)
│   ├─ FC03 read regs 5016..5035           │   ├─ FC03 read ...
│   ├─ FC03 read regs 5036..5039           │   └─ FC16 write (se pendente)
│   ├─ FC16 write (se pendente)            ├─ ...
│   └─ FC06 write (se pendente)            └─ Device [16]: Inversor (Slave 216)
├─ Device [2]: Inversor (Slave 102)             └─ FC03 read ...
│   └─ ...
├─ ...
└─ Device [15]: Inversor (Slave 115)
     └─ FC03 read ...

[COM1 e COM2 são barramentos RS-485 independentes]
[Cada ClientSerial opera em paralelo — tempo total = MAX(COM1, COM2)]
[Sequenciamento dentro de cada COM: dispara 1 request, aguarda xDone/xError, próximo]
```

**Tempo estimado de um ciclo completo:**

| Porta | Devices | Transações (est.) | Tempo a 9600 baud |
|---|---|---|---|
| COM1 | 1 medidor + 15 inversores = 16 | ~35 | ~900ms |
| COM2 | 16 inversores | ~35 | ~900ms |
| **Sistema** | **32 devices** | | **~900ms** (paralelo) |

---

## 10. AÇÕES FAIL-SAFE

Quando `ST_CommDiagnostics.eDeviceStatus = DS_CommLoss` (5 erros consecutivos):

**MEDIDOR perdido:**
- Congelar última medição por máximo 5s.
- Após 5s: assumir exportação no limite máximo.
- Ramp-down dos inversores até potência segura.
- Alarme nível crítico.

**INVERSOR perdido:**
- Remover do cálculo de distribuição de setpoints.
- Redistribuir carga entre inversores online.
- Se todos falharem: modo de emergência.

**Toda a porta COM falhou:**
- Assumir pior caso (exportação máxima).
- Trip via saída digital (se disponível).
- Alarme SCADA.

---

## 11. TESTABILIDADE

### 11.1 Com Simulador
- **ModRSsim2** — simulador de slave Modbus RTU (gratuito)
- Conectar via USB-RS485 ao PC
- Validar: polling, timeout, retry, escritas, sequenciamento

### 11.2 Testes de Borda
- CSV com 0 registros → iniciar sem crash
- Slave sem resposta → timeout, retry automático, transição para CommLoss
- Exceção Modbus → `eException` reportada, device continua online
- Cabo desconectado → detecção, recuperação automática ao reconectar
- Reconexão → retorno a DS_Online

### 11.3 Testes de Concorrência entre Tasks
- Task_Main escreve setpoint enquanto Task_ModbusComm lê → GVL garante consistência
- `bWritePending` sinalizado durante leitura → escrita ocorre no próximo slot

---

## 12. BIBLIOTECAS NECESSÁRIAS

| Biblioteca | Propósito | Dependência WAGO? |
|---|---|---|
| **ModbusFB** | ClientSerial, ClientRequest*, ClientRequest (base) | Não — CODESYS puro |
| **SysCom** | Usada internamente pelo ModbusFB | Não |
| **CAA File** | Leitura de CSV no boot | Não |
| **SysTypes2 Interfaces** | Tipos base | Não |
| **Standard** | TON, R_TRIG, LIMIT, etc | Não |
| **StringUtils** | Parsing de CSV | Não |

**Dependência WAGO:** Nenhuma no código ST. Mapeamento de portas seriais é implícito no firmware do CC100 751-9402. Se migrar de hardware, ajustar apenas `CODESYSControl_User.cfg`.

---

## 13. PONTOS DE ATENÇÃO

1. **Device Tree limpo:** Sem "Modbus COM/Client/Server". Apenas COM1 e COM2 sob "Serial".

2. **Endereçamento base-0:** "Registro 40001" = `uiStartItem := 0` no ModbusFB.

3. **Chamar TODOS os FBs a cada ciclo:** Client E todos os requests devem ser chamados em cada scan, mesmo inativos. Obrigatório para processamento interno do ModbusFB.

4. **`DWORD_TO_REAL`:** Em CODESYS V3.5, faz reinterpretação de bits (IEEE 754), não conversão numérica. Correto para Modbus.

5. **`ROL(WORD, 8)`:** Swap de bytes dentro de WORD 16-bit. Para byte orders MidBig/MidLittle.

6. **Baudrate uniforme por barramento:** Todos os devices na mesma porta COM devem usar mesmos parâmetros seriais. Se necessário baudrate diferente, usar a outra porta COM.

7. **Validação COM↔Conector:** Conectar device conhecido em um conector, comunicar via COM1. Confirmar. Marcar fisicamente os conectores.

8. **Logging em comissionamento:** Usar `udiLogOptions` do ClientSerial durante comissionamento para diagnóstico. Desabilitar em produção para economizar CPU.

9. **Convenção de indexação base-1:** Arrays de inversores usam `[1..15]` (COM1) e `[1..16]` (COM2), compatível com o código existente do PPC-GD. O medidor é indexado em `[0]` do array de profiles COM1 por ser device único. Nunca usar índice 0 para inversores.

---

## 14. MAPA DE MIGRAÇÃO — CÓDIGO EXISTENTE → NOVA ARQUITETURA

Esta é uma atualização do código já implementado e em operação. A máquina de estados do MainProgram (START → READ → CONTROL → WRITE → IDLE → FAIL → STOP) **não muda**. O fluxo permanece idêntico. O que muda é a camada de transporte Modbus subjacente.

### 14.1 FBs Substituídos

| FB Atual | Função | Substituição | Impacto |
|---|---|---|---|
| `FB_ModBus` | Transação Modbus unitária (TRIG→WAIT_BUSY→WAIT_DONE) usando `ModbusSlaveComPort` e triggers booleanos do Device Tree | **Eliminado.** Substituído por `ModbusFB.ClientRequestRead*` / `ClientRequestWrite*` com interface `xExecute`/`xDone`/`xError` nativa | O padrão de handshake (TRIG→WAIT_BUSY_ON→WAIT_DONE) é absorvido pelo ModbusFB internamente |
| `FB_WriteCom` | Orquestra escrita sequencial em até 15 (COM1) ou 16 (COM2) inversores × N canais por porta COM, usando `FB_ModBus` internamente | **Reescrito.** Nova versão usa `ClientRequestWrite*` ao invés de `FB_ModBus` + triggers. A lógica de sequenciamento (inv 1..N, canal 0..M) permanece, a interface externa (Reset, Done, bCritical, etc.) é preservada |
| `FB_CheckInversores` | Varredura de presença no startup: dispara 1 transação por inversor, conta respondentes | **Reescrito.** Mesma lógica e interface, mas usando `ClientRequestReadHoldingRegisters` ao invés de `FB_ModBus` + triggers |
| `ModbusChannel` (instância `fbChannel`) | Usado no MainProgram para leitura via Device Tree channels | **Eliminado.** Substituído por `ClientRequestReadHoldingRegisters` / `ClientRequestReadInputRegisters` disparados pela Task_ModbusComm |

### 14.2 FBs que NÃO Mudam

| FB | Razão |
|---|---|
| `FB_Startup` | A lógica de estados (stInit→stCheck_COM→stCheck_Medidor→stCheck_Inversores→stWait_K1→stWait_K2→stDone) permanece. Os estados `stCheck_Medidor` e `stCheck_Inversores` são atualizados internamente para usar os novos FBs de transporte, mas a interface com o MainProgram não muda |
| `FB_Controle` | Não usa Modbus. Recebe dados já convertidos |
| `FB_ValidaDados` | Não usa Modbus. Valida dados já lidos |
| `FB_FailSafe` | Usa `fbWriteCOM1`/`fbWriteCOM2` via interface existente (Done, bCritical). A interface é preservada |
| `FB_TurnOff` | Usa mesma interface de escrita |
| `FB_PowerController`, `FB_PI`, `FB_DroopP`, etc. | Não tocam em Modbus |

### 14.3 Estado `stCheck_COM` no FB_Startup — Mudança Crítica

**Antes:** Este estado verificava o driver Modbus do Device Tree via `DED.DEVICE_STATE`, esperando `Master_01` e `Master_02` atingirem estado RUNNING.

**Depois:** Não existe mais driver Modbus no Device Tree. Este estado deve ser substituído por:

```iecst
E_StartupStatus.stCheck_COM:
    // Conectar os dois ClientSerial e verificar xConnected
    // (a configuração dos clients é feita no stInit)
    
    TonComTimeout(IN := TRUE, PT := TimeComTimeout);
    
    xMaster01IsReady := GVL_CommData.bCOM1Connected;   // Escrito pela Task_ModbusComm
    xMaster02IsReady := GVL_CommData.bCOM2Connected;   // Escrito pela Task_ModbusComm
    
    IF xMaster01IsReady AND xMaster02IsReady THEN
        TonComTimeout(IN := FALSE);
        // Log e avança para stCheck_Medidor
        stState := E_StartupStatus.stCheck_Medidor;
    ELSIF TonComTimeout.Q THEN
        // Timeout — COM não conectou
        stState := E_StartupStatus.stError;
    END_IF
```

### 14.4 Estado READ no MainProgram — Mudança

**Antes:**
```iecst
fbReadMeas(tTimeout := T#250MS, trigInv := GVL_Main.trigMedidor100, pSlave := GVL_Main.pMedidor100^);
```

**Depois:** A leitura do medidor é executada pela Task_ModbusComm e os dados aparecem em `GVL_CommData`. O estado READ no MainProgram passa a:

```iecst
E_MachineState.READ:
    // Dados já estão em GVL_CommData (atualizados pela Task_ModbusComm)
    MedidorOK := FALSE;
    
    IF GVL_CommData.bMeterOnline THEN
        fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
        MedidorOK := fbValidaDados.bDadosOK;
        // ... mesma lógica de validação existente ...
        IF MedidorOK THEN
            NextState := E_MachineState.CONTROL;
        ELSE
            // ... mesma lógica de erro existente ...
        END_IF
    ELSE
        // Medidor em CommLoss
        ContaMeasModBusTimeOut := ContaMeasModBusTimeOut + 1;
        // ... mesma lógica de escalada existente ...
    END_IF
```

### 14.5 Estado WRITE no MainProgram — Mudança

**Antes:** `fbWriteCOM1` e `fbWriteCOM2` (tipo `FB_WriteCom`) orquestram escrita usando `FB_ModBus` + triggers + `POINTER TO ModbusSlaveComPort`.

**Depois:** `fbWriteCOM1` e `fbWriteCOM2` são reescritos para usar `ClientRequestWrite*`. A interface externa (Reset, Done, bCritical, ErrCount, TmoCount, LastFailInv, etc.) **é preservada**. O MainProgram não percebe a diferença — a assinatura do FB é a mesma, apenas o transporte interno muda.

### 14.6 GVL_Main — Variáveis Eliminadas

As seguintes variáveis de `GVL_Main` que eram ligadas ao mecanismo de triggers/Device Tree **são eliminadas permanentemente**:

```
// ELIMINAR — não existem mais na nova arquitetura:
trigInvCOM100       : ARRAY[1..15, 0..4] OF BOOL;      // triggers de rising edge para canais do driver
trigInvCOM200       : ARRAY[1..15, 0..4] OF BOOL;      // idem COM2
trigMedidor100      : BOOL;                              // trigger de leitura do medidor
pInversores100      : ARRAY[1..15] OF POINTER TO ModbusSlaveComPort;   // ponteiros para slaves do Device Tree
pInversores200      : ARRAY[1..15] OF POINTER TO ModbusSlaveComPort;   // idem COM2
pMedidor100         : POINTER TO ModbusSlaveComPort;                    // ponteiro para slave do medidor
```

**Por que os triggers são eliminados:**

Os arrays `trigInvCOM100[inv, ch]` existiam porque o `IoDrvModbus` usava rising edge de variáveis booleanas para disparar transações nos canais pré-configurados no Device Tree. O `FB_ModBus` setava `trigInv := TRUE`, o driver detectava a borda, executava a transação e sinalizava via `ModbusSlaveComPort.xBusy/xDone/xError`.

Com `ModbusFB.ClientSerial`, o disparo é feito diretamente no FB de request via `xExecute := TRUE`. Não existe trigger externo, nem canal pré-definido no IDE. O endereço, function code e dados são passados programaticamente em cada chamada do request. O conceito de "canais de escrita" (canal 0 = setpoint P, canal 1 = setpoint PF) continua existindo logicamente no novo `FB_WriteCom`, mas é implementado como sequência de chamadas a `ClientRequestWriteSingleRegister` / `ClientRequestWriteMultipleRegisters`.

Substituídas por:
- Profiles em `GVL_CommData.astProfilesCOM1[0..15]` (0=medidor, 1..15=inversores) e `GVL_CommData.astProfilesCOM2[1..16]` (1..16=inversores)
- Dados de leitura em `GVL_CommData.arInvActivePower_COM1[1..15]`, `arInvActivePower_COM2[1..16]`, etc.
- Dados de escrita em `GVL_CommData.arInvSetpointP_COM1[1..15]`, `arInvSetpointP_COM2[1..16]`, etc.
- Flags de escrita pendente: `GVL_CommData.bWritePendingCOM1`, `bWritePendingCOM2`

**Nota sobre indexação:** O código existente usa `FOR i := 1 TO NInversoresCOM01 DO ... GVL_Main.P_inv_kW[i] ... END_FOR`. A nova GVL mantém esta convenção com arrays `[1..15]` e `[1..16]`.

### 14.7 Tipos Eliminados / Substituídos

| Tipo Atual | Substituição |
|---|---|
| `E_ModbusResult` (BUSY, DONE, ERRO, TIMEOUT) | Mantido para compatibilidade interna dos novos FBs. Os `ClientRequest*` do ModbusFB usam `xDone`/`xError`/`eErrorID`, mas os FBs de orquestração (`FB_WriteCom` novo) podem manter `E_ModbusResult` na interface com o MainProgram |
| `ModbusSlaveComPort` | Eliminado. Era o FB gerado pelo Device Tree para cada slave |
| `ModbusChannel` | Eliminado. Era o FB de canal do IoDrvModbus |

### 14.8 Dependências DED (Device Description) Eliminadas

O estado `stCheck_COM` usava `DED.DEVICE_STATE`, `DED.ERROR` e métodos de diagnóstico do Device Tree. Estes são eliminados. A verificação de COM agora usa `ClientSerial.xConnected` / `ClientSerial.xError`.

### 14.9 Sequência de Migração Recomendada

1. **Fase 0 — Teste de validação.** Confirmar que `ModbusFB.ClientSerial` abre COM1 e COM2 no CC100. (Programa de teste já fornecido.)

2. **Fase 1 — Implementar Task_ModbusComm.** Nova task com `PRG_ModbusComm`, `FB_ModbusChannel`, `FB_DeviceHandler`. Testar com 1 medidor + 1 inversor. Validar dados em `GVL_CommData`.

3. **Fase 2 — Reescrever FB_WriteCom.** Manter interface externa idêntica. Substituir transporte interno. Testar escrita em 1 inversor.

4. **Fase 3 — Reescrever FB_CheckInversores.** Mesma interface, novo transporte. Testar startup completo.

5. **Fase 4 — Adaptar FB_Startup.** Substituir `stCheck_COM` e `stCheck_Medidor`. Testar sequência completa de inicialização.

6. **Fase 5 — Adaptar MainProgram.** Alterar estados READ e WRITE para usar `GVL_CommData`. Remover `fbChannel`, `fbReadMeas`. Testar ciclo completo START→READ→CONTROL→WRITE→IDLE.

7. **Fase 6 — Remover Device Tree Modbus.** Eliminar "Modbus COM", Masters, Slaves do Device Tree. Limpar GVL_Main das variáveis eliminadas. Remover biblioteca `IoDrvModbus`.

8. **Fase 7 — Integrar CSV.** Implementar `FB_ConfigLoader`. Testar troca de dispositivo via CSV sem recompilação.
