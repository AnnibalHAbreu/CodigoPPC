(* ═══════════════════════════════════════════════════════════════════════
   FB_WriteCom (NOVA VERSÃO — ModbusFB programático)
   ═══════════════════════════════════════════════════════════════════════
   Substitui o FB_WriteCom anterior que usava FB_ModBus (triggers) + 
   POINTER TO ModbusSlaveComPort.
   
   INTERFACE EXTERNA PRESERVADA — o MainProgram não precisa mudar:
     - Mesmos VAR_INPUT: Reset, tTimeout, nInverters, nChannelsToWrite, 
       maxErrors, maxTimeouts
     - Mesmos VAR_OUTPUT: Done, bCritical, ErrCount, TmoCount, InvIndex,
       ChIndex, LastFailInv, LastFailCh, FailRes
   
   MUDANÇA INTERNA:
     - Removido: trigInv (ARRAY OF BOOL), pInvPtr (ARRAY OF POINTER TO ModbusSlaveComPort)
     - Adicionado: rClient (referência ao ClientSerial da porta COM)
     - Usa ClientRequestWriteSingleRegister internamente (FC06)
     - Os endereços e valores de escrita vêm de arrays em GVL_Main
       (P_inv_Percent, PF_inv_Percent) convertidos para registro Modbus
   
   CONCEITO DE CANAIS (mantido):
     Canal 0 = Setpoint de Potência Ativa (%)
     Canal 1 = Setpoint de Fator de Potência (%)
     (extensível para canais 2..4 conforme necessidade)
   
   Os endereços Modbus dos canais por tipo de inversor serão futuramente
   carregados do CSV. Por enquanto, são configuráveis via "VAR_INPUT"
   ═══════════════════════════════════════════════════════════════════════ *)
   
FUNCTION_BLOCK FB_WriteCom
VAR_INPUT
    Reset            : BOOL;
    tTimeout         : TIME := T#150MS;
    nInverters       : UINT := 0;           // quantidade de inversores neste COM (<=16)
    nChannelsToWrite : UINT := 2;           // canais 0..4
    maxErrors        : UINT := 999;
    maxTimeouts      : UINT := 999;
    
    // ─── Novos parâmetros (substituem triggers/ponteiros) ────────
    // Arrays de slave IDs e endereços de registro por canal
    auiSlaveIds      : ARRAY[1..15] OF UINT;        // Slave IDs dos inversores neste COM
    auiRegAddr       : ARRAY[0..19] OF UINT;          // Endereço de registro por canal
    // Nota: auiSlaveIds e auiRegAddr devem ser preenchidos pelo PRG_ModbusComm
    // ou pelo MainProgram na inicialização, a partir da configuração CSV.
END_VAR

VAR_IN_OUT
    rClient          : ModbusFB.ClientSerial;         // Referência ao client desta porta COM
    auiWriteValues   : ARRAY[1..15, 0..19] OF UINT;   // Valores a escrever [inversor, canal]
END_VAR

VAR_OUTPUT
    Done        : BOOL;
    bCritical   : BOOL;
    ErrCount    : UINT;
    TmoCount    : UINT;
    InvIndex    : UINT;
    ChIndex     : INT;
    LastFailInv : UINT;
    LastFailCh  : INT;
    FailRes     : E_ModbusResult;
END_VAR

VAR
    // Request de escrita — uma instância reutilizada sequencialmente
    _fbWrite    : ModbusFB.ClientRequestWriteSingleRegister;
    _state      : (WS_IDLE, WS_SENDING, WS_WAITING) := WS_IDLE;
    _bInitDone  : BOOL;
    _tonTimeout : TON;
