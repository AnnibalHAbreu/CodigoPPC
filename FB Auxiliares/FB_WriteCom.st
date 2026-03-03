(*
  FB_WriteCom
  ==========
  Objetivo
  --------
  Orquestrar a escrita Modbus em um conjunto de inversores de um mesmo canal de comunicação (ex.: COM1 ou COM2),
  garantindo escrita SEQUENCIAL e determinística, respeitando a limitação dos inversores Goodwe de aceitar apenas
  "um registro por vez".

  Conceito de "canais"
  --------------------
  No seu driver, cada canal de escrita (0..4) é disparado por um trigger dedicado:
      trigInv[invIndex, channelIndex]
  Ex.: channel 0 = Setpoint P, channel 1 = Setpoint PF, etc.
  A quantidade de canais a escrever é configurável por COM via nChannelsToWrite (1..5).

  Política de falha (definida)
  ----------------------------
  - Em ERRO/TIMEOUT NÃO-crítico: incrementa contadores e PULA o inversor (vai para o próximo),
    resetando ChIndex := 0 (não tenta escrever PF se P falhou).
  - Em ERRO/TIMEOUT crítico (contadores > máximos): sinaliza bCritical e encerra (Done=TRUE) para o MainProgram
    decidir transição para FAIL.

  Robustez
  --------
  - Este FB chama um FB_ModBus interno (1 transação por vez). Recomenda-se que o FB_ModBus implemente handshake
    com xBusy (TRIG -> WAIT_BUSY_ON -> WAIT_DONE) para evitar "Done fantasma".
  - Este FB NÃO faz FC_LogEvent/Alarm Manager diretamente por padrão: expõe dados (última falha, contadores)
    para o MainProgram aplicar a política de log sem spam.

  Reset / uso
  -----------
  - Use xEnable = TRUE apenas enquanto estiver no estado WRITE.
  - Ao sair de WRITE (xEnable=FALSE), o FB reseta e fica pronto para o próximo ciclo.
*)
FUNCTION_BLOCK FB_WriteCom
VAR_INPUT
    Reset			 : BOOL;
	tTimeout         : TIME := T#100MS;    // timeout por operação (por canal)
    nInverters       : UINT := 0;          // quantidade de inversores no COM (<=15)
    nChannelsToWrite : UINT := 2;          // 1..5 (canais 0..4)
    maxErrors        : UINT := 999;        // acima disso vira crítico
    maxTimeouts      : UINT := 999;        // acima disso vira crítico
END_VAR

VAR_IN_OUT
    trigInv    : ARRAY[1..15, 0..4] OF BOOL;                        // triggers por inversor e por canal (do MainProgram)
    pInvPtr    : ARRAY[1..15] OF POINTER TO ModbusSlaveComPort;     // ponteiros para os slaves (um por inversor)
END_VAR

VAR_OUTPUT
    Done        : BOOL;    // terminou varrer todos inversores (ou encerrou por crítico)
    bCritical   : BOOL;    // TRUE => MainProgram deve ir para FAIL
    ErrCount    : UINT;    // contagem acumulada de ERRO
    TmoCount    : UINT;    // contagem acumulada de TIMEOUT

    InvIndex    : UINT;    // índice atual (1..15) - diagnóstico
    ChIndex     : INT;     // canal atual (0..4)  - diagnóstico

    LastFailInv : UINT;            // último inversor que falhou (para log)
    LastFailCh  : INT;             // último canal que falhou (para log)
    FailRes 	: E_ModbusResult;  // ERRO ou TIMEOUT (para log)
END_VAR

VAR
    fbTx     : FB_ModBus;
END_VAR

    
    IF Reset THEN
    		// clamp defensivo
    		Done := FALSE;
    		bCritical := FALSE;
            InvIndex := 1;
            ChIndex := 0;
            ErrCount := 0;
            TmoCount := 0;
            LastFailInv := 0;
            LastFailCh := 0;
            FailRes := E_ModbusResult.BUSY;
    ELSE
            // terminou todos
            IF (InvIndex <= nInverters) THEN
    
    	        // Executa 1 canal por vez do inversor atual
                fbTx(
        	        tTimeout := tTimeout,
                    trigInv  := trigInv[InvIndex, ChIndex],
                    pSlave   := pInvPtr[InvIndex]^
                    );
    
                CASE fbTx.result OF
                    E_ModbusResult.DONE:
                        // avança canal dentro do inversor
                        IF ChIndex < (nChannelsToWrite - 1) THEN
                            ChIndex := ChIndex + 1;
                        ELSE
                            // terminou todos canais do inversor
                            ChIndex := 0;
                            InvIndex := InvIndex + 1;
                        END_IF
    
                    E_ModbusResult.ERRO:
                        ErrCount := ErrCount + 1;
                        LastFailInv := InvIndex;
                        LastFailCh := ChIndex;
                        FailRes := E_ModbusResult.ERRO;
    
                        IF ErrCount > maxErrors THEN
    							FailRes := E_ModbusResult.ERRO;
                                bCritical := TRUE;
    							Done := TRUE;
                            ELSE
                                // não-crítico: pula inversor inteiro
                                ChIndex := 0;
                                InvIndex := InvIndex + 1;
                            END_IF
    
                        E_ModbusResult.TIMEOUT:
                            TmoCount := TmoCount + 1;
                            LastFailInv := InvIndex;
                            LastFailCh := ChIndex;
                            
                            IF TmoCount > maxTimeouts THEN
    							FailRes := E_ModbusResult.TIMEOUT;
                                bCritical := TRUE;
    							Done := TRUE;
                            ELSE
                                // não-crítico: pula inversor inteiro
                                ChIndex := 0;
                                InvIndex := InvIndex + 1;
                            END_IF
                    ELSE
                        // E_ModbusResult.BUSY = aguarda (não avança)
                    END_CASE
    		ELSE
    			Done := TRUE;
            END_IF
    END_IF
END_FUNCTION_BLOCK
