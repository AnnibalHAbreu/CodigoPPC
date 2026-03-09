# PPC-GD — Comunicação Modbus RTU Programática
# Documento Técnico Consolidado

**Projeto:** PPC-GD (Power Plant Controller — Geração Distribuída)
**Plataforma:** WAGO CC100 (751-9402)
**IDE:** CODESYS V3.5 SP21 Patch 4
**Protocolo:** Modbus RTU sobre RS-485
**Revisão:** 3.0
**Data:** 2026-03-09

---

## 1. OBJETIVO E ESCOPO

### 1.1 Motivação

Eliminar recompilação do projeto CODESYS quando dispositivos Modbus mudam. A comunicação Modbus RTU passa de configuração via Device Tree (IoDrvModbus) para implementação totalmente programática via biblioteca `ModbusFB`.

### 1.2 O Que Muda

| Componente | Antes | Depois |
|---|---|---|
| Transporte Modbus | IoDrvModbus + Device Tree | ModbusFB.ClientSerial programático |
| FB_ModBus | Triggers booleanos + ModbusSlaveComPort | Eliminado (absorvido pelo ModbusFB) |
| FB_WriteCom | Usa FB_ModBus + triggers + ponteiros | Reescrito com ClientRequestWriteSingleRegister |
| FB_CheckInversores | Usa FB_ModBus + triggers | Reescrito com ClientRequestReadHoldingRegisters |
| FB_Startup (stCheck_COM) | Verifica DED.DEVICE_STATE do Master | Verifica GVL_Comm.bCOMxConnected |
| FB_Startup (stCheck_Medidor) | Usa FB_ModBus + triggers | Verifica GVL_Comm.bMeterReadDone |
| MainProgram (READ) | fbReadMeas com triggers | Consulta GVL_Comm.eMeterResult |
| MainProgram (WRITE, FAIL, TURNOFF) | fbWriteCOM com triggers/ponteiros | fbWriteCOM com auiSlaveIds/rClient |
| Device Tree | Modbus COM + Master + Slaves | Apenas Serial > COM1, COM2 |
| GVL_Main | Triggers + ponteiros para slaves | Eliminados, substituídos por GVL_Comm |
| Configuração de devices | Hardcoded no IDE | Hardcoded no stInit (migração futura para CSV) |

### 1.3 O Que NÃO Muda

Máquina de estados do MainProgram (START→READ→CONTROL→WRITE→IDLE→FAIL→STOP→TURNOFF), FB_Controle, FB_ValidaDados, FB_FailSafe, FB_TurnOff, FB_PowerController, FB_PI, FB_PIQ, FB_DroopP, FB_Scheduler, FB_PAlloc, FB_QAlloc, FB_SafetyMargin, E_MachineState, E_ModbusResult (mantido), e toda a lógica de controle/proteção.

### 1.4 Convenções

- **Indexação base-1** para arrays de inversores: `[1..15]`, compatível com código existente
- **Canais de escrita**: `[0..19]`, até 20 canais por inversor
- **Medidor**: índice especial, não faz parte dos arrays de inversores

---

## 2. PLATAFORMA

### 2.1 Hardware — WAGO CC100 751-9402

| Recurso | Especificação |
|---|---|
| Portas seriais | **2 × RS-485** nativas |
| Firmware mínimo | FW28 (04.06.03) |

### 2.2 Portas Seriais — Confirmado no Equipamento

```
/dev/ttySTM0  → USB serviço/debug (NÃO usar para Modbus)
/dev/ttySTM1  → RS-485 #1 → COM1 (SysCom.SYS_COM_PORTS.SYS_COMPORT1)
/dev/ttySTM2  → RS-485 #2 → COM2 (SysCom.SYS_COM_PORTS.SYS_COMPORT2)
```

O mapeamento é implícito no firmware — não precisa de `[SysCom]` no `.cfg`.

### 2.3 Device Tree Final

```
751-9402 WAGO Compact Controller 100
├── Compact Controller 100 Onboard IO
│   ├── X5_DIO, X6_AIO, X12_DI, X13_RTD, X14_AIN
│   ├── Ethernet
│   └── Serial
│       ├── COM1 (COM1)
│       └── COM2 (COM2)
└── Application
    └── Configuração de tarefas
        ├── Task_Main (10ms, prioridade 10)
        └── Task_ModbusComm (2ms, prioridade 1)
```

**Sem** Modbus COM, Master, Slave, ou qualquer item Modbus no Device Tree.

