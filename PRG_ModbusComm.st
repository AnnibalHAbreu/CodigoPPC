(* ═══════════════════════════════════════════════════════════════════════
   PRG_ModbusComm — Programa de comunicação Modbus RTU
   ═══════════════════════════════════════════════════════════════════════
   Executa na Task_ModbusComm (cycle time: 2ms, prioridade alta).
   
   Responsabilidades:
     - Gerenciar dois ClientSerial (COM1 e COM2)
     - Ler registros do medidor (COM1) ciclicamente
     - Ler registros dos inversores para check de presença
     - Escrever setpoints nos inversores quando solicitado
     - Depositar dados raw em GVL_Comm para consumo pelo MainProgram
   
   IMPORTANTE:
     - Todos os FBs ModbusFB (client + requests) DEVEM ser chamados 
       a cada ciclo para processamento interno
     - Não contém lógica de controle — apenas transporte
   ═══════════════════════════════════════════════════════════════════════ *)
PROGRAM PRG_ModbusComm
VAR
    // ─── Clients seriais (um por porta COM) ──────────────────────
    clientCOM1      : ModbusFB.ClientSerial;
    clientCOM2      : ModbusFB.ClientSerial;
    
    // ─── Request de leitura do medidor (COM1) ────────────────────
    fbReadMeter     : ModbusFB.ClientRequestReadHoldingRegisters;
    
    // ─── Requests de leitura/escrita para inversores ─────────────
    // Para check de presença no startup e escrita de setpoints,
    // reutilizamos uma instância por operação ativa.
    // A escrita usa ClientRequestWriteSingleRegister (FC06) por 
    // compatibilidade com inversores Goodwe (1 reg por vez).
    fbInvRead       : ModbusFB.ClientRequestReadHoldingRegisters;
    fbInvWrite      : ModbusFB.ClientRequestWriteSingleRegister;
    fbInvWriteMulti : ModbusFB.ClientRequestWriteMultipleRegisters;
    
    // ─── Controle de inicialização ───────────────────────────────
    bInitDone       : BOOL := FALSE;
    
    // ─── Estado da leitura do medidor ────────────────────────────
    eMeterState     : (MS_IDLE, MS_READING, MS_DONE, MS_ERROR) := MS_IDLE;
    tonMeterPoll    : TON;          // Timer para intervalo entre leituras
    
    // ─── Medidor: parâmetros de leitura (do CSV ou hardcoded inicialmente) ───
    uiMeterSlaveId      : UINT := 100;     // Ajustar conforme instalação
    uiMeterStartReg     : UINT := 16#2006; // CHINT DTSU666: 0x2006 = primeiro registro
    uiMeterRegCount     : UINT := 44;      // 22 variáveis REAL = 44 words
    uiMeterPollMs       : UINT := 800;     // Intervalo de polling do medidor
    udiMeterTimeout     : UDINT := 2_000_000;  // 2s em µs