END_VAR


    // ═══════════════════════════════════════════════════════════════════
    // IMPLEMENTAÇÃO
    // ═══════════════════════════════════════════════════════════════════
    
    // Inicialização
    IF NOT _bInitDone THEN
        _bInitDone := TRUE;
        _fbWrite(rClient := rClient, udiTimeout := TIME_TO_UDINT(tTimeout) * 1000);
    END_IF
    
    // OBRIGATÓRIO: chamar o request a cada ciclo
    _fbWrite(rClient := rClient);
    
    // ── Reset ────────────────────────────────────────────────────────
    IF Reset THEN
        Done := FALSE;
        bCritical := FALSE;
        InvIndex := 1;
        ChIndex := 0;
        ErrCount := 0;
        TmoCount := 0;
        LastFailInv := 0;
        LastFailCh := 0;
        FailRes := E_ModbusResult.BUSY;
        _state := WS_IDLE;
        _fbWrite.xExecute := FALSE;
        RETURN;
    END_IF
    
    // ── Já terminou? ─────────────────────────────────────────────────
    IF Done THEN
        RETURN;
    END_IF
    
    // ── Varredura: inversores 1..nInverters, canais 0..nChannelsToWrite-1 ──
    IF InvIndex > nInverters THEN
        Done := TRUE;
        RETURN;
    END_IF
    
    CASE _state OF
    
        WS_IDLE:
            // Preparar e disparar escrita
            _fbWrite(
                rClient  := rClient,
                xExecute := TRUE,
                uiUnitId := auiSlaveIds[InvIndex],
                uiItem   := auiRegAddr[ChIndex],
                uiValue  := auiWriteValues[InvIndex, ChIndex]
            );
            _tonTimeout(IN := FALSE);
            _state := WS_WAITING;
    
        WS_WAITING:
            _tonTimeout(IN := TRUE, PT := tTimeout + T#500MS);
            
            IF _fbWrite.xDone THEN
                _fbWrite.xExecute := FALSE;
                _tonTimeout(IN := FALSE);
                
                // Avançar canal ou inversor
                IF ChIndex < (TO_INT(nChannelsToWrite) - 1) THEN
                    ChIndex := ChIndex + 1;
                ELSE
                    ChIndex := 0;
                    InvIndex := InvIndex + 1;
                END_IF
                _state := WS_IDLE;
                
            ELSIF _fbWrite.xError THEN
                _fbWrite.xExecute := FALSE;
                _tonTimeout(IN := FALSE);
                
                // Determinar tipo de erro
                IF _fbWrite.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                    TmoCount := TmoCount + 1;
                    LastFailInv := InvIndex;
                    LastFailCh := ChIndex;
                    FailRes := E_ModbusResult.TIMEOUT;
                    
                    IF TmoCount > maxTimeouts THEN
                        bCritical := TRUE;
                        Done := TRUE;
                    ELSE
                        ChIndex := 0;
                        InvIndex := InvIndex + 1;
                    END_IF
                ELSE
                    ErrCount := ErrCount + 1;
                    LastFailInv := InvIndex;
                    LastFailCh := ChIndex;
                    FailRes := E_ModbusResult.ERRO;
                    
                    IF ErrCount > maxErrors THEN
                        bCritical := TRUE;
                        Done := TRUE;
                    ELSE
                        ChIndex := 0;
                        InvIndex := InvIndex + 1;
                    END_IF
                END_IF
                _state := WS_IDLE;
                
            ELSIF _tonTimeout.Q THEN
                // Safety timeout (redundante com ModbusFB timeout)
                _fbWrite.xExecute := FALSE;
                _tonTimeout(IN := FALSE);
                TmoCount := TmoCount + 1;
                LastFailInv := InvIndex;
                LastFailCh := ChIndex;
                FailRes := E_ModbusResult.TIMEOUT;
                
                IF TmoCount > maxTimeouts THEN
                    bCritical := TRUE;
                    Done := TRUE;
                ELSE
                    ChIndex := 0;
                    InvIndex := InvIndex + 1;
                END_IF
                _state := WS_IDLE;
            END_IF
            // Else: BUSY — aguarda
    
    END_CASE
END_FUNCTION_BLOCK
