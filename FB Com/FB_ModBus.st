(* ═══════════════════════════════════════════════════════════════════════
   FB_ModBus (NOVA VERSÃO — ModbusFB programático)
   ═══════════════════════════════════════════════════════════════════════
   Substitui o FB_ModBus anterior que usava triggers booleanos e 
   ModbusSlaveComPort do Device Tree.

   Esta versão encapsula um ClientRequestReadHoldingRegisters do ModbusFB,
   mantendo a MESMA INTERFACE EXTERNA (E_ModbusResult) para que:
     - FB_WriteCom, FB_CheckInversores e FB_Startup não precisem mudar
       sua lógica interna de tratamento de resultado.
   
   MUDANÇA PRINCIPAL:
     Antes: trigInv (BOOL) + pSlave (ModbusSlaveComPort) → rising edge no driver
     Agora: xExecute + rClient (ClientSerial) + uiUnitId + uiStartItem + pData
   
   CONTRATO:
     - Chamar a cada ciclo da task de comunicação
     - Setar xTrigger := TRUE para disparar uma transação
     - Verificar result a cada ciclo
     - result = BUSY enquanto transação em andamento
     - result = DONE/ERRO/TIMEOUT quando concluída
   ═══════════════════════════════════════════════════════════════════════ *)
FUNCTION_BLOCK FB_ModBus

VAR_INPUT
    tTimeout        : TIME := T#500MS;
    uiUnitId        : UINT;                // Slave address (1..247)
    uiStartItem     : UINT;                // Endereço do registro (base 0)
    uiQuantity      : UINT := 1;           // Quantidade de registros
    bIsWrite        : BOOL := FALSE;       // FALSE=leitura FC03, TRUE=escrita FC06
    uiWriteValue    : UINT := 0;           // Valor para escrita FC06 (single register)
END_VAR

VAR_IN_OUT
    rClient         : ModbusFB.ClientSerial;   // Referência ao client serial
END_VAR

VAR_OUTPUT
    result          : E_ModbusResult;       // MESMA interface do FB_ModBus antigo
END_VAR

VAR
    // Requests internos
    _fbRead         : ModbusFB.ClientRequestReadHoldingRegisters;
    _fbWriteSingle  : ModbusFB.ClientRequestWriteSingleRegister;
    
    // Buffer de leitura (quando usado para leitura de diagnóstico)
    _awReadBuf      : ARRAY[0..1] OF WORD;
    
    // Estado interno
    _state          : (ST_IDLE, ST_EXECUTING) := ST_IDLE;
    _bInitDone      : BOOL;
    _tonTimeout     : TON;
END_VAR

    // ═══════════════════════════════════════════════════════════════════
    // IMPLEMENTAÇÃO
    // ═══════════════════════════════════════════════════════════════════
    
    // Inicialização dos requests (uma vez)
    IF NOT _bInitDone THEN
        _bInitDone := TRUE;
        _fbRead(rClient := rClient, udiTimeout := TIME_TO_UDINT(tTimeout) * 1000);
        _fbWriteSingle(rClient := rClient, udiTimeout := TIME_TO_UDINT(tTimeout) * 1000);
    END_IF
    
    // Chamar requests a cada ciclo (obrigatório)
    _fbRead(rClient := rClient);
    _fbWriteSingle(rClient := rClient);
    
    // Timeout de segurança
    _tonTimeout(IN := (_state = ST_EXECUTING), PT := tTimeout + T#1S);
    
    CASE _state OF
    
        ST_IDLE:
            result := E_ModbusResult.BUSY;
            // Nada a fazer — aguarda trigger externo
            // O trigger agora é feito pelo chamador setando result := BUSY
            // e chamando este FB com os parâmetros corretos.
            // Compatibilidade: o chamador (FB_WriteCom, FB_CheckInversores)
            // chama este FB a cada ciclo. Se result=BUSY e não estamos em 
            // ST_EXECUTING, disparamos a transação.
            
            IF NOT bIsWrite THEN
                // Leitura FC03
                _fbRead(
                    rClient     := rClient,
                    xExecute    := TRUE,
                    uiUnitId    := uiUnitId,
                    uiStartItem := uiStartItem,
                    uiQuantity  := uiQuantity,
                    pData       := ADR(_awReadBuf[0])
                );
            ELSE
                // Escrita FC06
                _fbWriteSingle(
                    rClient  := rClient,
                    xExecute := TRUE,
                    uiUnitId := uiUnitId,
                    uiItem   := uiStartItem,
                    uiValue  := uiWriteValue
                );
            END_IF
            _state := ST_EXECUTING;
    
        ST_EXECUTING:
            IF NOT bIsWrite THEN
                // Verificar leitura
                IF _fbRead.xDone THEN
                    _fbRead.xExecute := FALSE;
                    result := E_ModbusResult.DONE;
                    _state := ST_IDLE;
                ELSIF _fbRead.xError THEN
                    _fbRead.xExecute := FALSE;
                    IF _fbRead.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                        result := E_ModbusResult.TIMEOUT;
                    ELSE
                        result := E_ModbusResult.ERRO;
                    END_IF
                    _state := ST_IDLE;
                ELSIF _tonTimeout.Q THEN
                    _fbRead.xExecute := FALSE;
                    result := E_ModbusResult.TIMEOUT;
                    _state := ST_IDLE;
                ELSE
                    result := E_ModbusResult.BUSY;
                END_IF
            ELSE
                // Verificar escrita
                IF _fbWriteSingle.xDone THEN
                    _fbWriteSingle.xExecute := FALSE;
                    result := E_ModbusResult.DONE;
                    _state := ST_IDLE;
                ELSIF _fbWriteSingle.xError THEN
                    _fbWriteSingle.xExecute := FALSE;
                    IF _fbWriteSingle.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                        result := E_ModbusResult.TIMEOUT;
                    ELSE
                        result := E_ModbusResult.ERRO;
                    END_IF
                    _state := ST_IDLE;
                ELSIF _tonTimeout.Q THEN
                    _fbWriteSingle.xExecute := FALSE;
                    result := E_ModbusResult.TIMEOUT;
                    _state := ST_IDLE;
                ELSE
                    result := E_ModbusResult.BUSY;
                END_IF
            END_IF
    
    END_CASE
END_FUNCTION_BLOCK