### 2.4 Capacidade

| Porta | Dispositivos | Máximo |
|---|---|---|
| COM1 | 1 medidor + inversores | 1 + 15 = 16 devices |
| COM2 | Inversores | 15 devices |
| **Total** | | **31 devices** |

---

## 3. BIBLIOTECA ModbusFB — REFERÊNCIA

Baseado nos exemplos oficiais do CODESYS para o 751-9402.

### 3.1 FBs Utilizados

| FB | FC | Uso |
|---|---|---|
| `ClientSerial` | — | Gerencia porta COM, fila FIFO, conexão |
| `ClientRequestReadHoldingRegisters` | FC03 | Ler inversores, medidores |
| `ClientRequestReadInputRegisters` | FC04 | Ler dados somente-leitura |
| `ClientRequestWriteSingleRegister` | FC06 | Escrever 1 registro |
| `ClientRequestWriteMultipleRegisters` | FC16 | Escrever N registros |
| `ClientRequest` (base abstrata) | — | Array de ponteiros para iteração |

### 3.2 Regras Obrigatórias

1. **Chamar client E todos os requests a cada ciclo**, mesmo inativos
2. **Vinculação por referência**: `rClient` é `VAR_IN_OUT`, não ponteiro
3. **Endereçamento base-0**: "registro 40001" = `uiStartItem := 0`
4. **Retry automático**: `uiMaxRetries` no request
5. **Cycle time curto**: 2ms (exemplo oficial usa 1ms)

---

## 4. ARQUITETURA DE TASKS

### 4.1 Duas Tasks

| Task | Cycle Time | Prioridade | Programa |
|---|---|---|---|
| `Task_ModbusComm` | **2ms** | 1 (alta) | `PRG_ModbusComm` |
| `Task_Main` | **10ms** | 10 (normal) | `MainProgram` |

### 4.2 Sincronização via GVL_Comm

Escritor único por variável, sem locks. Tipos atômicos no ARM são seguros.

```
Task_ModbusComm ESCREVE → GVL_Comm (buffers de leitura, flags online, diagnóstico)
Task_Main LÊ ← GVL_Comm
Task_Main ESCREVE → GVL_Comm (bWritePendingCOMx)
Task_ModbusComm LÊ ← GVL_Comm (bWritePendingCOMx)
```

---

## 5. GVL_Comm — ESTADO ATUAL

```iecst
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    MAX_INV_PER_COM     : UINT := 15;
    MAX_WRITE_CHANNELS  : UINT := 20;
END_VAR

VAR_GLOBAL
    // Estado das portas COM
    bCOM1Connected, bCOM2Connected : BOOL;
    bCOM1Error, bCOM2Error         : BOOL;

    // Medidor (COM1)
    bMeterOnline        : BOOL;
    bMeterReadDone      : BOOL;
    eMeterResult        : E_ModbusResult;
    awMeterRawData      : ARRAY[0..63] OF WORD;
    uiMeterRegsRead     : UINT;

    // Inversores — status online
    abInvOnline_COM1    : ARRAY[1..15] OF BOOL;
    abInvOnline_COM2    : ARRAY[1..15] OF BOOL;
    uiInvOnlineCount_COM1, uiInvOnlineCount_COM2 : UINT;

    // Escrita — flags
    bWritePendingCOM1, bWritePendingCOM2 : BOOL;

    // Configuração de slaves (preenchidos no stInit)
    uiMeterSlaveId      : UINT := 100;
    auiInvSlaveIdsCOM1  : ARRAY[1..15] OF UINT;
    auiInvSlaveIdsCOM2  : ARRAY[1..15] OF UINT;
    auiWriteRegAddr     : ARRAY[0..19] OF UINT;

    // Flags gerais
    bConfigLoaded, bCommInitDone : BOOL;
END_VAR
```

---

## 6. NOVOS ARQUIVOS DE CÓDIGO

### 6.1 Inventário

| Arquivo | Tipo | Função |
|---|---|---|
| `GVL_Comm.st` | GVL | Variáveis compartilhadas entre tasks |
| `PRG_ModbusComm.st` | PROGRAM | Task_ModbusComm: clients, polling medidor |
| `FB_ModBus_NEW.st` | FB | Wrapper do ModbusFB com interface E_ModbusResult |
| `FB_WriteCom_NEW.st` | FB | Escrita sequencial: 15 inv × 20 canais |
| `FB_CheckInversores_NEW.st` | FB | Check de presença no startup |