END_VAR

    // ═══════════════════════════════════════════════════════════════════
    // INICIALIZAÇÃO (uma vez, no primeiro scan)
    // ═══════════════════════════════════════════════════════════════════
    IF NOT bInitDone THEN
        bInitDone := TRUE;
        
        // ── Configurar COM1 ──────────────────────────────────────────
        clientCOM1(
            iPort      := SysCom.SYS_COM_PORTS.SYS_COMPORT1,
            dwBaudRate := SysCom.SYS_BR_9600,
            byDataBits := 8,
            eParity    := SysCom.SYS_EVENPARITY,
            eStopBits  := SysCom.SYS_ONESTOPBIT,
            eRtuAscii  := ModbusFB.RtuAscii.RTU
        );
        clientCOM1(xConnect := TRUE);
        
        // ── Configurar COM2 ──────────────────────────────────────────
        clientCOM2(
            iPort      := SysCom.SYS_COM_PORTS.SYS_COMPORT2,
            dwBaudRate := SysCom.SYS_BR_9600,
            byDataBits := 8,
            eParity    := SysCom.SYS_EVENPARITY,
            eStopBits  := SysCom.SYS_ONESTOPBIT,
            eRtuAscii  := ModbusFB.RtuAscii.RTU
        );
        clientCOM2(xConnect := TRUE);
        
        // ── Configurar request de leitura do medidor ─────────────────
        fbReadMeter(
            rClient     := clientCOM1,
            uiUnitId    := uiMeterSlaveId,
            uiStartItem := uiMeterStartReg,
            uiQuantity  := uiMeterRegCount,
            pData       := ADR(GVL_Comm.awMeterRawData[0]),
            udiTimeout  := udiMeterTimeout,
            uiMaxRetries := 1
        );
        
        // ── Configurar requests de inversores (vinculados mas não disparados) ──
        fbInvRead(rClient := clientCOM1, udiTimeout := 2_000_000, uiMaxRetries := 1);
        fbInvWrite(rClient := clientCOM1, udiTimeout := 2_000_000);
        fbInvWriteMulti(rClient := clientCOM1, udiTimeout := 2_000_000);
        
        GVL_Comm.bCommInitDone := FALSE;
    END_IF
    
    // ═══════════════════════════════════════════════════════════════════
    // EXECUÇÃO CÍCLICA — OBRIGATÓRIO: chamar clients a cada ciclo
    // ═══════════════════════════════════════════════════════════════════
    clientCOM1();
    clientCOM2();
    
    // Propagar estado de conexão para GVL
    GVL_Comm.bCOM1Connected := clientCOM1.xConnected;
    GVL_Comm.bCOM2Connected := clientCOM2.xConnected;
    GVL_Comm.bCOM1Error     := clientCOM1.xError;
    GVL_Comm.bCOM2Error     := clientCOM2.xError;
    
    // Sinalizar que comunicação inicializou quando ambas COMs conectaram
    IF clientCOM1.xConnected AND clientCOM2.xConnected THEN
        GVL_Comm.bCommInitDone := TRUE;
    END_IF
    
    // ═══════════════════════════════════════════════════════════════════
    // PROCESSAR TODOS OS REQUESTS (obrigatório a cada ciclo)
    // ═══════════════════════════════════════════════════════════════════
    fbReadMeter(rClient := clientCOM1);
    fbInvRead(rClient := clientCOM1);   // client será trocado conforme necessidade
    fbInvWrite(rClient := clientCOM1);
    fbInvWriteMulti(rClient := clientCOM1);
    
    // ═══════════════════════════════════════════════════════════════════
    // POLLING DO MEDIDOR — Leitura cíclica
    // ═══════════════════════════════════════════════════════════════════
    IF clientCOM1.xConnected THEN
        CASE eMeterState OF
        
            MS_IDLE:
                // Aguardar intervalo de polling
                tonMeterPoll(IN := TRUE, PT := UINT_TO_TIME(uiMeterPollMs));
                IF tonMeterPoll.Q THEN
                    tonMeterPoll(IN := FALSE);
                    // Disparar leitura
                    fbReadMeter(
                        rClient     := clientCOM1,
                        xExecute    := TRUE,
                        uiUnitId    := uiMeterSlaveId,
                        uiStartItem := uiMeterStartReg,
                        uiQuantity  := uiMeterRegCount,
                        pData       := ADR(GVL_Comm.awMeterRawData[0])
                    );
                    eMeterState := MS_READING;
                END_IF
            
            MS_READING:
                IF fbReadMeter.xDone THEN
                    fbReadMeter.xExecute := FALSE;
                    GVL_Comm.bMeterReadDone := TRUE;
                    GVL_Comm.eMeterResult := E_ModbusResult.DONE;
                    GVL_Comm.bMeterOnline := TRUE;
                    GVL_Comm.uiMeterRegsRead := uiMeterRegCount;
                    eMeterState := MS_IDLE;
                    
                ELSIF fbReadMeter.xError THEN
                    fbReadMeter.xExecute := FALSE;
                    GVL_Comm.bMeterReadDone := TRUE;
                    // Mapear erro do ModbusFB para E_ModbusResult
                    IF fbReadMeter.eErrorID = ModbusFB.Error.ReplyTimeout THEN
                        GVL_Comm.eMeterResult := E_ModbusResult.TIMEOUT;
                    ELSE
                        GVL_Comm.eMeterResult := E_ModbusResult.ERRO;
                    END_IF
                    eMeterState := MS_IDLE;
                END_IF
                // xBusy: permanece em MS_READING
        
        END_CASE
    ELSE
        // COM1 desconectada
        GVL_Comm.bMeterOnline := FALSE;
        GVL_Comm.eMeterResult := E_ModbusResult.TIMEOUT;
        eMeterState := MS_IDLE;
    END_IF
    
    // Reset do flag de leitura concluída (consumido pelo MainProgram)
    // O MainProgram lê bMeterReadDone, processa, e o flag é resetado
    // no próximo ciclo de leitura do medidor.
    // (Alternativa: MainProgram reseta após consumir — decisão de design)
END_PROGRAM
