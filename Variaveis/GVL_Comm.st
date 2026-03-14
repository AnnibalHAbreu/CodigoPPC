(* ═══════════════════════════════════════════════════════════════════════
   GVL_Comm — Interface de dados entre Task_ModbusComm e Task_Main
   ═══════════════════════════════════════════════════════════════════════
   FASE 3: Adicionados arrays de valores de escrita e flags de retorno,
   para que FB_ModbusRTU_Write viva inteiramente na Task_ModbusComm.

   REGRA DE ESCRITOR ÚNICO (evita condição de corrida):
     Task_Main ESCREVE:
       bWritePendingCOM1/2, arWriteValuesCOM1/2
     Task_ModbusComm ESCREVE:
       bCOMxConnected, bCOMxError, bCommInitDone,
       bMeterOnline, bMeterReadDone, eMeterResult, awMeterRawData,
       abInvOnline_COMx, uiInvOnlineCount_COMx,
       bWriteDoneCOM1/2, bWriteCriticalCOM1/2,
       uiWriteErrCOM1/2, uiWriteTmoCOM1/2,
       uiWriteLastFailInvCOM1/2, eWriteLastFailResCOM1/2

   NENHUMA TASK ACESSA ClientSerial DA OUTRA.
   ═══════════════════════════════════════════════════════════════════════ *)
{attribute 'qualified_only'}

VAR_GLOBAL CONSTANT
    MAX_INV_PER_COM     : UINT := 15;   // Inversores por porta COM
    MAX_WRITE_CHANNELS  : UINT := 5;    // Canais de escrita por inversor (0..4)
END_VAR

VAR_GLOBAL
    // ─── Estado das portas COM (escrito por Task_ModbusComm) ─────────
    bCOM1Connected      : BOOL;
    bCOM2Connected      : BOOL;
    bCOM1Error          : BOOL;
    bCOM2Error          : BOOL;
    bCommInitDone       : BOOL;

    // ─── Medidor (COM1) ──────────────────────────────────────────────
    // Escrito por: Task_ModbusComm
    // Lido por:    Task_Main (estado READ)
    bMeterOnline        : BOOL;
    bMeterReadDone      : BOOL;     // Task_Main reseta para FALSE após consumir
    eMeterResult        : E_ModbusResult;
    awMeterRawData      : ARRAY[0..63] OF WORD;
    uiMeterRegsRead     : UINT;

    // Parâmetros de leitura do medidor (configurados no stInit)
    uiMeterSlaveId      : UINT := 100;
    uiMeterStartReg     : UINT := 16#2006;
    uiMeterRegCount     : UINT := 44;
    uiMeterPollMs       : UINT := 800;
    udiMeterTimeout     : UDINT := 2_000_000;   // µs

    // ─── Inversores — status de presença (escrito por Task_ModbusComm) ──
    abInvOnline_COM1        : ARRAY[1..15] OF BOOL;
    uiInvOnlineCount_COM1   : UINT;
    abInvOnline_COM2        : ARRAY[1..15] OF BOOL;
    uiInvOnlineCount_COM2   : UINT;

    // ─── Slave IDs (configurados no stInit, lidos por ambas as tasks) ───
    auiInvSlaveIdsCOM1  : ARRAY[1..15] OF UINT;
    auiInvSlaveIdsCOM2  : ARRAY[1..15] OF UINT;

    // ─── Interface de escrita — SENTIDO: Task_Main → Task_ModbusComm ─────
    // Task_Main preenche arWriteValues e seta bWritePending.
    // Task_ModbusComm consome o pending, executa e devolve Done/Critical.

    // Trigger: Task_Main seta TRUE; Task_ModbusComm reseta para FALSE
    bWritePendingCOM1   : BOOL;
    bWritePendingCOM2   : BOOL;

    // Valores físicos a escrever [inversor 1..15, canal 0..4]
    // Canal 0 = P_inv_Percent (0.0..100.0)
    // Canal 1 = PF_inv_Percent (1.0..100.0, formato Goodwe já calculado)
    arWriteValuesCOM1   : ARRAY[1..15, 0..4] OF REAL;
    arWriteValuesCOM2   : ARRAY[1..15, 0..4] OF REAL;

    // ─── Interface de escrita — SENTIDO: Task_ModbusComm → Task_Main ─────
    // Task_Main lê e reseta Done após consumir.
    bWriteDoneCOM1      : BOOL;
    bWriteDoneCOM2      : BOOL;
    bWriteCriticalCOM1  : BOOL;
    bWriteCriticalCOM2  : BOOL;

    // Diagnóstico de falhas de escrita (para log no MainProgram)
    uiWriteErrCOM1      : UINT;
    uiWriteTmoCOM1      : UINT;
    uiWriteLastFailInvCOM1 : UINT;
    eWriteLastFailResCOM1  : E_ModbusResult;

    uiWriteErrCOM2      : UINT;
    uiWriteTmoCOM2      : UINT;
    uiWriteLastFailInvCOM2 : UINT;
    eWriteLastFailResCOM2  : E_ModbusResult;

    // ─── Configuração geral ──────────────────────────────────────────
    bConfigLoaded       : BOOL;
END_VAR