### 6.2 FB_WriteCom — Interface

```
VAR_INPUT:
    Reset, tTimeout, nInverters, nChannelsToWrite, maxErrors, maxTimeouts
    auiSlaveIds  : ARRAY[1..15] OF UINT
    auiRegAddr   : ARRAY[0..19] OF UINT

VAR_IN_OUT:
    rClient      : ModbusFB.ClientSerial
    auiWriteValues : ARRAY[1..15, 0..19] OF UINT

VAR_OUTPUT:
    Done, bCritical, ErrCount, TmoCount, InvIndex, ChIndex,
    LastFailInv, LastFailCh, FailRes
```

### 6.3 FB_CheckInversores — Interface

```
VAR_INPUT:
    xEnable, tTxTimeout, tGlobalTimeout

VAR_IN_OUT:
    rClientCOM1, rClientCOM2 : ModbusFB.ClientSerial
    auiSlaveIdsCOM1, auiSlaveIdsCOM2 : ARRAY[1..15] OF UINT

VAR_OUTPUT:
    xDone, xFailed, uRespondedTotal, uConfiguredTotal,
    uLastFailIdx, uLastFailCOM
```

**Diferença chave:** FB_CheckInversores recebe AMBOS os clients (varre COM1 depois COM2 numa única instância). FB_WriteCom recebe UM client (instanciado separadamente: fbWriteCOM1 + fbWriteCOM2).

---

## 7. CONFIGURAÇÃO DE SLAVES — HARDCODED (ESTADO ATUAL)

No `stInit` do `FB_Startup`, substituir os ponteiros antigos por slave IDs numéricos:

### 7.1 Antes (Device Tree)

```iecst
GVL_Main.pMedidor100       := ADR(Medidor100);
GVL_Main.pInversores100[1] := ADR(Inversor101);   // Slave ID = 101
GVL_Main.pInversores100[2] := ADR(Inversor102);   // Slave ID = 102
// ... até [15]
GVL_Main.pInversores200[1] := ADR(Inversor201);   // Slave ID = 201
// ... até [15]
```

### 7.2 Depois (hardcoded)

```iecst
// Medidor
GVL_Comm.uiMeterSlaveId := 100;

// Inversores COM1 (slave addresses 101..115)
FOR indice := 1 TO 15 DO
    GVL_Comm.auiInvSlaveIdsCOM1[indice] := 100 + indice;
END_FOR

// Inversores COM2 (slave addresses 201..215)
FOR indice := 1 TO 15 DO
    GVL_Comm.auiInvSlaveIdsCOM2[indice] := 200 + indice;
END_FOR

// Endereços de escrita por canal (ajustar conforme datasheet do inversor)
GVL_Comm.auiWriteRegAddr[0] := 16#B99A;  // Canal 0: Setpoint P %
GVL_Comm.auiWriteRegAddr[1] := 16#B99B;  // Canal 1: Setpoint PF %
// Canais 2..19: preencher conforme necessidade, 0 se não usado
FOR indice := 2 TO 19 DO
    GVL_Comm.auiWriteRegAddr[indice] := 0;
END_FOR
```

---

## 8. CHAMADAS CORRIGIDAS NO MAINPROGRAM

### 8.1 Leitura do Medidor (estados READ, FAIL, TURNOFF)

Onde antes havia `fbReadMeas(...)`, agora:

```iecst
// Leitura é contínua na Task_ModbusComm
IF GVL_Comm.bMeterReadDone AND (GVL_Comm.eMeterResult = E_ModbusResult.DONE) THEN
    fbValidaDados(Meas_Device := GVL_Pers.MeasDeviceType);
    MedidorOK := fbValidaDados.bDadosOK;
ELSE
    MedidorOK := FALSE;
END_IF
```

**Importante:** O `FB_ValidaDados` precisa copiar `GVL_Comm.awMeterRawData` para seu UNION interno antes da conversão. Adicionar no início do FB_ValidaDados:

```iecst
CASE Meas_Device OF
    E_MeasDeviceType.CHINT_DTSU666:
        SysMemCpy(ADR(chint.WordArray[0]), ADR(GVL_Comm.awMeterRawData[0]),
                  UINT_TO_UDINT(GVL_Comm.uiMeterRegsRead) * 2);
    E_MeasDeviceType.RELAY_URP1439TU:
        SysMemCpy(ADR(URP1439.WordArray[0]), ADR(GVL_Comm.awMeterRawData[0]),
                  UINT_TO_UDINT(GVL_Comm.uiMeterRegsRead) * 2);
END_CASE
```

