(* ═══════════════════════════════════════════════════════════════════════
   FB_CheckInversores (NOVA VERSÃO — ModbusFB programático)
   ═══════════════════════════════════════════════════════════════════════
   INTERFACE EXTERNA PRESERVADA — FB_Startup não precisa mudar:
     - Mesmos VAR_INPUT: xEnable, tTxTimeout, tGlobalTimeout
     - Mesmos VAR_OUTPUT: xDone, xFailed, uRespondedTotal, uConfiguredTotal,
       uLastFailIdx, uLastFailCOM

   MUDANÇA INTERNA:
     - Removido: FB_ModBus (antigo) com triggers e ModbusSlaveComPort
     - Adicionado: ClientRequestReadHoldingRegisters via referência a ClientSerial
     - Lê slave IDs da configuração (GVL_Comm) ao invés de ponteiros do Device Tree
   
   A varredura permanece sequencial: 1 transação por ciclo de scan,
   COM1 primeiro, depois COM2.
   ═══════════════════════════════════════════════════════════════════════ *)
{attribute 'no_assign'}   
FUNCTION_BLOCK FB_CheckInversores

VAR_INPUT
    xEnable         : BOOL;
    tTxTimeout      : TIME := T#500MS;
    tGlobalTimeout  : TIME := T#60S;
END_VAR

VAR_IN_OUT
    rClientCOM1     : ModbusFB.ClientSerial;    // Referência ao client COM1
    rClientCOM2     : ModbusFB.ClientSerial;    // Referência ao client COM2
    // Arrays de slave IDs por porta COM
    auiSlaveIdsCOM1 : ARRAY[1..15] OF UINT;    // Slave IDs inversores COM1
    auiSlaveIdsCOM2 : ARRAY[1..15] OF UINT;    // Slave IDs inversores COM2
END_VAR

VAR_OUTPUT
    xDone           : BOOL;
    xFailed         : BOOL;
    uRespondedTotal : UINT;
    uConfiguredTotal: UINT;
    uLastFailIdx    : UINT;
    uLastFailCOM    : UINT;
END_VAR

VAR
    _fbRead         : ModbusFB.ClientRequestReadHoldingRegisters;
    _awBuf          : ARRAY[0..1] OF WORD;      // buffer mínimo para leitura de teste
    
    uCheckIdx       : UINT := 1;
    uCheckCOM       : UINT := 1;                // 1=COM1, 2=COM2, 3=avaliação
    uRespondedCOM1  : UINT := 0;
    uRespondedCOM2  : UINT := 0;
    bInitDone       : BOOL := FALSE;
    bReqInitDone    : BOOL := FALSE;
    TonGlobal       : TON;
    CheckThreshold  : REAL := 1.0;
    
    _state          : (CS_IDLE, CS_SENDING, CS_WAITING) := CS_IDLE;
    _uiRegAddr      : UINT := 0;               // Endereço de teste (reg 0 — qualquer holding register)
