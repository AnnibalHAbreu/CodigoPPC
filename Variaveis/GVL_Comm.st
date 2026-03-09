{attribute 'qualified_only'}
(* ═══════════════════════════════════════════════════════════════════════
   GVL_Comm — Área de dados da comunicação Modbus RTU programática
   ═══════════════════════════════════════════════════════════════════════
   Esta GVL é o ponto de interface entre a Task_ModbusComm (que executa
   a comunicação) e a Task_Main (que executa o controle).
   
   Capacidade:
   COM1: 1 medidor + até 15 inversores
   COM2: até 15 inversores
   Canais de escrita por inversor: até 20 (índices 0..19)
   
   REGRA DE CONCORRÊNCIA (escritor único):
     - Task_ModbusComm ESCREVE: bCOMxConnected, bMeterOnline, 
       bMeterReadDone, eMeterResult, awMeterRawData,
       bInvReadDone_COMx, eInvResult_COMx
     - Task_Main ESCREVE: bWritePendingCOMx, setpoints
     - Task_ModbusComm LÊ: bWritePendingCOMx, setpoints
   ═══════════════════════════════════════════════════════════════════════ *)
{attribute 'qualified_only'}

VAR_GLOBAL CONSTANT
    MAX_INV_PER_COM     	: UINT := 15;       // Inversores por porta COM
    MAX_WRITE_CHANNELS  	: UINT := 20;       // Canais de escrita por inversor (0..19)
END_VAR

VAR_GLOBAL
    // ─── Estado das portas COM ───────────────────────────────────
    bCOM1Connected      : BOOL;
    bCOM2Connected      : BOOL;
    bCOM1Error          : BOOL;
    bCOM2Error          : BOOL;

    // ─── Medidor (COM1) — Buffer raw para UN_chint/UN_URP1439 ───
    bMeterOnline        : BOOL;
    bMeterReadDone      : BOOL;
    eMeterResult        : E_ModbusResult;
    awMeterRawData      : ARRAY[0..63] OF WORD;
    uiMeterRegsRead     : UINT;

    // ─── Inversores COM1 — status de resposta ────────────────────
    abInvOnline_COM1        : ARRAY[1..15] OF BOOL;
    uiInvOnlineCount_COM1   : UINT;

    // ─── Inversores COM2 — status de resposta ────────────────────
    abInvOnline_COM2        : ARRAY[1..15] OF BOOL;
    uiInvOnlineCount_COM2   : UINT;

    // ─── Escrita — flags de pendência ────────────────────────────
    bWritePendingCOM1   : BOOL;
    bWritePendingCOM2   : BOOL;

    // ─── Configuração de slaves (preenchidos no stInit) ──────────
    uiMeterSlaveId      : UINT := 100;
    auiInvSlaveIdsCOM1  : ARRAY[1..15] OF UINT;
    auiInvSlaveIdsCOM2  : ARRAY[1..15] OF UINT;
    auiWriteRegAddr     : ARRAY[0..19] OF UINT;    // Endereço de registro por canal (0..19)

    // ─── Configuração geral ──────────────────────────────────────
    bConfigLoaded       : BOOL;
    bCommInitDone       : BOOL;
END_VAR