### 8.2 Escrita nos Inversores (estados WRITE, FAIL, TURNOFF)

Todas as chamadas de `fbWriteCOM1`/`fbWriteCOM2` usam esta interface:

```iecst
fbWriteCOM1(
    Reset            := <conforme contexto>,
    tTimeout         := T#150MS,
    nInverters       := GVL_Main.NInversoresCOM01,
    nChannelsToWrite := GVL_Pers.nChannelsToWriteCOM1,
    maxErrors        := GVL_Main.MAX_CH1_MODBUS_ERROS,
    maxTimeouts      := GVL_Main.MAX_CH1_MODBUS_TIMEOUTS,
    auiSlaveIds      := GVL_Comm.auiInvSlaveIdsCOM1,
    auiRegAddr       := GVL_Comm.auiWriteRegAddr,
    rClient          := PRG_ModbusComm.clientCOM1,
    auiWriteValues   := auiWriteValuesCOM1
);
```

Idem para `fbWriteCOM2` com `COM2`, `clientCOM2`, `auiWriteValuesCOM2`.

### 8.3 Variáveis no MainProgram

**Adicionar:**
```iecst
auiWriteValuesCOM1  : ARRAY[1..15, 0..19] OF UINT;
auiWriteValuesCOM2  : ARRAY[1..15, 0..19] OF UINT;
```

**Preencher no estado CONTROL:**
```iecst
FOR i := 1 TO GVL_Main.NInversoresCOM01 DO
    auiWriteValuesCOM1[i, 0] := REAL_TO_UINT(GVL_Main.P_inv_Percent[i] * 100.0);
    auiWriteValuesCOM1[i, 1] := REAL_TO_UINT(GVL_Main.PF_inv_Percent[i] * 100.0);
END_FOR
FOR i := 1 TO GVL_Main.NInversoresCOM02 DO
    auiWriteValuesCOM2[i, 0] := REAL_TO_UINT(GVL_Main.P_inv_Percent[i + 15] * 100.0);
    auiWriteValuesCOM2[i, 1] := REAL_TO_UINT(GVL_Main.PF_inv_Percent[i + 15] * 100.0);
END_FOR
```

**Zerar no FAIL (quando xReqZeroSetpoints):**
```iecst
FOR i := 1 TO 15 DO
    FOR ch := 0 TO TO_INT(GVL_Pers.nChannelsToWriteCOM1) - 1 DO
        auiWriteValuesCOM1[i, ch] := 0;
    END_FOR
    FOR ch := 0 TO TO_INT(GVL_Pers.nChannelsToWriteCOM2) - 1 DO
        auiWriteValuesCOM2[i, ch] := 0;
    END_FOR
END_FOR
```

**Remover:**
```iecst
fbChannel       : ModbusChannel;     // Eliminado
fbReadMeas      : FB_ModBus;         // Eliminado
```

### 8.4 FB_FailSafe — Ajuste na Chamada

```iecst
fbFailSafe(
    xMeasDone := GVL_Comm.bMeterReadDone,     // era: fbReadMeas.result = E_ModbusResult.DONE
    xMeasOK   := MedidorOK,
    // ... resto igual
);
```

---

## 9. GVL_Main — VARIÁVEIS ELIMINADAS

```iecst
// REMOVER permanentemente:
trigMedidor100  : BOOL;
pMedidor100     : POINTER TO ModbusSlaveComPort;
trigMedidor200  : BOOL;
pMedidor200     : POINTER TO ModbusSlaveComPort;
trigInvCOM100   : ARRAY[1..15, 0..4] OF BOOL;
trigInvCOM200   : ARRAY[1..15, 0..4] OF BOOL;
pInversores100  : ARRAY[1..15] OF POINTER TO ModbusSlaveComPort;
pInversores200  : ARRAY[1..15] OF POINTER TO ModbusSlaveComPort;
```

**Razão:** Os triggers de rising edge e ponteiros para `ModbusSlaveComPort` eram o mecanismo do `IoDrvModbus`. Com `ModbusFB.ClientSerial`, o disparo é via `xExecute` diretamente nos FBs de request. Os endereços e slave IDs vêm de `GVL_Comm`.

---

## 10. AÇÕES FAIL-SAFE

