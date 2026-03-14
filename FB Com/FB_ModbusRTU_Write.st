(* ═══════════════════════════════════════════════════════════════════════
   FB_ModbusRTU_Write
   ═══════════════════════════════════════════════════════════════════════
   Escreve setpoints em todos os inversores de uma porta COM usando o
   perfil do dispositivo (ST_InverterProfile) para determinar endereços,
   função Modbus e limites físicos.

   SUBSTITUI: FB_WriteCom (que usava arrays de endereços hardcoded e
   não tinha validação de range por canal).

   CONTRATO:
     - Instanciar dentro de PRG_ModbusComm (mesma task que o ClientSerial)
     - Chamar a cada ciclo da task de comunicação
     - xTrigger: pulso TRUE para iniciar nova varredura completa
     - xBusy: TRUE enquanto varredura em andamento
     - xDone: TRUE por 1 ciclo ao concluir (com ou sem erros não-críticos)
     - xCritical: TRUE se falhas ultrapassaram maxErrors/maxTimeouts
       → MainProgram deve ir para FAIL

   SEQUÊNCIA DE ESCRITA:
     Para cada inversor i (1..nInverters):
       Para cada canal c (0..Profile.nWriteRegs-1):
         Se Profile.WriteMap[c].bEnabled:
           1. Aplica LIMIT(MinPhys, valor, MaxPhys)
           2. Converte para UINT via Scale/Offset
           3. Escreve via FC06 (MaxRegsPerWrite=1) ou FC16 (futuro)
           4. Aguarda xDone/xError com timeout
           5. Em erro: incrementa contador, pula inversor, continua

   GESTÃO DE FALHAS:
     Falha não-crítica: pula inversor, continua varredura
     Crítica (>maxErrors ou >maxTimeouts): seta xCritical, para varredura
     O MainProgram decide o que fazer com xCritical (tipicamente → FAIL)
   ═══════════════════════════════════════════════════════════════════════ *)
{attribute 'no_assign'}
FUNCTION_BLOCK FB_ModbusRTU_Write

VAR_INPUT
    xTrigger        : BOOL;                         // Pulso TRUE inicia varredura
    nInverters      : UINT;                         // Qtd de inversores nesta COM (1..15)
    tTimeout        : TIME := T#500MS;              // Timeout por transação Modbus
    maxErrors       : UINT := 999;                  // Máx erros não-críticos antes de xCritical
    maxTimeouts     : UINT := 999;                  // Máx timeouts não-críticos antes de xCritical
    pProfile        : POINTER TO ST_InverterProfile; // Ponteiro para perfil do inversor (CONSTANT)
END_VAR

VAR_IN_OUT
    rClient         : ModbusFB.ClientSerial;        // Client desta porta COM (vive em PRG_ModbusComm)
    auiSlaveIds     : ARRAY[1..15] OF UINT;         // Slave IDs dos inversores
    arWriteValues   : ARRAY[1..15, 0..4] OF REAL;  // Valores físicos a escrever [inversor, canal]
                                                    // Canal 0 = P_inv_Percent (0..100)
                                                    // Canal 1 = PF_inv_Percent (1..20 ou 80..100)
END_VAR

VAR_OUTPUT
    xBusy           : BOOL;
    xDone           : BOOL;
    xCritical       : BOOL;
    ErrCount        : UINT;
    TmoCount        : UINT;
    LastFailInv     : UINT;
    LastFailCh      : UINT;
    LastFailRes     : E_ModbusResult;
END_VAR

VAR
    _fbWrite        : ModbusFB.ClientRequestWriteSingleRegister;
    _bInitDone      : BOOL := FALSE;
    _bTrigLast      : BOOL := FALSE;    // detecção de borda de subida em xTrigger

    _state          : (
        WS_IDLE,        // aguarda trigger
        WS_NEXT,        // avança para próximo inversor/canal (sem espera)
        WS_SENDING,     // dispara transação
        WS_WAITING      // aguarda resposta
    ) := WS_IDLE;

    _iInv           : UINT := 1;        // índice do inversor atual (1..nInverters)
    _iCh            : UINT := 0;        // índice do canal atual (0..nWriteRegs-1)
    _uiRawValue     : UINT;             // valor convertido para Modbus
    _rPhysValue     : REAL;             // valor físico clampado
    _tonTimeout     : TON;
    _rTrig          : R_TRIG;           // detector de borda