END_VAR

    // ── Reset quando desabilitado ────────────────────────────────────
    IF NOT xEnable THEN
        xDone            := FALSE;
        xFailed          := FALSE;
        uRespondedCOM1   := 0;
        uRespondedCOM2   := 0;
        uRespondedTotal  := 0;
        uConfiguredTotal := 0;
        uLastFailIdx     := 0;
        uLastFailCOM     := 0;
        uCheckIdx        := 1;
        uCheckCOM        := 1;
        bInitDone        := FALSE;
        bReqInitDone     := FALSE;
        _state           := CS_IDLE;
        TonGlobal(IN := FALSE);
        RETURN;
    END_IF
    
    // Se já terminou, mantém resultado
    IF xDone OR xFailed THEN
        RETURN;
    END_IF
    
    // Inicialização
    IF NOT bInitDone THEN
        uConfiguredTotal := GVL_Main.NInversoresCOM01 + GVL_Main.NInversoresCOM02;
        bInitDone := TRUE;
    END_IF
    
    // Inicialização do request (uma vez)
    IF NOT bReqInitDone THEN
        _fbRead(
            rClient     := rClientCOM1,
            udiTimeout  := TIME_TO_UDINT(tTxTimeout) * 1000,
            uiMaxRetries := 0   // Sem retry no check — queremos saber rápido
        );
        bReqInitDone := TRUE;
    END_IF
    
    // Chamar request a cada ciclo (obrigatório)
    IF uCheckCOM <= 1 THEN
        _fbRead(rClient := rClientCOM1);
    ELSE
        _fbRead(rClient := rClientCOM2);
    END_IF
    
    // Timeout global
    TonGlobal(IN := TRUE, PT := tGlobalTimeout);
    IF TonGlobal.Q THEN
        TonGlobal(IN := FALSE);
        uRespondedTotal := uRespondedCOM1 + uRespondedCOM2;
        xFailed := TRUE;
        RETURN;
    END_IF
    
    // ── Varredura COM1 ──────────────────────────────────────────────
    IF uCheckCOM = 1 THEN
        IF uCheckIdx <= GVL_Main.NInversoresCOM01 THEN
            
            CASE _state OF
                CS_IDLE:
                    // Disparar leitura de 1 registro do inversor atual
                    _fbRead(
                        rClient     := rClientCOM1,
                        xExecute    := TRUE,
                        uiUnitId    := auiSlaveIdsCOM1[uCheckIdx],
                        uiStartItem := _uiRegAddr,
                        uiQuantity  := 1,
                        pData       := ADR(_awBuf[0])
                    );
                    _state := CS_WAITING;
                    
                CS_WAITING:
                    IF _fbRead.xDone THEN
                        _fbRead.xExecute := FALSE;
                        uRespondedCOM1 := uRespondedCOM1 + 1;
                        GVL_Comm.abInvOnline_COM1[uCheckIdx] := TRUE;
                        uCheckIdx := uCheckIdx + 1;
                        _state := CS_IDLE;
                        
                    ELSIF _fbRead.xError THEN
                        _fbRead.xExecute := FALSE;
                        uLastFailIdx := uCheckIdx;
                        uLastFailCOM := 1;
                        GVL_Comm.abInvOnline_COM1[uCheckIdx] := FALSE;
                        uCheckIdx := uCheckIdx + 1;
                        _state := CS_IDLE;
                    END_IF
                    // BUSY: aguarda
            END_CASE
            
        ELSE
            // COM1 concluída — avançar para COM2
            uCheckIdx := 1;
            uCheckCOM := 2;
            _state := CS_IDLE;
        END_IF
    
    // ── Varredura COM2 ──────────────────────────────────────────────
    ELSIF uCheckCOM = 2 THEN
        IF GVL_Main.NInversoresCOM02 = 0 THEN
            uCheckCOM := 3;
            
        ELSIF uCheckIdx <= GVL_Main.NInversoresCOM02 THEN
            
            CASE _state OF
                CS_IDLE:
                    _fbRead(
                        rClient     := rClientCOM2,
                        xExecute    := TRUE,
                        uiUnitId    := auiSlaveIdsCOM2[uCheckIdx],
                        uiStartItem := _uiRegAddr,
                        uiQuantity  := 1,
                        pData       := ADR(_awBuf[0])
                    );
                    _state := CS_WAITING;
                    
                CS_WAITING:
                    IF _fbRead.xDone THEN
                        _fbRead.xExecute := FALSE;
                        uRespondedCOM2 := uRespondedCOM2 + 1;
                        GVL_Comm.abInvOnline_COM2[uCheckIdx] := TRUE;
                        uCheckIdx := uCheckIdx + 1;
                        _state := CS_IDLE;
                        
                    ELSIF _fbRead.xError THEN
                        _fbRead.xExecute := FALSE;
                        uLastFailIdx := uCheckIdx;
                        uLastFailCOM := 2;
                        GVL_Comm.abInvOnline_COM2[uCheckIdx] := FALSE;
                        uCheckIdx := uCheckIdx + 1;
                        _state := CS_IDLE;
                    END_IF
            END_CASE
            
        ELSE
            uCheckCOM := 3;
        END_IF
    
    // ── Avaliação final ─────────────────────────────────────────────
    ELSIF uCheckCOM = 3 THEN
        TonGlobal(IN := FALSE);
        uRespondedTotal := uRespondedCOM1 + uRespondedCOM2;
        
        IF uConfiguredTotal = 0 THEN
            xFailed := TRUE;
            RETURN;
        END_IF
        
        IF (TO_REAL(uRespondedTotal) / TO_REAL(uConfiguredTotal)) >= CheckThreshold THEN
            xDone := TRUE;
        ELSE
            xFailed := TRUE;
        END_IF
        
        GVL_Comm.uiInvOnlineCount_COM1 := uRespondedCOM1;
        GVL_Comm.uiInvOnlineCount_COM2 := uRespondedCOM2;
    END_IF
END_FUNCTION_BLOCK