Quando comunicação falha (erros consecutivos ≥ 5):

| Dispositivo perdido | Ação |
|---|---|
| Medidor | Congelar 5s → assumir exportação máxima → ramp-down → alarme |
| Inversor | Remover do cálculo → redistribuir carga |
| Toda a COM | Assumir pior caso → trip → alarme SCADA |

---

## 11. FASES DE MIGRAÇÃO

### Fase 0 — Preparação
- Adicionar biblioteca `ModbusFB` (≥ 4.3.0.0) no Library Manager
- Criar `Task_ModbusComm` (2ms, prioridade 1)
- Criar `GVL_Comm`

### Fase 1 — Adicionar novos arquivos
- `GVL_Comm.st`, `PRG_ModbusComm.st`, `FB_ModBus_NEW.st`, `FB_WriteCom_NEW.st`, `FB_CheckInversores_NEW.st`
- Novos coexistem com antigos (sufixo `_NEW`)

### Fase 2 — Testar comunicação básica
- Remover temporariamente Modbus do Device Tree
- Verificar `GVL_Comm.bCOM1Connected`, `bMeterOnline`

### Fase 3 — Migrar FB_Startup
- `stCheck_COM`: verificar `GVL_Comm.bCOMxConnected` ao invés de `DED.DEVICE_STATE`
- `stCheck_Medidor`: verificar `GVL_Comm.bMeterReadDone` ao invés de `FB_ModBus` + triggers
- `stCheck_Inversores`: usar `FB_CheckInversores_NEW` com `rClientCOM1/COM2`
- `stInit`: substituir ponteiros por slave IDs hardcoded em `GVL_Comm`

### Fase 4 — Migrar MainProgram
- Estado READ: consultar `GVL_Comm` ao invés de `fbReadMeas`
- Estado WRITE: nova interface do `FB_WriteCom`
- Estados FAIL e TURNOFF: mesma nova interface
- Remover `fbChannel`, `fbReadMeas`

### Fase 5 — Limpar
- Remover Modbus do Device Tree
- Remover triggers/ponteiros da GVL_Main
- Renomear FBs `_NEW` → nomes finais
- Remover `IoDrvModbus` do Library Manager

### Fase 6 — Validação completa
- Startup, READ, CONTROL, WRITE, IDLE, FAIL, TURNOFF, STOP
- Teste de perda de comunicação e recuperação

---

## 12. MIGRAÇÃO FUTURA — CONFIGURAÇÃO VIA CSV

### 12.1 Estado Atual (Fase Hardcoded)

Atualmente, a configuração de dispositivos está hardcoded no `stInit` do `FB_Startup`:
- Slave IDs: `FOR i := 1 TO 15 DO GVL_Comm.auiInvSlaveIdsCOM1[i] := 100 + i; END_FOR`
- Endereços de registro: `GVL_Comm.auiWriteRegAddr[0] := 16#B99A;`
- Parâmetros do medidor: `uiMeterSlaveId := 100`, `uiMeterStartReg := 16#2006`
- Baudrate/paridade: hardcoded no `PRG_ModbusComm`
- Canais de escrita: apenas 2 (`nChannelsToWriteCOM1/COM2 := 2` em GVL_Pers)

Para trocar de inversor, é preciso alterar os endereços, recompilar e fazer download. **A motivação original da migração ainda não está completa nesta fase.**

### 12.2 Estado Alvo (Fase CSV)

A configuração será lida de dois arquivos CSV no boot do controlador. **Nenhuma recompilação necessária** para trocar de dispositivo.

### 12.3 Formato dos CSVs

**`devices.csv`** — Um dispositivo por linha:
```csv
DeviceName;DeviceType;SlaveId;ComPort;Baudrate;Parity;MaxRegsPerWrite;PollInterval_ms;ResponseTimeout_ms;MaxRetries
Medidor_CHINT;METER;100;1;9600;2;1;800;2000;1
Sungrow_SG110CX_01;INVERTER;101;1;9600;2;10;1000;1000;2
Sungrow_SG110CX_02;INVERTER;102;1;9600;2;10;1000;1000;2
Goodwe_GW50K_01;INVERTER;201;2;9600;2;1;1000;1000;2
```