END_VAR

        // ═══════════════════════════════════════════════════════════════════
        // INICIALIZAÇÃO (uma vez)
        // ═══════════════════════════════════════════════════════════════════
        IF NOT _bInitDone THEN
            _bInitDone := TRUE;
            _fbWrite(rClient := rClient, udiTimeout := TIME_TO_UDINT(tTimeout) * 1000);
        END_IF
    
        // Obrigatório: chamar o request a cada ciclo
        _fbWrite(rClient := rClient);
    
        // Detecção de borda de subida em xTrigger
        _rTrig(CLK := xTrigger);
    
        // ═══════════════════════════════════════════════════════════════════
        // GUARD: profile válido
        // ═══════════════════════════════════════════════════════════════════
        IF pProfile = 0 THEN
            // Ponteiro nulo — não há o que fazer, sinaliza crítico
            xCritical := TRUE;
            xDone := FALSE;
            xBusy := FALSE;
            RETURN;
        END_IF
    
        // ═══════════════════════════════════════════════════════════════════
        // MÁQUINA DE ESTADOS
        // ═══════════════════════════════════════════════════════════════════
        CASE _state OF
    
            // ── IDLE: aguarda trigger ────────────────────────────────────
            WS_IDLE:
                xBusy := FALSE;
                xDone := FALSE;
                _tonTimeout(IN := FALSE);
    
                IF _rTrig.Q AND nInverters > 0 AND pProfile^.nWriteRegs > 0 THEN
                    // Inicia nova varredura
                    _iInv       := 1;
                    _iCh        := 0;
                    ErrCount    := 0;
                    TmoCount    := 0;
                    xCritical   := FALSE;
                    xDone       := FALSE;
                    xBusy       := TRUE;
                    _state      := WS_NEXT;
                END_IF
    
            // ── NEXT: decide próxima operação ou encerra ─────────────────
            WS_NEXT:
                xBusy := TRUE;
    
                // Avança canal — pula desabilitados
                WHILE _iCh < pProfile^.nWriteRegs AND
                      NOT pProfile^.WriteMap[_iCh].bEnabled DO
                    _iCh := _iCh + 1;
                END_WHILE
    
                // Verificar se esgotou canais deste inversor
                IF _iCh >= pProfile^.nWriteRegs THEN
                    // Avança inversor
                    _iCh := 0;
                    _iInv := _iInv + 1;
                END_IF
    
                // Verificar se esgotou inversores
                IF _iInv > nInverters THEN
                    // Varredura completa
                    xBusy  := FALSE;
                    xDone  := TRUE;
                    _state := WS_IDLE;
                ELSE
                    _state := WS_SENDING;
                END_IF
    
            // ── SENDING: prepara e dispara transação ─────────────────────
            WS_SENDING:
                xBusy := TRUE;
    
                // 1. Ler valor físico do array de entrada
                _rPhysValue := arWriteValues[_iInv, _iCh];
    
                // 2. Aplicar LIMIT com limites do profile
                _rPhysValue := LIMIT(
                    pProfile^.WriteMap[_iCh].MinPhys,
                    _rPhysValue,
                    pProfile^.WriteMap[_iCh].MaxPhys
                );
    
                // 3. Converter para UINT via Scale (Offset aplicado antes da divisão)
                // ValorReg = (ValorFísico - Offset) / Scale
                // Scale sempre != 0 pois está no profile validado
                IF pProfile^.WriteMap[_iCh].Scale <> 0.0 THEN
                    _uiRawValue := REAL_TO_UINT(
                        (_rPhysValue - pProfile^.WriteMap[_iCh].Offset)
                        / pProfile^.WriteMap[_iCh].Scale
                    );
                ELSE
                    // Scale inválido — usa 0 (safe: inversor recebe 0%)
                    _uiRawValue := 0;
                END_IF
    
                // 4. Disparar escrita FC06
                _fbWrite(
                    rClient  := rClient,
                    xExecute := TRUE,
                    uiUnitId := auiSlaveIds[_iInv],
                    uiItem   := pProfile^.WriteMap[_iCh].Address,
                    uiValue  := _uiRawValue
                );
    
                _tonTimeout(IN := FALSE); // reset antes de iniciar contagem
                _state := WS_WAITING;
    
            // ── WAITING: aguarda resposta da transação ───────────────────
            WS_WAITING:
                xBusy := TRUE;
                _tonTimeout(IN := TRUE, PT := tTimeout + T#500MS); // safety margin
    
                IF _fbWrite.xDone THEN
                    // Sucesso
                    _fbWrite.xExecute := FALSE;
                    _tonTimeout(IN := FALSE);
                    _iCh := _iCh + 1;      // avança canal
                    _state := WS_NEXT;
    
                ELSIF _fbWrite.xError THEN
                    _fbWrite.xExecute := FALSE;
                    _tonTimeout(IN := FALSE);
                    LastFailInv := _iInv;
                    LastFailCh  := _iCh;
    
                    IF _fbWrite.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                        TmoCount    := TmoCount + 1;
                        LastFailRes := E_ModbusResult.TIMEOUT;
                    ELSE
                        ErrCount    := ErrCount + 1;
                        LastFailRes := E_ModbusResult.ERRO;
                    END_IF
    
                    IF ErrCount > maxErrors OR TmoCount > maxTimeouts THEN
                        xCritical := TRUE;
                        xBusy     := FALSE;
                        xDone     := TRUE;
                        _state    := WS_IDLE;
                    ELSE
                        // Falha não-crítica: pula este inversor, continua
                        _iCh  := 0;
                        _iInv := _iInv + 1;
                        _state := WS_NEXT;
                    END_IF
    
                ELSIF _tonTimeout.Q THEN
                    // Safety timeout (nunca deveria ocorrer se tTimeout está correto)
                    _fbWrite.xExecute := FALSE;
                    _tonTimeout(IN := FALSE);
                    TmoCount    := TmoCount + 1;
                    LastFailInv := _iInv;
                    LastFailCh  := _iCh;
                    LastFailRes := E_ModbusResult.TIMEOUT;
    
                    IF TmoCount > maxTimeouts THEN
                        xCritical := TRUE;
                        xBusy     := FALSE;
                        xDone     := TRUE;
                        _state    := WS_IDLE;
                    ELSE
                        _iCh  := 0;
                        _iInv := _iInv + 1;
                        _state := WS_NEXT;
                    END_IF
                END_IF
                // BUSY: permanece em WS_WAITING
    
        END_CASE
END_FUNCTION_BLOCK