**`registers.csv`** — Registros por dispositivo:
```csv
DeviceName;Tag;RegAddress;RegCount;FunctionCode;DataType;ByteOrder;Scale;Offset;GroupId;IsWritable;WriteChannel
Medidor_CHINT;Ua;8198;2;3;4;0;0.1;0.0;1;0;-1
Medidor_CHINT;Pt;8210;2;3;4;0;0.0001;0.0;1;0;-1
Sungrow_SG110CX_01;ActivePower;5016;2;3;4;0;1.0;0.0;1;0;-1
Sungrow_SG110CX_01;SetpointP;5000;1;6;0;0;100.0;0.0;10;1;0
Sungrow_SG110CX_01;SetpointPF;5001;1;6;0;0;100.0;0.0;10;1;1
Goodwe_GW50K_01;SetpointP;47509;1;6;0;0;100.0;0.0;10;1;0
```

Convenção:
- `FunctionCode`: 3=FC03, 4=FC04, 6=FC06, 16=FC16
- `DataType`: 0=UINT16, 1=INT16, 2=UINT32, 3=INT32, 4=FLOAT32
- `ByteOrder`: 0=BigEndian, 1=LittleEndian, 2=MidBig, 3=MidLittle
- `WriteChannel`: -1=não escrevível, 0..19=canal de escrita (mapeia para `auiWriteRegAddr[ch]`)

### 12.4 Localização dos Arquivos

| Local | Uso |
|---|---|
| `/home/admin/ppc_config/` | Recomendado — persistente |
| `/media/sd/ppc_config/` | Alternativa — cartão SD |

### 12.5 Procedimento de Troca de Dispositivo (sem recompilação)

1. Editar CSV via SSH: `nano /home/admin/ppc_config/devices.csv`
2. Reiniciar runtime: `sudo systemctl restart codesyscontrol`
3. `FB_ConfigLoader` relê CSVs no boot e preenche `GVL_Comm` automaticamente

### 12.6 O Que o FB_ConfigLoader Fará

No boot (chamado pelo `stInit` do `FB_Startup`):

1. Ler `devices.csv` → preencher `GVL_Comm.auiInvSlaveIdsCOM1/COM2`, `uiMeterSlaveId`, parâmetros de COM
2. Ler `registers.csv` → preencher `GVL_Comm.auiWriteRegAddr[]`, configurar parâmetros de leitura do medidor no `PRG_ModbusComm`
3. Ajustar `nChannelsToWrite` dinamicamente com base na quantidade de registros escrevíveis
4. Sinalizar `GVL_Comm.bConfigLoaded := TRUE`

### 12.7 Impacto no Código Existente

A transição de hardcoded para CSV é **transparente** para o MainProgram e os FBs de controle. Os dados chegam nos mesmos arrays (`GVL_Comm.auiInvSlaveIdsCOM1`, etc.) — apenas a fonte muda (de FOR loop hardcoded para leitura de arquivo).

### 12.8 Bibliotecas Adicionais para CSV

| Biblioteca | Propósito |
|---|---|
| `CAA File` | Abrir, ler, fechar arquivos no filesystem Linux |
| `StringUtils` | Parsing de linhas CSV (FIND, MID, LEFT, etc.) |

Ambas são CODESYS puro, sem dependência do WAGO.

---

## 13. BIBLIOTECAS

| Biblioteca | Propósito | Dep. WAGO? |
|---|---|---|
| **ModbusFB** (≥ 4.3.0.0) | ClientSerial + ClientRequest* | Não |
| **SysCom** | Usada internamente pelo ModbusFB | Não |
| **CAA File** | Leitura de CSV (Fase CSV) | Não |
| **StringUtils** | Parsing de CSV (Fase CSV) | Não |
| **Standard** | TON, R_TRIG, LIMIT | Não |

---

## 14. PONTOS DE ATENÇÃO

1. **Device Tree limpo** — sem Modbus COM/Client/Server
2. **Endereçamento base-0** — "registro 40001" = `uiStartItem := 0`
3. **Chamar TODOS os FBs ModbusFB a cada ciclo** — obrigatório
4. **Baudrate uniforme por barramento** — todos os devices na mesma COM com mesmos parâmetros
5. **Validar COM↔Conector** — testar e marcar fisicamente
6. **Conversão REAL→UINT** — depende do formato do inversor (×100? ×10? direto?)
7. **`DWORD_TO_REAL`** — reinterpretação de bits em V3.5 (correto para IEEE 754)
8. **Indexação base-1** para inversores, base-0 para canais
9. **Logging ModbusFB** — usar `udiLogOptions` em comissionamento, desabilitar em produção
